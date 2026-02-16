import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/providers/socket_provider.dart';
import 'package:sync_music/widgets/floating_emojis.dart';
import 'package:sync_music/widgets/party_chat.dart';
import 'package:sync_music/widgets/party_lyrics.dart';
import 'package:sync_music/widgets/party_player.dart';
import 'package:sync_music/widgets/party_queue.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:sync_music/widgets/exit_confirmation_dialog.dart';
import 'package:sync_music/party_ended_screen.dart';
import 'package:sync_music/party_kicked_screen.dart';
import 'package:sync_music/theme/party_themes.dart';
import 'package:sync_music/widgets/party/party_header.dart';
import 'package:sync_music/widgets/party/party_reactions.dart';
import 'package:sync_music/widgets/party/party_bottom_nav.dart';
import 'package:sync_music/widgets/party/party_search_bar.dart';

class PartyScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> party;
  final String username;

  const PartyScreen({super.key, required this.party, required this.username});

  @override
  ConsumerState<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends ConsumerState<PartyScreen> {
  final YouTubeService _ytService = YouTubeService();
  final GlobalKey<PartyPlayerState> _playerKey = GlobalKey<PartyPlayerState>();

  bool _canPop = false;
  int _selectedIndex = 0;
  int _unreadMessages = 0;

  final StreamController<String> _reactionStreamCtrl =
      StreamController<String>.broadcast();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    // Subscribe to reactions
    final socket = ref.read(socketProvider);
    socket.on("REACTION", _onReactionReceived);
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (_selectedIndex == 2) {
        _unreadMessages = 0;
      }
    });
  }

  void _onReactionReceived(dynamic data) {
    if (!mounted) return;
    _reactionStreamCtrl.add(data['emoji']);
  }

  @override
  void dispose() {
    final socket = ref.read(socketProvider);
    socket.off("REACTION", _onReactionReceived);

    WakelockPlus.disable();
    _reactionStreamCtrl.close();
    _ytService.dispose();
    super.dispose();
  }

  void _sendReaction(String emoji) {
    ref
        .read(partyStateProvider.notifier)
        .sendReaction(widget.party["id"], emoji);
    _reactionStreamCtrl.add(emoji);
  }

  @override
  Widget build(BuildContext context) {
    final themeIndex = ref.watch(partyStateProvider.select((s) => s.themeIndex));
    final isDisconnected = ref.watch(partyStateProvider.select((s) => s.isDisconnected));
    final partySize = ref.watch(partyStateProvider.select((s) => s.partySize));
    final isHost = ref.watch(partyProvider.select((s) => s.isHost));

    ref.listen(partyStateProvider.select((s) => s.messages.length), (prev, next) {
      if (_selectedIndex != 2) {
        final diff = next - (prev ?? 0);
        if (diff > 0) {
          setState(() => _unreadMessages += diff);
        }
      }
    });

    ref.listen(partyProvider.select((s) => s.isPartyEnded), (prev, ended) {
      if (ended) {
        setState(() => _canPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final message = ref.read(partyProvider).endMessage;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => PartyEndedScreen(
                message: message ?? "The host has ended the party.",
              ),
            ),
          );
        });
      }
    });

    ref.listen(partyProvider.select((s) => s.isKicked), (prev, kicked) {
      if (kicked) {
        setState(() => _canPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const PartyKickedScreen()),
          );
        });
      }
    });

    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await showExitConfirmationDialog(context, isHost);
        if (shouldLeave == true) {
          setState(() => _canPop = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pop();
          });
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: FloatingEmojis(
          reactionStream: _reactionStreamCtrl.stream,
          child: RepaintBoundary(
            child: Container(
              decoration: BoxDecoration(gradient: PartyThemes.gradients[themeIndex]),
              child: SafeArea(
                child: Column(
                  children: [
                    PartyHeader(
                      partyId: widget.party["id"],
                      partySize: partySize,
                      isHost: isHost,
                      isDisconnected: isDisconnected,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: PartyPlayer(
                        key: _playerKey,
                        partyId: widget.party['id'],
                      ),
                    ),
                    const SizedBox(height: 10),
                    PartyReactions(onReaction: _sendReaction),
                    const SizedBox(height: 12),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          _KeepAliveWrapper(
                            child: Column(
                              children: [
                                Expanded(child: PartyQueue(partyId: widget.party['id'])),
                                PartySearchBar(partyId: widget.party['id'], username: widget.username),
                              ],
                            ),
                          ),
                          const _KeepAliveWrapper(child: PartyLyrics()),
                          _KeepAliveWrapper(
                            child: PartyChat(
                              partyId: widget.party['id'],
                              username: widget.username,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isKeyboardOpen)
                      PartyBottomNav(
                        selectedIndex: _selectedIndex,
                        unreadMessages: _unreadMessages,
                        onItemSelected: _onItemTapped,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const _KeepAliveWrapper({required this.child});

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}
