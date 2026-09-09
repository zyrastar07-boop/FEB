import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';
import '../design/tokens.dart';
import 'feb_wave_loader.dart';

/// AuthGuard — logic-based route guard for authenticated-only screens.
///
/// The UI already prevents navigation to sensitive screens for signed-out
/// users; this closes the gap for direct routing (deep links, back-stack
/// restoration, future route tables). While the session is being resolved a
/// branded loading shell is shown; when no user is present the screen is
/// never built and a pop back to the first route is issued.
///
/// Usage:
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => const AuthGuard(child: AccountDetailsScreen()),
/// ));
/// ```
class AuthGuard extends StatefulWidget {
  const AuthGuard({
    super.key,
    required this.child,
    this.sessionResolver,
  });

  final Widget child;

  /// Overridable session lookup. Defaults to the real [AuthService] session;
  /// tests inject a fake to avoid touching Firebase.
  final Future<User?> Function()? sessionResolver;

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  User? _user;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final user = widget.sessionResolver != null
        ? await widget.sessionResolver!()
        : await AuthService().getCurrentUserSession();
    if (!mounted) return;
    setState(() {
      _user = user;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      return const Scaffold(
        backgroundColor: AppDesignTokens.backgroundCanvas,
        body: Center(child: WaveLoader()),
      );
    }
    if (_user == null) {
      // Signed out: bounce to root instead of building the protected child.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const Scaffold(
        backgroundColor: AppDesignTokens.backgroundCanvas,
        body: Center(child: WaveLoader()),
      );
    }
    return widget.child;
  }
}
