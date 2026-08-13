import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Subscription tiers offered by Mela.
enum SubscriptionTier { free, premiumMonthly, premiumYearly }

/// Payment region selector.
enum PaymentRegion { ethiopia, international }

/// Result of a payment / verification attempt.
class PaymentResult {
  final bool success;
  final String message;
  final String? transactionId;
  final double? amount;
  final String? currency;
  final String? provider;
  final Map<String, dynamic>? raw;

  const PaymentResult({
    required this.success,
    required this.message,
    this.transactionId,
    this.amount,
    this.currency,
    this.provider,
    this.raw,
  });

  factory PaymentResult.fail(String message) =>
      PaymentResult(success: false, message: message);

  factory PaymentResult.ok({
    required String message,
    String? transactionId,
    double? amount,
    String? currency,
    String? provider,
    Map<String, dynamic>? raw,
  }) =>
      PaymentResult(
        success: true,
        message: message,
        transactionId: transactionId,
        amount: amount,
        currency: currency,
        provider: provider,
        raw: raw,
      );
}

/// Unified payment & subscription manager.
///
/// Ethiopian flows use Verify.et (`POST https://verify.et/api/verify`).
/// International flow is Patreon only (join link + membership verification).
///
/// Set `VERIFY_ET_API_KEY` and optionally `PATREON_CREATOR_TOKEN` /
/// `PATREON_VERIFY_URL` before production.
class PaymentService extends ChangeNotifier {
  static final PaymentService instance = PaymentService._internal();
  PaymentService._internal();

  // ── Merchant details (shown to customers + used in Verify.et) ────────
  /// Your Telebirr / CBE Birr receive number (shown in the pay UI).
  static const String merchantPhone = '0997035330';

  /// Commercial Bank of Ethiopia account number (shown for bank transfer).
  static const String cbeAccountNumber = '1000655339861';

