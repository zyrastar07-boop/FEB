import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'adaptive_logo_title.dart';

/// Poster-matched gradient band that hosts the movie logo and makes it
/// readable regardless of ink color.
///
/// A representative color is sampled from the movie artwork ([backdropUrl]).
/// The band's *top zone* (where the logo sits) is tuned to the logo ink:
///
///  * dark logo → the zone is lifted toward a light tint so the dark ink pops
///  * white logo → the zone stays dark so the white ink keeps contrast
///  * no logo / still assessing → neutral poster-tinted mid zone
///
/// Below the logo zone the band always fades into the app's page background
/// so the white metadata text that follows stays readable, and the band
/// reads as the hero artwork fading down the page.
class PosterLogoBand extends StatefulWidget {
  const PosterLogoBand({
    super.key,
    required this.title,
    required this.titleStyle,
    required this.logoUrl,
    required this.backdropUrl,
    this.logoHeight = 64,
    this.height = 210,
  });

  /// Movie / show name (fallback text if the logo image errors).
  final String title;

  /// Text style for the fallback title.
  final TextStyle titleStyle;

  /// Studio logo URL (always shown when present).
  final String? logoUrl;

  /// Artwork whose palette drives the band (hero backdrop/poster).
  final String? backdropUrl;

  /// Height reserved for the logo block.
  final double logoHeight;

  /// Total band height — the logo zone occupies the top, the rest fades to
  /// the page background.
  final double height;

  @override
  State<PosterLogoBand> createState() => _PosterLogoBandState();
}

class _PosterLogoBandState extends State<PosterLogoBand> {
  static const Color _pageBg = Color(0xFF08090D);

  /// Session cache: artwork URL → sampled representative color.
  static final Map<String, Color> _artCache = {};

  /// Session cache: logo URL → ink brightness verdict.
  static final Map<String, LogoBrightness> _logoCache = {};

  LogoBrightness _logo = LogoBrightness.unknown;
  Color _artColor = const Color(0xFF23272E); // neutral while sampling

  @override
  void initState() {
    super.initState();
    _sampleArtwork();
    _assessLogo();
  }

  @override
  void didUpdateWidget(PosterLogoBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backdropUrl != widget.backdropUrl) {
      _artColor = const Color(0xFF23272E);
      _sampleArtwork();
    }
    if (oldWidget.logoUrl != widget.logoUrl) _assessLogo();
  }

  Future<void> _sampleArtwork() async {
    final url = widget.backdropUrl;
    if (url == null || url.isEmpty) return;
    final cached = _artCache[url];
    if (cached != null) {
      if (mounted && cached != _artColor) setState(() => _artColor = cached);
      return;
    }
    final color = await fetchRepresentativeColor(url);
    if (color != null) {
      _artCache[url] = color;
      if (mounted) setState(() => _artColor = color);
    }
  }

  Future<void> _assessLogo() async {
    final url = widget.logoUrl;
    if (url == null || url.isEmpty) return;
    final cached = _logoCache[url];
    if (cached != null) {
      if (mounted && cached != _logo) setState(() => _logo = cached);
      return;
    }
    final verdict = await AdaptiveLogoTitle.assessLogoBrightness(url);
    _logoCache[url] = verdict;
    if (mounted && verdict != _logo) setState(() => _logo = verdict);
  }

  /// Fetches + downsamples [url] and returns the mean color of its opaque
  /// pixels. Null on any failure (callers keep their neutral fallback).
  static Future<Color?> fetchRepresentativeColor(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(
        res.bodyBytes,
        targetWidth: 64,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return null;
        final bytes = data.buffer.asUint8List();
        var r = 0.0, g = 0.0, b = 0.0, count = 0.0;
        for (var i = 0; i < bytes.length; i += 4) {
          final a = bytes[i + 3] / 255.0;
          if (a < 0.1) continue;
          r += bytes[i] * a;
          g += bytes[i + 1] * a;
          b += bytes[i + 2] * a;
          count += a;
        }
        if (count == 0) return null;
        return Color.fromARGB(
          255,
          (r / count).round().clamp(0, 255).toInt(),
          (g / count).round().clamp(0, 255).toInt(),
          (b / count).round().clamp(0, 255).toInt(),
        );
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// How far the band top is lifted toward white/black for the logo ink.
  double get _lift {
    return switch (_logo) {
      LogoBrightness.dark => 0.74, // dark ink → light zone behind it
      LogoBrightness.bright => 0.08, // white ink → keep the zone dark
      LogoBrightness.unknown => 0.34, // neutral until we know
    };
  }

  @override
  Widget build(BuildContext context) {
    // Paint colors for the gradient:
    //   lit   – the logo zone (lifted poster color)
    //   mid   – transition, still tinted but dark enough for white text
    //   pageBg – where the band ends (bottom edge is invisible vs the page)
    final lit = Color.lerp(_artColor, Colors.white, _lift)!;
    final mid = Color.lerp(lit, _pageBg, 0.72)!;
    final colors = [lit, mid, _pageBg];

    final logoSlotTop = 6.0;
    final slotFraction =
        (logoSlotTop + widget.logoHeight) / widget.height; // ≈ upper zone

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, slotFraction.clamp(0.0, 0.75), 1.0],
            colors: colors,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: logoSlotTop,
                child: const SizedBox.shrink(),
              ),
              SizedBox(
                height: widget.logoHeight,
                width: double.infinity,
                child: AdaptiveLogoTitle(
                  title: widget.title,
                  titleStyle: widget.titleStyle,
                  logoUrl: widget.logoUrl,
                  height: widget.logoHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
