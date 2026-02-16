import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sync_music/services/remote_config_service.dart';
import 'package:sync_music/widgets/generate_party_image.dart';
import 'package:sync_music/widgets/party/party_end_sheet.dart';
import 'package:sync_music/widgets/party/party_leave_sheet.dart';
import 'package:sync_music/widgets/party/party_members_sheet.dart';
import 'package:sync_music/widgets/party/party_qr_sheet.dart';
import 'package:sync_music/widgets/party/party_settings_sheet.dart';

class PartyHeader extends StatelessWidget {
  final String partyId;
  final int partySize;
  final bool isHost;
  final bool isDisconnected;

  const PartyHeader({
    super.key,
    required this.partyId,
    required this.partySize,
    required this.isHost,
    required this.isDisconnected,
  });

  void _shareParty() async {
    final serverUrl = RemoteConfigService().getServerUrl();
    final link = "$serverUrl/join/$partyId";

    // Generate the image
    final imageFile = await generatePartyImage(partyId);

    // Prepare ShareParams
    final params = ShareParams(
      files: [XFile(imageFile.path)],
      text:
          "Join my music party on Sync Music! Use CODE: $partyId.\nOr click on this link: $link to join.",
      title: "Join Sync Music Party",
    );

    // Share
    await SharePlus.instance.share(params);
  }

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: partyId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Party Code Copied!"),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PartySettingsSheet(partyId: partyId),
    );
  }

  void _showQRCode(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => PartyQRSheet(partyId: partyId),
    );
  }

  void _showMembersList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => PartyMembersSheet(partyId: partyId),
    );
  }

  void _leaveParty(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const PartyLeaveSheet(),
    );
  }

  void _endParty(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => PartyEndSheet(partyId: partyId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Party Code & Connection
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isDisconnected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 8,
                        height: 8,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        "Reconnecting...",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              GestureDetector(
                onTap: () => _copyCode(context),
                child: Row(
                  children: [
                    Text(
                      partyId,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      FontAwesomeIcons.copy,
                      size: 14,
                      color: Colors.white.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showMembersList(context),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        FontAwesomeIcons.users,
                        size: 12,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "$partySize active",
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Actions
          Row(
            children: [
              _HeaderIconButton(
                icon: FontAwesomeIcons.shareFromSquare,
                onTap: _shareParty,
              ),
              const SizedBox(width: 8),
              if (isHost) ...[
                _HeaderIconButton(
                  icon: FontAwesomeIcons.gear,
                  onTap: () => _showSettings(context),
                ),
                const SizedBox(width: 8),
                _HeaderIconButton(
                  icon: FontAwesomeIcons.qrcode,
                  onTap: () => _showQRCode(context),
                ),
                const SizedBox(width: 8),
                _HeaderIconButton(
                  icon: FontAwesomeIcons.powerOff,
                  onTap: () => _endParty(context),
                  color: Colors.redAccent,
                ),
              ] else ...[
                _HeaderIconButton(
                  icon: FontAwesomeIcons.qrcode,
                  onTap: () => _showQRCode(context),
                ),
                const SizedBox(width: 8),
                _HeaderIconButton(
                  icon: FontAwesomeIcons.rightFromBracket,
                  onTap: () => _leaveParty(context),
                  color: Colors.redAccent,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: color ?? Colors.white),
      ),
    );
  }
}
