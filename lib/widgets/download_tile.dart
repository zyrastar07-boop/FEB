import 'package:flutter/material.dart';
import '../design/tokens.dart';

const _gold = AppDesignTokens.gold;

/// A row in the download sheet quality/episode lists.
///
/// Shows a title, optional subtitle, optional trailing widget (e.g. a
/// downloaded check), and a trailing download action. [highlighted] marks
/// the recommended option; [enabled] gates the action while a download is
/// being prepared.
class DownloadTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool highlighted;
  final bool enabled;
  final VoidCallback? onDownload;
  final Widget? trailing;

  const DownloadTile({
    super.key,
    required this.title,
    this.subtitle,
    this.highlighted = false,
    this.enabled = true,
    this.onDownload,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnTap = enabled ? onDownload : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: highlighted ? _gold.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted ? _gold.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        onTap: effectiveOnTap,
        title: Row(
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (highlighted) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'BEST',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: subtitle == null || subtitle!.isEmpty
            ? null
            : Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 4),
            ],
            IconButton(
              // Disabled while [enabled] is false; tap target stays the row.
              onPressed: effectiveOnTap,
              icon: Icon(
                Icons.download_rounded,
                size: 20,
                color: effectiveOnTap == null ? Colors.white24 : _gold,
              ),
              tooltip: 'Download',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}
