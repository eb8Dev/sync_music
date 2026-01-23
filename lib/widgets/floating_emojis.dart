import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class FloatingEmojis extends StatelessWidget {
  final Stream<String> reactionStream;
  final Widget child;

  const FloatingEmojis({
    super.key,
    required this.reactionStream,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The main content - static relative to the animation
        child,
        // The overlay - completely decoupled and ignores touches
        Positioned.fill(
          child: IgnorePointer(
            child: _EmojiOverlay(reactionStream: reactionStream),
          ),
        ),
      ],
    );
  }
}

class _EmojiOverlay extends StatefulWidget {
  final Stream<String> reactionStream;

  const _EmojiOverlay({required this.reactionStream});

  @override
  State<_EmojiOverlay> createState() => _EmojiOverlayState();
}

class _EmojiOverlayState extends State<_EmojiOverlay> with SingleTickerProviderStateMixin {
  final List<Particle> _particles = [];
  late Ticker _ticker;
  final Random _random = Random();
  double _lastTime = 0;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _subscription = widget.reactionStream.listen(_addEmoji);
  }

  void _addEmoji(String emoji) {
    if (!mounted) return;
    
    // Start slightly below the visible area (1.1 height)
    // Randomize X position
    final particle = Particle(
      emoji: emoji,
      x: _random.nextDouble(), 
      y: 1.1, 
      size: _random.nextDouble() * 20 + 30, // 30-50 size
      speed: _random.nextDouble() * 0.3 + 0.2, // 0.2 - 0.5 screen height per sec
      wobbleOffset: _random.nextDouble() * 2 * pi,
    );

    _particles.add(particle);

    if (!_ticker.isActive) {
      _lastTime = 0;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final double currentTime = elapsed.inMilliseconds / 1000.0;
    final double dt = _lastTime == 0 ? 0.016 : currentTime - _lastTime;
    _lastTime = currentTime;

    if (_particles.isEmpty) {
      _ticker.stop();
      return;
    }

    setState(() {
      _particles.removeWhere((p) {
        p.update(dt);
        // Remove when it goes well above the screen (-0.2)
        return p.y < -0.2;
      });
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only repaint this widget, nothing else
    if (_particles.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: CustomPaint(
        painter: _EmojiPainter(_particles),
      ),
    );
  }
}

class Particle {
  String emoji;
  double x; // 0.0 to 1.0 (relative to width)
  double y; // 1.1 to -0.2 (relative to height)
  double size;
  double speed;
  double wobbleOffset;
  double timeAlive = 0;
  TextPainter? _textPainter;

  Particle({
    required this.emoji,
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.wobbleOffset,
  });

  void update(double dt) {
    timeAlive += dt;
    y -= speed * dt;
  }

  TextPainter getPainter() {
    if (_textPainter == null) {
      _textPainter = TextPainter(
        text: TextSpan(
          text: emoji,
          style: TextStyle(fontSize: size),
        ),
        textDirection: TextDirection.ltr,
      );
      _textPainter!.layout();
    }
    return _textPainter!;
  }
}

class _EmojiPainter extends CustomPainter {
  final List<Particle> particles;

  _EmojiPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final painter = p.getPainter();
      
      // Calculate positions
      final wobble = sin(p.timeAlive * 3 + p.wobbleOffset) * 20;
      final dx = p.x * size.width + wobble;
      final dy = p.y * size.height;

      canvas.save();
      canvas.translate(dx, dy);

      // Fade out effect using Scale instead of Opacity (cheaper)
      // Start scaling down when it reaches top 20% of screen
      if (p.y < 0.2) {
        final scale = (p.y + 0.2) / 0.4; // Map -0.2..0.2 to 0..1
        final clampedScale = scale.clamp(0.0, 1.0);
        canvas.scale(clampedScale);
      }

      // Draw centered
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_EmojiPainter oldDelegate) => true;
}
