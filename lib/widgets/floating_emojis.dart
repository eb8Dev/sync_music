import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
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
        RepaintBoundary(child: child),
        Positioned.fill(
          child: IgnorePointer(
            child: FloatingEmojiOverlay(reactionStream: reactionStream),
          ),
        ),
      ],
    );
  }
}

class FloatingEmojiOverlay extends StatefulWidget {
  final Stream<String> reactionStream;

  const FloatingEmojiOverlay({super.key, required this.reactionStream});

  @override
  State<FloatingEmojiOverlay> createState() =>
      _FloatingEmojiOverlayState();
}

class _FloatingEmojiOverlayState extends State<FloatingEmojiOverlay>
    with SingleTickerProviderStateMixin {
  late ParticleController _controller;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _controller = ParticleController(this)
      ..speedFactor = 1.5 // 🔥 change this anytime (1.0 = normal)
      ..maxParticles = 80;
    _subscription =
        widget.reactionStream.listen(_controller.addEmoji);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _EmojiPainter(_controller),
        willChange: true,
      ),
    );
  }
}

// ------------------------------------------------------------

class ParticleController extends ChangeNotifier {
  final List<Particle> particles = [];
  final TickerProvider vsync;
  late final Ticker _ticker;
  final Random _random = Random();

  // ---- TUNABLES ----
  double speedFactor = 1.0; // Global vertical speed
  double wobbleSpeed = 4.0; // Horizontal motion speed
  double wobbleAmount = 18.0; // Horizontal motion distance
  int maxParticles = 60;

  double _lastTime = 0;

  // Cache for pre-rendered emoji images
  final Map<String, ui.Image> _imageCache = {};

  ParticleController(this.vsync) {
    _ticker = vsync.createTicker(_onTick);
  }

  Future<void> addEmoji(String emoji) async {
    // Limit particles for performance
    if (particles.length >= maxParticles) {
      particles.removeAt(0);
    }

    // Get or create cached image
    ui.Image? image = _imageCache[emoji];
    if (image == null) {
      try {
        image = await _renderEmojiToImage(emoji);
        _imageCache[emoji] = image;
      } catch (_) {
        return;
      }
    }

    particles.add(
      Particle(
        image: image,
        x: _random.nextDouble(),
        y: 1.1,
        size: _random.nextDouble() * 16 + 28,
        speed: (_random.nextDouble() * 0.3 + 0.25) *
            speedFactor,
        wobbleOffset: _random.nextDouble() * 2 * pi,
      ),
    );

    if (!_ticker.isActive) {
      _lastTime = 0;
      _ticker.start();
    }
  }

  Future<ui.Image> _renderEmojiToImage(String emoji) {
    const double fontSize = 48.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final painter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: const TextStyle(fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    );

    painter.layout();
    painter.paint(canvas, Offset.zero);

    return recorder
        .endRecording()
        .toImage(painter.width.toInt(), painter.height.toInt());
  }

  void _onTick(Duration elapsed) {
    if (particles.isEmpty) {
      _ticker.stop();
      notifyListeners();
      return;
    }

    final currentTime =
        elapsed.inMicroseconds / 1000000.0;
    final dt = _lastTime == 0
        ? 0.016
        : (currentTime - _lastTime);
    _lastTime = currentTime;

    final safeDt = min(dt, 0.05); // smoother + responsive

    particles.removeWhere((p) {
      p.update(safeDt);
      return p.y < -0.25;
    });

    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

// ------------------------------------------------------------

class Particle {
  final ui.Image image;
  double x;
  double y;
  double size;
  double speed;
  double wobbleOffset;
  double timeAlive = 0;

  Particle({
    required this.image,
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
}

// ------------------------------------------------------------

class _EmojiPainter extends CustomPainter {
  final ParticleController controller;
  final Paint _paint = Paint()
    ..filterQuality = FilterQuality.low; // faster

  _EmojiPainter(this.controller) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final particles = controller.particles;
    if (particles.isEmpty) return;

    for (final p in particles) {
      final wobble = sin(
                p.timeAlive * controller.wobbleSpeed +
                    p.wobbleOffset,
              ) *
          controller.wobbleAmount;

      final dx = p.x * size.width + wobble;
      final dy = p.y * size.height;

      canvas.save();
      canvas.translate(dx, dy);

      double scale = p.size / p.image.height;

      // Fade out near top
      if (p.y < 0.25) {
        final fade =
            (p.y + 0.25) / 0.5;
        scale *= fade.clamp(0.0, 1.0);
      }

      canvas.scale(scale);

      canvas.drawImage(
        p.image,
        Offset(
          -p.image.width / 2,
          -p.image.height / 2,
        ),
        _paint,
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _EmojiPainter oldDelegate) =>
      true;
}
