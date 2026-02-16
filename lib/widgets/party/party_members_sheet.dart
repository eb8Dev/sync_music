import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/providers/socket_provider.dart';

class PartyMembersSheet extends ConsumerWidget {
  final String partyId;

  const PartyMembersSheet({super.key, required this.partyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(partyStateProvider.select((s) => s.members));
    final isHost = ref.watch(partyProvider.select((s) => s.isHost));
    final socket = ref.read(socketProvider);

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
          Flexible(
            child: members.isEmpty
                ? const Center(
                    child: Text(
                      "Loading members...",
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
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
    );
  }
}
