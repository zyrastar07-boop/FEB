import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../home_screen.dart';

/// Onboarding / gate screen for sign-in.
///
/// Pass [reason] when the user is redirected for a specific unlock
/// (e.g. `"1080p"` or `"stream_download"`). Headers adapt automatically.
class ActionScreen extends StatefulWidget {
  /// Optional unlock reason. When null → welcome flow.
  /// Known values: `"1080p"`, `"stream_download"`.
  final String? reason;

  const ActionScreen({super.key, this.reason});

  @override
  State<ActionScreen> createState() => _ActionScreenState();
}

class _ActionScreenState extends State<ActionScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _loadingType; // 'guest', 'google'

  bool get _isUnlockFlow =>
      widget.reason != null && widget.reason!.trim().isNotEmpty;

  String get _title {
    if (!_isUnlockFlow) return 'Welcome 👋';
    return 'Unlock HD Quality 🎬';
  }

  String get _subtitle {
    if (!_isUnlockFlow) {
      return 'Sign in or continue as guest to get started.';
    }
    return 'Sign in to stream and download high-definition '
        '(1080p or higher) content seamlessly.';
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFFD4AF37),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _completeOnboarding({bool asGuest = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_first_launch', false);
      // Track whether this session can use HD
      if (!asGuest) {
        await prefs.setBool('hd_unlocked', true);
      }
    } catch (_) {}

    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      // Return true so callers know auth succeeded
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

  Future<void> _handleGuestSignIn() async {
    setState(() {
      _isLoading = true;
      _loadingType = 'guest';
    });
    try {
      final credential = await _authService.signInAnonymously();
      if (credential != null && mounted) {
        _showSnackBar('Signed in as Guest');
        await _completeOnboarding(asGuest: true);
      }
    } catch (e) {
      _showSnackBar('Guest sign-in failed: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingType = null;
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _loadingType = 'google';
    });
    try {
      final credential = await _authService.signInWithGoogle();
      if (credential != null && mounted) {
        _showSnackBar('Signed in with Google successfully!');
        await _completeOnboarding(asGuest: false);
      }
    } catch (e) {
      _showSnackBar('Google Sign-In failed: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingType = null;
        });
      }
    }
  }

  void _openLogin() {
    // Navigate to your existing LoginScreen if present in the project.
    // Adjust the import / route name to match your codebase.
    try {
      Navigator.of(context).pushNamed('/login');
    } catch (_) {
      _showSnackBar('Open LoginScreen from your routes', isError: false);
    }
  }

  void _openSignup() {
    try {
      Navigator.of(context).pushNamed('/signup');
    } catch (_) {
      _showSnackBar('Open SignupScreen from your routes', isError: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color brownBackground = Color(0xFF1E140E);
    const Color cardBrown = Color(0xFF2C1D15);
    const Color goldAccent = Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: brownBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Top Image Header
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: goldAccent.withValues(alpha: 0.18),
                            blurRadius: 40,
                            spreadRadius: 4,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/fab.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: cardBrown,
                            child: const Center(
                              child: Icon(Icons.image,
                                  color: goldAccent, size: 48),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.2),
                            brownBackground.withValues(alpha: 0.4),
                            brownBackground,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: goldAccent,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _subtitle,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.amber.shade100.withValues(alpha: 0.8),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Google — primary with glow
                  _buildActionButton(
                    text: 'Continue with Google',
                    backgroundColor: goldAccent,
                    textColor: Colors.black,
                    icon: _buildGoogleLogo(),
                    isLoading: _isLoading && _loadingType == 'google',
                    onPressed: _isLoading ? null : _handleGoogleSignIn,
                    glow: true,
                  ),
                  const SizedBox(height: 14),

                  // Guest
                  _buildActionButton(
                    text: 'Continue as Guest',
                    backgroundColor: cardBrown,
                    textColor: Colors.white,
                    icon: const Icon(
                      Icons.person_outline_rounded,
                      color: goldAccent,
                      size: 22,
                    ),
                    isLoading: _isLoading && _loadingType == 'guest',
                    onPressed: _isLoading ? null : _handleGuestSignIn,
                    glow: false,
                  ),

                  const SizedBox(height: 20),

                  // Direct auth navigation
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _isLoading ? null : _openLogin,
                        child: Text(
                          'Log in',
                          style: TextStyle(
                            color: Colors.amber.shade100.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '·',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      TextButton(
                        onPressed: _isLoading ? null : _openSignup,
                        child: Text(
                          'Sign up',
                          style: TextStyle(
                            color: Colors.amber.shade100.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String text,
    required Color backgroundColor,
    required Color textColor,
    required Widget icon,
    required bool isLoading,
    required VoidCallback? onPressed,
    bool glow = false,
  }) {
    const goldAccent = Color(0xFFD4AF37);
    return Container(
      height: 54,
      width: double.infinity,
      decoration: glow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: goldAccent.withValues(alpha: 0.35),
                  blurRadius: 15,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ],
            )
          : null,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF3D291E), width: 1),
          ),
        ),
        onPressed: onPressed,
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGoogleLogo() {
    return Container(
      width: 20,
      height: 20,
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