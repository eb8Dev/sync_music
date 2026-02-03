import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/providers/socket_provider.dart';
import 'package:sync_music/widgets/floating_emojis.dart';
import 'package:sync_music/widgets/party_chat.dart';
import 'package:sync_music/widgets/party_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:sync_music/widgets/exit_confirmation_dialog.dart';

class MoviePartyScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> party;
  final String username;

  const MoviePartyScreen({
    super.key,
    required this.party,
    required this.username,
  });

  @override
  ConsumerState<MoviePartyScreen> createState() => _MoviePartyScreenState();
}

class _MoviePartyScreenState extends ConsumerState<MoviePartyScreen> {
  bool _showControls = true;
  Timer? _controlsTimer;
  bool _showChat = false;
  int _unreadMessages = 0;
  bool _canPop = false;
  
  final StreamController<String> _reactionStreamCtrl =
      StreamController<String>.broadcast();

  @override
  void initState() {
    super.initState();
    // Force Landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    // Listeners
    final socket = ref.read(socketProvider);
    socket.on("REACTION", _onReactionReceived);
    socket.on("PARTY_ENDED", _onPartyEnded);
    socket.on("KICKED", _onKicked);

    _startControlsTimer();
  }

  @override
  void dispose() {
    // Revert to Portrait
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    WakelockPlus.disable();

    final socket = ref.read(socketProvider);
    socket.off("REACTION", _onReactionReceived);
    socket.off("PARTY_ENDED", _onPartyEnded);
    socket.off("KICKED", _onKicked);

    _reactionStreamCtrl.close();
    _controlsTimer?.cancel();
    super.dispose();
  }

  void _onReactionReceived(data) {
    if (!mounted) return;
    _reactionStreamCtrl.add(data['emoji']);
  }

