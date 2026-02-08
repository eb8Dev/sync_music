import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/widgets/custom_snackbar.dart';

class PartyControls extends ConsumerWidget {
  final String partyId;
  final bool enableDecoration;

  const PartyControls({
    super.key,
    required this.partyId,
    this.enableDecoration = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHost = ref.watch(partyProvider.select((s) => s.isHost));
    final settings = ref.watch(partyStateProvider.select((s) => s.settings));
    final guestControls = settings["guestControls"] == true;

    final content = (isHost || guestControls)
        ? const _HostControls()
        : _GuestControls(partyId: partyId);

    if (!enableDecoration) {
      return content;
    }

    // We pass context to split functions to keep build clean
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: content,
      ),
    );
  }
}

class _HostControls extends ConsumerWidget {
  const _HostControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partyId = ref.watch(partyProvider.select((s) => s.partyId))!;
    final isPlaying = ref.watch(partyStateProvider.select((s) => s.isPlaying));
    final currentIndex = ref.watch(
      partyStateProvider.select((s) => s.currentIndex),
    );
    final queueLen = ref.watch(
      partyStateProvider.select((s) => s.queue.length),
    );

    final notifier = ref.read(partyStateProvider.notifier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlButton(
          icon: FontAwesomeIcons.backwardStep,
          onTap: currentIndex > 0
              ? () => notifier.changeTrack(partyId, currentIndex - 1)
              : null,
        ),
        const SizedBox(width: 24),
        _ControlButton(
          icon: isPlaying ? FontAwesomeIcons.pause : FontAwesomeIcons.play,
          isPrimary: true,
          size: 64,
          iconSize: 28,
          onTap: () {
            if (isPlaying) {
              notifier.pause(partyId);
            } else {
              notifier.play(partyId);
            }
          },
        ),
        const SizedBox(width: 24),
        _ControlButton(
          icon: FontAwesomeIcons.forwardStep,
          onTap: currentIndex < queueLen - 1
              ? () => notifier.changeTrack(partyId, currentIndex + 1)
              : null,
        ),
      ],
    );
  }
}


class _GuestControls extends ConsumerWidget {
  final String partyId;

  const _GuestControls({required this.partyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partySize = ref.watch(partyStateProvider.select((s) => s.partySize));
    final votes = ref.watch(partyStateProvider.select((s) => s.votesCount));
    final required = ref.watch(
      partyStateProvider.select((s) => s.votesRequired),
    );
    final settings = ref.watch(partyStateProvider.select((s) => s.settings));
    final voteSkipEnabled = settings["voteSkip"] == true;

    final notifier = ref.read(partyStateProvider.notifier);

    // If disabled by host, block voting completely
    final canVote = partySize >= 5 && voteSkipEnabled;
    final progress = required > 0 ? (votes / required).clamp(0.0, 1.0) : 0.0;

    Color barColor;
    if (!voteSkipEnabled) {
      barColor = Colors.grey.withValues(alpha: 0.3);
    } else if (!canVote) {
      barColor = Colors.grey;
    } else if (progress >= 1.0) {
      barColor = const Color(0xFF00D2FF); // Cyan
    } else {
      barColor = const Color(0xFFFF2E63); // Hot Pink
    }

    return Center(
      child: InkWell(
        onTap: (canVote && voteSkipEnabled)
            ? () => notifier.voteSkip(partyId)
            : () {
                if (!voteSkipEnabled) {
                  CustomSnackbar.show(
                    context,
                    "Voting is disabled by the host.",
                    isError: true,
                  );
                }
              },
        borderRadius: BorderRadius.circular(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: 200,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),

                // 🧊 Frosted glass fill
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.06),
                  ],
                ),

                // Glass edge highlight
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 0.8,
                ),

                // 🌈 Local glow (does not affect other UIs)
                boxShadow: [
                  BoxShadow(
                    color: barColor.withValues(
                      alpha: (canVote && voteSkipEnabled) ? 0.45 : 0.2,
                    ),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        !voteSkipEnabled ? "Voting Disabled" : "Vote to Skip",
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: const [
                                Shadow(blurRadius: 6, color: Colors.black54),
                              ],
                            ),
                      ),
                      Text(
                        !voteSkipEnabled
                            ? "Host Locked"
                            : (canVote
                                  ? "$votes/$required"
                                  : "5+ users needed"),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        // Frosted track
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.25),
                            Colors.white.withValues(alpha: 0.08),
                          ],
                        ),
                      ),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.transparent, // important
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool isDestructive;
  final double size;
  final double iconSize;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
    // ignore: unused_element_parameter
    this.isDestructive = false,
    this.size = 48,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDisabled = onTap == null;

    Color accentColor = Colors.white;
    Color glowColor = Colors.transparent;

    if (isPrimary) {
      accentColor = theme.primaryColor;
      glowColor = theme.primaryColor;
    } else if (isDestructive) {
      accentColor = const Color(0xFFFF2E63); // Hot Pink
      glowColor = accentColor;
    } else if (isDisabled) {
      accentColor = Colors.white24;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),

              // 🧊 Glass fill (instead of flat bgColor)
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: isDisabled ? 0.06 : 0.16),
                  Colors.white.withValues(alpha: isDisabled ? 0.03 : 0.08),
                ],
              ),

              // Glass edge
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 0.8,
              ),

              // 🌈 Glow / depth
              boxShadow: [
                if (!isDisabled && (isPrimary || isDestructive))
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: iconSize, color: accentColor),
          ),
        ),
      ),
    );
  }
}
