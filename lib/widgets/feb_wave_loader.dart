import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../design/motion.dart';
import '../design/tokens.dart';

/// FEB Wave Loader — organic, premium, Warm Cream wave/pulse animation.
///
/// Replaces standard Material `CircularProgressIndicator` across the app.
/// Uses an `AnimationController` + custom painter to produce a fluid wave
/// that fits the ORYZO editorial aesthetic. No shadows; depth comes from
/// the Warm Cream pigment against the Walnut Shadow canvas.
///
/// Usage:
/// ```dart
/// const WaveLoader()
/// // or with custom size:
/// WaveLoader(size: 160)
/// ```
class WaveLoader extends StatefulWidget {
  final double size;
  final bool showLabel;
  final String? label;

  const WaveLoader({
    super.key,
    this.size = 120,
    this.showLabel = false,
    this.label,
  });

  @override
  State<WaveLoader> createState() => _WaveLoaderState();
}

class _WaveLoaderState extends State<WaveLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rescale();
    });
  }

  void _rescale() {
    if (!mounted) return;
    _controller.duration = AppMotion.scaled(context, AppMotion.slow);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rescale();
  }


  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Wave disc.
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _WavePainter(
                  progress: _controller.value,
                  color: AppDesignTokens.textCream,
                ),
              );
            },
          ),
          // Central frozen core for editorial anchor.
          Container(
            width: widget.size * 0.32,
            height: widget.size * 0.32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppDesignTokens.textCream.withValues(alpha: 0.08),
            ),
          ),
          if (widget.showLabel || widget.label != null)
            Positioned(
              bottom: widget.size * 0.05,
              child: Text(
                widget.label?.toUpperCase() ?? 'NOW PLAYING',
                style: AppDesignTokens.microLegal.copyWith(
                  color: AppDesignTokens.textCream.withValues(alpha: 0.85),
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final Color color;

  _WavePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.46;

    // Outer ring — single flowing waveform.
    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final path = Path();
    final segments = 64;
    final step = (2 * math.pi) / segments;

    for (var i = 0; i < segments; i++) {
      final angle = i * step;
      final wave = math.sin(angle * 3 + progress * 2 * math.pi) * radius * 0.12;
      final r = radius + wave;
      final x = center.dx + math.cos(angle) * r;
      final y = center.dy + math.sin(angle) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, ringPaint);

    // Inner softer wave layer.
    final softPaint = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final innerPath = Path();
    final innerRadius = radius * 0.7;
    for (var i = 0; i < segments; i++) {
      final angle = i * step;
      final wave =
          math.sin(angle * 3 + progress * 2 * math.pi + 0.6) * innerRadius * 0.12;
      final r = innerRadius + wave;
      final x = center.dx + math.cos(angle) * r;
      final y = center.dy + math.sin(angle) * r;
      if (i == 0) {
        innerPath.moveTo(x, y);
      } else {
        innerPath.lineTo(x, y);
      }
    }
    innerPath.close();
    canvas.drawPath(innerPath, softPaint);

    // Slow radial pulse — faint Warm Cream bloom.
    final pulseOpacity = (0.5 + 0.5 * math.sin(progress * 2 * math.pi)) * 0.18;
    final pulsePaint = Paint()
      ..color = color.withValues(alpha: pulseOpacity)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.92, pulsePaint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.progress != progress || old.color != color;
}

