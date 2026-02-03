import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sync_music/services/support_service.dart';
import 'package:sync_music/support_screen.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  void _handleRateUs() {
    _supportService.openStoreListing();
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("SETTINGS"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, -0.6),
            radius: 1.8,
            colors: [
              Color(0xFF1A1F35), // Deep Midnight
              Color(0xFF0B0E14), // Almost Black
            ],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              const Text(
                "SUPPORT",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              
              _SettingsTile(
                icon: Icons.support_agent,
                title: "Contact Support",
                subtitle: "Report bugs or request features",
                onTap: () {
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
                onTap: _handleRateUs,
              ),

              const SizedBox(height: 32),

              const Text(
                "LEGAL",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
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

              const SizedBox(height: 40),

              // ---- VERSION (TAP 7x) ----
              Center(
                child: GestureDetector(
                  onTap: _onVersionTap,
                  child: Text(
                    "Version $_version",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha:0.3),
                      fontSize: 12,
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha:0.08)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Theme.of(context).primaryColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha:0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white.withValues(alpha:0.2),
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
                color: Colors.white.withValues(alpha:0.5),
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
