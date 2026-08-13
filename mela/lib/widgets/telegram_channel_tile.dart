import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/iptv_channel_model.dart';

/// Telegram-inspired channel list tile.
class TelegramChannelTile extends StatelessWidget {
  final IptvChannel channel;
  final VoidCallback onTap;
  final bool isPlaying;

  const TelegramChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0xFFFFB800).withValues(alpha: 0.08),
        highlightColor: Colors.white.withValues(alpha: 0.03),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // ── Circular logo ──────────────────────────────────────────
              _buildAvatar(),
              const SizedBox(width: 14),

              // ── Title + subtitle ───────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: isPlaying
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (isPlaying) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB800)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                color: Color(0xFFFFB800),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Subtitle row
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF4CAF50),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${channel.groupTitle}'
                            '${channel.country != null ? ' · ${channel.country}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // ── Quality badge ──────────────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  channel.quality,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isPlaying
              ? const Color(0xFFFFB800).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.12),
          width: isPlaying ? 2 : 1.2,
        ),
        boxShadow: isPlaying
            ? [
                BoxShadow(
                  color: const Color(0xFFFFB800).withValues(alpha: 0.25),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: ClipOval(
        child: channel.logoUrl != null && channel.logoUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: channel.logoUrl!,
                fit: BoxFit.cover,
                placeholder: (_, _) => _fallbackIcon(),
                errorWidget: (_, _, _) => _fallbackIcon(),
                fadeInDuration: const Duration(milliseconds: 200),
              )
            : _fallbackIcon(),
      ),
    );
  }

  Widget _fallbackIcon() {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Icon(
        Icons.live_tv_rounded,
        size: 26,
        color: Colors.white.withValues(alpha: 0.35),
      ),
    );
  }
}