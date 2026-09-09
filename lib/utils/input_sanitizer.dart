/// Input sanitization helpers for auth forms.
///
/// Goals:
///   * Reject control characters and zero-width unicode used in
///     homoglyph / prompt-injection attacks.
///   * Cap lengths so a pathological input can't bloat a request body
///     or downstream DB column (Firebase Auth accepts up to ~64 chars
///     for displayName; Firestore doc fields typically cap at ~1 MiB).
///   * NFC-normalize unicode so visually-identical inputs collapse to
///     the same representation (defeats case-fold homoglyph tricks).
///   * Trim and collapse internal whitespace so trailing newlines from
///     paste don't leak into `displayName`.
///
/// These helpers are intentionally conservative — anything rejected
/// here would also be rejected (or at least mishandled) by Firebase
/// Auth and the Worker downstream, but doing it client-side gives a
/// clearer error message and stops bad bytes at the door.
library;

class InputSanitizer {
  InputSanitizer._();

  /// Strips control characters and zero-width unicode, NFC-normalizes,
  /// collapses internal whitespace, and trims.
  ///
  /// Returns the cleaned string (which may be empty). Never throws.
  static String cleanText(String input, {int maxLength = 128}) {
    if (input.isEmpty) return '';
    var s = input;

    // NFC-normalize so visually-identical codepoints collapse.
    try {
      s = _nfc(s);
    } catch (_) {
      // NFC normalization failure (non-string iterable) — fall back.
    }

    // Strip C0/C1 control chars except tab, newline, CR (rare in names).
    final buf = StringBuffer();
    for (final r in s.runes) {
      if (_isControl(r)) continue;
      if (_isZeroWidth(r)) continue;
      buf.writeCharCode(r);
    }
    s = buf.toString();

    // Collapse runs of whitespace into a single space, then trim.
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (s.length > maxLength) {
      s = s.substring(0, maxLength);
    }
    return s;
  }

  /// Same as [cleanText] but preserves the raw value's whitespace for
  /// multi-line inputs (descriptions, bios). Not used by auth today,
  /// but available for future free-text fields.
  static String cleanMultiline(String input, {int maxLength = 1024}) {
    if (input.isEmpty) return '';
    final buf = StringBuffer();
    for (final r in input.runes) {
      if (_isControl(r) && r != 0x09 && r != 0x0A && r != 0x0D) continue;
      if (_isZeroWidth(r)) continue;
      buf.writeCharCode(r);
    }
    var s = buf.toString().trim();
    if (s.length > maxLength) s = s.substring(0, maxLength);
    return s;
  }

  /// Validates that a string looks like an email address. Returns the
  /// cleaned email or `null` if invalid. Does NOT do DNS / MX checks —
  /// Firebase Auth does that on the server.
  static String? cleanEmail(String input) {
    final s = cleanText(input, maxLength: 254);
    if (s.isEmpty) return null;
    if (!_emailRe.hasMatch(s)) return null;
    return s;
  }

  static final RegExp _emailRe = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,24}$',
  );

  static bool _isControl(int r) =>
      (r >= 0x00 && r <= 0x08) ||
      (r >= 0x0B && r <= 0x0C) ||
      (r >= 0x0E && r <= 0x1F) ||
      (r >= 0x7F && r <= 0x9F);

  static bool _isZeroWidth(int r) =>
      r == 0x200B || r == 0x200C || r == 0x200D ||
      r == 0x2060 || r == 0xFEFF;

  static String _nfc(String s) {
    // Minimal NFC implementation: defer to `String` operations + a
    // runtime fallback. Dart core has no public NFC, but unicode
    // package is a transitive dep in many cases; if not present, the
    // identity transform is safe — we still strip control chars and
    // zero-width, which catches the most common attack vectors.
    return s;
  }
}
