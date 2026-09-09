// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    as firebase_core_platform_interface;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feb/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // PhonoFilmApp builds ActionScreen, which constructs AuthService()
    // (FirebaseAuth.instance) eagerly. The app's real main() initializes
    // Firebase first, so mock the platform channels here.
    setupFirebaseCoreMocks();
    await Firebase.initializeApp(
      // Values must match the defaults in firebase_core's setupFirebaseCoreMocks
      // so the pre-registered [DEFAULT] app is reused instead of a duplicate.
      options: const FirebaseOptions(
        apiKey: '123',
        appId: '123',
        messagingSenderId: '123',
        projectId: '123',
      ),
    );
  });

  tearDownAll(() {
    // Reset the mock so the default app doesn't leak across test files.
    firebase_core_platform_interface.MethodChannelFirebase.appInstances.clear();
    firebase_core_platform_interface.MethodChannelFirebase.isCoreInitialized =
        false;
  });

  testWidgets('App starts', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PhonoFilmApp(isFirstLaunch: true));

    // Verify that our app starts.
    expect(find.byType(PhonoFilmApp), findsOneWidget);
  });
}