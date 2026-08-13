import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/font_service.dart';

const _gold = Color(0xFFFFB800);

/// Row with "Best of" provider pill + optional "From the Dev" action pill.
class ProviderPillSelector extends StatelessWidget {
  final String selectedName;
  final List<Map<String, dynamic>> providers;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final String prefixLabel;

  /// Opens developer-curated collections (not shown on Home).
  final VoidCallback? onDevPicksTap;

  const ProviderPillSelector({
    super.key,
    required this.selectedName,
    required this.providers,
    required this.onSelected,
    this.prefixLabel = 'Best of',
    this.onDevPicksTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            prefixLabel,
            style: FontService.instance.label(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded,
              color: Colors.white38, size: 16),
          const SizedBox(width: 8),
          PopupMenuButton<Map<String, dynamic>>(
            onSelected: (p) {
              HapticFeedback.selectionClick();
              onSelected(p);
            },
            color: const Color(0xFF1A1A1A),
            elevation: 12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            offset: const Offset(0, 44),
            itemBuilder: (context) {
              return providers.map((p) {
                final name = p['name'] as String? ?? '';
                final selected = selectedName == name;
                return PopupMenuItem<Map<String, dynamic>>(
                  value: p,
                  child: Text(
                    name,
                    style: TextStyle(
                      color: selected ? _gold : Colors.white,
                      fontSize: 13.5,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                );
              }).toList();
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selectedName,
                    overflow: TextOverflow.ellipsis,
                    style: FontService.instance.label(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (onDevPicksTap != null) ...[
            const Spacer(),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onDevPicksTap!();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _gold.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        color: _gold, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      'From the Dev',
                      style: FontService.instance.label(
                        color: _gold,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}