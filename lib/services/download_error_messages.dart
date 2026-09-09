/// Translates raw download failure strings into short, user-friendly
/// messages for the downloads list UI.
class DownloadErrorMessages {
  DownloadErrorMessages._();

  /// Returns a compact human-readable message for [raw].
  ///
  /// Pattern order matters: specific signals first, generic fallback last.
  static String friendly(String raw) {
    final lower = raw.toLowerCase();

    // Range/partial-content failures — resume will not fix a 416.
    if (lower.contains('416') ||
        lower.contains('range not satisfiable')) {
      return 'Download data is out of range. Delete and re-download.';
    }

    // Storage pressure — the most actionable failure for big files.
    if (lower.contains('enospc') ||
        lower.contains('no space left') ||
        lower.contains('insufficient storage') ||
        lower.contains('not enough space')) {
      return 'Not enough storage space.';
    }

    // Network / connectivity.
    if (lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('network is unreachable') ||
        lower.contains('failed host lookup') ||
        lower.contains('software caused connection abort')) {
      return 'Network connection lost. Check your internet.';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'The connection timed out.';
    }

    // Source availability.
    if (lower.contains('403') || lower.contains('forbidden')) {
      return 'The source refused the request.';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'The video is no longer available at this source.';
    }
    if (lower.contains('429') || lower.contains('too many requests')) {
      return 'The source is rate limiting. Try again later.';
    }
    if (lower.contains('5')) {
      return 'The source server is having trouble.';
    }

    // HLS-specific failures from the segment downloader.
    if (lower.contains('segment') || lower.contains('hls')) {
      return 'Stream segments failed to download.';
    }

    // Container verification (post-download repair failed).
    if (lower.contains('container could not be verified') ||
        lower.contains('verify')) {
      return 'The downloaded file failed verification.';
    }

    // Debrid / resolution failures propagated from playback.
    if (lower.contains('notcached') ||
        lower.contains('not cached') ||
        lower.contains('debrid')) {
      return 'Debrid could not resolve this source.';
    }

    // Final fallback: trim the noisy Exception("...") wrapper to something
    // readable but honest, never blank.
    var text = raw.replaceFirst(RegExp(r'^\s*Exception:\s*', caseSensitive: false), '').trim();
    if (text.isEmpty) text = raw.trim();
    if (text.isEmpty) return 'Download failed.';
    if (text.length > 90) text = '${text.substring(0, 87)}…';
    return text;
  }
}
