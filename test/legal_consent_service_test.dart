import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feb/services/legal_consent_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('LegalConsentService', () {
    test('hasAccepted is false before any acceptance', () async {
      expect(await LegalConsentService.instance.hasAccepted(), isFalse);
    });

    test('accept() persists the flag and is idempotent', () async {
      final svc = LegalConsentService.instance;
      await svc.accept();
      expect(await svc.hasAccepted(), isTrue);
      // Accepting twice must not throw and must stay true.
      await svc.accept();
      expect(await svc.hasAccepted(), isTrue);
    });

    test('flag survives a fresh read from the same store', () async {
      final svc = LegalConsentService.instance;
      await svc.accept();

      // Simulate a restart: re-read from SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('legal_consent_accepted_v1'), isTrue);
      expect(await LegalConsentService.instance.hasAccepted(), isTrue);
    });

    test('resetForTest clears the flag', () async {
      final svc = LegalConsentService.instance;
      await svc.accept();
      expect(await svc.hasAccepted(), isTrue);

      await LegalConsentService.resetForTest();
      expect(await svc.hasAccepted(), isFalse);
    });
  });
}