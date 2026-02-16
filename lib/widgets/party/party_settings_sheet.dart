import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/theme/party_themes.dart';

class PartySettingsSheet extends ConsumerWidget {
  final String partyId;

  const PartySettingsSheet({super.key, required this.partyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(partyStateProvider.select((s) => s.settings));
    final themeIndex = ref.watch(partyStateProvider.select((s) => s.themeIndex));

    void update(String key, bool value) {
      final newSettings = Map<String, bool>.from(settings);
      newSettings[key] = value;
      ref.read(partyStateProvider.notifier).updateSettings(partyId, newSettings);
    }

    void applyPreset(String type) {
      Map<String, bool> newSettings = {};
      if (type == 'host') {
        newSettings = {
          "guestControls": false,
          "guestQueueing": false,
          "voteSkip": false,
        };
      } else if (type == 'guest') {
        newSettings = {
          "guestControls": false,
          "guestQueueing": true,
          "voteSkip": true,
        };
      } else if (type == 'collab') {
        newSettings = {
          "guestControls": true,
          "guestQueueing": true,
          "voteSkip": false,
        };
      }
      ref.read(partyStateProvider.notifier).updateSettings(partyId, newSettings);
    }

    return Container(
      padding: const EdgeInsets.all(24.0),
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Party Settings",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),

          // ---- PRESETS ----
          const Text(
            "PRESETS",
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PresetCard(
                  icon: FontAwesomeIcons.shieldHalved,
                  label: "Host Mode",
                  color: Colors.redAccent,
                  onTap: () => applyPreset('host'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PresetCard(
                  icon: FontAwesomeIcons.checkToSlot,
                  label: "Guest Mode",
                  color: Colors.blueAccent,
                  onTap: () => applyPreset('guest'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PresetCard(
                  icon: FontAwesomeIcons.handshake,
                  label: "Collab",
                  color: Colors.greenAccent,
                  onTap: () => applyPreset('collab'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // ---- CONTROLS ----
          const Text(
            "PERMISSIONS",
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          _SwitchTile(
            label: "Guest Controls",
            subtitle: "Allow guests to Play, Pause & Seek",
            value: settings["guestControls"] ?? false,
            onChanged: (v) => update("guestControls", v),
          ),
          _SwitchTile(
            label: "Guest Queueing",
            subtitle: "Allow guests to add songs",
            value: settings["guestQueueing"] ?? true,
            onChanged: (v) => update("guestQueueing", v),
          ),
          _SwitchTile(
            label: "Voting to Skip",
            subtitle: "Enable vote-to-skip system",
            value: settings["voteSkip"] ?? true,
            onChanged: (v) => update("voteSkip", v),
          ),

          const SizedBox(height: 32),

          // ---- THEME ----
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "THEME",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              Text(
                "Current: #${themeIndex + 1}",
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: PartyThemes.gradients.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final isSelected = themeIndex == index;
                return GestureDetector(
                  onTap: () {
                    ref.read(partyStateProvider.notifier).changeTheme(partyId);
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: PartyThemes.gradients[index],
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                    ),
                    child: isSelected
                        ? const Icon(
                            FontAwesomeIcons.check,
                            color: Colors.white,
                            size: 18,
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PresetCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Theme.of(context).primaryColor,
            activeTrackColor: Theme.of(context).primaryColor.withValues(alpha: 0.3),
            inactiveThumbColor: Colors.grey,
            inactiveTrackColor: Colors.grey.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }
}
