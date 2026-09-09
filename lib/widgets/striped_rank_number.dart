//striped rank number.dart
import 'dart:math' as math;
import '../design/tokens.dart';
import 'package:flutter/material.dart';

/// Large rank numeral with diagonal gold/dark stripes, white outline, soft glow.
class StripedRankNumber extends StatelessWidget {
  final int rank;
  final double fontSize;

  const StripedRankNumber({
    super.key,
    required this.rank,
    this.fontSize = 72,
  });

  @override
  Widget build(BuildContext context) {
    final text = rank.toString();
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 0.9,
      letterSpacing: -2,
      fontFamily: 'Roboto',
    );

    return CustomPaint(
      painter: _RankGlowPainter(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // White outline (stroke)
          Text(
            text,
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 4.5
                ..color = Colors.white,
            ),
          ),
          // Striped fill via shader mask
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment(-1, -1),
                end: Alignment(1, 1),
                colors: [
                  Color(0xFFF2C94C),
                  AppDesignTokens.gold,
                  Color(0xFF1A1200),
                  AppDesignTokens.gold,
                  Color(0xFF0A0800),
                  Color(0xFFE0A82E),
                  Color(0xFF1A1200),
                  AppDesignTokens.gold,
                ],
                stops: [0.0, 0.12, 0.24, 0.38, 0.52, 0.66, 0.80, 1.0],
                transform: GradientRotation(math.pi / 4), // ~45°
              ).createShader(bounds);
            },
            child: Text(
              text,
              style: style.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.45, size.height * 0.55);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppDesignTokens.gold.withValues(alpha: 0.35),
          AppDesignTokens.gold.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: size.height * 0.7));
    canvas.drawCircle(center, size.height * 0.65, paint);

    // Dark backdrop disc for contrast over bright posters
    final dark = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, size.height * 0.42, dark);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}