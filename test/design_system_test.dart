import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feb/design/tokens.dart';
import 'package:feb/widgets/app_button.dart';
import 'package:feb/widgets/glass_surface.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('AppButton compact geometry', () {
    testWidgets('medium button renders with compact token paddings',
        (tester) async {
      await tester.pumpWidget(_host(const AppButton(
        onPressed: null,
        child: Text('OK'),
      )));

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('OK'),
          matching: find.byType(Container),
        ).first,
      );
      final padding = container.padding as EdgeInsets;
      // Compact geometry: 12 horizontal / 6 vertical on medium.
      expect(padding.horizontal, AppDesignTokens.space3);
      expect(padding.vertical, AppDesignTokens.space1 + 2);
    });

    testWidgets('small button renders with compact token paddings',
        (tester) async {
      await tester.pumpWidget(_host(const AppButton(
        size: AppButtonSize.small,
        onPressed: null,
        child: Text('OK'),
      )));

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('OK'),
          matching: find.byType(Container),
        ).first,
      );
      final padding = container.padding as EdgeInsets;
      // Compact geometry: 8 horizontal / 4 vertical on small.
      expect(padding.horizontal, AppDesignTokens.space2);
      expect(padding.vertical, AppDesignTokens.space1);
    });

    testWidgets('onPressed fires exactly once per tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(AppButton(
        onPressed: () => taps++,
        child: const Text('TAP'),
      )));

      await tester.tap(find.text('TAP'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('glass variant exposes the child text for semantics',
        (tester) async {
      await tester.pumpWidget(_host(const AppButton(
        variant: AppButtonVariant.glass,
        onPressed: null,
        child: Text('GLASS'),
      )));

      expect(find.text('GLASS'), findsOneWidget);
      expect(find.byType(GlassSurface), findsOneWidget);
    });
  });

  group('GlassSurface', () {
    testWidgets('renders a BackdropFilter and respects the child',
        (tester) async {
      await tester.pumpWidget(_host(const GlassSurface(
        fill: GlassFill.bar,
        child: Text('frosted'),
      )));

      expect(find.text('frosted'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('reduced-transparency users get a solid surface (no blur)',
        (tester) async {
      // MediaQuery.disableAnimations is how the app detects the
      // reduced-transparency preference (see AppMotion).
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: GlassSurface(child: const Text('solid')),
            ),
          ),
        ),
      ));

      expect(find.text('solid'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    test('glass tiers map to token fills and blurs', () {
      // Tier pairings stay in sync with the design tokens.
      expect(AppDesignTokens.glassBlurBar, greaterThan(AppDesignTokens.glassBlurSheet));
      expect(AppDesignTokens.glassBlurSheet, greaterThan(AppDesignTokens.glassBlurChip));
      expect(AppDesignTokens.glassFillBar.a, greaterThan(AppDesignTokens.glassFillSubtle.a));
    });
  });

  group('Gold refinement (ORYZO Noir Gold)', () {
    test('signature gold is refined down from the original FFB800', () {
      // Original hot amber was 0xFFFFB800; refined brass is darker.
      expect(AppDesignTokens.gold.toARGB32(), isNot(0xFFFFB800));
      expect((AppDesignTokens.gold.r * 255.0).round(), lessThan(0xFF));
      expect((AppDesignTokens.gold.g * 255.0).round(), lessThan(0xB8));
    });

    test('muted gold stays darker than the signature gold', () {
      // Perceptual ordering: muted gold must read quieter than gold.
      final goldLuma = AppDesignTokens.gold.computeLuminance();
      final mutedLuma = AppDesignTokens.goldMuted.computeLuminance();
      expect(mutedLuma, lessThan(goldLuma));
    });

    test('espresso text keeps WCAG-ish contrast on the refined gold', () {
      final contrast = _contrastRatio(
        AppDesignTokens.textOnGold,
        AppDesignTokens.gold,
      );
      // The design target is ≥ 9:1 (original was ~10:1 on the brighter gold).
      expect(contrast, greaterThanOrEqualTo(9.0));
    });

    test('glass tokens stay inside the warm noir palette', () {
      // Glass fills must be dark (alpha-diluted noir), never white glass.
      for (final c in [
        AppDesignTokens.glassFillBar,
        AppDesignTokens.glassFillSheet,
        AppDesignTokens.glassFillSubtle,
      ]) {
        expect((c.r * 255.0).round(), lessThan(0x30));
        expect((c.g * 255.0).round(), lessThan(0x20));
      }
    });
  });

}

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
