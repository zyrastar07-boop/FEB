import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

/// Which pre-baked glass fill/blur pairing to use. Mirrors the token tiers:
/// [bar] floats over scrolling content, [sheet] for panels/dialogs,
/// [subtle] for chips & inline overlays.
enum GlassFill { bar, sheet, subtle }

/// GlassSurface — THE way to build a glass-morphism surface in this app.
///
/// Wrap any content and it gets:
/// - a warm-noir translucent fill (from [AppDesignTokens] glass tokens),
/// - a real `BackdropFilter` blur (refresh-rate & reduced-transparency aware),
/// - a gold hairline border plus a top specular highlight,
/// - an optional depth shadow for floating chrome.
///
/// Accessibility: when the user prefers reduced transparency
/// ([AppMotion.shouldReduceTransparency]) the surface renders as a solid
/// ORYZO card (surfaceElevated + borderCork) with zero blur — same layout,
/// no legibility cost.
///
/// ```dart
/// GlassSurface(
///   fill: GlassFill.bar,
///   borderRadius: 999,
///   child: Text('Hello'),
/// )
/// ```
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.fill = GlassFill.sheet,
    this.borderRadius,
    this.fillColor,
    this.blurSigma,
    this.borderColor,
    this.padding,
    this.margin,
    this.sheen = true,
    this.floating = false,
  });

  final Widget child;

  /// Preset fill + blur tier. Ignored for fill/blur when [fillColor] or
  /// [blurSigma] is provided explicitly.
  final GlassFill fill;

  /// Corner radius. Defaults to [AppDesignTokens.radiusLg].
  final double? borderRadius;

  /// Overrides the tier fill color (alpha included).
  final Color? fillColor;

  /// Overrides the tier blur sigma.
  final double? blurSigma;

  /// Overrides the gold hairline border color (alpha included).
  final Color? borderColor;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Render the top-to-bottom specular highlight inside the surface.
  final bool sheen;

  /// Apply [AppDesignTokens.glassShadow] — only for chrome that floats over
  /// content (nav bar, search dock). Flat in-flow surfaces keep this off.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.shouldReduceTransparency(context);
    final double radius = borderRadius ?? AppDesignTokens.radiusLg.topLeft.x;

    // Reduced transparency → solid ORYZO card, no blur, no sheen.
    if (reduce) {
      return Container(
        margin: margin,
        decoration: BoxDecoration(
          color: fillColor != null
              ? Color.alphaBlend(fillColor!, AppDesignTokens.backgroundCanvas)
              : AppDesignTokens.surfaceElevated,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppDesignTokens.borderCork, width: 1),
        ),
        padding: padding,
        child: child,
      );
    }

    final (Color, double) tier = switch (fill) {
      GlassFill.bar => (
        AppDesignTokens.glassFillBar,
        AppDesignTokens.glassBlurBar,
      ),
      GlassFill.sheet => (
        AppDesignTokens.glassFillSheet,
        AppDesignTokens.glassBlurSheet,
      ),
      GlassFill.subtle => (
        AppDesignTokens.glassFillSubtle,
        AppDesignTokens.glassBlurChip,
      ),
    };

    final double sigma = blurSigma ?? tier.$2;
    final Color effectiveFill = fillColor ?? tier.$1;
    final Color border = borderColor ?? AppDesignTokens.glassBorder;

    return Container(
      margin: margin,
      decoration: floating
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: AppDesignTokens.glassShadow,
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: effectiveFill,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: border, width: 1),
              // Specular sheen: light "catches" the top edge of the glass.
              gradient: sheen
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppDesignTokens.glassHighlight,
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.35],
                    )
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
