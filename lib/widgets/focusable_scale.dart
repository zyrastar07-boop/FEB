import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';

const _gold = AppDesignTokens.gold;
const _focusAnimDuration = Duration(milliseconds: 160);
const _focusAnimCurve = Curves.easeOutCubic;

/// @deprecated Mobile-only build — FocusableScale is retained for keyboard/D-pad
/// support on desktop/web. For mobile-only targets, prefer [AppCard],
/// [AppButton], [AppChip], or [PosterCard] which use InkWell + Semantics
/// without FocusNode overhead.
///
/// Migration: replace `FocusableScale(onTap: ...)` with
/// `AppCard(onTap: ...)` or `AppButton(onPressed: ...)` depending on visual role.
@Deprecated('mobile-only-strip: use AppCard/AppButton/AppChip/PosterCard instead')
class FocusableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scale;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? focusColor;
  final String? debugLabel;

  const FocusableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
    this.scale = 1.05,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.padding,
    this.focusColor,
    this.debugLabel,
  });

  @override
  State<FocusableScale> createState() => _FocusableScaleState();
}

class _FocusableScaleState extends State<FocusableScale> {
  late final FocusNode _node;
  bool _owned = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _node = widget.focusNode!;
    } else {
      _node = FocusNode(debugLabel: widget.debugLabel ?? 'FocusableScale');
      _owned = true;
    }
    _node.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted && _focused != _node.hasFocus) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    if (_owned) _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.numpadEnter) {
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.focusColor ?? _gold;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final animDuration = reduceMotion ? Duration.zero : _focusAnimDuration;
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _focused ? widget.scale : 1.0,
          duration: animDuration,
          curve: _focusAnimCurve,
          child: AnimatedContainer(
            duration: animDuration,
            curve: _focusAnimCurve,
            padding: widget.padding,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: Border.all(
                color: _focused ? color : Colors.transparent,
                width: _focused ? 2.5 : 0,
              ),
              boxShadow: _focused && !reduceMotion
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}