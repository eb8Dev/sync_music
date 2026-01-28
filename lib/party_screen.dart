import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/providers/socket_provider.dart';
import 'package:sync_music/widgets/neon_empty.dart';
import 'package:sync_music/widgets/neon_loader.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:sync_music/widgets/floating_emojis.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:sync_music/services/remote_config_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    // Convert error to int if possible for check
    int? errorCode = int.tryParse(error);

    String message = "Playback Error: $error. Skipping...";
    if (errorCode == 150 || errorCode == 101) {
      message = "Video restricted (Error $errorCode). Skipping...";
    } else if (errorCode == 100) {
      message = "Video not found (Error 100). Skipping...";
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );

    final isHost = ref.read(partyProvider).isHost;
    if (isHost) {
      // Skip faster for restricted videos to avoid "stuck" feeling
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && isHost) {
          ref.read(partyStateProvider.notifier).endTrack(widget.party["id"]);
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
    ref.read(socketProvider).on("REACTION", _onReactionReceived);
    ref.read(socketProvider).on("PARTY_ENDED", _onPartyEnded);
    ref.read(socketProvider).on("KICKED", _onKicked);
  }

  void _onReactionReceived(data) {
    if (mounted) {
      _reactionStreamCtrl.add(data["emoji"] ?? "❤️");
    }
  }

  void _onPartyEnded(data) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(data["message"] ?? "Party ended")));
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _onKicked(msg) async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final partyId = widget.party["id"];
    final kickKey = "kicks_$partyId";
    final kicks = prefs.getStringList(kickKey) ?? [];
    kicks.add(DateTime.now().toIso8601String());
    await prefs.setStringList(kickKey, kicks);

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

  Future<void> _addVideo(yt.Video video) async {
    setState(() => isSearching = true);
    final isPlayable = await _ytService.isVideoPlayable(video.id.value);
    setState(() => isSearching = false);

    if (!mounted) return;

    if (!isPlayable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Cannot add this video (Age Restricted or Unavailable).",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check for duplicates
    final currentQueue = ref.read(partyStateProvider).queue;
    final isDuplicate = currentQueue.any((track) {
      final trackId = YoutubePlayer.convertUrlToId(track['url']);
      return trackId == video.id.value;
    });
    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This song is already in the queue!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    ref.read(partyStateProvider.notifier).addTrack(widget.party["id"], {
      "url": video.url,
      "title": video.title,
      "addedBy": widget.username,
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
        text:
            "Join my music party on Sync Music! use CODE: ${widget.party["id"]}.\nOr You can directly click on this $link here to join.",
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
    final socket = ref.read(socketProvider);
    socket.off("REACTION", _onReactionReceived);
    socket.off("PARTY_ENDED", _onPartyEnded);
    socket.off("KICKED", _onKicked);

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
    Widget statusChip() {
      final connected = !partyState.isDisconnected;
      final bgColor = isHost
          ? const Color(0xFF8CFC86)
          : const Color(0xFF03DAC6);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? Colors.green : Colors.red,
                boxShadow: connected
                    ? [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
            ),
            Text(
              isHost ? "HOST" : "GUEST",
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    // --- RE-USED WIDGETS ---
    Widget header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Party ID + Copy
          InkWell(
            onTap: _copyCode,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Text(
                  "🎵 ${widget.party["id"]}",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.copy, size: 14, color: Colors.white70),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Members
          GestureDetector(
            onTap: _showMembersList,
            child: Row(
              children: [
                const Icon(Icons.people, size: 14, color: Colors.white70),
                const SizedBox(width: 4),
                Text(
                  "${partyState.partySize}",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Actions
          Row(
            children: [
              IconButton(
                tooltip: "Share",
                icon: const Icon(Icons.share, size: 20),
                onPressed: _shareParty,
              ),
              if (isHost)
                IconButton(
                  tooltip: "Theme",
                  icon: const Icon(Icons.palette, size: 20),
                  onPressed: _changeTheme,
                ),
              if (isHost)
                IconButton(
                  tooltip: "QR Code",
                  icon: const Icon(Icons.qr_code, size: 20),
                  onPressed: _showQRCode,
                ),

              const SizedBox(width: 6),

              // Connection + Role Chip
              statusChip(),
            ],
          ),
        ],
      ),
    );

    Widget player = AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Background Glow Layer
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0A0F1F), Color(0xFF120A2A)],
                ),
              ),
            ),

            // Glass Blur Layer
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.35),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),

            // Content Layer
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: showPlayer
                  ? (_controller == null
                        ? const NeonLoader()
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: YoutubePlayer(
                              key: const ValueKey("player"),
                              controller: _controller!,
                              showVideoProgressIndicator: true,
                              progressIndicatorColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              onEnded: (_) {
                                if (isHost &&
                                    _lastEndedIndex !=
                                        partyState.currentIndex) {
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
                                  final now =
                                      DateTime.now().millisecondsSinceEpoch;

                                  if (state.startedAt != null &&
                                      now > state.startedAt!) {
                                    startSeconds =
                                        (now - state.startedAt!) ~/ 1000;
                                  }

                                  _controller!.seekTo(
                                    Duration(seconds: startSeconds),
                                  );
                                  _controller!.play();
                                }
                              },
                            ),
                          ))
                  : NeonEmptyState(isEndOfQueue: isEndOfQueue),
            ),
          ],
        ),
      ),
    );

    Widget reactions = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: ["🔥", "❤️", "🎉", "😂", "👋", "💃"].map((emoji) {
          return InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => _sendReaction(emoji),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          );
        }).toList(),
      ),
    );

    Widget guestControls(BuildContext context) {
      final canVote = partyState.partySize >= 5;
      final votes = partyState.votesCount;
      final required = partyState.votesRequired;

      final progress = required > 0 ? (votes / required).clamp(0.0, 1.0) : 0.0;

      Color barColor;
      if (!canVote) {
        barColor = Colors.grey;
      } else if (progress >= 1.0) {
        barColor = Colors.greenAccent;
      } else {
        barColor = Colors.amber;
      }

      return Row(
        children: [
          // Vote Section
          Expanded(
            child: InkWell(
              onTap: canVote ? _voteSkip : null,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Vote to Skip",
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),

                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: 6,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: progress),
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) {
                            return LinearProgressIndicator(
                              value: value,
                              backgroundColor: Colors.white12,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                barColor,
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      canVote
                          ? "$votes / $required votes"
                          : "Need 5+ users (Now: ${partyState.partySize})",
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Leave Button
          IconButton(
            tooltip: "Leave Party",
            icon: const Icon(Icons.exit_to_app),
            color: Colors.redAccent,
            onPressed: _leaveParty,
          ),
        ],
      );
    }

    Widget hostControls(BuildContext context) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: "Previous",
            icon: const Icon(Icons.skip_previous),
            iconSize: 34,
            onPressed: partyState.currentIndex > 0 ? _prevTrack : null,
          ),

          IconButton(
            tooltip: partyState.isPlaying ? "Pause" : "Play",
            iconSize: 52,
            icon: Icon(
              partyState.isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
            ),
            color: Theme.of(context).primaryColor,
            onPressed: partyState.isPlaying ? _pause : _resyncPlay,
          ),

          IconButton(
            tooltip: "Next",
            icon: const Icon(Icons.skip_next),
            iconSize: 34,
            onPressed: partyState.currentIndex < partyState.queue.length - 1
                ? _nextTrack
                : null,
          ),

          // End Party
          IconButton(
            tooltip: "End Party",
            icon: const Icon(Icons.stop_circle),
            color: Colors.redAccent,
            onPressed: _endParty,
          ),
        ],
      );
    }

    Widget controls = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          // color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: isHost ? hostControls(context) : guestControls(context),
      ),
    );

    Widget searchBar = Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: Colors.transparent,
      child: Column(
        children: [
          // ---- SEARCH RESULTS / EMPTY STATE ----
          if (searchCtrl.text.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
              ),
              child: searchResults.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          "No videos found",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.4),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: searchResults.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.white.withOpacity(0.05),
                      ),
                      itemBuilder: (_, i) {
                        final video = searchResults[i];
                        return InkWell(
                          onTap: () => _addVideo(video),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                // Thumbnail
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    video.thumbnails.lowResUrl,
                                    width: 36,
                                    height: 36,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Title
                                Expanded(
                                  child: Text(
                                    video.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

          // ---- SEARCH INPUT ----
          TextField(
            controller: searchCtrl,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Search YouTube",
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 12,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: Colors.white.withOpacity(0.4),
                size: 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
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
        final theme = Theme.of(context);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            opacity: isCurrent ? 0.12 : 0.06,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),

              // Leading: subtle playing indicator or index
              leading: isCurrent
                  ? Icon(
                      Icons.equalizer_rounded,
                      color: theme.primaryColor,
                      size: 18,
                    )
                  : Text(
                      "${i + 1}",
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

              // Title
              title: Text(
                track["title"],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                  color: isCurrent ? Colors.white : Colors.white70,
                ),
              ),

              // Subtitle
              subtitle: Text(
                "Added by ${track["addedBy"] ?? 'Unknown'}",
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  letterSpacing: 0.3,
                ),
              ),

              // Trailing action
              trailing: isHost
                  ? IconButton(
                      splashRadius: 18,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.white54,
                        size: 18,
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
                    "Welcome to chat — say hi 👋",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  itemCount: partyState.messages.length,
                  itemBuilder: (context, index) {
                    final msg = partyState
                        .messages[partyState.messages.length - 1 - index];

                    // ---- SYSTEM MESSAGE ----
                    if (msg['type'] == 'system') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              msg['text'] ?? "",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.45),
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    final isMe = msg['senderId'] == socket.id;
                    final theme = Theme.of(context);

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? theme.primaryColor.withOpacity(0.85)
                              : Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: Radius.circular(isMe ? 12 : 2),
                            bottomRight: Radius.circular(isMe ? 2 : 12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Username (only for others)
                            if (!isMe)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  msg['username'] ?? "Guest",
                                  style: TextStyle(
                                    color: theme.primaryColor.withOpacity(0.9),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),

                            // Message text
                            Text(
                              msg['text'] ?? "",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // ---- INPUT BAR ----
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: chatCtrl,
                  decoration: InputDecoration(
                    hintText: "Send a message…",
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                splashRadius: 20,
                icon: const Icon(Icons.send_rounded),
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
                                  // ---- TAB BAR ----
                                  TabBar(
                                    controller: _tabController,
                                    overlayColor: WidgetStateProperty.all(
                                      Colors.transparent,
                                    ),
                                    indicatorSize: TabBarIndicatorSize.label,
                                    indicatorWeight: 2,
                                    indicatorColor: Theme.of(
                                      context,
                                    ).primaryColor.withOpacity(0.9),
                                    labelColor: Colors.white,
                                    unselectedLabelColor: Colors.white
                                        .withOpacity(0.45),
                                    labelStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.6,
                                    ),
                                    unselectedLabelStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.4,
                                    ),
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
                                              AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .primaryColor
                                                      .withOpacity(0.9),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Text(
                                                  _unreadMessages > 9
                                                      ? "9+"
                                                      : _unreadMessages
                                                            .toString(),
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 6),

                                  // ---- TAB CONTENT ----
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

                // ---- MOBILE LAYOUT (REFINED) ----
                return Column(
                  children: [
                    // ---- CONNECTION STATUS BANNER ----
                    if (partyState.isDisconnected)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.9),
                        ),
                        child: const Text(
                          "Reconnecting…",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            letterSpacing: 0.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                    // ---- FIXED HEADER ----
                    header,

                    // ---- COLLAPSIBLE PLAYER ----
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: isKeyboardOpen ? 0 : 1,
                        child: SizedBox(
                          height: isKeyboardOpen ? 0 : null,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: player,
                              ),
                              const SizedBox(height: 10),
                              reactions,
                              const SizedBox(height: 10),
                              controls,
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ---- TABS ----
                    TabBar(
                      controller: _tabController,
                      overlayColor: MaterialStateProperty.all(
                        Colors.transparent,
                      ),
                      indicatorSize: TabBarIndicatorSize.label,
                      indicatorWeight: 2,
                      indicatorColor: Theme.of(
                        context,
                      ).primaryColor.withOpacity(0.9),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white.withOpacity(0.45),
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                      ),
                      tabs: [
                        const Tab(text: "QUEUE"),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("CHAT"),
                              if (_unreadMessages > 0) ...[
                                const SizedBox(width: 6),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).primaryColor.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _unreadMessages > 9
                                        ? "9+"
                                        : _unreadMessages.toString(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // ---- TAB CONTENT ----
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
