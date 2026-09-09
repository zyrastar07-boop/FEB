import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../design/motion.dart';
import '../design/tokens.dart';

/// Lightweight, dependency-free cinematic 3D backdrop.
///
/// It uses Flutter's compositor rather than a WebGL dependency, so it is safe
/// for Android and keeps the existing app architecture intact. The geometry
/// is decorative only and never participates in navigation or data loading.
class Cinematic3DBackdrop extends StatefulWidget {
  final Widget child;
  final double intensity;

  const Cinematic3DBackdrop({
    super.key,
    required this.child,
    this.intensity = 1.0,
  });

  @override
  State<Cinematic3DBackdrop> createState() => _Cinematic3DBackdropState();
}

class _Cinematic3DBackdropState extends State<Cinematic3DBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.shouldReduceMotion(context)) return widget.child;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value * math.pi * 2;
                final angle = math.sin(t) * 0.018 * widget.intensity;
                final depth = 1.0 + math.sin(t * 0.7) * 0.018 * widget.intensity;
                return CustomPaint(
                  painter: _DepthPainter(t: t, intensity: widget.intensity),
                  child: Center(
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateX(angle)
                        ..rotateY(math.cos(t * 0.8) * 0.018 * widget.intensity)
                        ..scale(depth),
                      child: const SizedBox.expand(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _DepthPainter extends CustomPainter {
  final double t;
  final double intensity;

  const _DepthPainter({required this.t, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.55, size.height * 0.30);
    final radius = math.min(size.width, size.height) * 0.36;
    final pulse = 0.92 + math.sin(t * 0.9) * 0.05 * intensity;

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          AppDesignTokens.gold.withValues(alpha: 0.055),
          AppDesignTokens.gold.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * pulse));
    canvas.drawCircle(center, radius * pulse, glow);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = AppDesignTokens.gold.withValues(alpha: 0.045);
    canvas.drawCircle(center, radius * (0.68 + math.sin(t) * 0.025), ring);
    canvas.drawCircle(center, radius * (0.84 + math.cos(t * 0.7) * 0.025), ring);
  }

  @override
  bool shouldRepaint(covariant _DepthPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.intensity != intensity;
}
