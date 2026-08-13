import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/payment_service.dart';
import 'manage_subscription_screen.dart';

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  final AuthService _authService = AuthService();
  bool _isSigningOut = false;
  bool _isDeleting = false;

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _getAuthMethod(User? user) {
    if (user == null) return "Unknown";
    if (user.isAnonymous) return "Guest / Anonymous";
    for (final providerInfo in user.providerData) {
      final pId = providerInfo.providerId.toLowerCase();
      if (pId.contains('google')) return "Google Account";
      if (pId.contains('apple')) return "Apple ID";
      if (pId.contains('password')) return "Email & Password";
    }
    return "Firebase Auth";
  }

  String _formatDate(DateTime? date) {
    if (date == null) return "N/A";
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> _handleSignOut() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSigningOut = true);
    try {
      await _authService.signOut();
      if (mounted) {
        _showSnackBar('Signed out successfully.');
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showSnackBar('Sign out failed: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  Future<void> _handleDeleteAccount() async {
    HapticFeedback.heavyImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Account?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to permanently delete your account? This action cannot be undone.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);
    try {
      final user = _authService.currentUser;
      if (user != null) {
        await user.delete();
      }
      if (mounted) {
        _showSnackBar('Account deleted.');
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showSnackBar('Failed to delete account: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final isPremium = PaymentService.instance.isPremium;

    final displayName = user?.displayName ?? (user?.isAnonymous == true ? 'Guest User' : 'Mela User');
    final email = user?.email ?? (user?.isAnonymous == true ? 'Guest Account (No Email)' : 'No Email');
    final photoUrl = user?.photoURL;
    final uid = user?.uid ?? 'Not Signed In';
    final authMethod = _getAuthMethod(user);
    final creationDate = _formatDate(user?.metadata.creationTime);
    final lastSignInDate = _formatDate(user?.metadata.lastSignInTime);

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Account Details',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            children: [
              // Avatar & Name Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  children: [
                    Hero(
                      tag: 'user_avatar_hero',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(50),
                        child: photoUrl != null && photoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photoUrl,
                                width: 84,
                                height: 84,
                                fit: BoxFit.cover,
                                memCacheWidth: 200,
                                memCacheHeight: 200,
                                placeholder: (context, url) => Container(
                                  width: 84,
                                  height: 84,
                                  color: Colors.white10,
                                  child: const Icon(Icons.person, color: Colors.white54, size: 40),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: 84,
                                  height: 84,
                                  color: const Color(0xFF22C55E),
                                  child: Center(
                                    child: Text(
                                      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                width: 84,
                                height: 84,
                                color: const Color(0xFF22C55E),
                                child: Center(
                                  child: Text(
                                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Subscription Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isPremium
                            ? const Color(0xFFFFB800).withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isPremium ? const Color(0xFFFFB800) : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPremium ? Icons.star_rounded : Icons.person_outline,
                            color: isPremium ? const Color(0xFFFFB800) : Colors.white70,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isPremium ? 'Mela Premium Member' : 'Free Account',
                            style: TextStyle(
                              color: isPremium ? const Color(0xFFFFB800) : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Account Details Information Section
              _buildSectionTitle('Account Overview'),
              const SizedBox(height: 10),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(
                      icon: Icons.fingerprint,
                      label: 'User ID',
                      value: uid.length > 16 ? '${uid.substring(0, 16)}...' : uid,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: uid));
                        _showSnackBar('User ID copied to clipboard');
                      },
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    _buildInfoRow(
                      icon: Icons.login_rounded,
                      label: 'Sign-in Provider',
                      value: authMethod,
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    _buildInfoRow(
                      icon: Icons.calendar_today_rounded,
                      label: 'Account Created',
                      value: creationDate,
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    _buildInfoRow(
                      icon: Icons.history_toggle_off_rounded,
                      label: 'Last Sign In',
                      value: lastSignInDate,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Account Management Actions
              _buildSectionTitle('Management & Actions'),
              const SizedBox(height: 10),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  children: [
                    _buildActionRow(
                      icon: Icons.workspace_premium_rounded,
                      label: 'Manage Subscription',
                      iconColor: const Color(0xFFFFB800),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ManageSubscriptionScreen()),
                        );
                      },
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    _buildActionRow(
                      icon: Icons.logout_rounded,
                      label: 'Sign Out',
                      iconColor: Colors.orangeAccent,
                      isLoading: _isSigningOut,
                      onTap: _isSigningOut || _isDeleting ? null : _handleSignOut,
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    _buildActionRow(
                      icon: Icons.delete_forever_rounded,
                      label: 'Delete Account',
                      iconColor: Colors.redAccent,
                      isLoading: _isDeleting,
                      onTap: _isSigningOut || _isDeleting ? null : _handleDeleteAccount,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white60, size: 20),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Icon(Icons.copy_rounded, color: Colors.white38, size: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String label,
    required Color iconColor,
    bool isLoading = false,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: iconColor == Colors.redAccent ? Colors.redAccent : Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: isLoading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(iconColor),
              ),
            )
          : const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
    );
  }
}
