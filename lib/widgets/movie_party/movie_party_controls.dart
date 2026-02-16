import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sync_music/services/remote_config_service.dart';
import 'package:sync_music/widgets/generate_party_image.dart';

class MoviePartyControls extends ConsumerWidget {
  final Map<String, dynamic> party;
  final String username;
  final bool showControls;
  final bool showChat;
  final int unreadMessages;
  final VoidCallback onToggleControls;
  final VoidCallback onToggleChat;
  final VoidCallback onShowMembers;
  final VoidCallback onAddContent;
  final Function(String) onReaction;
  final VoidCallback onBack;

  const MoviePartyControls({
    super.key,
    required this.party,
    required this.username,
    required this.showControls,
    required this.showChat,
    required this.unreadMessages,
    required this.onToggleControls,
    required this.onToggleChat,
    required this.onShowMembers,
    required this.onAddContent,
    required this.onReaction,
    required this.onBack,
  });

  void _shareParty() async {
    final serverUrl = RemoteConfigService().getServerUrl();
    final partyCode = party["id"];
    final link = "$serverUrl/join/$partyCode";

    final imageFile = await generatePartyImage(partyCode);

    final params = ShareParams(
      files: [XFile(imageFile.path)],
      text:
          "Join my movie party on Sync Music! Use CODE: $partyCode.\nOr click on this link: $link to join.",
      title: "Join Sync Music Party",
    );

    await SharePlus.instance.share(params);
  }

  void _endParty(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151922),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      FontAwesomeIcons.powerOff,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    "End Party?",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                "This will kick all members and close the party. Are you sure you want to end the session?",
                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  ref.read(partyStateProvider.notifier).endParty(party['id']);
                },
                child: const Text(
                  "END PARTY NOW",
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Keep Party Alive",
                  style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _seek(WidgetRef ref, int seconds) {
    final state = ref.read(partyStateProvider);
    if (!state.isPlaying || state.startedAt == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final currentPos = (now - state.startedAt!) ~/ 1000;
    final newPos = (currentPos + seconds).clamp(0, 99999);

    ref.read(partyStateProvider.notifier).seek(party["id"], newPos);
    onToggleControls();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHost = ref.watch(partyProvider.select((s) => s.isHost));
    final partySize = ref.watch(partyStateProvider.select((s) => s.partySize));
    final isPlaying = ref.watch(partyStateProvider.select((s) => s.isPlaying));
    final queue = ref.watch(partyStateProvider.select((s) => s.queue));

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: showControls ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !showControls,
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
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          FontAwesomeIcons.chevronLeft,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: onBack,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        party["name"] ?? "Movie Party",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          shadows: [
                            Shadow(
                              blurRadius: 10,
                              color: Colors.black,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          FontAwesomeIcons.shareFromSquare,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: _shareParty,
                      ),
                      if (isHost)
                        IconButton(
                          icon: const Icon(
                            FontAwesomeIcons.plus,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: onAddContent,
                        ),
                      IconButton(
                        onPressed: onShowMembers,
                        icon: Row(
                          children: [
                            const Icon(
                              FontAwesomeIcons.users,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "$partySize",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isHost)
                        IconButton(
                          icon: const Icon(
                            FontAwesomeIcons.powerOff,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          onPressed: () => _endParty(context, ref),
                        ),
                    ],
                  ),
                ),
                if (isHost && queue.isNotEmpty)
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _seek(ref, -5),
                          icon: const Icon(
                            FontAwesomeIcons.rotateLeft,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 24),
                        IconButton(
                          onPressed: () {
                            final notifier = ref.read(
                              partyStateProvider.notifier,
                            );
                            if (isPlaying) {
                              notifier.pause(party['id']);
                            } else {
                              notifier.play(party['id']);
                            }
                            onToggleControls();
                          },
                          icon: Icon(
                            isPlaying
                                ? FontAwesomeIcons.circlePause
                                : FontAwesomeIcons.circlePlay,
                            color: Colors.white,
                            size: 64,
                            shadows: [
                              BoxShadow(
                                color: Theme.of(context).primaryColor,
                                blurRadius: 20,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        IconButton(
                          onPressed: () => _seek(ref, 5),
                          icon: const Icon(
                            FontAwesomeIcons.rotateRight,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (queue.isEmpty && isHost)
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: onAddContent,
                      icon: const Icon(
                        FontAwesomeIcons.plus,
                        size: 16,
                      ),
                      label: const Text("Add Movie"),
                    ),
                  ),
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ...["🔥", "😂", "😱", "😢", "👏"].map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          child: GestureDetector(
                            onTap: () => onReaction(e),
                            child: Text(
                              e,
                              style: const TextStyle(fontSize: 32),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            icon: Icon(
                              showChat
                                  ? FontAwesomeIcons.solidComment
                                  : FontAwesomeIcons.comment,
                              color: Colors.white,
                              size: 24,
                            ),
                            onPressed: onToggleChat,
                          ),
                          if (unreadMessages > 0)
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
                                  unreadMessages > 9 ? "!" : "$unreadMessages",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
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
    );
  }
}
