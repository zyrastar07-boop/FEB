import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Full-screen legal document viewer.
///
/// Contains placeholder boilerplate for the Terms of Service and the Privacy
/// Policy, including the disclosure structure required by GDPR (EU) and CCPA
/// (California). The text below is a compliance *skeleton* — every
/// `[Placeholder]` must be filled in and the final wording reviewed by legal
/// counsel before production use.
class LegalScreen extends StatefulWidget {
  /// Which section to open first: 'terms' or 'privacy'.
  final String initialSection;

  const LegalScreen({super.key, this.initialSection = 'terms'});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late String _section;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection == 'privacy' ? 'privacy' : 'terms';
  }

  void _select(String section) {
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundCanvas,
      appBar: AppBar(
        title: const Text('Legal'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          TextButton(
            onPressed: () => _select(_section == 'terms' ? 'privacy' : 'terms'),
            child: Text(
              _section == 'terms' ? 'Privacy Policy' : 'Terms of Service',
              style: const TextStyle(
                color: AppDesignTokens.gold,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                _tab('Terms of Service', 'terms'),
                const SizedBox(width: 10),
                _tab('Privacy Policy', 'privacy'),
              ],
            ),
          ),
          Expanded(
            child: _section == 'terms'
                ? const _TermsDocument()
                : const _PrivacyDocument(),
          ),
        ],
      ),
    );
  }

  Widget _tab(String label, String value) {
    final selected = _section == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _select(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppDesignTokens.gold.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: AppDesignTokens.radiusMd,
            border: Border.all(
              color: selected
                  ? AppDesignTokens.gold
                  : AppDesignTokens.borderCork,
              width: 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? AppDesignTokens.gold
                  : Colors.white54,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Shared document scaffolding
// ────────────────────────────────────────────────────────────────────────────

class _LegalDoc extends StatelessWidget {
  final String effectiveDate;
  final String intro;
  final List<_DocSectionData> sections;

  const _LegalDoc({
    required this.effectiveDate,
    required this.intro,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppDesignTokens.gold.withValues(alpha: 0.08),
            borderRadius: AppDesignTokens.radiusMd,
            border: Border.all(
              color: AppDesignTokens.gold.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: const Text(
            'Placeholder draft — pending legal review. Replace [bracketed] '
            'fields and have this document reviewed by counsel before release.',
            style: TextStyle(
              color: AppDesignTokens.gold,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          effectiveDate,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Text(
          intro,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        for (final s in sections) ...[
          _DocSection(s),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _DocSectionData {
  final String title;
  final List<String> paragraphs;
  final List<String> bullets;

  const _DocSectionData(this.title, {this.paragraphs = const [], this.bullets = const []});
}

class _DocSection extends StatelessWidget {
  final _DocSectionData data;

  const _DocSection(this.data);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (data.paragraphs.isNotEmpty)
          for (final p in data.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                p,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
        if (data.bullets.isNotEmpty)
          for (final b in data.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle,
                        size: 5, color: AppDesignTokens.gold),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Terms of Service
// ────────────────────────────────────────────────────────────────────────────

class _TermsDocument extends StatelessWidget {
  const _TermsDocument();

  @override
  Widget build(BuildContext context) {
    return const _LegalDoc(
      effectiveDate: 'Effective date: [Date] · Last updated: [Date]',
      intro:
          'These Terms of Service ("Terms") govern your use of the FEB '
          'application ("the App") operated by [Company Name] ("we", "us", '
          '"our"). By installing, accessing, or using the App, you agree to '
          'be bound by these Terms.',
      sections: [
        _DocSectionData('1. Acceptance of Terms',
            paragraphs: [
              'By creating an account, signing in, or continuing to use the '
                  'App, you confirm that you have read, understood, and agree '
                  'to these Terms and our Privacy Policy. If you do not agree, '
                  'do not use the App.',
            ]),
        _DocSectionData('2. License & Permitted Use',
            paragraphs: [
              'We grant you a limited, non-exclusive, non-transferable, '
                  'revocable license to use the App for personal, '
                  'non-commercial purposes, subject to these Terms. You may '
                  'not copy, modify, distribute, sell, or lease any part of '
                  'the App, or use it to build a competing product.',
            ]),
        _DocSectionData('3. Accounts & Security',
            paragraphs: [
              'You are responsible for safeguarding your account credentials '
                  'and for all activity under your account. Notify us '
                  'immediately of any unauthorized use at [Support Email].',
            ]),
        _DocSectionData('4. Content & Third-Party Sources',
            paragraphs: [
              'The App is a media companion. Availability of titles and '
                  'streams depends on third-party servers and sources you '
                  'configure. We do not host, produce, or license the media '
                  'content accessed through the App, and we are not '
                  'responsible for the availability, legality, or quality of '
                  'third-party content. You are responsible for ensuring your '
                  'use of the App complies with applicable law.',
            ]),
        _DocSectionData('5. Acceptable Use',
            bullets: [
              'Do not use the App to infringe any copyright, trademark, or '
                  'other intellectual property right.',
              'Do not attempt to circumvent, disable, or interfere with '
                  'security-related features of the App.',
              'Do not use the App in a way that violates applicable law, '
                  'including export or content laws of your jurisdiction.',
              'Do not reverse engineer, decompile, or extract the source '
                  'code of the App.',
            ]),
        _DocSectionData('6. Termination',
            paragraphs: [
              'We may suspend or terminate your access to the App at any '
                  'time, with or without notice, if you breach these Terms. '
                  'You may stop using the App at any time by uninstalling it.',
            ]),
        _DocSectionData('7. Disclaimer of Warranties',
            paragraphs: [
              'The App is provided "as is" and "as available" without '
                  'warranties of any kind, express or implied, including '
                  'implied warranties of merchantability, fitness for a '
                  'particular purpose, and non-infringement.',
            ]),
        _DocSectionData('8. Limitation of Liability',
            paragraphs: [
              'To the maximum extent permitted by law, we shall not be '
                  'liable for any indirect, incidental, special, consequential, '
                  'or punitive damages, or any loss of data, arising out of '
                  'or in connection with your use of the App.',
            ]),
        _DocSectionData('9. Changes to These Terms',
            paragraphs: [
              'We may update these Terms from time to time. Material changes '
                  'will be communicated in the App. Continued use after '
                  'changes take effect constitutes acceptance of the revised '
                  'Terms.',
            ]),
        _DocSectionData('10. Contact',
            paragraphs: [
              'Questions about these Terms? Contact us at [Support Email] or '
                  '[Mailing Address].',
            ]),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Privacy Policy (incl. GDPR / CCPA structure)
// ────────────────────────────────────────────────────────────────────────────

class _PrivacyDocument extends StatelessWidget {
  const _PrivacyDocument();

  @override
  Widget build(BuildContext context) {
    return const _LegalDoc(
      effectiveDate: 'Effective date: [Date] · Last updated: [Date]',
      intro:
          'This Privacy Policy explains what information the FEB application '
          '("the App") collects, why we collect it, how it is used, and the '
          'choices and rights you have — including the rights granted to you '
          'under the EU General Data Protection Regulation (GDPR) and the '
          'California Consumer Privacy Act (CCPA).',
      sections: [
        _DocSectionData('1. Information We Collect',
            paragraphs: [
              'We collect information you provide directly, such as your '
                  'account details (name, email) when you sign in, and '
                  'information collected automatically, such as device type, '
                  'app version, and usage events needed to operate the App.',
              'Content you interact with (watch history, lists, downloads) '
                  'is stored primarily on your device. Some of it may sync to '
                  'our servers when you sign in, solely to restore your '
                  'experience across devices.',
            ]),
        _DocSectionData('2. How We Use Information',
            bullets: [
              'Provide, maintain, and improve the App and its features.',
              'Sync your library across devices when you are signed in.',
              'Send service notifications you have opted into (e.g., new '
                  'episode alerts).',
              'Respond to support requests and enforce our Terms.',
              'We do NOT sell your personal information.',
            ]),
        _DocSectionData('3. Storage & Security',
            paragraphs: [
              'Sensitive local values are encrypted at rest on your device '
                  'using AES-256-GCM. Data transmitted to our servers is sent '
                  'over TLS. No method of transmission or storage is 100% '
                  'secure, and we cannot guarantee absolute security.',
            ]),
        _DocSectionData('4. GDPR Rights (EU/EEA Users)',
            paragraphs: [
              'If you are located in the European Economic Area, you have '
                  'the following rights under the GDPR, subject to '
                  'applicable exceptions:',
            ],
            bullets: [
              'Right of access — obtain a copy of the personal data we hold '
                  'about you.',
              'Right to rectification — correct inaccurate or incomplete data.',
              'Right to erasure ("right to be forgotten") — request deletion '
                  'of your personal data.',
              'Right to data portability — receive your data in a '
                  'machine-readable format and transmit it elsewhere.',
              'Right to restriction of processing — limit how we use your '
                  'data in certain circumstances.',
              'Right to object — object to processing based on legitimate '
                  'interests or for direct marketing.',
              'Right to withdraw consent — where processing is based on '
                  'consent, withdraw it at any time.',
              'Right to lodge a complaint — with your local supervisory '
                  'authority (e.g., [Data Protection Authority]).',
            ]),
        _DocSectionData('5. CCPA Rights (California Residents)',
            paragraphs: [
              'Under the California Consumer Privacy Act (CCPA) / California '
                  'Privacy Rights Act (CPRA), California residents have the '
                  'following rights:',
            ],
            bullets: [
              'Right to know — request disclosure of the categories and '
                  'specific pieces of personal information we have collected '
                  'about you, and how it is used and shared.',
              'Right to delete — request deletion of personal information we '
                  'have collected, subject to exceptions.',
              'Right to correct — request correction of inaccurate personal '
                  'information.',
              'Right to opt-out of sale/sharing — we do not sell personal '
                  'information; if that changes we will update this policy '
                  'and provide an opt-out.',
              'Right to non-discrimination — we will not discriminate '
                  'against you for exercising your CCPA rights.',
              'Right to limit sensitive data use — where we process '
                  'sensitive personal information, we limit it to what is '
                  'necessary to provide the App.',
            ]),
        _DocSectionData('6. How to Exercise Your Rights',
            paragraphs: [
              'To exercise any of the rights above, email [Privacy Email] or '
                  'use the in-app "Privacy & data" settings. We will respond '
                  'within the timeframe required by law (generally 30–45 '
                  'days). We may ask you to verify your identity before '
                  'fulfilling a request. You may designate an authorized '
                  'agent to submit requests on your behalf.',
            ]),
        _DocSectionData('7. Data Retention',
            paragraphs: [
              'We retain personal data only as long as necessary for the '
                  'purposes described in this policy, to comply with legal '
                  'obligations, or to resolve disputes. Locally stored '
                  'content is deleted when you clear it or uninstall the App.',
            ]),
        _DocSectionData('8. Children\'s Privacy',
            paragraphs: [
              'The App is not directed to children under [13/16]. We do not '
                  'knowingly collect personal information from children. If '
                  'you believe a child has provided us personal information, '
                  'contact [Privacy Email] and we will delete it.',
            ]),
        _DocSectionData('9. Contact & Data Controller',
            paragraphs: [
              'For privacy questions or requests: [Privacy Email] · '
                  '[Mailing Address] · Attn: Privacy. The data controller for '
                  'GDPR purposes is [Company Name], [Address].',
            ]),
      ],
    );
  }
}