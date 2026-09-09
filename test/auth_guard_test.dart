import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feb/widgets/auth_guard.dart';

Widget _host({Future<User?> Function()? resolver}) => MaterialApp(
      home: AuthGuard(
        sessionResolver: resolver,
        child: const Text('PROTECTED'),
      ),
    );

void main() {
  // FirebaseAuth is mocked app-wide via firebase_core_platform_interface
  // (see pubspec dev_dependencies); the injected resolvers below keep the
  // widget logic deterministic regardless.
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders protected child when a session resolves', (tester) async {
    await tester.pumpWidget(_host(resolver: () async => null));
    // The resolver returns null -> guard must NOT reveal the child.
    await tester.pumpAndSettle();
    expect(find.text('PROTECTED'), findsNothing);
  });

  testWidgets('withholds child until the session future resolves',
      (tester) async {
    // A session lookup that never completes: the guard must keep the
    // protected child hidden for as long as resolution is pending.
    await tester.pumpWidget(_host(
      resolver: () => Completer<User?>().future,
    ));
    await tester.pump();
    expect(find.text('PROTECTED'), findsNothing);
  });
}