  void _onPartyEnded(data) {
    if (!mounted) return;
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(data['message'] ?? "Party Ended")));
      }
    });
  }

  void _onKicked(data) {
    if (!mounted) return;
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You have been kicked from the party.")),
        );
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) _startControlsTimer();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_showChat) {
        setState(() => _showControls = false);
      }
    });
  }

  void _sendReaction(String emoji) {
    ref
        .read(partyStateProvider.notifier)
        .sendReaction(widget.party["id"], emoji);
    _reactionStreamCtrl.add(emoji);
    _startControlsTimer(); // Keep controls alive
  }

  void _seek(int seconds) {
     final state = ref.read(partyStateProvider);
     if (!state.isPlaying || state.startedAt == null) return; // Only seek while playing for now

     final now = DateTime.now().millisecondsSinceEpoch;
     final currentPos = (now - state.startedAt!) ~/ 1000;
     final newPos = (currentPos + seconds).clamp(0, 99999); // Clamp to positive
     
     ref.read(partyStateProvider.notifier).seek(widget.party["id"], newPos);
     _startControlsTimer();
  }

  void _showMembersList() {
    _startControlsTimer(); // Reset timer
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Align(
          alignment: Alignment.centerLeft, // Show as side drawer in landscape
          child: Container(
            width: 300,
            margin: const EdgeInsets.only(top: 20, bottom: 20, left: 20),
            decoration: BoxDecoration(
                color: const Color(0xFF121212).withValues(alpha:0.95),
                borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(24.0),
            child: Consumer(
              builder: (context, ref, _) {
                final members = ref.watch(
                  partyStateProvider.select((s) => s.members),
                );
                final isHost = ref.watch(partyProvider.select((s) => s.isHost));
                final socket = ref.read(socketProvider);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white))
                        ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: members.isEmpty
                          ? const Center(
                              child: Text(
                                "Loading...",
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
                                  contentPadding: EdgeInsets.zero,
                                  leading: Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: const BoxDecoration(
                                      color: Colors.white10,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      member['avatar'] ?? "👤",
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
                                  title: Text(
                                    "${member['username'] ?? 'Guest'} ${isMe ? '(You)' : ''}",
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
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
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            Navigator.pop(context);
                                            ref
                                                .read(partyStateProvider.notifier)
                                                .kickUser(
                                                  widget.party['id'],
                                                  member['id'],
                                                );
                                          },
                                        )
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHost = ref.watch(partyProvider.select((s) => s.isHost));
    final partySize = ref.watch(partyStateProvider.select((s) => s.partySize));
    final isPlaying = ref.watch(partyStateProvider.select((s) => s.isPlaying));
    final queue = ref.watch(partyStateProvider.select((s) => s.queue));

    // Listen for unread messages
    ref.listen(partyStateProvider.select((s) => s.messages.length), (prev, next) {
        if (!_showChat && (next > (prev ?? 0))) {
            setState(() => _unreadMessages += (next - (prev ?? 0)));
        }
    });

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await showExitConfirmationDialog(context, isHost);
        if (shouldLeave == true) {
           if (mounted) {
              setState(() => _canPop = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) Navigator.of(context).pop();
              });
           }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: FloatingEmojis(
        reactionStream: _reactionStreamCtrl.stream,
        child: Stack(
          children: [
            // 1. VIDEO LAYER (Full Screen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleControls,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: PartyPlayer(
                      partyId: widget.party['id'],
                      isFullScreen: true,
                    ),
                  ),
                ),
              ),
            ),

            // 2. CONTROLS OVERLAY
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _showControls ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black54,
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black87,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Stack(
                      children: [
                        // TOP BAR
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.party["name"] ?? "Movie Party",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                                ),
                              ),
                              const Spacer(),
                              
                              // Members Button
                              IconButton(
                                  onPressed: _showMembersList,
                                  icon: Row(
                                      children: [
                                          const Icon(Icons.people, color: Colors.white, size: 20),
                                          const SizedBox(width: 4),
                                          Text("$partySize", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                      ],
                                  ),
                              ),

                              const SizedBox(width: 8),

                              // Host End Button
                              if (isHost)
                                IconButton(
                                  icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent),
                                  onPressed: () {
                                     _startControlsTimer();
                                     showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: const Color(0xFF1E1E1E),
                                          title: const Text("End Party?", style: TextStyle(color: Colors.white)),
                                          content: const Text("Terminate the session for everyone?", style: TextStyle(color: Colors.white70)),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                                            TextButton(
                                                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                                onPressed: () {
                                                    Navigator.pop(context);
                                                    ref.read(partyStateProvider.notifier).endParty(widget.party['id']);
                                                }, 
                                                child: const Text("End Party")
                                            ),
                                          ],
                                        ),
                                      );
                                  },
                                ),
                            ],
                          ),
                        ),
                        
                        // CENTER CONTROLS (Host Only)
                        if (isHost && queue.isNotEmpty)
                            Center(
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                        IconButton(
                                            iconSize: 48,
                                            onPressed: () => _seek(-5),
                                            icon: const Icon(Icons.replay_5_rounded, color: Colors.white),
                                        ),
                                        const SizedBox(width: 24),
                                        IconButton(
                                            iconSize: 80,
                                            onPressed: () {
                                                final notifier = ref.read(partyStateProvider.notifier);
                                                if (isPlaying) {
                                                    notifier.pause(widget.party['id']);
                                                } else {
                                                    notifier.play(widget.party['id']);
                                                }
                                                _startControlsTimer();
                                            },
                                            icon: Icon(
                                                isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, 
                                                color: Colors.white,
                                                shadows: [BoxShadow(color: Theme.of(context).primaryColor, blurRadius: 20)],
                                            ),
                                        ),
                                        const SizedBox(width: 24),
                                        IconButton(
                                            iconSize: 48,
                                            onPressed: () => _seek(5),
                                            icon: const Icon(Icons.forward_5_rounded, color: Colors.white),
                                        ),
                                    ],
                                ),
                            ),

                        // CENTER - ADD VIDEO PROMPT (If empty)
                        if (queue.isEmpty && isHost)
                           Center(
                             child: ElevatedButton.icon(
                               onPressed: () {
                                 ScaffoldMessenger.of(context).showSnackBar(
                                   const SnackBar(content: Text("Use the standard party mode to add videos for now!")),
                                 );
                               }, 
                               icon: const Icon(Icons.add),
                               label: const Text("Add Movie"),
                             ),
                           ),

                        // BOTTOM BAR
                        Positioned(
                          bottom: 24,
                          left: 24,
                          right: 24,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // REACTIONS
                              ...["🔥", "😂", "😱", "😢", "👏"].map(
                                (e) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: GestureDetector(
                                    onTap: () => _sendReaction(e),
                                    child: Text(
                                      e,
                                      style: const TextStyle(fontSize: 32),
                                    ),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              // CHAT TOGGLE
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                    IconButton(
                                        icon: Icon(
                                        _showChat
                                            ? Icons.chat_bubble
                                            : Icons.chat_bubble_outline,
                                        color: Colors.white,
                                        ),
                                        onPressed: () {
                                            setState(() {
                                                _showChat = !_showChat;
                                                if (_showChat) _unreadMessages = 0;
                                            });
                                            if (_showChat) {
                                                _controlsTimer?.cancel(); 
                                            } else {
                                                _startControlsTimer();
                                            }
                                        },
                                    ),
                                    if (_unreadMessages > 0)
                                        Positioned(
                                            right: 8,
                                            top: 8,
                                            child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(
                                                    color: Colors.redAccent,
                                                    shape: BoxShape.circle,
                                                ),
                                                child: Text(
                                                    _unreadMessages > 9 ? "!" : "$_unreadMessages",
                                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                            ),
                                        ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 3. CHAT DRAWER (Right Side)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              top: 0,
              bottom: 0,
              right: _showChat ? 0 : -350,
              width: 350,
              child: Container(
                color: Colors.black.withValues(alpha:0.85),
                child: SafeArea(
                  child: Column(
                    children: [
                       Row(
                         children: [
                           IconButton(
                             icon: const Icon(Icons.close, color: Colors.white),
                             onPressed: () => setState(() => _showChat = false),
                           ),
                           const Text("Chat", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                         ],
                       ),
                       Expanded(
                         child: PartyChat(
                            partyId: widget.party['id'],
                            username: widget.username,
                         ),
                       ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}