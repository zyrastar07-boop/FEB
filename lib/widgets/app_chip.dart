import 'package:flutter/material.dart';
import '../design/tokens.dart';
import '../design/motion.dart';

/// AppChip — unified chip primitive for categories, filters, badges, history.
/// Variants: primary (gold), secondary (card), ghost (transparent), destructive.
/// Sizes: small (inline), medium (default), large (prominent).
class AppChip extends StatefulWidget {
  const AppChip({
    super.key,
    required this.label,
    this.icon,
    this.trailingIcon,
    this.onTap,
    this.onDeleted,
    this.variant = AppChipVariant.secondary,
    this.size = AppChipSize.medium,
    this.selected = false,
    this.enabled = true,
    this.padding,
    this.semanticLabel,
  });

  final String label;
  final Widget? icon;
  final Widget? trailingIcon;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;
  final AppChipVariant variant;
  final AppChipSize size;
  final bool selected;
  final bool enabled;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;

  @override
  State<AppChip> createState() => _AppChipState();
}

class _AppChipState extends State<AppChip> with SingleTickerProviderStateMixin {
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
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _pressController,
      curve: AppMotion.easeOut,
      reverseCurve: AppMotion.easeOut,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rescale();
    });
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
    if (!widget.enabled || widget.onTap == null) return;
    setState(() => _pressed = true);
    _pressController.forward();
  }

  void _handleTapUp(TapUpDetails _) {
    if (!widget.enabled || widget.onTap == null) return;
    _release();
    widget.onTap?.call();
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
    final radius = AppDesignTokens.radiusFull;
    final enabled = widget.enabled && (widget.onTap != null || widget.onDeleted != null);

    final (bgColor, fgColor, borderColor) = _colorsForVariant(
      widget.variant,
      widget.selected,
      enabled,
      _pressed,
    );

    final (hp, vp, iconSize, gap, fontSize) = _metricsForSize(widget.size);

    final horizontalPadding = widget.padding?.horizontal ?? hp;
    final verticalPadding = widget.padding?.vertical ?? vp;

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          SizedBox(width: iconSize, height: iconSize, child: widget.icon!),
          SizedBox(width: gap),
        ],
        Text(
          widget.label,
          style: AppDesignTokens.labelMedium().copyWith(
            fontSize: fontSize,
            color: fgColor,
            fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        if (widget.trailingIcon != null) ...[
          SizedBox(width: gap),
          SizedBox(width: iconSize, height: iconSize, child: widget.trailingIcon!),
        ],
        if (widget.onDeleted != null) ...[
          SizedBox(width: gap),
          GestureDetector(
            onTap: widget.enabled ? widget.onDeleted : null,
            child: Icon(
              Icons.close_rounded,
              size: iconSize,
              color: fgColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );

    final chip = AnimatedScale(
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
          color: bgColor,
          borderRadius: radius,
          border: borderColor != null ? Border.all(color: borderColor, width: 1) : null,
        ),
        child: content,
      ),
    );

    if (!enabled || widget.onTap == null) {
      return Semantics(
        button: widget.onTap != null,
        enabled: enabled,
        label: widget.semanticLabel,
        child: chip,
      );
    }

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius),
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          borderRadius: radius,
          splashFactory: _NoSplashFactory(),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.pressed)) {
              return AppDesignTokens.goldSoft;
            }
            if (states.contains(WidgetState.hovered)) {
              return AppDesignTokens.goldSoft.withValues(alpha: 0.3);
            }
            return null;
          }),
          child: chip,
        ),
      ),
    );
  }

  (Color, Color, Color?) _colorsForVariant(
    AppChipVariant variant,
    bool selected,
    bool enabled,
    bool pressed,
  ) {
    if (!enabled) {
      return (
        AppDesignTokens.card,
        AppDesignTokens.textQuaternary,
        AppDesignTokens.border,
      );
    }

    if (selected) {
      return (
        AppDesignTokens.gold,
        AppDesignTokens.textOnGold,
        null,
      );
    }

    switch (variant) {
      case AppChipVariant.primary:
        final bg = pressed
            ? AppDesignTokens.gold.withValues(alpha: 0.85)
            : AppDesignTokens.gold;
        return (bg, AppDesignTokens.textOnGold, null);
      case AppChipVariant.secondary:
        final bg = pressed ? AppDesignTokens.cardHover : AppDesignTokens.card;
        return (bg, AppDesignTokens.textPrimary, AppDesignTokens.border);
      case AppChipVariant.ghost:
        final bg = pressed ? AppDesignTokens.cardHover : Colors.transparent;
        return (bg, AppDesignTokens.textSecondary, null);
      case AppChipVariant.destructive:
        final bg = pressed
            ? AppDesignTokens.error.withValues(alpha: 0.85)
            : AppDesignTokens.error;
        return (bg, AppDesignTokens.textInverse, null);
      case AppChipVariant.outline:
        return (Colors.transparent, AppDesignTokens.textPrimary, AppDesignTokens.gold);
    }
  }

  (double, double, double, double, double) _metricsForSize(AppChipSize size) {
    return switch (size) {
      AppChipSize.small => (AppDesignTokens.space3, AppDesignTokens.space1, 12, AppDesignTokens.space1, 11),
      AppChipSize.medium => (AppDesignTokens.space4, AppDesignTokens.space2, 14, AppDesignTokens.space2, 12.5),
      AppChipSize.large => (AppDesignTokens.space5, AppDesignTokens.space3, 16, AppDesignTokens.space2, 14),
    };
  }
}

enum AppChipVariant { primary, secondary, ghost, destructive, outline }
enum AppChipSize { small, medium, large }

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
