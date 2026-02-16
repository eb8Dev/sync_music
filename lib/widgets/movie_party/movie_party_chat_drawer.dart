import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sync_music/widgets/party_chat.dart';

class MoviePartyChatDrawer extends StatelessWidget {
  final bool showChat;
  final String partyId;
  final String username;
  final VoidCallback onClose;

  const MoviePartyChatDrawer({
    super.key,
    required this.showChat,
    required this.partyId,
    required this.username,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      top: 0,
      bottom: 0,
      right: showChat ? 0 : -350,
      width: 350,
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      FontAwesomeIcons.xmark,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: onClose,
                  ),
                  const Text(
                    "Chat",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: PartyChat(
                  partyId: partyId,
                  username: username,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
