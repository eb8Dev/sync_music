import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';

class PartyControls extends ConsumerWidget {
  final String partyId;
  final VoidCallback onLeave;

  const PartyControls({
    super.key,
    required this.partyId,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHost = ref.watch(partyProvider.select((s) => s.isHost));
    
    // We pass context to split functions to keep build clean
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: isHost 
            ? const _HostControls() 
            : _GuestControls(partyId: partyId, onLeave: onLeave),
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
    final currentIndex = ref.watch(partyStateProvider.select((s) => s.currentIndex));
    final queueLen = ref.watch(partyStateProvider.select((s) => s.queue.length));
    
    final notifier = ref.read(partyStateProvider.notifier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ControlButton(
          icon: Icons.skip_previous_rounded,
          onTap: currentIndex > 0 
              ? () => notifier.changeTrack(partyId, currentIndex - 1) 
              : null,
        ),

        _ControlButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          isPrimary: true,
          size: 64,
          iconSize: 32,
          onTap: () {
             if (isPlaying) {
               notifier.pause(partyId);
             } else {
               notifier.play(partyId);
             }
          },
        ),

        _ControlButton(
          icon: Icons.skip_next_rounded,
          onTap: currentIndex < queueLen - 1
              ? () => notifier.changeTrack(partyId, currentIndex + 1)
              : null,
        ),

        _ControlButton(
          icon: Icons.power_settings_new_rounded,
          isDestructive: true,
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E),
                title: const Text("End Party?", style: TextStyle(color: Colors.white)),
                content: const Text(
                  "This will kick all members and close the party. Are you sure?",
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel"),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                    onPressed: () {
                      Navigator.pop(context);
                      notifier.endParty(partyId);
                    },
                    child: const Text("End Party"),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _GuestControls extends ConsumerWidget {
  final String partyId;
  final VoidCallback onLeave;

  const _GuestControls({required this.partyId, required this.onLeave});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partySize = ref.watch(partyStateProvider.select((s) => s.partySize));
    final votes = ref.watch(partyStateProvider.select((s) => s.votesCount));
    final required = ref.watch(partyStateProvider.select((s) => s.votesRequired));
    
    final notifier = ref.read(partyStateProvider.notifier);

    final canVote = partySize >= 5;
    final progress = required > 0 ? (votes / required).clamp(0.0, 1.0) : 0.0;

    Color barColor;
    if (!canVote) {
      barColor = Colors.grey;
    } else if (progress >= 1.0) {
      barColor = const Color(0xFF00D2FF); // Cyan
    } else {
      barColor = const Color(0xFFFF2E63); // Hot Pink
    }

    return Row(
      children: [
        // Vote Section
        Expanded(
          child: InkWell(
            onTap: canVote ? () => notifier.voteSkip(partyId) : null,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Vote to Skip",
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        canVote ? "$votes/$required" : "5+ users needed",
                        style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 4,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Leave Button
        _ControlButton(
          icon: Icons.logout_rounded,
          isDestructive: true,
          onTap: onLeave,
        ),
      ],
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
    this.isDestructive = false,
    this.size = 48,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDisabled = onTap == null;

    Color bgColor = Colors.white.withOpacity(0.08);
    Color iconColor = Colors.white;

    if (isPrimary) {
      bgColor = theme.primaryColor;
      iconColor = Colors.white;
    } else if (isDestructive) {
      bgColor = const Color(0xFF2C0404); // Deep Red
      iconColor = const Color(0xFFFF2E63); // Hot Pink
    } else if (isDisabled) {
      bgColor = Colors.white.withOpacity(0.02);
      iconColor = Colors.white24;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: isDestructive ? Border.all(color: iconColor.withOpacity(0.3)) : null,
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Icon(icon, size: iconSize, color: iconColor),
      ),
    );
  }
}
