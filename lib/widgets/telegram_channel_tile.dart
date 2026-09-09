import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/iptv_channel_model.dart';
import '../design/tokens.dart';
import '../design/motion.dart';

/// Channel tile for the Live TV browser.
///
/// Rounded-square logo, color-coded quality badge, inline favorite toggle
/// and an animated equalizer "now playing" state for the active channel.
class TelegramChannelTile extends StatefulWidget {
  final IptvChannel channel;
  final VoidCallback onTap;
  final bool isPlaying;
  final bool isFavorite;
  final VoidCallback? onFavoriteTap;

  const TelegramChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
    this.isPlaying = false,
    this.isFavorite = false,
    this.onFavoriteTap,
  });

  @override
  State<TelegramChannelTile> createState() => _TelegramChannelTileState();
}

class _TelegramChannelTileState extends State<TelegramChannelTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _eqCtrl;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _eqCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.slow,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rescale();
    });

    if (widget.isPlaying) _eqCtrl.repeat(reverse: true);
  }

  void _rescale() {
    if (!mounted) return;
    _eqCtrl.duration = AppMotion.scaled(context, AppMotion.slow);
  }

  @override
  void didUpdateWidget(covariant TelegramChannelTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) _syncEqualizer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rescale();
  }

  void _syncEqualizer() {
    if (widget.isPlaying && !_eqCtrl.isAnimating) {
      _eqCtrl.repeat(reverse: true);
    } else if (!widget.isPlaying && _eqCtrl.isAnimating) {
      _eqCtrl.stop();
      _eqCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _eqCtrl.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.shouldReduceMotion(context);
    final isPlaying = widget.isPlaying;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        splashColor: AppDesignTokens.gold.withValues(alpha: 0.08),
        highlightColor: Colors.white.withValues(alpha: 0.03),
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: reduceMotion ? AppMotion.instant : AppMotion.scaled(context, AppMotion.micro),
          curve: AppMotion.easeOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                // ── Gold accent bar for the active channel ─────────────
                if (isPlaying) ...[
                  Container(
                    width: 3,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppDesignTokens.gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],

                // ── Rounded-square logo ────────────────────────────────
                _buildAvatar(),
                const SizedBox(width: 14),

                // ── Title + subtitle ────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTitleRow(),
                      const SizedBox(height: 3),
                      _buildSubtitleRow(),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // ── Quality badge + favorite toggle ─────────────────────
                _buildTrailing(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleRow() {
    final playing = widget.isPlaying;
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.channel.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: playing ? AppDesignTokens.gold : Colors.white,
              fontSize: 16,
              fontWeight: playing ? FontWeight.w700 : FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (playing) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppDesignTokens.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                color: AppDesignTokens.gold,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSubtitleRow() {
    final channel = widget.channel;
    final subtitle =
        channel.groupTitle.isNotEmpty ? channel.groupTitle : 'Uncategorized';
    final country = channel.country?.trim();
    final text = country != null && country.isNotEmpty
        ? '$subtitle · $country'
        : subtitle;

    return Row(
      children: [
        if (widget.isPlaying) ...[
          _buildEqualizer(),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  /// Three gold bars that bounce while the channel is playing.
  Widget _buildEqualizer() {
    final reduceMotion = AppMotion.shouldReduceMotion(context);
    return SizedBox(
      width: 16,
      height: 12,
      child: AnimatedBuilder(
        animation: _eqCtrl,
        builder: (context, _) {
          final t = _eqCtrl.value;
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Container(
                  width: 2.5,
                  height: 2 + 10 * (reduceMotion ? 0.5 : _eqBarHeight(t, i)),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.gold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  double _eqBarHeight(double t, int index) {
    final v = math.sin(t * 2 * math.pi + index * 1.7);
    return (v + 1) / 2; // 0..1
  }

  Widget _buildTrailing() {
    final fav = widget.isFavorite;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildQualityBadge(),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: widget.onFavoriteTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: fav
                  ? AppDesignTokens.gold.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              fav ? Icons.star_rounded : Icons.star_outline_rounded,
              color: fav ? AppDesignTokens.gold : Colors.white54,
              size: 17,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQualityBadge() {
    final q = widget.channel.quality.toUpperCase();
    final (fg, bg, border) = switch (q) {
      '4K' => (
          AppDesignTokens.gold,
          AppDesignTokens.goldSoft,
          AppDesignTokens.gold.withValues(alpha: 0.4),
        ),
      'FHD' => (
          Colors.white,
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.14),
        ),
      'SD' => (
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.05),
          Colors.white.withValues(alpha: 0.07),
        ),
      _ => (
          Colors.white.withValues(alpha: 0.85),
          Colors.white.withValues(alpha: 0.07),
          Colors.white.withValues(alpha: 0.09),
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppDesignTokens.radiusSm,
        border: Border.all(color: border),
      ),
      child: Text(
        q,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final playing = widget.isPlaying;
    final logo = widget.channel.logoUrl;

    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: AppDesignTokens.radiusMd,
        border: Border.all(
          color: playing
              ? AppDesignTokens.gold.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.1),
          width: playing ? 2 : 1,
        ),
        boxShadow: playing
            ? [
                BoxShadow(
                  color: AppDesignTokens.gold.withValues(alpha: 0.22),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: AppDesignTokens.radiusSm,
        child: logo != null && logo.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: logo,
                fit: BoxFit.cover,
                placeholder: (_, _) => _fallback(),
                errorWidget: (_, _, _) => _fallback(),
                fadeInDuration: AppMotion.scaled(context, AppMotion.fast),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppDesignTokens.goldSoft,
            const Color(0xFF1E1E1E),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.live_tv_rounded,
          size: 24,
          color: AppDesignTokens.gold.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
