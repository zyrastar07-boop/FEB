import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../screens/legal_screen.dart';
import '../services/legal_consent_service.dart';

/// Full-screen, non-bypassable gate that blocks app usage until the user
/// accepts the Terms of Service and Privacy Policy.
///
/// Wraps the app's home widget (alongside [MaintenanceGate]); while consent
/// is missing the user only ever sees the consent screen — no back button,
/// no system-back dismissal, no skip. Acceptance is stored once and re-used
/// on every subsequent launch.
class LegalConsentGate extends StatefulWidget {
  final Widget child;

  const LegalConsentGate({super.key, required this.child});

  @override
  State<LegalConsentGate> createState() => _LegalConsentGateState();
}

class _LegalConsentGateState extends State<LegalConsentGate> {
  bool? _accepted; // null while loading

  @override
  void initState() {
    super.initState();
    LegalConsentService.instance.hasAccepted().then((accepted) {
      if (mounted) setState(() => _accepted = accepted);
    });
  }

  Future<void> _accept() async {
    await LegalConsentService.instance.accept();
    if (mounted) setState(() => _accepted = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted == null) {
      // Brief blank while the stored flag is read — avoids a flash of the
      // consent screen for users who already accepted.
      return const Scaffold(
        backgroundColor: AppDesignTokens.backgroundCanvas,
        body: SizedBox.shrink(),
      );
    }
    if (_accepted == true) return widget.child;
    return _ConsentScreen(onAccept: _accept);
  }
}

class _ConsentScreen extends StatelessWidget {
  final VoidCallback onAccept;

  const _ConsentScreen({required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppDesignTokens.backgroundCanvas,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.shield_outlined,
                        color: AppDesignTokens.gold, size: 44),
                    const SizedBox(height: 16),
                    const Text(
                      'Welcome to FEB',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Before you continue, please review and accept our '
                      'Terms of Service and Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SummaryCard(
                      title: 'What you agree to',
                      lines: const [
                        'FEB is a personal media companion. Content availability '
                            'depends on the servers and sources you configure.',
                        'Your watch history, lists, and downloads stay on this '
                            'device unless you sign in and sync via your account.',
                        'We do not sell personal data. See the full Privacy '
                            'Policy for your GDPR/CCPA rights.',
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LegalScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Read the full Terms of Service & Privacy Policy',
                        style: TextStyle(
                          color: AppDesignTokens.gold,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppDesignTokens.gold,
                          foregroundColor: AppDesignTokens.textOnGold,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        onPressed: onAccept,
                        child: const Text(
                          'I Agree — Continue',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'By continuing you accept the Terms of Service and '
                      'confirm you have read the Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final List<String> lines;

  const _SummaryCard({required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceElevated,
        borderRadius: AppDesignTokens.radiusMd,
        border: Border.all(color: AppDesignTokens.borderCork, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppDesignTokens.textCream,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(Icons.circle,
                        size: 5, color: AppDesignTokens.gold),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}