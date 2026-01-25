import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/providers/socket_provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:sync_music/widgets/floating_emojis.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:sync_music/services/remote_config_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:share_plus/share_plus.dart';

class PartyScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> party;
  final String username;

  const PartyScreen({super.key, required this.party, required this.username});

  @override
  ConsumerState<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends ConsumerState<PartyScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final YouTubeService _ytService = YouTubeService();
  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController chatCtrl = TextEditingController();
  Timer? _debounce;
  List<yt.Video> searchResults = [];
  bool isSearching = false;

  YoutubePlayerController? _controller;
  late TabController _tabController;
  int _unreadMessages = 0;
  int? _lastEndedIndex;

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

  void _handlePlayerError(String error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Playback Error: $error. Skipping..."),
        backgroundColor: Colors.red,
      ),
    );

    final isHost = ref.read(partyProvider).isHost;
    if (isHost) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && isHost) {
          ref.read(partyStateProvider.notifier).endTrack(widget.party["id"]);
          // Wait, I need to add endTrack to notifier or emit directly.
          // Let's emit directly for this specific case if I didn't add it.
          // Or add it to notifier.
        }
      });
    }
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.party["id"]));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Party Code Copied!")));
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

    final partyState = ref.read(partyStateProvider);
    if (partyState.isPlaying &&
        partyState.queue.isNotEmpty &&
        partyState.currentIndex < partyState.queue.length) {
      _initPlayer(partyState);
    }

    // Listen for reactions directly from socket since it's a stream-like event
    ref.read(socketProvider).on("REACTION", (data) {
      if (mounted) {
        _reactionStreamCtrl.add(data["emoji"] ?? "❤️");
      }
    });

    ref.read(socketProvider).on("PARTY_ENDED", (data) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(data["message"] ?? "Party ended")));
      Navigator.of(context).popUntil((route) => route.isFirst);
    });

    ref.read(socketProvider).on("KICKED", (msg) {
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
    });
  }

  void _initPlayer(DetailedPartyState state) {
    final videoId = YoutubePlayer.convertUrlToId(
      state.queue[state.currentIndex]["url"],
    );
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
      _controller!.addListener(() {
        if (_controller!.value.hasError) {
          _handlePlayerError(_controller!.value.errorCode.toString());
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final partyState = ref.read(partyStateProvider);
    if (state == AppLifecycleState.resumed) {
      if (partyState.isPlaying &&
          _controller != null &&
          !_controller!.value.isPlaying) {
        _controller!.play();
      }
    }
  }

  void _onPlaybackStateChanged(
    DetailedPartyState? previous,
    DetailedPartyState next,
  ) {
    if (!mounted) return;

    if (!next.isPlaying) {
      _controller?.pause();
      return;
    }

    if (next.queue.isEmpty || next.currentIndex >= next.queue.length) return;

    bool trackChanged =
        (previous == null || next.currentIndex != previous.currentIndex);
    final videoId = YoutubePlayer.convertUrlToId(
      next.queue[next.currentIndex]["url"],
    );
    if (videoId == null) return;

    if (_controller != null) {
      if (trackChanged) {
        int startSeconds = 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (next.startedAt != null && now > next.startedAt!) {
          startSeconds = (now - next.startedAt!) ~/ 1000;
        }
        _controller!.load(videoId, startAt: startSeconds);
      } else {
        // Sync logic
        final now = DateTime.now().millisecondsSinceEpoch;
        if (next.startedAt != null) {
          final seekMs = now - next.startedAt!;
          final localPos = _controller!.value.position.inMilliseconds;
          if ((localPos - seekMs).abs() > 2000) {
            _controller!.seekTo(Duration(milliseconds: seekMs));
          }
        }
        if (!_controller!.value.isPlaying) _controller!.play();
      }
    } else {
      _initPlayer(next);
      setState(() {}); // Rebuild to show player
    }
  }

  // ---------------- ACTIONS ----------------
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
    ref.read(partyStateProvider.notifier).addTrack(widget.party["id"], {
      "url": video.url,
      "title": video.title,
      "addedBy": widget.username,
    });
    searchCtrl.clear();
    setState(() => searchResults = []);
    FocusScope.of(context).unfocus();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Added '${video.title}' to queue"),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
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
              Navigator.pop(context);
              Navigator.pop(context);
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
              ref
                  .read(partyStateProvider.notifier)
                  .endParty(widget.party["id"]);
            },
            child: const Text("End Party"),
          ),
        ],
      ),
    );
  }

  void _pause() =>
      ref.read(partyStateProvider.notifier).pause(widget.party["id"]);
  void _resyncPlay() =>
      ref.read(partyStateProvider.notifier).play(widget.party["id"]);
  void _changeTrack(int index) => ref
      .read(partyStateProvider.notifier)
      .changeTrack(widget.party["id"], index);
  void _prevTrack() =>
      _changeTrack(ref.read(partyStateProvider).currentIndex - 1);
  void _nextTrack() =>
      _changeTrack(ref.read(partyStateProvider).currentIndex + 1);
  void _removeTrack(String trackId) => ref
      .read(partyStateProvider.notifier)
      .removeTrack(widget.party["id"], trackId);
  void _voteSkip() =>
      ref.read(partyStateProvider.notifier).voteSkip(widget.party["id"]);
  void _sendReaction(String emoji) => ref
      .read(partyStateProvider.notifier)
      .sendReaction(widget.party["id"], emoji);

  void _sendMessage() {
    final text = chatCtrl.text.trim();
    if (text.isEmpty) return;
    ref
        .read(partyStateProvider.notifier)
        .sendMessage(widget.party["id"], text, widget.username);
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

  void _changeTheme() =>
      ref.read(partyStateProvider.notifier).changeTheme(widget.party["id"]);
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
              ref
                  .read(partyStateProvider.notifier)
                  .kickUser(widget.party["id"], targetId);
            },
            child: const Text("Kick"),
          ),
        ],
      ),
    );
  }

  void _showMembersList() {
    final members = ref.read(partyStateProvider).members;
    final socket = ref.read(socketProvider);
    final isHost = ref.read(partyProvider).isHost;

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
                child: members.isEmpty
                    ? const Center(
                        child: Text(
                          "Loading members...",
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final member = members[index];
                          final isMe = member['id'] == socket.id;
                          final isMemberHost = member['isHost'] == true;
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
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
                                      Navigator.pop(context);
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
    _controller?.dispose();
    searchCtrl.dispose();
    chatCtrl.dispose();
    _reactionStreamCtrl.close();
    _tabController.dispose();
    _ytService.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final partyState = ref.watch(partyStateProvider);
    final partyMeta = ref.watch(partyProvider);
    final isHost = partyMeta.isHost;
    final socket = ref.watch(socketProvider);

    ref.listen(partyStateProvider, (previous, next) {
      _onPlaybackStateChanged(previous, next);

      // Update unread messages if chat tab is not active
      if (next.messages.length > (previous?.messages.length ?? 0)) {
        if (_tabController.index != 1) {
          setState(
            () => _unreadMessages +=
                (next.messages.length - (previous?.messages.length ?? 0)),
          );
        }
      }
    });

    final bool isEndOfQueue =
        partyState.currentIndex >= partyState.queue.length &&
        partyState.queue.isNotEmpty;
    final bool isEmptyQueue = partyState.queue.isEmpty;
    final bool showPlayer = !isEmptyQueue && !isEndOfQueue;

    // --- RE-USED WIDGETS ---
    Widget header = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: _copyCode,
                child: Row(
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
                    const SizedBox(width: 8),
                    const Icon(Icons.copy, size: 16),
                  ],
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
                    IconButton(
                      icon: const Icon(
                        Icons.palette,
                        size: 20,
                        color: Colors.white70,
                      ),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.only(right: 8),
                      onPressed: _changeTheme,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.qr_code,
                        size: 20,
                        color: Colors.white70,
                      ),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.only(right: 8),
                      onPressed: _showQRCode,
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
                      "${partyState.partySize} Online",
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
          Row(
            children: [
               // Connection Status Dot
               Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: partyState.isDisconnected ? Colors.red : Colors.green,
                  boxShadow: [
                    if (!partyState.isDisconnected)
                      BoxShadow(
                        color: Colors.green.withOpacity(0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                  ],
                ),
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
                    ? const Center(child: CircularProgressIndicator())
                    : YoutubePlayer(
                        controller: _controller!,
                        showVideoProgressIndicator: true,
                        progressIndicatorColor: Theme.of(context).primaryColor,
                        onEnded: (_) {
                          if (isHost &&
                              _lastEndedIndex != partyState.currentIndex) {
                            _lastEndedIndex = partyState.currentIndex;
                            ref
                                .read(partyStateProvider.notifier)
                                .endTrack(widget.party["id"]);
                          }
                        },
                        onReady: () {
                          final state = ref.read(partyStateProvider);
                          if (state.isPlaying) {
                            int startSeconds = 0;
                            final now = DateTime.now().millisecondsSinceEpoch;
                            if (state.startedAt != null &&
                                now > state.startedAt!) {
                              startSeconds = (now - state.startedAt!) ~/ 1000;
                            }
                            _controller!.seekTo(
                              Duration(seconds: startSeconds),
                            );
                            _controller!.play();
                          }
                        },
                      ))
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.queue_music,
                        size: 48,
                        color: Colors.white24,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isEndOfQueue ? "End of Queue" : "Queue is Empty",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Add songs to continue the party!",
                        style: TextStyle(color: Colors.white38),
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
              decoration: const BoxDecoration(
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
                      partyState.partySize < 5
                          ? "Need 5+ Users to Vote (Current: ${partyState.partySize})"
                          : "Vote to Skip (${partyState.votesCount}/${partyState.votesRequired} from ${partyState.partySize})",
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: partyState.partySize < 5
                          ? Colors.grey
                          : Colors.amber,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: partyState.partySize >= 5 ? _voteSkip : null,
                  ),
                ),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text("LEAVE PARTY"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.4),
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
                      onPressed: partyState.currentIndex > 0
                          ? _prevTrack
                          : null,
                    ),
                    IconButton(
                      iconSize: 56,
                      icon: Icon(
                        partyState.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                      ),
                      color: Theme.of(context).primaryColor,
                      onPressed: partyState.isPlaying ? _pause : _resyncPlay,
                    ),
                    IconButton(
                      iconSize: 42,
                      icon: const Icon(Icons.skip_next),
                      color: Colors.white,
                      onPressed:
                          partyState.currentIndex < partyState.queue.length - 1
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
      // color: const Color(0xFF1E1E1E),
      color: Colors.transparent,
      child: Column(
        children: [
          if (searchResults.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.transparent,
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

            TextField(
            controller: searchCtrl,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Search YouTube songs",
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.white10,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );

    Widget queueList = ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      itemCount: partyState.queue.length,
      itemBuilder: (context, i) {
        final track = partyState.queue[i];
        final isCurrent = i == partyState.currentIndex;
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
          child: partyState.messages.isEmpty
              ? Center(
                  child: Text(
                    "Welcome to chat, Say hi!",
                    style: TextStyle(color: Colors.white.withOpacity(0.3)),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: partyState.messages.length,
                  itemBuilder: (context, index) {
                    final msg = partyState
                        .messages[partyState.messages.length - 1 - index];
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
                    final isMe = msg['senderId'] == socket.id;
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

    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      body: FloatingEmojis(
        reactionStream: _reactionStreamCtrl.stream,
        child: Container(
          decoration: BoxDecoration(gradient: _themes[partyState.themeIndex]),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Desktop / Tablet Layout
                if (constraints.maxWidth > 600) {
                  return Column(
                    children: [
                      if (partyState.isDisconnected)
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
                            Container(width: 1, color: Colors.white10),
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

                // Mobile Layout (Reactive)
                return Column(
                  children: [
                    if (partyState.isDisconnected)
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
                    
                    // Fixed Header (Always visible)
                    header,

                    // Collapsible Player & Controls
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: SizedBox(
                        height: isKeyboardOpen ? 0 : null,
                        child: SingleChildScrollView(
                           physics: const NeverScrollableScrollPhysics(),
                           child: Column(
                              children: [
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
                      ),
                    ),

                    // Tabs (Always visible)
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
                        unselectedLabelColor: Theme.of(
                          context,
                        ).disabledColor,
                        indicatorColor: Theme.of(context).primaryColor,
                      ),
                    
                    // Expanded Tab View (Takes remaining space)
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
// Remove _SliverAppBarDelegate as it is no longer used

