import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/wyzie_subtitle_service.dart';

import '../design/tokens.dart';

const _gold = AppDesignTokens.gold;

/// Bottom sheet: list Wyzie tracks + Off. Returns selected track or null for Off.
///
/// Usage:
/// ```dart
/// final track = await SubtitleTrackPicker.show(
///   context,
///   tracks: tracks,
///   selectedId: currentId,
/// );
/// if (track == null) { /* Off */ }
/// else { /* download track.url and parse */ }
/// ```
class SubtitleTrackPicker {
  SubtitleTrackPicker._();

  static Future<WyzieSubtitleTrack?> show(
    BuildContext context, {
    required List<WyzieSubtitleTrack> tracks,
    String? selectedId,
    bool allowOff = true,
  }) {
    return showModalBottomSheet<WyzieSubtitleTrack?>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Subtitles',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    children: [
                      if (allowOff)
                        _tile(
                          ctx,
                          title: 'Off',
                          subtitle: 'Hide subtitles',
                          selected: selectedId == null || selectedId == 'off',
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.pop(ctx, null);
                          },
                        ),
                      if (tracks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No subtitle tracks found for this title.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      else
                        ...tracks.map((t) {
                          final selected = selectedId == t.id;
                          final hi = t.isHearingImpaired ? ' · HI' : '';
                          return _tile(
                            ctx,
                            title: t.displayLanguage.isNotEmpty
                                ? t.displayLanguage
                                : t.languageCode,
                            subtitle:
                                '${t.languageCode.toUpperCase()} · ${t.format.toUpperCase()}$hi'
                                '${t.source != null ? ' · ${t.source}' : ''}',
                            selected: selected,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(ctx, t);
                            },
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _tile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? const Color(0xFF332A15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? _gold : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.closed_caption
                      : Icons.closed_caption_outlined,
                  color: selected ? _gold : Colors.white54,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected ? _gold : Colors.white,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_rounded, color: _gold, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}