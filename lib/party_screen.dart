import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:sync_music/widgets/floating_emojis.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:share_plus/share_plus.dart';

class PartyScreen extends StatefulWidget {
  final IO.Socket socket;
  final Map<String, dynamic> party;
  final String username;

  const PartyScreen({
    super.key,
    required this.socket,
    required this.party,
    required this.username,
  });

  @override
  State<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends State<PartyScreen> with WidgetsBindingObserver {
  final YouTubeService _ytService = YouTubeService();
  final TextEditingController searchCtrl = TextEditingController();
  Timer? _debounce;
  List<yt.Video> searchResults = [];
  bool isSearching = false;

  YoutubePlayerController? _controller;

  List<dynamic> queue = [];
  int currentIndex = 0;
  int? _serverStartedAt;
  int? _lastEndedIndex;

  bool isHost = false;
  bool _isPlaying = false;
  int partySize = 1;
  int votesCount = 0;
  int votesRequired = 0;

  final StreamController<String> _reactionStreamCtrl = StreamController<String>.broadcast();

  // Listeners
  late dynamic _playbackListener;
  late dynamic _queueListener;
  late dynamic _syncListener;
  late dynamic _errorListener;
  late dynamic _partySizeListener;
  late dynamic _voteUpdateListener;
  late dynamic _reactionListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();

    queue = List.from(widget.party["queue"] ?? []);
    currentIndex = widget.party["currentIndex"] ?? 0;
    isHost = widget.party["hostId"] == widget.socket.id;
    _isPlaying = widget.party["isPlaying"] == true;

    if (_isPlaying && queue.isNotEmpty && currentIndex < queue.length) {
      _serverStartedAt = (widget.party["startedAt"] as num?)?.toInt();
      final videoId = YoutubePlayer.convertUrlToId(queue[currentIndex]["url"]);

      if (videoId != null) {
        _controller = YoutubePlayerController(
          initialVideoId: videoId,
          flags: const YoutubePlayerFlags(
            autoPlay: false,
            mute: false,
            hideControls: true,
            disableDragSeek: true,
          ),
        );
      }
    }

    // ---- Define Listeners ----
    _playbackListener = (data) => _onPlaybackUpdate(data);
    _queueListener = (data) {
      if (!mounted) return;
      setState(() {
        queue = List.from(data);
      });
    };
    _syncListener = (data) => _onSync(data);
    _errorListener = (msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg.toString())));
    };
    _partySizeListener = (data) {
      if (!mounted) return;
      setState(() {
        partySize = data["size"] ?? 1;
      });
    };
    _voteUpdateListener = (data) {
      if (!mounted) return;
      setState(() {
        votesCount = data["votes"] ?? 0;
        votesRequired = data["required"] ?? 0;
      });
    };
    _reactionListener = (data) {
      if (!mounted) return;
      _reactionStreamCtrl.add(data["emoji"] ?? "❤️");
    };

    // ---- Attach Listeners ----
    widget.socket.on("PLAYBACK_UPDATE", _playbackListener);
    widget.socket.on("QUEUE_UPDATED", _queueListener);
    widget.socket.on("SYNC", _syncListener);
    widget.socket.on("ERROR", _errorListener);
    widget.socket.on("PARTY_SIZE", _partySizeListener);
    widget.socket.on("VOTE_UPDATE", _voteUpdateListener);
    widget.socket.on("REACTION", _reactionListener);
    
    // Request initial size
    // Note: The server should emit this on join, but we can also rely on subsequent updates.

    widget.socket.on("PARTY_ENDED", (data) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(data["message"] ?? "Party ended")));

      Navigator.of(context).popUntil((route) => route.isFirst);
    });

    widget.socket.on("HOST_UPDATE", (data) {
      if (!mounted) return;
      final newHostId = data["hostId"];
      setState(() {
        isHost = newHostId == widget.socket.id;
      });
      if (isHost) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You are now the host!")),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isPlaying && _controller != null && !_controller!.value.isPlaying) {
        _controller!.play();
      }
    }
  }

  // ---------------- PLAYBACK HANDLER ----------------
  void _onPlaybackUpdate(dynamic data) {
    if (!mounted) return;

    final bool isPlaying = data["isPlaying"] == true;
    
    // Notify guests about host actions
    if (!isHost && _isPlaying != isPlaying) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPlaying ? "Host started playing" : "Host paused playback"),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }

    _isPlaying = isPlaying;

    if (!isPlaying) {
      _controller?.pause();
      // Force UI update to show Play button
      setState(() {}); 
      return;
    }

    final int index = data["currentIndex"] ?? 0;
    final int startedAt = (data["startedAt"] as num?)?.toInt() ?? 0;

    // Check for end of queue state
    if (queue.isNotEmpty && index >= queue.length) {
        setState(() {
            currentIndex = index;
        });
        return;
    }

    if (queue.isEmpty) return;

    bool trackChanged = (index != currentIndex);
    currentIndex = index;
    _serverStartedAt = startedAt;

    final videoId = YoutubePlayer.convertUrlToId(queue[currentIndex]["url"]);
    if (videoId == null) return;

    if (_controller != null) {
      if (trackChanged) {
        int startSeconds = 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (startedAt > 0 && now > startedAt) {
          startSeconds = (now - startedAt) ~/ 1000;
        }
        _controller!.load(videoId, startAt: startSeconds);
      } else {
        final now = DateTime.now().millisecondsSinceEpoch;
        final seekMs = now - startedAt;
        if ((_controller!.value.position.inMilliseconds - seekMs).abs() >
            1000) {
          _controller!.seekTo(Duration(milliseconds: seekMs));
        }
        if (!_controller!.value.isPlaying) _controller!.play();
      }
      setState(() {});
      return;
    }

    _controller = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
        hideControls: true,
        disableDragSeek: true,
      ),
    );
    setState(() {});
  }

  // ---------------- SYNC HANDLER ----------------
  void _onSync(dynamic data) {
    if (!mounted) return;

    final int serverIndex = data["currentIndex"] ?? currentIndex;
    if (serverIndex != currentIndex) {
      _onPlaybackUpdate({
        "isPlaying": true,
        "currentIndex": serverIndex,
        "startedAt": data["startedAt"],
      });
      return;
    }

    if (_controller == null || !_controller!.value.isPlaying) return;

    final int startedAt = (data["startedAt"] as num).toInt();
    final now = DateTime.now().millisecondsSinceEpoch;
    final serverPos = now - startedAt;
    final localPos = _controller!.value.position.inMilliseconds;

    if ((serverPos - localPos).abs() > 2000) {
      _controller!.seekTo(Duration(milliseconds: serverPos));
    }
  }

  // ---------------- SEARCH & ADD ----------------
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        searchResults = [];
        isSearching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => isSearching = true);
      final results = await _ytService.searchVideos(query);
      if (mounted) {
        setState(() {
          searchResults = results;
          isSearching = false;
        });
      }
    });
  }

  void _addVideo(yt.Video video) {
    widget.socket.emit("ADD_TRACK", {
      "partyId": widget.party["id"],
      "track": {
        "url": video.url,
        "title": video.title,
        "addedBy": widget.username,
      },
    });
    searchCtrl.clear();
    setState(() => searchResults = []);
    FocusScope.of(context).unfocus();
  }

  void _endParty() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("End Party"),
        content: const Text(
          "This will end the party for everyone. Are you sure?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              widget.socket.emit("END_PARTY", {"partyId": widget.party["id"]});
            },
            child: const Text("End Party"),
          ),
        ],
      ),
    );
  }

  void _pause() => widget.socket.emit("PAUSE", {"partyId": widget.party["id"]});
  void _resyncPlay() =>
      widget.socket.emit("PLAY", {"partyId": widget.party["id"]});

  void _changeTrack(int index) {
    widget.socket.emit("CHANGE_INDEX", {
      "partyId": widget.party["id"],
      "newIndex": index,
    });
  }

  void _prevTrack() => _changeTrack(currentIndex - 1);
  void _nextTrack() => _changeTrack(currentIndex + 1);

  void _removeTrack(String trackId) {
    widget.socket.emit("REMOVE_TRACK", {
      "partyId": widget.party["id"],
      "trackId": trackId,
    });
  }

  void _voteSkip() {
    widget.socket.emit("VOTE_SKIP", {"partyId": widget.party["id"]});
  }

  void _sendReaction(String emoji) {
    widget.socket.emit("SEND_REACTION", {
      "partyId": widget.party["id"],
      "emoji": emoji,
    });
    // Optimistic UI update
    _reactionStreamCtrl.add(emoji);
  }

  void _showQRCode() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          "Scan to Join",
          style: TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: 250,
          height: 250,
          child: Center(
            child: QrImageView(
              data: widget.party["id"],
              version: QrVersions.auto,
              size: 250.0,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  void _shareParty() {
    Share.share(
      "Join my music party on Sync Music! Code: ${widget.party["id"]}",
      subject: "Join Sync Music Party",
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    widget.socket.off("PLAYBACK_UPDATE", _playbackListener);
    widget.socket.off("QUEUE_UPDATED", _queueListener);
    widget.socket.off("SYNC", _syncListener);
    widget.socket.off("ERROR", _errorListener);
    widget.socket.off("PARTY_SIZE", _partySizeListener);
    widget.socket.off("VOTE_UPDATE", _voteUpdateListener);
    widget.socket.off("REACTION", _reactionListener);
    widget.socket.off("PARTY_ENDED");
    widget.socket.off("HOST_UPDATE");
    _controller?.dispose();
    searchCtrl.dispose();
    _reactionStreamCtrl.close();

    _ytService.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final bool isEndOfQueue = currentIndex >= queue.length && queue.isNotEmpty;
    final bool isEmptyQueue = queue.isEmpty;
    final bool showPlayer = !isEmptyQueue && !isEndOfQueue;

    return Scaffold(
      body: FloatingEmojis(
        reactionStream: _reactionStreamCtrl.stream,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF000000), Color(0xFF1A1A1A)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ---- Header ----
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Text(
                                "PARTY: ${widget.party["id"]}",
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                  color: Colors.white,
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.share, size: 20, color: Colors.white70),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.only(right: 8),
                                    onPressed: _shareParty,
                                  ),
                                  if (isHost)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: IconButton(
                                        icon: const Icon(Icons.qr_code, size: 20, color: Colors.white70),
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                        onPressed: _showQRCode,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                  children: [
                                      const Icon(Icons.people, size: 14, color: Colors.white70),
                                      const SizedBox(width: 4),
                                      Text(
                                          "$partySize Online",
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                  ],
                              ),
                          ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isHost
                              ? const Color(0xFFBB86FC)
                              : const Color(0xFF03DAC6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isHost ? "HOST" : "GUEST",
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ---- Player Area ----
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: Colors.black,
                        child: showPlayer
                            ? (_controller == null
                                ? Center(
                                    child: Text(
                                      _isPlaying ? "Loading..." : "Waiting...",
                                      style: const TextStyle(color: Colors.white54),
                                    ),
                                  )
                                : YoutubePlayer(
                                    controller: _controller!,
                                    showVideoProgressIndicator: true,
                                    progressIndicatorColor: Theme.of(
                                      context,
                                    ).primaryColor,
                                    onEnded: (_) {
                                      if (isHost && _lastEndedIndex != currentIndex) {
                                        _lastEndedIndex = currentIndex;
                                        widget.socket.emit("TRACK_ENDED", {
                                          "partyId": widget.party["id"],
                                        });
                                      }
                                    },
                                    onReady: () {
                                      if (_serverStartedAt != null && _isPlaying) {
                                        final now =
                                            DateTime.now().millisecondsSinceEpoch;
                                        final seekMs = now - _serverStartedAt!;
                                        _controller!.seekTo(
                                          Duration(milliseconds: seekMs),
                                        );
                                        _controller!.play();
                                      }
                                    },
                                  ))
                            : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.queue_music,
                                      size: 48,
                                      color: Colors.white24,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      isEndOfQueue 
                                          ? "End of Queue" 
                                          : "Queue is Empty",
                                      style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Add songs to continue the party!",
                                      style: const TextStyle(color: Colors.white38),
                                    ),
                                  ],
                                ),
                            ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ---- Reactions Toolbar ----
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ["🔥", "❤️", "🎉", "😂", "👋", "💃"].map((emoji) {
                      return GestureDetector(
                        onTap: () => _sendReaction(emoji),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 24),

                // ---- Vote to Skip (Guests Only) ----
                if (!isHost)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.thumbs_up_down_outlined),
                        label: Text(
                          partySize < 5 
                            ? "Vote Skip (Need 5+ Users)" 
                            : "Vote to Skip ($votesCount/$votesRequired)",
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: partySize < 5 ? Colors.grey : Colors.amber,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: partySize >= 5 ? _voteSkip : null,
                      ),
                    ),
                  ),

                // ---- Host Controls ----
                if (isHost)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              iconSize: 42,
                              icon: const Icon(Icons.skip_previous),
                              color: Colors.white,
                              onPressed: currentIndex > 0 ? _prevTrack : null,
                            ),
                            IconButton(
                              iconSize: 56,
                              icon: Icon(
                                _isPlaying
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_fill,
                              ),
                              color: Theme.of(context).primaryColor,
                              onPressed: _isPlaying ? _pause : _resyncPlay,
                            ),
                            IconButton(
                              iconSize: 42,
                              icon: const Icon(Icons.skip_next),
                              color: Colors.white,
                              onPressed:
                                  currentIndex < queue.length - 1
                                      ? _nextTrack
                                      : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.stop_circle),
                            label: const Text("END PARTY"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _endParty,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // ---- Queue List ----
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: queue.length,
                    itemBuilder: (_, i) {
                      final track = queue[i];
                      final isCurrent = i == currentIndex;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          opacity: isCurrent ? 0.1 : 0.05,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            leading: isCurrent
                                ? Icon(
                                    Icons.equalizer_rounded,
                                    color: Theme.of(context).primaryColor,
                                    size: 20,
                                  )
                                : Text(
                                    "${i + 1}",
                                    style: const TextStyle(color: Colors.white54),
                                  ),
                            title: Text(
                              track["title"],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent ? Colors.white : Colors.white70,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              "By ${track["addedBy"] ?? 'Unknown'}",
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                            trailing: isHost
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.white54, size: 20),
                                    onPressed: () => _removeTrack(track["id"]),
                                  )
                                : null,
                            onTap: isHost ? () => _changeTrack(i) : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ---- Search / Add ----
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF1E1E1E),
                  child: Column(
                    children: [
                      TextField(
                        controller: searchCtrl,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: "Search YouTube songs...",
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: isSearching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.black,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      if (searchResults.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 150),
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: searchResults.length,
                            itemBuilder: (_, i) {
                              final video = searchResults[i];
                              return ListTile(
                                dense: true,
                                leading: Image.network(
                                  video.thumbnails.lowResUrl,
                                  width: 30,
                                  fit: BoxFit.cover,
                                ),
                                title: Text(
                                  video.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onTap: () => _addVideo(video),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
