import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../design/motion.dart';
import 'package:http/http.dart' as http;

/// Brightness verdict for a fetched logo.
enum LogoBrightness {
  /// Logo not (yet) assessed — no fetch happened or verdict pending.
  unknown,

  /// Logo ink is dark (designed for light backgrounds). On a dark surface it
  /// would be invisible, so callers should put it on a lighter band.
  dark,

  /// Logo ink is bright (white/light). Shows fine on dark surfaces.
  bright,
}

/// Renders a movie/studio logo, always showing it when a [logoUrl] exists
/// (never swapping in plain text). It asynchronously measures the logo's ink
/// brightness and reports it through [onAssessed] so surrounding UI (e.g. a
/// backdrop band behind the title) can tune itself for contrast.
///
/// The text title is used only when there is no logo or the image fails.
class AdaptiveLogoTitle extends StatefulWidget {
  const AdaptiveLogoTitle({
    super.key,
    required this.title,
    required this.titleStyle,
    this.logoUrl,
    this.onAssessed,
    this.height = 64,
    this.maxLogoWidth = 220,
    this.alignment = Alignment.centerLeft,
    this.expandTitleToFullWidth = false,
    this.logoErrorWidget,
  });

  /// Fallback text (the movie / show name) when no logo exists / it errors.
  final String title;

  /// Text style used for the fallback title.
  final TextStyle titleStyle;

  /// Studio logo URL. When null the title is shown instead.
  final String? logoUrl;

  /// Called once the logo ink brightness is known (or known to be absent).
  final ValueChanged<LogoBrightness>? onAssessed;

  /// Box height reserved for the logo / title.
  final double height;

  /// Max horizontal footprint for wide studio logos.
  final double maxLogoWidth;

  /// Where the logo / title sit inside the reserved box.
  final Alignment alignment;

  /// When true the fallback title fills the whole available width (so it
  /// wraps/ellipsizes against the parent) instead of sizing to its text.
  final bool expandTitleToFullWidth;

  /// Replaces the default error state (which shows [title]).
  final Widget Function(BuildContext, String, Object)? logoErrorWidget;

  /// Mean Rec.709 luminance of opaque pixels (alpha-composited over black)
  /// of the decoded [image]. Transparent pixels are ignored.
  static Future<double> meanOpaqueLuminance(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return 0;
    final bytes = data.buffer.asUint8List();
    final stride = image.width > 128 ? 4 : 1; // sample for very wide images

    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < bytes.length; i += 4 * stride) {
      final r = bytes[i] / 255.0;
      final g = bytes[i + 1] / 255.0;
      final b = bytes[i + 2] / 255.0;
      final a = bytes[i + 3] / 255.0;
      if (a < 0.03) continue; // skip fully transparent pixels
      final luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) * a;
      sum += luma;
      count++;
    }
    return count == 0 ? 0 : sum / count;
  }

  /// Fetches [url] and classifies its ink brightness. Network/decode failures
  /// report [LogoBrightness.unknown].
  static Future<LogoBrightness> assessLogoBrightness(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        return LogoBrightness.unknown;
      }
      final codec = await ui.instantiateImageCodec(
        res.bodyBytes,
        targetWidth: 512,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final lum = await meanOpaqueLuminance(image);
        // A logo whose ink is very sparse/dim is treated as dark.
        return lum >= 0.5 ? LogoBrightness.bright : LogoBrightness.dark;
      } finally {
        image.dispose();
      }
    } catch (_) {
      return LogoBrightness.unknown;
    }
  }

  @override
  State<AdaptiveLogoTitle> createState() => _AdaptiveLogoTitleState();
}

class _AdaptiveLogoTitleState extends State<AdaptiveLogoTitle> {
  /// Session cache: logo URL → verdict. Avoids refetching on revisits.
  static final Map<String, LogoBrightness> _cache = {};

  @override
  void initState() {
    super.initState();
    _assess();
  }

  @override
  void didUpdateWidget(AdaptiveLogoTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logoUrl != widget.logoUrl) _assess();
  }

  Future<void> _assess() async {
    final url = widget.logoUrl;
    if (url == null || url.isEmpty) {
      widget.onAssessed?.call(LogoBrightness.unknown);
      return;
    }
    final cached = _cache[url];
    if (cached != null) {
      widget.onAssessed?.call(cached);
      return;
    }
    final verdict = await AdaptiveLogoTitle.assessLogoBrightness(url);
    _cache[url] = verdict;
    widget.onAssessed?.call(verdict);
  }

  @override
  Widget build(BuildContext context) {
    final title = Text(
      widget.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: widget.titleStyle,
    );

    Widget titleSlot() {
      final box = SizedBox(
        height: widget.height,
        width: widget.expandTitleToFullWidth ? double.infinity : null,
        child: Align(alignment: widget.alignment, child: title),
      );
      return widget.expandTitleToFullWidth ? Center(child: box) : box;
    }

    final logoUrl = widget.logoUrl;
    if (logoUrl == null || logoUrl.isEmpty) return titleSlot();

    return SizedBox(
      height: widget.height,
      width: widget.expandTitleToFullWidth ? double.infinity : widget.maxLogoWidth,
      child: CachedNetworkImage(
        imageUrl: logoUrl,
        fit: BoxFit.contain,
        alignment: widget.alignment,
        memCacheHeight: (widget.height * 2).round(),         fadeInDuration: AppMotion.scaled(context, AppMotion.standard),

        placeholder: (_, _) => const SizedBox.shrink(),
        errorWidget: widget.logoErrorWidget ?? (_, _, _) => titleSlot(),
      ),
    );
  }
}

