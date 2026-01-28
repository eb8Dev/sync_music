import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sync_music/services/support_service.dart';
import 'package:sync_music/support_screen.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final SupportService _supportService = SupportService();

  String _version = "—";
  String _packageName = "—";
  String _installer = "—";
  int _tapCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    final info = await PackageInfo.fromPlatform();

    setState(() {
      _version = "${info.version} (${info.buildNumber})";
      _packageName = info.packageName;
      _installer = info.installerStore?.isNotEmpty == true
          ? info.installerStore!
          : "Unknown / APK";
    });
  }

  Future<void> _launchLegalUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint("Could not launch $url");
    }
  }

  void _handleRateUs(BuildContext context) {
    Navigator.pop(context);

    // Delay avoids "noContextOrActivity"
    Future.delayed(const Duration(milliseconds: 500), () {
      _supportService.requestReview();
    });
  }

  void _onVersionTap() {
    _tapCount++;
    if (_tapCount >= 7) {
      _tapCount = 0;
      _showDebugSheet();
    }
  }

  void _showDebugSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: GlassCard(
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "DEBUG INFO",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _DebugRow("Package", _packageName),
                  _DebugRow("Version", _version),
                  _DebugRow("Installer", _installer),
                  _DebugRow(
                    "Build Mode",
                    kReleaseMode
                        ? "Release"
                        : kProfileMode
                        ? "Profile"
                        : "Debug",
                  ),
                  _DebugRow(
                    "Platform",
                    "${Platform.operatingSystem} ${Platform.operatingSystemVersion}",
                  ),

                  const SizedBox(height: 16),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Close"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassCard(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- HEADER ----
              const Text(
                "SETTINGS & SUPPORT",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),

              const SizedBox(height: 24),

              // ---- SUPPORT ----
              _SettingsTile(
                icon: Icons.support_agent,
                title: "Contact Support",
                subtitle: "Report bugs or request features",
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SupportScreen()),
                  );
                },
              ),

              const SizedBox(height: 16),

              _SettingsTile(
                icon: Icons.star_rate_rounded,
                title: "Rate Us",
                subtitle: "Love the app? Let us know!",
                onTap: () => _handleRateUs(context),
              ),

              const SizedBox(height: 24),

              // ---- LEGAL ----
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "LEGAL",
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              _SettingsTile(
                icon: Icons.description_outlined,
                title: "Terms of Service",
                subtitle: "Read our terms",
                onTap: () => _launchLegalUrl(
                  "https://sites.google.com/view/termsofservice-syncmusic/home",
                ),
              ),

              const SizedBox(height: 8),

              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: "Privacy Policy",
                subtitle: "How we use your data",
                onTap: () => _launchLegalUrl(
                  "https://sites.google.com/view/privacypolicy-syncmusic/home",
                ),
              ),

              const SizedBox(height: 24),

              // ---- VERSION (TAP 7x) ----
              GestureDetector(
                onTap: _onVersionTap,
                child: Text(
                  "Version $_version",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 12,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).primaryColor, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withOpacity(0.3),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------

class _DebugRow extends StatelessWidget {
  final String label;
  final String value;

  const _DebugRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
