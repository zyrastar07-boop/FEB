import 'package:flutter/material.dart';
import '../design/tokens.dart';
import 'app_button.dart';

/// SectionHeader — unified section title with optional trailing action.
/// Used across home, search, detail, library, profile.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.actionLabel,
    this.actionIcon,
    this.style = SectionHeaderStyle.defaultStyle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? action;
  final String? actionLabel;
  final IconData? actionIcon;
  final SectionHeaderStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: style.padding ?? const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: style.titleStyle ?? AppDesignTokens.headlineMedium(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: style.subtitleStyle ?? AppDesignTokens.bodySmall(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            _ActionButton(
              label: actionLabel,
              icon: actionIcon,
              onPressed: action!,
              style: style.actionStyle,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.style,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onPressed;
  final SectionHeaderActionStyle? style;

  @override
  Widget build(BuildContext context) {
    final s = style ?? const SectionHeaderActionStyle();

    return AppButton(
      onPressed: onPressed,
      variant: s.variant ?? AppButtonVariant.ghost,
      size: AppButtonSize.small,
      leadingIcon: icon != null ? Icon(icon, size: 14) : null,
      padding: s.padding,
      child: label != null
          ? Text(
              label!,
              style: AppDesignTokens.labelSmall()
                  .copyWith(color: AppDesignTokens.textSecondary),
            )
          : const SizedBox.shrink(),
    );
  }
}

class SectionHeaderStyle {
  const SectionHeaderStyle({
    this.titleStyle,
    this.subtitleStyle,
    this.padding,
    this.actionStyle,
  });

  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final EdgeInsetsGeometry? padding;
  final SectionHeaderActionStyle? actionStyle;

  static const SectionHeaderStyle defaultStyle = SectionHeaderStyle(
    titleStyle: null,
    subtitleStyle: null,
    padding: null,
    actionStyle: null,
  );

  static final SectionHeaderStyle compact = SectionHeaderStyle(
    titleStyle: AppDesignTokens.titleMedium(),
    subtitleStyle: AppDesignTokens.bodySmall(),
    padding: EdgeInsets.symmetric(horizontal: AppDesignTokens.space4),
    actionStyle: SectionHeaderActionStyle(
      variant: AppButtonVariant.ghost,
      padding: EdgeInsets.symmetric(
        horizontal: AppDesignTokens.space2,
        vertical: AppDesignTokens.space1,
      ),
    ),
  );

  static final SectionHeaderStyle prominent = SectionHeaderStyle(
    titleStyle: AppDesignTokens.headlineLarge(),
    subtitleStyle: AppDesignTokens.bodyMedium(),
    padding: EdgeInsets.symmetric(horizontal: AppDesignTokens.space4),
    actionStyle: SectionHeaderActionStyle(
      variant: AppButtonVariant.secondary,
      padding: EdgeInsets.symmetric(
        horizontal: AppDesignTokens.space3,
        vertical: AppDesignTokens.space2,
      ),
    ),
  );
}

class SectionHeaderActionStyle {
  const SectionHeaderActionStyle({
    this.variant,
    this.padding,
  });

  final AppButtonVariant? variant;
  final EdgeInsetsGeometry? padding;
}