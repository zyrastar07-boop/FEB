import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/font_service.dart';
import '../services/payment_service.dart';
import '../widgets/liquid_glass.dart';

const _gold = Color(0xFFD4AF37);
const _bg = Color(0xFF0A0A0A);

class ManageSubscriptionScreen extends StatefulWidget {
  const ManageSubscriptionScreen({super.key});

  @override
  State<ManageSubscriptionScreen> createState() =>
      _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState extends State<ManageSubscriptionScreen> {
  PaymentRegion _region = PaymentRegion.ethiopia;
  SubscriptionTier _selectedTier = SubscriptionTier.premiumMonthly;
  bool _busy = false;
  String? _statusMessage;
  bool _statusSuccess = false;

  PaymentService get _pay => PaymentService.instance;

  @override
  void initState() {
    super.initState();
    _pay.init().then((_) {
      if (mounted) setState(() {});
    });
    _pay.addListener(_onPayChanged);
  }

  @override
  void dispose() {
    _pay.removeListener(_onPayChanged);
    super.dispose();
  }

  void _onPayChanged() {
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _runPayment(Future<PaymentResult> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        _statusSuccess = result.success;
        _statusMessage = result.message;
      });
      if (result.success) {
        HapticFeedback.mediumImpact();
        _toast(result.message);
      } else {
        HapticFeedback.heavyImpact();
        _toast(result.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusSuccess = false;
        _statusMessage = e.toString();
      });
      _toast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Ethiopian verification modal ─────────────────────────────────────

  Widget _payToCard({
    required String label,
    required String value,
    IconData icon = Icons.phone_android_rounded,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              _toast('Copied $value');
            },
            icon: const Icon(Icons.copy_rounded, color: _gold, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _openEthiopianVerify(String provider) async {
    final refCtrl = TextEditingController();
    // CBE suffix is fixed to your account's last 8 digits — customer does not type it.
    final suffixCtrl =
        TextEditingController(text: PaymentService.cbeAccountSuffix);
    // CBE Birr verification needs the *sender* phone that appears on the receipt.
    final senderPhoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final title = switch (provider) {
      'telebirr' => 'Telebirr verification',
      'cbe' => 'CBE transfer verification',
      'cbebirr' => 'CBE Birr verification',
      _ => 'Verify payment',
    };

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: FontService.instance.display(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    provider == 'telebirr'
                        ? 'Send the plan amount to the Telebirr number below, then enter the transaction number from your SMS/receipt.'
                        : provider == 'cbe'
                            ? 'Transfer the plan amount to the CBE account below, then enter the FT reference from your receipt.'
                            : 'Send the plan amount via CBE Birr to the number below, then enter the receipt number.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  // Always show where money must go
                  if (provider == 'telebirr' || provider == 'cbebirr')
                    _payToCard(
                      label: provider == 'telebirr'
                          ? 'Send Telebirr to'
                          : 'Send CBE Birr to',
                      value: PaymentService.merchantPhone,
                      icon: Icons.phone_android_rounded,
                    ),
                  if (provider == 'cbe')
                    _payToCard(
                      label: 'CBE account number',
                      value: PaymentService.cbeAccountNumber,
                      icon: Icons.account_balance_rounded,
                    ),
                  Text(
                    'Amount due: ${_formatPrice(_pay.priceFor(_selectedTier, PaymentRegion.ethiopia))} ETB',
                    style: const TextStyle(color: _gold, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: refCtrl,
                    style: const TextStyle(color: Colors.white),
                    textCapitalization: TextCapitalization.characters,
                    decoration: _fieldDecoration(
                      provider == 'telebirr'
                          ? 'Your transaction number'
                          : provider == 'cbebirr'
                              ? 'Your receipt number'
                              : 'Your reference number (e.g. FT…)',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      return null;
                    },
                  ),
                  if (provider == 'cbe') ...[
                    const SizedBox(height: 12),
                    // Suffix is pre-filled from your account — read-only display
                    TextFormField(
                      controller: suffixCtrl,
                      readOnly: true,
                      style: const TextStyle(color: Colors.white70),
                      decoration: _fieldDecoration(
                        'Account suffix (auto: last 8 of your CBE account)',
                      ),
                    ),
                  ],
                  if (provider == 'cbebirr') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: senderPhoneCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.phone,
                      decoration: _fieldDecoration(
                        'Your phone (the one that sent the CBE Birr)',
                      ),
                      validator: (v) {
                        if (v == null ||
                            v.replaceAll(RegExp(r'\s+'), '').length < 9) {
                          return 'Enter the sender phone on the receipt';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        if (formKey.currentState?.validate() != true) return;
                        Navigator.pop(ctx, true);
                      },
                      child: const Text(
                        'Verify payment',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await _runPayment(() => _pay.verifyEthiopianPayment(
          provider: provider,
          reference: refCtrl.text.trim(),
          accountSuffix:
              provider == 'cbe' ? PaymentService.cbeAccountSuffix : null,
          // CBE Birr: Verify.et needs the *sender* phone from the receipt.
          phone: provider == 'cbebirr' ? senderPhoneCtrl.text.trim() : null,
          expectedAmount:
              _pay.priceFor(_selectedTier, PaymentRegion.ethiopia),
          tier: _selectedTier,
        ));
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      counterText: '',
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  String _formatPrice(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  // ── International handlers ───────────────────────────────────────────

  Future<void> _payPatreon() async {
    await _runPayment(() => _pay.authenticatePatreonTier());
  }

  /// Functional “I’ve subscribed” — asks for Patreon email and verifies.
  Future<void> _confirmPatreon() async {
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final email = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Confirm Patreon membership',
                  style: FontService.instance.display(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter the same email you used when joining on Patreon. We check that an active membership exists before unlocking Premium.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: emailCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: _fieldDecoration('Patreon account email'),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty || !s.contains('@')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      if (formKey.currentState?.validate() != true) return;
                      Navigator.pop(ctx, emailCtrl.text.trim());
                    },
                    child: const Text(
                      'Verify membership',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (email == null || email.isEmpty || !mounted) return;
    await _runPayment(
      () => _pay.confirmPatreonPledge(email: email, tier: _selectedTier),
    );
  }

  Future<void> _cancelSub() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Cancel Premium?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'You will keep access until the current period ends on this device, then return to Free.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Premium',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel plan',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _pay.cancelSubscription();
      _toast('Subscription cancelled');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 24),
                    children: [
                      _buildStatusCard(),
                      const SizedBox(height: 20),
                      _buildRegionToggle(),
                      const SizedBox(height: 20),
                      Text(
                        'Choose a plan',
                        style: FontService.instance.label(
                          color: Colors.white38,
                          fontSize: 11,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _tierCard(
                        SubscriptionTier.free,
                        'Free',
                        'Ads · Standard quality · Limited downloads',
                        '0',
                      ),
                      _tierCard(
                        SubscriptionTier.premiumMonthly,
                        'Premium Monthly',
                        'Ad-free · 1080p · Unlimited downloads',
                        _formatPrice(
                          _pay.priceFor(
                            SubscriptionTier.premiumMonthly,
                            _region,
                          ),
                        ),
                        badge: 'Popular',
                      ),
                      _tierCard(
                        SubscriptionTier.premiumYearly,
                        'Premium Yearly',
                        'Everything in Monthly · 2 months free',
                        _formatPrice(
                          _pay.priceFor(
                            SubscriptionTier.premiumYearly,
                            _region,
                          ),
                        ),
                        badge: 'Best value',
                      ),
                      const SizedBox(height: 18),
                      if (_selectedTier != SubscriptionTier.free) ...[
                        Text(
                          _region == PaymentRegion.ethiopia
                              ? 'Pay with Ethiopian methods'
                              : 'Pay internationally',
                          style: FontService.instance.label(
                            color: Colors.white38,
                            fontSize: 11,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_region == PaymentRegion.ethiopia)
                          ..._localMethods()
                        else
                          ..._internationalMethods(),
                      ],
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 16),
                        _statusBanner(),
                      ],
                      if (_pay.isPremium) ...[
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: _busy ? null : _cancelSub,
                          child: const Text(
                            'Cancel subscription',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_busy) _loadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 18),
          ),
          Expanded(
            child: Text(
              'Manage Subscription',
              style: FontService.instance.display(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final premium = _pay.isPremium;
    return LiquidGlassContainer(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      borderColor: premium ? _gold.withValues(alpha: 0.45) : null,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: premium
                  ? const LinearGradient(
                      colors: [Color(0xFFF39C12), _gold],
                    )
                  : null,
              color: premium ? null : Colors.white12,
            ),
            child: Icon(
              premium ? Icons.workspace_premium_rounded : Icons.person_outline,
              color: premium ? Colors.black : Colors.white54,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _pay.tierLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _pay.statusLabel,
                  style: TextStyle(
                    color: premium ? _gold : Colors.white54,
                    fontSize: 12,
                  ),
                ),
                if (_pay.lastProvider != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'via ${_pay.lastProvider}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          if (premium)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _gold.withValues(alpha: 0.5)),
              ),
              child: const Text(
                'ACTIVE',
                style: TextStyle(
                  color: _gold,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRegionToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _regionChip(
            PaymentRegion.ethiopia,
            'Local (Ethiopia)',
            Icons.flag_rounded,
          ),
          _regionChip(
            PaymentRegion.international,
            'International',
            Icons.public_rounded,
          ),
        ],
      ),
    );
  }

  Widget _regionChip(PaymentRegion region, String label, IconData icon) {
    final selected = _region == region;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _region = region);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _gold.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: selected
                ? Border.all(color: _gold.withValues(alpha: 0.4))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16, color: selected ? _gold : Colors.white38),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _gold : Colors.white54,
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tierCard(
    SubscriptionTier tier,
    String title,
    String subtitle,
    String price, {
    String? badge,
  }) {
    final selected = _selectedTier == tier;
    final currency =
        _region == PaymentRegion.ethiopia ? 'ETB' : 'USD';
    final period = tier == SubscriptionTier.premiumYearly
        ? '/ year'
        : tier == SubscriptionTier.premiumMonthly
            ? '/ month'
            : '';

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedTier = tier);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: LiquidGlassContainer(
          borderRadius: 16,
          padding: const EdgeInsets.all(14),
          borderColor: selected ? _gold.withValues(alpha: 0.5) : null,
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? _gold : Colors.white38,
                    width: 2,
                  ),
                  color: selected ? _gold : Colors.transparent,
                ),
                child: selected
                    ? const Icon(Icons.check, size: 14, color: Colors.black)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _gold.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(
                                color: _gold,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    tier == SubscriptionTier.free ? 'Free' : '$price $currency',
                    style: TextStyle(
                      color: selected ? _gold : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (period.isNotEmpty)
                    Text(
                      period,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _localMethods() {
    return [
      _payMethodTile(
        icon: Icons.phone_android_rounded,
        title: 'Telebirr',
        subtitle: 'Pay to ${PaymentService.merchantPhone}',
        onTap: () => _openEthiopianVerify('telebirr'),
      ),
      _payMethodTile(
        icon: Icons.account_balance_rounded,
        title: 'CBE (Commercial Bank)',
        subtitle: 'Account ${PaymentService.cbeAccountNumber}',
        onTap: () => _openEthiopianVerify('cbe'),
      ),
      _payMethodTile(
        icon: Icons.payments_outlined,
        title: 'CBE Birr',
        subtitle: 'Pay to ${PaymentService.merchantPhone}',
        onTap: () => _openEthiopianVerify('cbebirr'),
      ),
    ];
  }

  List<Widget> _internationalMethods() {
    // International: Patreon only (no cards / Apple Pay / Google Pay / PayPal).
    return [
      _payMethodTile(
        icon: Icons.favorite_rounded,
        title: 'Patreon',
        subtitle: 'Join at patreon.com/16592174',
        onTap: _payPatreon,
      ),
      const SizedBox(height: 4),
      TextButton.icon(
        onPressed: _busy ? null : _confirmPatreon,
        icon: const Icon(Icons.verified_outlined, color: _gold, size: 18),
        label: const Text(
          'I’ve subscribed on Patreon',
          style: TextStyle(color: _gold, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          'After joining, tap the button above and enter the email you used on Patreon so we can verify your membership.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ),
    ];
  }

  Widget _payMethodTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: _busy
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: LiquidGlassContainer(
          borderRadius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _gold, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white38, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (_statusSuccess ? Colors.greenAccent : Colors.redAccent)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (_statusSuccess ? Colors.greenAccent : Colors.redAccent)
              .withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _statusSuccess
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            color: _statusSuccess ? Colors.greenAccent : Colors.redAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage!,
              style: TextStyle(
                color: _statusSuccess ? Colors.greenAccent : Colors.redAccent,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Container(
            width: 200,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _gold.withValues(alpha: 0.3)),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    color: _gold,
                    strokeWidth: 2.5,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'Processing payment…',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}