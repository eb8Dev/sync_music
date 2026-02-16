import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/providers/socket_provider.dart';

class MoviePartyMembersSheet extends ConsumerWidget {
  final String partyId;

  const MoviePartyMembersSheet({super.key, required this.partyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(partyStateProvider.select((s) => s.members));
    final isHost = ref.watch(partyProvider.select((s) => s.isHost));
    final socket = ref.read(socketProvider);

    return Align(
      alignment: Alignment.centerLeft, // Show as side drawer in landscape
      child: Container(
        width: 300,
        margin: const EdgeInsets.only(top: 20, bottom: 20, left: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF121212).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(24.0),
        child: Column(
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
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    FontAwesomeIcons.xmark,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
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
                                    FontAwesomeIcons.circleMinus,
                                    color: Colors.redAccent,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    ref.read(partyStateProvider.notifier).kickUser(
                                          partyId,
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
        ),
      ),
    );
  }
}