  /// Last 8 digits of [cbeAccountNumber] — used as Verify.et accountSuffix.
  static String get cbeAccountSuffix {
    final digits = cbeAccountNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8) return digits.substring(digits.length - 8);
    return digits;
  }

  // ── Configuration (replace API key in production / via env) ──────────
  /// Verify.et API key — prefer a thin backend proxy in production so the
  /// key is not embedded in the client binary long-term.
  static const String verifyEtApiKey = String.fromEnvironment(
    'VERIFY_ET_API_KEY',
    defaultValue: 'REPLACE_WITH_VERIFY_ET_API_KEY',
  );

  /// Merchant settlement account for Telebirr (Verify.et body).
  static const String telebirrSettlementAccount = merchantPhone;

  /// Your real Patreon membership join link.
  static const String patreonCheckoutUrl = String.fromEnvironment(
    'PATREON_URL',
    defaultValue: 'https://www.patreon.com/16592174/join',
  );

  /// Optional: Patreon creator access token (from Patreon developer portal).
  /// When set, [verifyPatreonMembership] can call the Patreon API.
  static const String patreonCreatorAccessToken = String.fromEnvironment(
    'PATREON_CREATOR_TOKEN',
    defaultValue: '',
  );

  /// Optional backend that validates a patron by email / Patreon user id.
  static const String patreonVerifyBackendUrl = String.fromEnvironment(
    'PATREON_VERIFY_URL',
    defaultValue: '',
  );

  static const String _prefsPrefix = 'mela_sub_';

  // ── Pricing ──────────────────────────────────────────────────────────
  static const double monthlyPriceUsd = 4.99;
  static const double yearlyPriceUsd = 39.99;
  static const double monthlyPriceEtb = 299.0;
  static const double yearlyPriceEtb = 2499.0;

  // ── State ────────────────────────────────────────────────────────────
  bool _initialized = false;
  bool isPremium = false;
  SubscriptionTier tier = SubscriptionTier.free;
  DateTime? expiryDate;
  String? lastProvider;
  String? lastTransactionId;
  bool isProcessing = false;
  String? lastError;

  bool get isInitialized => _initialized;

  String get tierLabel {
    switch (tier) {
      case SubscriptionTier.free:
        return 'Free';
      case SubscriptionTier.premiumMonthly:
        return 'Premium Monthly';
      case SubscriptionTier.premiumYearly:
        return 'Premium Yearly';
    }
  }

  String get statusLabel {
    if (!isPremium) return 'Free plan';
    if (expiryDate == null) return 'Premium · Active';
    final days = expiryDate!.difference(DateTime.now()).inDays;
    if (days < 0) return 'Premium · Expired';
    if (days == 0) return 'Premium · Ends today';
    return 'Premium · ${days}d left';
  }

  // ── Lifecycle ────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      isPremium = prefs.getBool('${_prefsPrefix}isPremium') ?? false;
      final tierName = prefs.getString('${_prefsPrefix}tier') ?? 'free';
      tier = SubscriptionTier.values.firstWhere(
        (t) => t.name == tierName,
        orElse: () => SubscriptionTier.free,
      );
      final expMs = prefs.getInt('${_prefsPrefix}expiry');
      if (expMs != null) {
        expiryDate = DateTime.fromMillisecondsSinceEpoch(expMs);
      }
      lastProvider = prefs.getString('${_prefsPrefix}provider');
      lastTransactionId = prefs.getString('${_prefsPrefix}txId');

      // Auto-expire if past date
      if (isPremium &&
          expiryDate != null &&
          expiryDate!.isBefore(DateTime.now())) {
        await _setSubscription(
          premium: false,
          tier: SubscriptionTier.free,
          expiry: null,
          provider: lastProvider,
          transactionId: lastTransactionId,
        );
      }
    } catch (e) {
      debugPrint('[PaymentService] init error: $e');
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_prefsPrefix}isPremium', isPremium);
    await prefs.setString('${_prefsPrefix}tier', tier.name);
    if (expiryDate != null) {
      await prefs.setInt(
          '${_prefsPrefix}expiry', expiryDate!.millisecondsSinceEpoch);
    } else {
      await prefs.remove('${_prefsPrefix}expiry');
    }
    if (lastProvider != null) {
      await prefs.setString('${_prefsPrefix}provider', lastProvider!);
    }
    if (lastTransactionId != null) {
      await prefs.setString('${_prefsPrefix}txId', lastTransactionId!);
    }
  }

  Future<void> _setSubscription({
    required bool premium,
    required SubscriptionTier tier,
    DateTime? expiry,
    String? provider,
    String? transactionId,
  }) async {
    isPremium = premium;
    this.tier = tier;
    expiryDate = expiry;
    lastProvider = provider;
    lastTransactionId = transactionId;
    lastError = null;
    await _persist();
    notifyListeners();
  }

  void _setProcessing(bool v) {
    isProcessing = v;
    notifyListeners();
  }

  // ── Public API ───────────────────────────────────────────────────────

  /// Refresh subscription from local store (and optionally remote).
  Future<bool> checkSubscriptionStatus() async {
    await init();
    if (isPremium &&
        expiryDate != null &&
        expiryDate!.isBefore(DateTime.now())) {
      await _setSubscription(
        premium: false,
        tier: SubscriptionTier.free,
        expiry: null,
        provider: lastProvider,
        transactionId: lastTransactionId,
      );
      return false;
    }
    notifyListeners();
    return isPremium;
  }

  /// Verify an Ethiopian transfer via Verify.et.
  ///
  /// [provider] — `telebirr` | `cbe` | `cbebirr`
  /// [reference] — transaction / reference / receipt number
  /// [accountSuffix] — last 8 digits for CBE (required for bank `cbe`)
  /// [phone] — required for `cbebirr`
  /// [expectedAmount] — optional amount check in ETB
  /// [tier] — which plan to unlock on success
  Future<PaymentResult> verifyEthiopianPayment({
    required String provider,
    required String reference,
    String? accountSuffix,
    String? phone,
    double? expectedAmount,
    SubscriptionTier tier = SubscriptionTier.premiumMonthly,
  }) async {
    await init();
    final bank = provider.toLowerCase().trim();
    final ref = reference.trim();

    if (ref.isEmpty) {
      return PaymentResult.fail('Enter a valid transaction / reference number.');
    }

    if (bank == 'cbe') {
      final suffix = (accountSuffix ?? '').trim();
      if (!RegExp(r'^\d{8}$').hasMatch(suffix)) {
        return PaymentResult.fail(
          'CBE requires the last 8 digits of the account number.',
        );
      }
    }

    if (bank == 'cbebirr') {
      final p = (phone ?? '').replaceAll(RegExp(r'\s+'), '');
      if (p.length < 9) {
        return PaymentResult.fail(
          'CBE Birr requires the sender phone number.',
        );
      }
    }

    _setProcessing(true);
    lastError = null;

    try {
      final body = <String, dynamic>{'bank': bank};

      switch (bank) {
        case 'telebirr':
          body['transactionNumber'] = ref;
          body['settlementAccount'] = telebirrSettlementAccount;
          break;
        case 'cbe':
          body['referenceNumber'] = ref;
          body['accountSuffix'] = accountSuffix!.trim();
          break;
        case 'cbebirr':
          body['receiptNumber'] = ref;
          body['phone'] = phone!.replaceAll(RegExp(r'\s+'), '');
          break;
        default:
          body['reference'] = ref;
          if (accountSuffix != null && accountSuffix.isNotEmpty) {
            body['accountSuffix'] = accountSuffix.trim();
          }
      }

      final idempotencyKey =
          'mela-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

      final uri = Uri.parse('https://verify.et/api/verify')
          .replace(queryParameters: {'waitMs': '5000'});

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': verifyEtApiKey,
              'Idempotency-Key': idempotencyKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));

      final decoded = _safeJson(response.body);

      // Pending / async — poll status URL if present
      if (response.statusCode == 202 ||
          (decoded['data'] is Map &&
              (decoded['data']['processingStatus'] == 'queued' ||
                  decoded['data']['processingStatus'] == 'running'))) {
        final requestId = decoded['requestId']?.toString() ??
            decoded['data']?['requestId']?.toString();
        final statusUrl = decoded['links']?['statusUrl']?.toString() ??
            (requestId != null
                ? 'https://verify.et/api/verify/$requestId'
                : null);

        if (statusUrl != null) {
          final polled = await _pollVerifyEt(statusUrl);
          if (polled != null) {
            return await _completeEthiopianSuccess(
              polled,
              bank: bank,
              expectedAmount: expectedAmount,
              tier: tier,
            );
          }
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final verified = _isVerifiedPayload(decoded);
        if (verified) {
          return await _completeEthiopianSuccess(
            decoded,
            bank: bank,
            expectedAmount: expectedAmount,
            tier: tier,
          );
        }
        final msg = decoded['message']?.toString() ??
            'Payment could not be verified. Check the reference and try again.';
        lastError = msg;
        return PaymentResult.fail(msg);
      }

      final err = decoded['message']?.toString() ??
          'Verify.et returned HTTP ${response.statusCode}';
      lastError = err;
      return PaymentResult.fail(err);
    } on TimeoutException {
      lastError = 'Verification timed out. Try again in a moment.';
      return PaymentResult.fail(lastError!);
    } catch (e) {
      lastError = e.toString();
      return PaymentResult.fail('Verification failed: $e');
    } finally {
      _setProcessing(false);
    }
  }

  Future<PaymentResult> _completeEthiopianSuccess(
    Map<String, dynamic> decoded, {
    required String bank,
    double? expectedAmount,
    required SubscriptionTier tier,
  }) async {
    final data = _extractDataMap(decoded);
    final amount = _asDouble(data['amount'] ?? decoded['amount']);
    final currency =
        (data['currency'] ?? decoded['currency'] ?? 'ETB').toString();
    final txId = (data['referenceNumber'] ??
            data['transactionNumber'] ??
            data['receiptNumber'] ??
            decoded['transaction_id'] ??
            decoded['requestId'] ??
            'et-${DateTime.now().millisecondsSinceEpoch}')
        .toString();

    if (expectedAmount != null && amount != null) {
      // Allow small tolerance (1 ETB) for rounding
      if ((amount - expectedAmount).abs() > 1.0) {
        final msg =
            'Verified amount ($amount $currency) does not match expected ($expectedAmount ETB).';
        lastError = msg;
        return PaymentResult.fail(msg);
      }
    }

    final duration = tier == SubscriptionTier.premiumYearly
        ? const Duration(days: 365)
        : const Duration(days: 30);

    await _setSubscription(
      premium: true,
      tier: tier,
      expiry: DateTime.now().add(duration),
      provider: bank,
      transactionId: txId,
    );

    return PaymentResult.ok(
      message: 'Payment verified. Premium unlocked.',
      transactionId: txId,
      amount: amount,
      currency: currency,
      provider: bank,
      raw: decoded,
    );
  }

  Future<Map<String, dynamic>?> _pollVerifyEt(String statusUrl) async {
    for (var attempt = 0; attempt < 12; attempt++) {
      await Future.delayed(Duration(milliseconds: 800 + attempt * 200));
      try {
        final res = await http.get(
          Uri.parse(statusUrl),
          headers: {'x-api-key': verifyEtApiKey},
        ).timeout(const Duration(seconds: 12));
        final body = _safeJson(res.body);
        final status = body['data']?['processingStatus']?.toString() ??
            body['verification']?['processingStatus']?.toString() ??
            body['status']?.toString();

        if (status == 'completed' ||
            status == 'success' ||
            status == 'verified' ||
            _isVerifiedPayload(body)) {
          return body;
        }
        if (status == 'failed' || status == 'not_found') {
          return body;
        }
      } catch (_) {
        // continue polling
      }
    }
    return null;
  }

  bool _isVerifiedPayload(Map<String, dynamic> decoded) {
    if (decoded['success'] == true &&
        (decoded['data'] is List || decoded['data'] is Map)) {
      final data = decoded['data'];
      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is Map &&
            (first['verified'] == true || first['status'] == 'success')) {
          return true;
        }
      }
      if (data is Map &&
          (data['verified'] == true ||
              data['status'] == 'success' ||
              data['status'] == 'verified')) {
        return true;
      }
    }
    if (decoded['status'] == 'verified') return true;
    if (decoded['verification'] is Map &&
        decoded['verification']['verified'] == true) {
      return true;
    }
    return false;
  }

  Map<String, dynamic> _extractDataMap(Map<String, dynamic> decoded) {
    final data = decoded['data'];
    if (data is List && data.isNotEmpty && data.first is Map) {
      return Map<String, dynamic>.from(data.first as Map);
    }
    if (data is Map) return Map<String, dynamic>.from(data);
    return Map<String, dynamic>.from(decoded);
  }

  // Stripe / PayPal removed — local payments + Patreon only.

  // ── Patreon ──────────────────────────────────────────────────────────

  /// Opens your real Patreon join page:
  /// https://www.patreon.com/16592174/join
  Future<PaymentResult> authenticatePatreonTier({String? accessToken}) async {
    await init();
    _setProcessing(true);
    lastError = null;

    try {
      // If a member access token is supplied, verify via API / backend first.
      if (accessToken != null && accessToken.isNotEmpty) {
        final verified = await verifyPatreonMembership(emailOrToken: accessToken);
        if (verified.success) return verified;
      }

      final uri = Uri.parse(patreonCheckoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return PaymentResult.ok(
          message:
              'Patreon opened. After you finish pledging, return here, enter the email you used on Patreon, and tap “I’ve subscribed”.',
          provider: 'patreon',
          raw: {'requiresConfirm': true, 'url': patreonCheckoutUrl},
        );
      }
      return PaymentResult.fail(
        'Could not open Patreon. Visit $patreonCheckoutUrl in your browser, then confirm here.',
      );
    } catch (e) {
      lastError = e.toString();
      return PaymentResult.fail('Patreon error: $e');
    } finally {
      _setProcessing(false);
    }
  }

  /// Verifies an active Patreon membership for [emailOrToken].
  ///
  /// Order of checks:
  /// 1. Your backend at [patreonVerifyBackendUrl] (recommended)
  /// 2. Patreon API with [patreonCreatorAccessToken] if configured
  ///
  /// Without (1) or (2), automatic verification cannot succeed — Patreon does
  /// not allow a pure client app to list your patrons without a secret token.
  Future<PaymentResult> verifyPatreonMembership({
    required String emailOrToken,
    SubscriptionTier tier = SubscriptionTier.premiumMonthly,
  }) async {
    await init();
    final id = emailOrToken.trim();
    if (id.isEmpty) {
      return PaymentResult.fail('Enter the email address used on Patreon.');
    }

    _setProcessing(true);
    lastError = null;

    try {
      // 1) Your own verify endpoint (best production path)
      if (patreonVerifyBackendUrl.isNotEmpty) {
        final res = await http
            .post(
              Uri.parse(patreonVerifyBackendUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'email': id, 'tier': tier.name}),
            )
            .timeout(const Duration(seconds: 20));
        final body = _safeJson(res.body);
        final active = res.statusCode >= 200 &&
            res.statusCode < 300 &&
            (body['active'] == true ||
                body['isPatron'] == true ||
                body['patron_status'] == 'active_patron' ||
                body['success'] == true);
        if (active) {
          return await _activateInternational(
            tier: tier,
            provider: 'patreon',
            transactionId: body['id']?.toString() ??
                body['patron_id']?.toString() ??
                'patreon-${id.hashCode.abs()}',
            amount: monthlyPriceUsd,
            currency: 'USD',
          );
        }
        final msg = body['message']?.toString() ??
            'No active Patreon membership found for that email.';
        lastError = msg;
        return PaymentResult.fail(msg);
      }

      // 2) Direct Patreon API (requires creator token from developers.patreon.com)
      if (patreonCreatorAccessToken.isNotEmpty) {
        final res = await http.get(
          Uri.parse(
            'https://www.patreon.com/api/oauth2/v2/campaigns'
            '?include=tiers&fields%5Bcampaign%5D=creation_name',
          ),
          headers: {
            'Authorization': 'Bearer $patreonCreatorAccessToken',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 20));

        if (res.statusCode == 200) {
          // Token is valid — look up members (simplified: campaign reachable).
          // Full member-by-email search needs members endpoint + pagination.
          final membersRes = await http.get(
            Uri.parse(
              'https://www.patreon.com/api/oauth2/v2/members'
              '?include=user,currently_entitled_tiers'
              '&fields%5Bmember%5D=patron_status,email,full_name,last_charge_status'
              '&fields%5Buser%5D=email',
            ),
            headers: {
              'Authorization': 'Bearer $patreonCreatorAccessToken',
            },
          ).timeout(const Duration(seconds: 25));

          final membersBody = _safeJson(membersRes.body);
          final data = membersBody['data'];
          if (data is List) {
            final needle = id.toLowerCase();
            for (final m in data) {
              if (m is! Map) continue;
              final attrs = m['attributes'] is Map
                  ? Map<String, dynamic>.from(m['attributes'] as Map)
                  : <String, dynamic>{};
              final email = (attrs['email'] ?? '').toString().toLowerCase();
              final status = (attrs['patron_status'] ?? '').toString();
              final charge = (attrs['last_charge_status'] ?? '').toString();
              if (email == needle &&
                  (status == 'active_patron' || charge == 'Paid')) {
                return await _activateInternational(
                  tier: tier,
                  provider: 'patreon',
                  transactionId: m['id']?.toString() ??
                      'patreon-${email.hashCode.abs()}',
                  amount: monthlyPriceUsd,
                  currency: 'USD',
                );
              }
            }
          }
          lastError = 'No active patron found for that email on Patreon.';
          return PaymentResult.fail(lastError!);
        }
        lastError =
            'Patreon API error ${res.statusCode}. Check PATREON_CREATOR_TOKEN.';
        return PaymentResult.fail(lastError!);
      }

      // No verification backend / token configured
      return PaymentResult.fail(
        'Patreon verification is not configured yet. '
        'Set PATREON_VERIFY_URL (backend) or PATREON_CREATOR_TOKEN '
        '(from https://www.patreon.com/portal/registration/register-clients) '
        'so memberships can be checked automatically.',
      );
    } on TimeoutException {
      lastError = 'Patreon verification timed out. Try again.';
      return PaymentResult.fail(lastError!);
    } catch (e) {
      lastError = e.toString();
      return PaymentResult.fail('Patreon verification failed: $e');
    } finally {
      _setProcessing(false);
    }
  }

  /// Called when the user taps “I’ve subscribed on Patreon”.
  /// Pass the email they used on Patreon — this is the functional path.
  Future<PaymentResult> confirmPatreonPledge({
    required String email,
    SubscriptionTier tier = SubscriptionTier.premiumMonthly,
  }) async {
    return verifyPatreonMembership(emailOrToken: email, tier: tier);
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  Future<PaymentResult> _activateInternational({
    required SubscriptionTier tier,
    required String provider,
    required String transactionId,
    required double amount,
    required String currency,
    bool demo = false,
  }) async {
    final duration = tier == SubscriptionTier.premiumYearly
        ? const Duration(days: 365)
        : const Duration(days: 30);

    await _setSubscription(
      premium: true,
      tier: tier,
      expiry: DateTime.now().add(duration),
      provider: provider,
      transactionId: transactionId,
    );

    return PaymentResult.ok(
      message: demo
          ? 'Premium activated (local/demo mode). Connect your payment backend for production.'
          : 'Payment successful. Premium unlocked.',
      transactionId: transactionId,
      amount: amount,
      currency: currency,
      provider: provider,
    );
  }

  /// Cancel / downgrade to free (local).
  Future<void> cancelSubscription() async {
    await _setSubscription(
      premium: false,
      tier: SubscriptionTier.free,
      expiry: null,
      provider: lastProvider,
      transactionId: lastTransactionId,
    );
  }

  double priceFor(SubscriptionTier tier, PaymentRegion region) {
    if (tier == SubscriptionTier.free) return 0;
    if (region == PaymentRegion.ethiopia) {
      return tier == SubscriptionTier.premiumYearly
          ? yearlyPriceEtb
          : monthlyPriceEtb;
    }
    return tier == SubscriptionTier.premiumYearly
        ? yearlyPriceUsd
        : monthlyPriceUsd;
  }

  String currencyFor(PaymentRegion region) =>
      region == PaymentRegion.ethiopia ? 'ETB' : 'USD';

  Map<String, dynamic> _safeJson(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return {};
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}