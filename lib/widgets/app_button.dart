import 'package:flutter/material.dart';
import '../design/tokens.dart';
import '../design/motion.dart';
import 'glass_surface.dart';

/// AppButton — unified button primitive with primary/secondary/ghost/glass
/// variants. Uses InkWell ripple + scale-on-press. No FocusableScale (mobile-only).
///
/// Geometry is deliberately compact: horizontal padding 12 / 16 / 20 and
/// vertical 4 / 6 / 8 across [AppButtonSize.small/medium/large] keeps every
/// button visually consistent and space-efficient app-wide.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.leadingIcon,
    this.trailingIcon,
    this.fullWidth = false,
    this.padding,
    this.borderRadius,
    this.enabled = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final bool fullWidth;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final bool enabled;
  final String? semanticLabel;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scaleAnimation;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: AppMotion.micro,
      reverseDuration: AppMotion.fast,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(
      parent: _pressController,
      curve: AppMotion.easeOut,
      // Springy release: quick settle with a whisper of overshoot.
      reverseCurve: AppMotion.easePressRelease,
    ));

    // Scale to device refresh rate once the build context is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rescale();
    });

    // Re-scale whenever dependencies change (theme, refresh rate update).
  }

  void _rescale() {
    if (!mounted) return;
    _pressController.duration = AppMotion.scaled(context, AppMotion.micro);
    _pressController.reverseDuration = AppMotion.scaled(context, AppMotion.fast);
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rescale();
  }

  void _handleTapDown(TapDownDetails _) {
    if (!widget.enabled) return;
    setState(() => _pressed = true);
    _pressController.forward();
  }

  void _handleTapUp(TapUpDetails _) {
    if (!widget.enabled) return;
    // Note: do NOT invoke `widget.onPressed` here — InkWell already
    // dispatches `onTap` on tap completion. Calling it again caused
    // double-fire (e.g. two `Navigator.pop` calls in a row on the
    // detail-screen back button, leaving a black route beneath).
    _release();
  }

  void _handleTapCancel() {
    _release();
  }

  void _release() {
    if (mounted) {
      setState(() => _pressed = false);
      _pressController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.shouldReduceMotion(context);
    final radius = widget.borderRadius ?? AppDesignTokens.radiusFull;
    final enabled = widget.enabled && widget.onPressed != null;

    final (bgColor, fgColor, borderColor, shadows, isGlass) = _colorsForVariant(
      widget.variant,
      enabled,
      _pressed,
    );

    // Compact geometry: h 8/12/16 · v 4/6/8 for small/medium/large.
    // (Previously 12–16 horizontal + 4–8 vertical on small/medium — visibly
    // bulkier. All paddings stay on the 4px ORYZO spacing grid.)
    final horizontalPadding = widget.padding?.horizontal ??
        switch (widget.size) {
          AppButtonSize.small => AppDesignTokens.space2,
          AppButtonSize.medium => AppDesignTokens.space3,
          AppButtonSize.large => AppDesignTokens.space5,
        };
    final verticalPadding = widget.padding?.vertical ??
        switch (widget.size) {
          AppButtonSize.small => AppDesignTokens.space1,
          AppButtonSize.medium => AppDesignTokens.space1 + 2,
          AppButtonSize.large => AppDesignTokens.space2,
        };

    final textStyle = _textStyleForSize(widget.size, fgColor);
    final iconSize = _iconSizeForSize(widget.size);

    Widget content = Row(
      mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.leadingIcon != null) ...[
          SizedBox(width: iconSize, height: iconSize, child: widget.leadingIcon!),
          SizedBox(width: AppDesignTokens.space1),
        ],
        DefaultTextStyle(style: textStyle, child: widget.child),
        if (widget.trailingIcon != null) ...[
          SizedBox(width: AppDesignTokens.space1),
          SizedBox(width: iconSize, height: iconSize, child: widget.trailingIcon!),
        ],
      ],
    );

    final button = AnimatedScale(
      scale: reduceMotion ? 1.0 : _scaleAnimation.value,
      duration: reduceMotion ? AppMotion.instant : AppMotion.scaled(context, AppMotion.micro),
      curve: AppMotion.easeOut,
      child: AnimatedContainer(
        duration: reduceMotion ? AppMotion.instant : AppMotion.scaled(context, AppMotion.fast),
        curve: AppMotion.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: isGlass && !reduceMotion
              ? null
              : bgColor, // glass paints its fill inside GlassSurface
          borderRadius: radius,
          border: borderColor != null
              ? Border.all(color: borderColor, width: 1)
              : null,
          boxShadow: AppDesignTokens.elevationNone,
        ),
        child: isGlass
            ? GlassSurface(
                fill: GlassFill.subtle,
                borderRadius: radius.topLeft.x,
                fillColor: reduceMotion
                    ? AppDesignTokens.glassFillSubtle
                    : bgColor,
                borderColor: borderColor,
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                sheen: !reduceMotion,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: 0.0,
                      child: content,
                    ),
                    content,
                  ],
                ),
              )
            : content,
      ),
    );

    if (!enabled) {
      return Semantics(
        button: true,
        enabled: false,
        label: widget.semanticLabel,
        child: button,
      );
    }

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius),
        child: InkWell(
          onTap: widget.onPressed,
          onLongPress: widget.onLongPress,
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          borderRadius: radius,
          splashFactory: _NoSplashFactory(),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
            // On the gold CTA a brown tint reads muddy — shade with espresso
            // so a press looks like a deeper, richer gold instead.
            final isPrimary = widget.variant == AppButtonVariant.primary;
            if (states.contains(WidgetState.pressed)) {
              return isPrimary
                  ? AppDesignTokens.textOnGold.withValues(alpha: 0.12)
                  : AppDesignTokens.surfaceElevated.withValues(alpha: 0.5);
            }
            if (states.contains(WidgetState.hovered)) {
              return isPrimary
                  ? AppDesignTokens.textOnGold.withValues(alpha: 0.05)
                  : AppDesignTokens.surfaceElevated.withValues(alpha: 0.3);
            }
            return null;
          }),
          child: button,
        ),
      ),
    );
  }

  (Color, Color, Color?, List<BoxShadow>, bool) _colorsForVariant(
    AppButtonVariant variant,
    bool enabled,
    bool pressed,
  ) {
    if (!enabled) {
      return (
        AppDesignTokens.card,
        AppDesignTokens.textQuaternary,
        AppDesignTokens.border,
        AppDesignTokens.elevationNone,
        false,
      );
    }

    switch (variant) {
      case AppButtonVariant.primary:
        // Noir-gold CTA: signature gold fill, espresso text, no shadow.
        // Matches AppChip / category-filter selected pills so every gold fill
        // reads the same across the system.
        final bg = pressed
            ? AppDesignTokens.gold.withValues(alpha: 0.85)
            : AppDesignTokens.gold;
        return (
          bg,
          AppDesignTokens.textOnGold,
          null,
          AppDesignTokens.elevationNone,
          false,
        );
      case AppButtonVariant.secondary:
        // Ghost/secondary: transparent, 1px Warm Cream border, cream text.
        final bg = pressed ? AppDesignTokens.surfaceElevated : Colors.transparent;
        return (
          bg,
          AppDesignTokens.textCream,
          AppDesignTokens.textCream,
          AppDesignTokens.elevationNone,
          false,
        );
      case AppButtonVariant.ghost:
        final bg = pressed ? AppDesignTokens.surfaceElevated : Colors.transparent;
        return (
          bg,
          AppDesignTokens.textCream,
          null,
          AppDesignTokens.elevationNone,
          false,
        );
      case AppButtonVariant.glass:
        // Glass morphism: frosted warm-noir fill behind blurred content,
        // gold hairline border, cream text. Press deepens the fill.
        final bg = pressed
            ? AppDesignTokens.glassFillSheet
            : AppDesignTokens.glassFillSubtle;
        return (
          bg,
          AppDesignTokens.textCream,
          AppDesignTokens.glassBorder,
          AppDesignTokens.elevationNone,
          true,
        );
      case AppButtonVariant.destructive:
        // ORYZO uses Ember Accent as the rare accent, also for destructive.
        final bg = pressed
            ? AppDesignTokens.accentEmber.withValues(alpha: 0.85)
            : AppDesignTokens.accentEmber;
        return (
          bg,
          AppDesignTokens.textCream,
          null,
          AppDesignTokens.elevationNone,
          false,
        );
    }
  }

  TextStyle _textStyleForSize(AppButtonSize size, Color color) {
    return switch (size) {
      AppButtonSize.small => AppDesignTokens.labelSmall(color: color),
      AppButtonSize.medium => AppDesignTokens.labelMedium(color: color),
      AppButtonSize.large => AppDesignTokens.labelLarge(color: color),
    };
  }

  double _iconSizeForSize(AppButtonSize size) {
    return switch (size) {
      AppButtonSize.small => 12,
      AppButtonSize.medium => 16,
      AppButtonSize.large => 20,
    };
  }
}

enum AppButtonVariant { primary, secondary, ghost, glass, destructive }
enum AppButtonSize { small, medium, large }

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
