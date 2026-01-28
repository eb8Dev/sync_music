
import 'package:flutter/material.dart';

/// Minimal animated "now playing" dot
class PlayingDot extends StatefulWidget {
  final Color color;
  const PlayingDot({super.key, required this.color});

  @override
  State<PlayingDot> createState() => _PlayingDotState();
}

class _PlayingDotState extends State<PlayingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
