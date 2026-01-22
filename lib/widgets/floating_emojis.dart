import 'dart:math';
import 'package:flutter/material.dart';

class FloatingEmojis extends StatefulWidget {
  final Stream<String> reactionStream;
  final Widget child;

  const FloatingEmojis({
    super.key,
    required this.reactionStream,
    required this.child,
  });

  @override
  State<FloatingEmojis> createState() => _FloatingEmojisState();
}

class _FloatingEmojisState extends State<FloatingEmojis> with TickerProviderStateMixin {
  final List<_FloatingEmoji> _emojis = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    widget.reactionStream.listen(_addEmoji);
  }

  void _addEmoji(String emoji) {
    if (!mounted) return;
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    final animation = Tween<double>(begin: 0, end: 1).animate(controller);
    
    final entry = _FloatingEmoji(
      id: DateTime.now().millisecondsSinceEpoch.toString() + _random.nextInt(1000).toString(),
      emoji: emoji,
      controller: controller,
      animation: animation,
      xStart: _random.nextDouble() * 0.8 + 0.1, // 10% to 90% width
      size: _random.nextDouble() * 20 + 30, // 30 to 50 size
    );

    setState(() {
      _emojis.add(entry);
    });

    controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _emojis.removeWhere((e) => e.id == entry.id);
        });
        controller.dispose();
      }
    });
  }

  @override
  void dispose() {
    for (var e in _emojis) {
      e.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        ..._emojis.map((e) {
          return AnimatedBuilder(
            animation: e.animation,
            builder: (context, child) {
              return Positioned(
                left: MediaQuery.of(context).size.width * e.xStart,
                bottom: 100 + (MediaQuery.of(context).size.height * 0.6 * e.animation.value),
                child: Opacity(
                  opacity: 1.0 - e.animation.value, // Fade out
                  child: Transform.translate(
                    offset: Offset(
                      sin(e.animation.value * 10) * 20, // Wiggle
                      0,
                    ),
                    child: Text(
                      e.emoji,
                      style: TextStyle(fontSize: e.size),
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}

class _FloatingEmoji {
  final String id;
  final String emoji;
  final AnimationController controller;
  final Animation<double> animation;
  final double xStart;
  final double size;

  _FloatingEmoji({
    required this.id,
    required this.emoji,
    required this.controller,
    required this.animation,
    required this.xStart,
    required this.size,
  });
}
