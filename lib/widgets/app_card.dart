import 'package:flutter/material.dart';
import '../design/tokens.dart';
import '../design/motion.dart';

/// AppCard — unified card primitive replacing ad-hoc Container+BorderRadius.
/// Supports elevation, border, hover/press states, and optional child clipping.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.margin,
    this.elevation = AppCardElevation.none,
    this.border = true,
    this.borderColor,
    this.backgroundColor,
    this.borderRadius,
    this.clipBehavior = Clip.none,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final AppCardElevation elevation;
  final bool border;
  final Color? borderColor;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final Clip clipBehavior;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.shouldReduceMotion(context);
    final radius = borderRadius ?? AppDesignTokens.radiusLg;
    final bgColor = backgroundColor ?? AppDesignTokens.card;
    final brdColor = borderColor ?? AppDesignTokens.border;
    final shadows = AppDesignTokens.elevationNone;

    final card = AnimatedContainer(
      duration: reduceMotion ? AppMotion.instant : AppMotion.standardScaled(context),
      curve: AppMotion.curveOrLinear(context, AppMotion.easeOut),
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: radius,
        border: border
          ? Border.all(color: brdColor, width: 1)
          : null,
        boxShadow: shadows,
      ),
      clipBehavior: clipBehavior,
      child: child,
    );

    if (onTap == null && onLongPress == null && semanticLabel == null) {
      return card;
    }

    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: clipBehavior,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: radius,
          splashFactory: _NoSplashFactory(),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.pressed)) {
              return AppDesignTokens.surfaceElevated.withValues(alpha: 0.5);
            }
            if (states.contains(WidgetState.hovered)) {
              return AppDesignTokens.surfaceElevated.withValues(alpha: 0.3);
            }
            return null;
          }),
          child: card,
        ),
      ),
    );
  }

}

enum AppCardElevation { none, low, medium, high, gold }

/// Splash factory that produces no visual splash — we use overlayColor instead.
class _NoSplashFactory extends InteractiveInkFeatureFactory {
  const _NoSplashFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    return _NoSplash(
      controller: controller,
      referenceBox: referenceBox,
      color: color,
      onRemoved: onRemoved,
    );
  }
}

class _NoSplash extends InteractiveInkFeature {
  _NoSplash({
    required super.controller,
    required super.referenceBox,
    required super.color,
    required super.onRemoved,
  });

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {}
}