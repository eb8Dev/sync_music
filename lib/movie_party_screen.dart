import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/providers/socket_provider.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:sync_music/widgets/floating_emojis.dart';
import 'package:sync_music/widgets/party_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:sync_music/widgets/exit_confirmation_dialog.dart';
import 'package:sync_music/party_ended_screen.dart';
import 'package:sync_music/widgets/movie_party/movie_add_content_dialog.dart';
import 'package:sync_music/widgets/movie_party/movie_party_chat_drawer.dart';
import 'package:sync_music/widgets/movie_party/movie_party_controls.dart';
import 'package:sync_music/widgets/movie_party/movie_party_members_sheet.dart';

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
  final YouTubeService _ytService = YouTubeService();
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
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    final socket = ref.read(socketProvider);
    socket.on("REACTION", _onReactionReceived);
    socket.on("PARTY_ENDED", _onPartyEnded);
    socket.on("KICKED", _onKicked);

    _startControlsTimer();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
    _ytService.dispose();
    super.dispose();
  }

  void _showAddContentDialog() {
    _controlsTimer?.cancel();

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => MovieAddContentDialog(
        ytService: _ytService,
        onVideoSelected: (video) {
          ref.read(partyStateProvider.notifier).addTrack(widget.party["id"], {
            "url": video.url,
            "title": video.title,
            "addedBy": widget.username,
          });
          Navigator.pop(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Added ${video.title}")));
          _startControlsTimer();
        },
      ),
    ).then((_) => _startControlsTimer());
  }

  void _onReactionReceived(dynamic data) {
    if (!mounted) return;
    _reactionStreamCtrl.add(data['emoji']);
  }

  void _onPartyEnded(dynamic data) {
    if (!mounted) return;
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PartyEndedScreen(
              message: data['message'] ?? "The host has ended the party.",
            ),
          ),
        );
      }
    });
  }

  void _onKicked(dynamic data) {
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
    _startControlsTimer();
  }

  void _showMembersList() {
    _startControlsTimer();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return MoviePartyMembersSheet(partyId: widget.party['id']);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHost = ref.watch(partyProvider.select((s) => s.isHost));

    ref.listen(partyStateProvider.select((s) => s.messages.length), (
      prev,
      next,
    ) {
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
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleControls,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: PartyPlayer(
                        partyId: widget.party['id'],
                        isFullScreen: true,
                        enableControlsOverlay: false,
                      ),
                    ),
                  ),
                ),
              ),
              MoviePartyControls(
                party: widget.party,
                username: widget.username,
                showControls: _showControls,
                showChat: _showChat,
                unreadMessages: _unreadMessages,
                onToggleControls: _toggleControls,
                onToggleChat: () {
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
                onShowMembers: _showMembersList,
                onAddContent: _showAddContentDialog,
                onReaction: _sendReaction,
                onBack: () => Navigator.pop(context),
              ),
              MoviePartyChatDrawer(
                showChat: _showChat,
                partyId: widget.party['id'],
                username: widget.username,
                onClose: () => setState(() => _showChat = false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
