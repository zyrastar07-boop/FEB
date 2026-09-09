import 'package:flutter/material.dart';

/// Cloudflare Turnstile challenge wrapper.
///
/// Server-side verification keys (secret + siteverify) live in the Worker
/// repo (this client only knows the public site key). When
/// [TURNSTILE_SITE_KEY] is empty, the widget renders an immediate pass so
/// forks / dev builds aren't blocked. In production builds the key is
/// injected via `--dart-define=TURNSTILE_SITE_KEY=…` (see `.env.example`).
///
/// This is a stub: the real Turnstile widget is rendered server-side by
/// the Worker as a challenge page or via the official Flutter Turnstile
/// SDK once it's added as a dependency. The widget exposes the contract
/// the auth screens depend on so they can be wired up today.
class TurnstileGate extends StatefulWidget {
  const TurnstileGate({
    super.key,
    required this.onVerified,
    this.actionLabel,
  });

  /// Called once the user has cleared the challenge. The parent should
  /// proceed with the underlying auth action (sign-in, sign-up, …).
  final ValueChanged<String> onVerified;

  /// Optional label rendered above the challenge (e.g. "Verify before
  /// signing in"). Cosmetic only.
  final String? actionLabel;

  /// Build-time site key. Injected at compile time; never logged.
  static const String siteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');

  @override
  State<TurnstileGate> createState() => _TurnstileGateState();
}

class _TurnstileGateState extends State<TurnstileGate> {
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    if (TurnstileGate.siteKey.isEmpty) {
      // No key configured (dev / fork). Auto-pass so the screen still
      // functions and the contract is exercised in tests.
      _verified = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onVerified('dev-bypass');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verified) {
      return const SizedBox.shrink();
    }

    // Production rendering lives behind the real Turnstile SDK / WebView
    // integration (out of scope for this client-side hardening pass).
    // For now, surface a clear "Pending integration" banner so the
    // missing piece is visible.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.amber, size: 18),
              SizedBox(width: 8),
              Text(
                'Bot verification pending',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Cloudflare Turnstile is not yet wired into the client. '
            'Server-side rate limits still apply.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          if (widget.actionLabel != null)
            Text(
              widget.actionLabel!,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
        ],
      ),
    );
  }
}
