import 'dart:ui';
import 'package:flutter/material.dart';
import '../design/tokens.dart';
import '../design/motion.dart';

class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? borderColor;
  final Color? backgroundColor;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 30.0,
    this.padding,
    this.margin,
    this.borderColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.shouldReduceTransparency(context);
    final fill = backgroundColor ??
        (reduce
            ? AppDesignTokens.surfaceElevated // solid bronze fallback
            : AppDesignTokens.glassFillSubtle);
    final edge = borderColor ??
        AppDesignTokens.glassBorder;
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppMotion.glassBlur(context, 16.0),
            sigmaY: AppMotion.glassBlur(context, 16.0),
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: edge, width: 1.2),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}