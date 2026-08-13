import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Concentric radar-style pulse rings around a glowing satellite icon.
/// Use this instead of plain text loaders during stream scraping / buffering.
class SatellitePulseLoader extends StatefulWidget {
  final double size;
  final Color color;
  final String? label;

  const SatellitePulseLoader({
    super.key,
    this.size = 120,
    this.color = const Color(0xFFD4AF37),
    this.label,
  });

  @override
  State<SatellitePulseLoader> createState() => _SatellitePulseLoaderState();
}

class _SatellitePulseLoaderState extends State<SatellitePulseLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final color = widget.color;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return CustomPaint(
                painter: _RadarPainter(
                  progress: _ctrl.value,
                  color: color,
                ),
                child: Center(
                  child: Container(
                    width: size * 0.28,
                    height: size * 0.28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.15),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.45),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.satellite_alt_rounded,
                      color: color,
                      size: size * 0.16,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 16),
          Text(
            widget.label!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width * 0.48;

    // Three staggered rings
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = maxR * Curves.easeOut.transform(t);
      final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.55;

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * (1.0 - t * 0.5);

      canvas.drawCircle(center, radius, paint);
    }

    // Soft sweep arc
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.25),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
        transform: GradientRotation(progress * 2 * math.pi),
      ).createShader(Rect.fromCircle(center: center, radius: maxR))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxR * 0.92, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.progress != progress || old.color != color;
}