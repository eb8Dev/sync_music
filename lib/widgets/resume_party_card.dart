import 'dart:ui';
import 'package:flutter/material.dart';

class ResumePartyCard extends StatefulWidget {
  final String partyId;
  final bool isHost;
  final VoidCallback onHostRejoin;
  final VoidCallback onGuestRejoin;
  final VoidCallback onDismiss;

  const ResumePartyCard({
    super.key,
    required this.partyId,
    required this.isHost,
    required this.onHostRejoin,
    required this.onGuestRejoin,
    required this.onDismiss,
  });

  @override
  State<ResumePartyCard> createState() => _ResumePartyCardState();
}

class _ResumePartyCardState extends State<ResumePartyCard> with SingleTickerProviderStateMixin {
  bool _disabled = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // Creates a breathing/pulsing effect for the icon
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _run(VoidCallback action) {
    if (_disabled) return;
    setState(() => _disabled = true);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _disabled ? 0.6 : 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Stack(
            children: [
              // Gradient Border & Background Container
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  // Subtle gradient to simulate light hitting glass
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0.04),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // Animated Icon
                        _PulsingIcon(
                          controller: _pulseController,
                          icon: Icons.history_rounded,
                          color: accentColor,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "SESSION FOUND",
                                style: TextStyle(
                                  color: accentColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Resume Party #${widget.partyId}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            hoverColor: Colors.white.withValues(alpha: 0.1),
                          ),
                          icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                          onPressed: _disabled ? null : widget.onDismiss,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        if (widget.isHost) ...[
                          Expanded(
                            child: _BouncyButton(
                              label: "HOST",
                              icon: Icons.admin_panel_settings_outlined,
                              onTap: () => _run(widget.onHostRejoin),
                              isPrimary: true,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: _BouncyButton(
                            label: "JOIN",
                            icon: Icons.login_rounded,
                            onTap: () => _run(widget.onGuestRejoin),
                            isPrimary: !widget.isHost,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Decorative "Shine" on top border
              Positioned(
                top: 0,
                left: 20,
                right: 20,
                height: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.5),
                        Colors.transparent,
                      ],
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

class _PulsingIcon extends StatelessWidget {
  final AnimationController controller;
  final IconData icon;
  final Color color;

  const _PulsingIcon({
    required this.controller,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3 * controller.value),
                blurRadius: 12 + (8 * controller.value),
                spreadRadius: 2 * controller.value,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

class _BouncyButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool isPrimary;
  final Color color;

  const _BouncyButton({
    required this.label,
    this.icon,
    required this.onTap,
    required this.isPrimary,
    required this.color,
  });

  @override
  State<_BouncyButton> createState() => _BouncyButtonState();
}

class _BouncyButtonState extends State<_BouncyButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: widget.isPrimary
                ? LinearGradient(
                    colors: [widget.color, widget.color.withValues(alpha: 0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: widget.isPrimary ? null : Colors.white.withValues(alpha: 0.08),
            border: widget.isPrimary
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: widget.isPrimary
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 18,
                  color: widget.isPrimary ? Colors.black87 : Colors.white,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.isPrimary ? Colors.black87 : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}