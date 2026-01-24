import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:sync_music/widgets/floating_emojis.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:sync_music/services/remote_config_service.dart';
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

class _PartyScreenState extends State<PartyScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final YouTubeService _ytService = YouTubeService();
  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController chatCtrl = TextEditingController();
  Timer? _debounce;
  List<yt.Video> searchResults = [];
  bool isSearching = false;

  YoutubePlayerController? _controller;

  List<dynamic> queue = [];
  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> membersList = [];
  int currentIndex = 0;
  int? _serverStartedAt;
  int? _lastEndedIndex;

  bool isHost = false;
  bool _isPlaying = false;
  bool isDisconnected = false;
  int partySize = 1;
  int votesCount = 0;
  int votesRequired = 0;

  late TabController _tabController;
  int _unreadMessages = 0;
  int _currentThemeIndex = 0;

  static const List<LinearGradient> _themes = [
    LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF000000), Color(0xFF1A1A1A)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2E0249), Color(0xFF570A57)], // Purple
    ),
    LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFF0F2027), Color(0xFF2C5364)], // Blue/Green
    ),
    LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF430404), Color(0xFF680808)], // Red
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF141E30), Color(0xFF243B55)], // Deep Blue
    ),
  ];

  final StreamController<String> _reactionStreamCtrl =
      StreamController<String>.broadcast();

  // Listeners
  late dynamic _playbackListener;
  late dynamic _queueListener;
  late dynamic _syncListener;
  late dynamic _errorListener;
  late dynamic _partySizeListener;
  late dynamic _voteUpdateListener;
  late dynamic _reactionListener;
  late dynamic _chatListener;
  late dynamic _infoListener;
  late dynamic _membersListener;
  late dynamic _kickedListener;
  late dynamic _partyStateListener;
  late dynamic _themeListener;

  void _handlePlayerError(String error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Playback Error: $error. Skipping..."),
        backgroundColor: Colors.red,
      ),
    );

    if (isHost) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && isHost) {
          widget.socket.emit("TRACK_ENDED", {"partyId": widget.party["id"]});
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _unreadMessages > 0) {
        setState(() => _unreadMessages = 0);
      }
    });

    queue = List.from(widget.party["queue"] ?? []);
    currentIndex = widget.party["currentIndex"] ?? 0;
    isHost = widget.party["hostId"] == widget.socket.id;
    _isPlaying = widget.party["isPlaying"] == true;
    partySize = widget.party["size"] ?? 1;
    _currentThemeIndex = widget.party["themeIndex"] ?? 0;

    debugPrint("Initial Party Data Members: ${widget.party["members"]}");
    if (widget.party["members"] != null) {
      try {
        membersList = List<Map<String, dynamic>>.from(widget.party["members"]);
      } catch (e) {
        debugPrint("Error parsing initial members list: $e");
      }
    }

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
        // ignore: cascade_invocations
        _controller!.addListener(() {
          if (_controller!.value.hasError) {
            _handlePlayerError(_controller!.value.errorCode.toString());
          }
        });
      }
    }

    // ---- Define Listeners ----
    _playbackListener = (data) => _onPlaybackUpdate(data);
    _queueListener = (data) {
      if (!mounted) return;
      final newQueue = List.from(data);

      // Check for added songs
      if (newQueue.length > queue.length) {
        final newTrack = newQueue.last;
        _addSystemMessage(
          "${newTrack['addedBy'] ?? 'Someone'} added '${newTrack['title']}'",
        );
      }

      setState(() {
        queue = newQueue;
      });
    };
    _syncListener = (data) => _onSync(data);
    _errorListener = (msg) {
      if (!mounted) return;
      final message = msg.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      if (message.contains("Party not found")) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
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
    _chatListener = (data) {
      if (!mounted) return;
      setState(() {
        messages.add({...Map<String, dynamic>.from(data), 'type': 'user'});
        if (_tabController.index != 1) {
          _unreadMessages++;
        }
      });
    };
    _infoListener = (msg) {
      if (!mounted) return;
      _addSystemMessage(msg.toString());
    };
    _membersListener = (data) {
      debugPrint("MEMBERS_LIST received: $data");
      if (!mounted) return;
      try {
        setState(() {
          membersList = List<Map<String, dynamic>>.from(data);
        });
      } catch (e) {
        debugPrint("Error parsing members list: $e");
      }
    };
    _kickedListener = (msg) {
      if (!mounted) return;
      showDialog(
        barrierDismissible: false,
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("You have been kicked"),
          content: Text(msg.toString()),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );
    };

    // Handle reconnection state update
    _partyStateListener = (data) {
      if (!mounted) return;
      debugPrint("PartyScreen: Received PARTY_STATE update (Reconnection)");

      setState(() {
        // Update basic properties
        isHost = data["isHost"] == true;
        partySize = data["size"] ?? partySize;
        queue = List.from(data["queue"] ?? []);
        _currentThemeIndex = data["themeIndex"] ?? _currentThemeIndex;

        // Handle playback state if changed
        final newIndex = data["currentIndex"] ?? 0;
        final newIsPlaying = data["isPlaying"] == true;
        final newStartedAt = data["startedAt"];

        // If something fundamental changed, trigger playback update logic
        if (newIndex != currentIndex || newIsPlaying != _isPlaying) {
          _onPlaybackUpdate({
            "isPlaying": newIsPlaying,
            "currentIndex": newIndex,
            "startedAt": newStartedAt,
          });
        }
      });

      if (isHost) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Reconnected as Host!")));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Reconnected to Party!")));
      }
    };

    _themeListener = (data) {
      if (!mounted) return;
      setState(() {
        _currentThemeIndex = data["themeIndex"] ?? 0;
      });
    };

    // ---- Attach Listeners ----
    widget.socket.on("PLAYBACK_UPDATE", _playbackListener);
    widget.socket.on("QUEUE_UPDATED", _queueListener);
    widget.socket.on("SYNC", _syncListener);
    widget.socket.on("ERROR", _errorListener);
    widget.socket.on("PARTY_SIZE", _partySizeListener);
    widget.socket.on("VOTE_UPDATE", _voteUpdateListener);
    widget.socket.on("REACTION", _reactionListener);
    widget.socket.on("CHAT_MESSAGE", _chatListener);
    widget.socket.on("INFO", _infoListener);
    widget.socket.on("MEMBERS_LIST", _membersListener);
    widget.socket.on("KICKED", _kickedListener);
    widget.socket.on("PARTY_STATE", _partyStateListener);
    widget.socket.on("THEME_UPDATE", _themeListener);

    // Connection Status Listeners
    widget.socket.onDisconnect((_) {
      if (mounted) setState(() => isDisconnected = true);
    });
    widget.socket.onConnect((_) {
      if (mounted) setState(() => isDisconnected = false);
    });

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
        _addSystemMessage("You are now the host!");
      }
    });
  }

  void _addSystemMessage(String text) {
    setState(() {
      messages.add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'text': text,
        'type': 'system',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      if (_tabController.index != 1) {
        _unreadMessages++;
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
          content: Text(
            isPlaying ? "Host started playing" : "Host paused playback",
          ),
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
    _controller!.addListener(() {
      if (_controller!.value.hasError) {
        _handlePlayerError(_controller!.value.errorCode.toString());
      }
    });
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

  void _leaveParty() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Leave Party"),
        content: const Text("Are you sure you want to leave?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to Home
            },
            child: const Text("Leave"),
          ),
        ],
      ),
    );
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

  void _sendMessage() {
    final text = chatCtrl.text.trim();
    if (text.isEmpty) return;

    widget.socket.emit("SEND_MESSAGE", {
      "partyId": widget.party["id"],
      "message": text,
      "username": widget.username,
    });
    chatCtrl.clear();
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
    final serverUrl = RemoteConfigService().getServerUrl();
    final link = "$serverUrl/join/${widget.party["id"]}";

    SharePlus.instance.share(
      ShareParams(
        text: "Join my music party on Sync Music! Click here: $link",
        subject: "Join Sync Music Party",
      ),
    );
  }

  void _changeTheme() {
    final nextIndex = (_currentThemeIndex + 1) % _themes.length;
    widget.socket.emit("CHANGE_THEME", {
      "partyId": widget.party["id"],
      "themeIndex": nextIndex,
    });
  }

  void _kickUser(String targetId, String username) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Kick $username?"),
        content: const Text(
          "Are you sure you want to remove this user from the party?",
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
              widget.socket.emit("KICK_USER", {
                "partyId": widget.party["id"],
                "targetId": targetId,
              });
            },
            child: const Text("Kick"),
          ),
        ],
      ),
    );
  }

  void _showMembersList() {
    debugPrint("apk: Memebers list: $membersList");
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "MEMBERS",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: membersList.isEmpty
                    ? const Center(
                        child: Text(
                          "Loading members...",
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: membersList.length,
                        itemBuilder: (context, index) {
                          final member = membersList[index];
                          final isMe = member['id'] == widget.socket.id;
                          final isMemberHost = member['isHost'] == true;

                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                member['avatar'] ?? "👤",
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                            title: Text(
                              "${member['username'] ?? 'Guest'} ${isMe ? '(You)' : ''}",
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: isMemberHost
                                ? const Text(
                                    "HOST",
                                    style: TextStyle(
                                      color: Color(0xFFBB86FC),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                            trailing: isHost && !isMemberHost
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () {
                                      Navigator.pop(
                                        context,
                                      ); // Close sheet before dialog
                                      _kickUser(
                                        member['id'],
                                        member['username'],
                                      );
                                    },
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
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
    widget.socket.off("CHAT_MESSAGE", _chatListener);
    widget.socket.off("INFO", _infoListener);
    widget.socket.off("MEMBERS_LIST", _membersListener);
    widget.socket.off("KICKED", _kickedListener);
    widget.socket.off("PARTY_STATE", _partyStateListener);
    widget.socket.off("THEME_UPDATE", _themeListener);
    widget.socket.off("PARTY_ENDED");
    widget.socket.off("HOST_UPDATE");
    _controller?.dispose();
    searchCtrl.dispose();
    chatCtrl.dispose();
    _reactionStreamCtrl.close();
    _tabController.dispose();

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

    // --- WIDGET COMPONENTS ---
    Widget header = Padding(
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
                    icon: const Icon(
                      Icons.share,
                      size: 20,
                      color: Colors.white70,
                    ),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(right: 8),
                    onPressed: _shareParty,
                  ),
                  if (isHost) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: IconButton(
                        icon: const Icon(
                          Icons.palette,
                          size: 20,
                          color: Colors.white70,
                        ),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        onPressed: _changeTheme,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: IconButton(
                        icon: const Icon(
                          Icons.qr_code,
                          size: 20,
                          color: Colors.white70,
                        ),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        onPressed: _showQRCode,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: _showMembersList,
                child: Row(
                  children: [
                    const Icon(Icons.people, size: 14, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      "$partySize Online",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isHost ? const Color(0xFFBB86FC) : const Color(0xFF03DAC6),
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
    );

    Widget player = AspectRatio(
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
                        progressIndicatorColor: Theme.of(context).primaryColor,
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
                            final now = DateTime.now().millisecondsSinceEpoch;
                            final seekMs = now - _serverStartedAt!;
                            _controller!.seekTo(Duration(milliseconds: seekMs));
                            _controller!.play();
                          }
                        },
                      ))
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.queue_music, size: 48, color: Colors.white24),
                      const SizedBox(height: 16),
                      Text(
                        isEndOfQueue ? "End of Queue" : "Queue is Empty",
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
    );

    Widget reactions = Padding(
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
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
          );
        }).toList(),
      ),
    );

    Widget controls = Column(
      children: [
        if (!isHost)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.thumbs_up_down_outlined),
                    label: Text(
                      partySize < 5
                          ? "Vote Skip (Need 5+ Users)"
                          : "Vote to Skip ($votesCount/$votesRequired)",
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: partySize < 5
                          ? Colors.grey
                          : Colors.amber,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: partySize >= 5 ? _voteSkip : null,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text("LEAVE PARTY"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.8),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _leaveParty,
                  ),
                ),
              ],
            ),
          ),
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
                      onPressed: currentIndex < queue.length - 1
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
      ],
    );

    Widget searchBar = Container(
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              filled: true,
              fillColor: Colors.black,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
    );

    Widget queueList = ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: queue.length,
      itemBuilder: (context, i) {
        final track = queue[i];
        final isCurrent = i == currentIndex;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            opacity: isCurrent ? 0.1 : 0.05,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
                ),
              ),
              subtitle: Text(
                "By ${track["addedBy"] ?? 'Unknown'}",
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
              trailing: isHost
                  ? IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.white54,
                        size: 20,
                      ),
                      onPressed: () => _removeTrack(track["id"]),
                    )
                  : null,
              onTap: isHost ? () => _changeTrack(i) : null,
            ),
          ),
        );
      },
    );

    Widget chatView = Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    "Welcome to chat, Say hi!",
                    style: TextStyle(color: Colors.white.withOpacity(0.3)),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[messages.length - 1 - index];

                    if (msg['type'] == 'system') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Center(
                          child: Text(
                            msg['text'] ?? "",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      );
                    }

                    final isMe = msg['senderId'] == widget.socket.id;
                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(context).primaryColor.withOpacity(0.8)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Text(
                                msg['username'] ?? "Guest",
                                style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            Text(
                              msg['text'] ?? "",
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: chatCtrl,
                  decoration: InputDecoration(
                    hintText: "Send a message...",
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                color: Theme.of(context).primaryColor,
                onPressed: _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      body: FloatingEmojis(
        reactionStream: _reactionStreamCtrl.stream,
        child: Container(
          decoration: BoxDecoration(gradient: _themes[_currentThemeIndex]),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // ---- TABLET / DESKTOP LAYOUT (> 600px) ----
                if (constraints.maxWidth > 600) {
                  return Column(
                    children: [
                      if (isDisconnected)
                        Container(
                          width: double.infinity,
                          color: Colors.redAccent,
                          padding: const EdgeInsets.all(4),
                          child: const Text(
                            "Disconnected from server... Reconnecting...",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      Expanded(
                        child: Row(
                          children: [
                            // LEFT COLUMN (Fixed)
                            Expanded(
                              flex: 5,
                              child: Column(
                                children: [
                                  header,
                                  Expanded(
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 500,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              player,
                                              const SizedBox(height: 12),
                                              reactions,
                                              const SizedBox(height: 12),
                                              controls,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // DIVIDER
                            Container(width: 1, color: Colors.white10),
                            // RIGHT COLUMN (Tabs)
                            Expanded(
                              flex: 4,
                              child: Column(
                                children: [
                                  TabBar(
                                    controller: _tabController,
                                    tabs: [
                                      const Tab(text: "QUEUE"),
                                      Tab(
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Text("CHAT"),
                                            if (_unreadMessages > 0) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Text(
                                                  _unreadMessages > 9
                                                      ? "9+"
                                                      : _unreadMessages
                                                            .toString(),
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                    labelColor: Colors.white,
                                    unselectedLabelColor: Colors.grey,
                                    indicatorColor: Colors.purpleAccent,
                                  ),
                                  Expanded(
                                    child: TabBarView(
                                      controller: _tabController,
                                      children: [
                                        Column(
                                          children: [
                                            Expanded(child: queueList),
                                            searchBar,
                                          ],
                                        ),
                                        chatView,
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                // ---- MOBILE LAYOUT (< 600px) ----
                return Column(
                  children: [
                    if (isDisconnected)
                      Container(
                        width: double.infinity,
                        color: Colors.redAccent,
                        padding: const EdgeInsets.all(4),
                        child: const Text(
                          "Disconnected from server... Reconnecting...",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Column(
                              children: [
                                header,
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: player,
                                ),
                                const SizedBox(height: 24),
                                reactions,
                                const SizedBox(height: 24),
                                controls,
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _SliverAppBarDelegate(
                              TabBar(
                                controller: _tabController,
                                tabs: [
                                  const Tab(text: "QUEUE"),
                                  Tab(
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Text("CHAT"),
                                        if (_unreadMessages > 0) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Text(
                                              _unreadMessages > 9
                                                  ? "9+"
                                                  : _unreadMessages.toString(),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                                labelColor: Colors.white,
                                unselectedLabelColor: Colors.grey,
                                indicatorColor: Colors.purpleAccent,
                              ),
                              // backgroundColor: const Color(0xFF1A1A1A),
                              backgroundColor: const Color(0xFF1A1A1A),
                            ),
                          ),
                          SliverFillRemaining(
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                Column(
                                  children: [
                                    Expanded(child: queueList),
                                    searchBar,
                                  ],
                                ),
                                chatView,
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Only show search bar if Queue tab is selected?
                    // Actually, let's keep it sticky at bottom for now, mainly for Queue.
                    // Ideally it should be inside Queue tab, but it was fixed at bottom.
                    // Let's put it inside the Queue tab column above.
                    // Wait, if I put it in Queue tab, it will scroll with it or stick to bottom of tab.
                    // I put it in `Column` inside TabBarView above, so it sticks to bottom of that tab.
                    // BUT, `queueList` is a ListView, so it needs `Expanded`.
                    // I fixed that in Desktop view. In Mobile view, `queueList` is just the list.
                    // The previous mobile layout had `searchBar` outside the ScrollView.

                    // For Mobile, I moved searchBar inside the Queue Tab to keep UI clean when chatting.
                  ],
                );
              },
            ),
          ),
        ),
      ),
      // ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  final Color backgroundColor;

  _SliverAppBarDelegate(this._tabBar, {required this.backgroundColor});

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: backgroundColor, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return true;
  }
}
