import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:feb/services/addon_models.dart';
import 'package:feb/services/addon_repository.dart';

const _manifestBody = '''
{
  "id": "com.example.cinemeta",
  "name": "Cinemeta",
  "version": "1.0.0",
  "description": "Example add-on",
  "resources": ["catalog", "meta", "stream"],
  "types": ["movie", "series"],
  "catalogs": [{"type": "movie", "id": "top", "name": "Top"}]
}
''';

/// Fetcher that records every URL it is asked for and returns a valid manifest.
class FakeFetcher {
  final List<String> requested = [];
  Object? nextError;
  int callCount = 0;

  Future<String> call(String url, {bool forceRefresh = false}) async {
    callCount++;
    requested.add('${forceRefresh ? 'FORCE ' : ''}$url');
    if (nextError != null) {
      throw nextError!;
    }
    return _manifestBody;
  }
}

Future<void> pumpUntil(bool Function() condition,
    {int attempts = 200}) async {
  for (var i = 0; i < attempts; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition not met within ${attempts * 10}ms');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AddonRepository URL handling', () {
    test('normalizes raw urls to https manifest.json', () async {
      final fetcher = FakeFetcher();
      final repo = AddonRepository.forTesting(fetcher: fetcher.call);
      await repo.ensureLoaded();

      final result = await repo.addAddon('cinemeta.example/addon');
      expect(result, isA<AddAddonSuccess>());
      expect(fetcher.requested,
          ['https://cinemeta.example/addon/manifest.json']);
    });

    test('accepts explicit scheme and preserves query strings', () async {
      final fetcher = FakeFetcher();
      final repo = AddonRepository.forTesting(fetcher: fetcher.call);
      await repo.ensureLoaded();

      await repo.addAddon('https://x.example/m/manifest.json?api=2');
      expect(fetcher.requested.last,
          'https://x.example/m/manifest.json?api=2');
    });

    test('rejects blank urls', () async {
      final fetcher = FakeFetcher();
      final repo = AddonRepository.forTesting(fetcher: fetcher.call);
      await repo.ensureLoaded();

      final result = await repo.addAddon('   ');
      expect(result, isA<AddAddonError>());
      expect(fetcher.requested, isEmpty);
    });

    test('rejects duplicate installs', () async {
      final fetcher = FakeFetcher();
      final repo = AddonRepository.forTesting(fetcher: fetcher.call);
      await repo.ensureLoaded();

      final first = await repo.addAddon('cinemeta.example');
      expect(first, isA<AddAddonSuccess>());
      final second = await repo.addAddon('https://cinemeta.example');
      expect(second, isA<AddAddonError>());
      expect(fetcher.callCount, 1);
    });
  });

  group('AddonRepository lifecycle', () {
    test('addAddon parses the manifest into state', () async {
      final fetcher = FakeFetcher();
      final repo = AddonRepository.forTesting(fetcher: fetcher.call);
      await repo.ensureLoaded();

      final result = await repo.addAddon('cinemeta.example');
      expect(result, isA<AddAddonSuccess>());
      final addon = repo.addons.single;
      expect(addon.manifestUrl, 'https://cinemeta.example/manifest.json');
      expect(addon.enabled, isTrue);
      expect(addon.isActive, isTrue);
      expect(addon.manifest!.name, 'Cinemeta');
      expect(addon.manifest!.catalogs.single.id, 'top');
    });

    test('fetch failure surfaces AddAddonError and adds nothing', () async {
      final fetcher = FakeFetcher()..nextError = Exception('boom');
      final repo = AddonRepository.forTesting(fetcher: fetcher.call);
      await repo.ensureLoaded();

      final result = await repo.addAddon('cinemeta.example');
      expect(result, isA<AddAddonError>());
      expect(repo.addons, isEmpty);
    });

    test('removeAddon deletes from state', () async {
      final fetcher = FakeFetcher();
      final repo = AddonRepository.forTesting(fetcher: fetcher.call);
      await repo.ensureLoaded();

      await repo.addAddon('cinemeta.example');
      expect(repo.addons, hasLength(1));
      repo.removeAddon('https://cinemeta.example/manifest.json');
      expect(repo.addons, isEmpty);
    });

    test('toggling off does not refetch a known manifest', () async {
      final fetcher = FakeFetcher();
      final repo = AddonRepository.forTesting(fetcher: fetcher.call);
      await repo.ensureLoaded();

      await repo.addAddon('cinemeta.example');
      final before = fetcher.callCount;

      repo.setAddonEnabled('https://cinemeta.example/manifest.json', false);
      expect(repo.addons.single.enabled, isFalse);
      expect(repo.addons.single.isActive, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(fetcher.callCount, before);

      repo.setAddonEnabled('https://cinemeta.example/manifest.json', true);
      expect(repo.addons.single.enabled, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(fetcher.callCount, before);
    });

    test('re-enabling a stored-but-unfetched addon fetches its manifest',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('feb_addons_installed_urls', [
        'https://cinemeta.example/manifest.json',
      ]);
      await prefs.setString(
        'feb_addons_enabled_states',
        jsonEncode({'https://cinemeta.example/manifest.json': false}),
      );

      final fetcher = FakeFetcher();
      final repo = AddonRepository.forTesting(fetcher: fetcher.call);
      await repo.ensureLoaded();
      expect(repo.addons.single.manifest, isNull);
      expect(fetcher.requested, isEmpty);

      repo.setAddonEnabled('https://cinemeta.example/manifest.json', true);
      expect(repo.addons.single.enabled, isTrue);
      await pumpUntil(() => repo.addons.single.manifest != null);
      expect(fetcher.requested,
          ['https://cinemeta.example/manifest.json']);
    });

    test('refreshAddon failure records errorMessage on the addon', () async {
      final fetcher = FakeFetcher();
      final repo = AddonRepository.forTesting(fetcher: fetcher.call);
      await repo.ensureLoaded();
      await repo.addAddon('cinemeta.example');

      fetcher.nextError = Exception('down');
      await repo.refreshAddon('https://cinemeta.example/manifest.json',
          forceRefresh: true);
      expect(repo.addons.single.errorMessage, isNotNull);
      expect(repo.addons.single.manifest, isNotNull);
      expect(repo.addons.single.isRefreshing, isFalse);
    });
  });

  group('AddonRepository persistence', () {
    test('installed urls and enabled states survive reload', () async {
      final firstFetcher = FakeFetcher();
      final first = AddonRepository.forTesting(fetcher: firstFetcher.call);
      await first.ensureLoaded();
      await first.addAddon('one.example');
      await first.addAddon('two.example');
      first.removeAddon('https://one.example/manifest.json');
      first.setAddonEnabled('https://two.example/manifest.json', false);

      // Fresh repository over the same (mocked) storage.
      final secondFetcher = FakeFetcher();
      final second = AddonRepository.forTesting(fetcher: secondFetcher.call);
      expect(second.isLoaded, isFalse);
      await second.ensureLoaded();
      expect(second.isLoaded, isTrue);

      expect(second.addons, hasLength(1));
      expect(second.addons.single.manifestUrl,
          'https://two.example/manifest.json');
      expect(second.addons.single.enabled, isFalse);
    });

    test('ensureLoaded refreshes enabled manifests that lack one', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('feb_addons_installed_urls', [
        'https://cinemeta.example/manifest.json',
      ]);

      final fetcher = FakeFetcher();
      final repo = AddonRepository.forTesting(fetcher: fetcher.call);
      await repo.ensureLoaded();

      expect(repo.addons.single.enabled, isTrue);
      // Pending addon shows refreshing until its manifest lands.
      await pumpUntil(() => repo.addons.single.manifest != null);
      expect(repo.addons.single.manifest!.name, 'Cinemeta');
      expect(repo.addons.single.isRefreshing, isFalse);
      expect(fetcher.requested,
          ['https://cinemeta.example/manifest.json']);
    });

    test('disabled persisted addons are not fetched on load', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('feb_addons_installed_urls', [
        'https://cinemeta.example/manifest.json',
      ]);
      await prefs.setString(
        'feb_addons_enabled_states',
        jsonEncode({'https://cinemeta.example/manifest.json': false}),
      );

      final fetcher = FakeFetcher();
      final repo = AddonRepository.forTesting(fetcher: fetcher.call);
      await repo.ensureLoaded();

      expect(repo.addons.single.enabled, isFalse);
      // Give any (wrong) fetch a chance to fire, then assert none did.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fetcher.requested, isEmpty);
    });
  });
}
