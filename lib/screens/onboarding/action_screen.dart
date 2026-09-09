import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../services/addon_repository.dart';
import '../home_screen.dart';
import '../auth/login_screen.dart';
import '../auth/signup_screen.dart';

/// Onboarding / gate screen redesigned to match sleek centered ambient UI.
class ActionScreen extends StatefulWidget {
  /// Optional unlock reason. When null → welcome flow.
  /// Known values: `"1080p"`, `"stream_download"`.
  final String? reason;

  const ActionScreen({super.key, this.reason});

  @override
  State<ActionScreen> createState() => _ActionScreenState();
}

class _ActionScreenState extends State<ActionScreen> {
  static const Color _bgDark = Color(0xFF0D0D0E);
  static const Color _goldAccent = Color(0xFFD4AF37);
  static const Color _textSecondary = Color(0xFF9E9E9E);

  final AuthService _authService = AuthService();
  bool _isLoading = false;

  bool get _isUnlockFlow =>
      widget.reason != null && widget.reason!.trim().isNotEmpty;

  String get _title {
    if (!_isUnlockFlow) return 'Welcome';
    return 'Unlock HD Quality';
  }

  String get _subtitle {
    if (!_isUnlockFlow) {
      return 'Starting today, stream and sync your favorite content effortlessly.';
    }
    return 'Sign in to stream and download high-definition (1080p or higher) content seamlessly.';
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : _goldAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _completeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_first_launch', false);
      await prefs.setBool('hd_unlocked', true);
      await AddonRepository.instance.installDefaultAddons();
    } catch (_) {}

    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const HomeScreen(),
          transitionsBuilder: (_, animation, _, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final credential = await _authService.signInWithGoogle();
      if (credential != null && mounted) {
        _showSnackBar('Signed in with Google successfully!');
        await _completeOnboarding();
      }
    } catch (e) {
      _showSnackBar('Google Sign-In failed: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }

  void _openSignup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SignupScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: Stack(
        children: [
          // Ambient Glowing Arc Header Background
          Positioned(
            top: -100,
            left: -50,
            right: -50,
            height: 380,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _goldAccent.withValues(alpha: 0.35),
                    const Color(0xFFB8860B).withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // Main Layout Wrapper (Supports Mobile, Tablets, Desktop, Smart TVs)
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 32),

                      // Center Icon / App Logo Branding
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.diversity_3_rounded,
                          size: 42,
                          color: _goldAccent,
                        ),
                      ),

                      const SizedBox(height: 36),

                      // Title
                      Text(
                        _title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                          height: 1.2,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Subtitle
                      Text(
                        _subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          color: _textSecondary,
                          height: 1.45,
                        ),
                      ),

                      const SizedBox(height: 48),

                      // Capsule Google Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          autofocus: true,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _goldAccent,
                            foregroundColor: Colors.black,
                            elevation: 8,
                            shadowColor: _goldAccent.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          onPressed: _isLoading ? null : _handleGoogleSignIn,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildGoogleIcon(),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Continue with Google',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Bottom Auth Links: Log in · Sign up
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: _isLoading ? null : _openLogin,
                            child: const Text(
                              'Log in',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4.0),
                            child: Text(
                              '·',
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _isLoading ? null : _openSignup,
                            child: const Text(
                              'Sign up',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // Disclaimer Footnote
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          'By tapping Continue with Google, you agree with our Terms of Service and Privacy Policy.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.4),
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleIcon() {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontWeight: FontWeight.w900,
          fontSize: 14,
          fontFamily: 'Roboto',
        ),
      ),
    );
  }
}