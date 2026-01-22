import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

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

  // Listeners
  late dynamic _playbackListener;
  late dynamic _queueListener;
  late dynamic _syncListener;
  late dynamic _errorListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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

    // ---- Attach Listeners ----
    widget.socket.on("PLAYBACK_UPDATE", _playbackListener);
    widget.socket.on("QUEUE_UPDATED", _queueListener);
    widget.socket.on("SYNC", _syncListener);
    widget.socket.on("ERROR", _errorListener);
    widget.socket.on("PARTY_ENDED", (data) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(data["message"] ?? "Party ended")));

      Navigator.of(context).popUntil((route) => route.isFirst);
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
    _isPlaying = isPlaying;

    if (!isPlaying) {
      _controller?.pause();
      return;
    }

    final int index = data["currentIndex"] ?? 0;
    final int startedAt = (data["startedAt"] as num?)?.toInt() ?? 0;

    if (queue.isEmpty || index >= queue.length) return;

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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.socket.off("PLAYBACK_UPDATE", _playbackListener);
    widget.socket.off("QUEUE_UPDATED", _queueListener);
    widget.socket.off("SYNC", _syncListener);
    widget.socket.off("ERROR", _errorListener);
    widget.socket.off("PARTY_ENDED");
    _controller?.dispose();
    searchCtrl.dispose();

    _ytService.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
                    Text(
                      "PARTY: ${widget.party["id"]}",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: Colors.white,
                      ),
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
                      child: _controller == null
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
                            ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ---- Host Controls ----
              if (isHost)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.pause),
                              label: const Text("PAUSE"),
                              onPressed: _pause,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.play_arrow),
                              label: const Text("RESYNC"),
                              onPressed: _resyncPlay,
                            ),
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
    );
  }
}
