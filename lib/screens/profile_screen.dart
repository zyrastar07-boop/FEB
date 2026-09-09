// profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../design/tokens.dart';
import '../widgets/auth_guard.dart';
import '../widgets/app_card.dart';
import '../widgets/floating_nav_bar.dart';
import '../services/font_service.dart';
import '../services/app_settings_service.dart';
import '../services/cellular_data_service.dart';
import '../services/user_library_service.dart';
import '../services/continue_watching_service.dart';
import '../services/payment_service.dart';
import '../services/update_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/share_service.dart';
import 'account_details_screen.dart';
import 'onboarding/action_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'manage_subscription_screen.dart';
import 'iptv_channel_list_screen.dart';
import 'legal_screen.dart';
import 'addons_screen.dart';
import 'debrid_screen.dart';
import '../services/download_service.dart';

const _gold = AppDesignTokens.goldMuted;
const _bg = AppDesignTokens.backgroundCanvas;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _inProgressCount = 0;
  late final AuthService _auth;
  late final Stream<User?> _authStream;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
  GoogleSignInAccount? _googleUser;

  @override
  void initState() {
    super.initState();
    _auth = AuthService();
    _authStream = _auth.authStateChanges;
    FontService.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    FontService.instance.addListener(_onFontChanged);
    _loadInProgress();
    _googleSignIn.signInSilently().then((account) {
      if (mounted) setState(() => _googleUser = account);
    });
  }

  @override
  void dispose() {
    FontService.instance.removeListener(_onFontChanged);
    super.dispose();
  }

  void _onFontChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadInProgress() async {
    try {
      final entries = await ContinueWatchingService.getEntries();
      if (mounted) setState(() => _inProgressCount = entries.length);
    } catch (_) {}
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF1A1A1A),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _tap(VoidCallback fn) {
    HapticFeedback.selectionClick();
    fn();
  }



  void _onNavTapped(int index) {
    HapticFeedback.selectionClick();
    if (index == 4) return;
    if (index == 0) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (index == 1) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const SearchScreen()));
      return;
    }
    if (index == 2) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const IptvChannelListScreen()));
      return;
    }
    if (index == 3) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LibraryScreen()));
      return;
    }
  }

  void _openLibrary() {
    HapticFeedback.selectionClick();
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const LibraryScreen()));
  }

  void _openDownloads() => _openLibrary();
  void _openWatchlist() => _openLibrary();
  void _openWatched() => _openLibrary();
  void _openInProgress() => _openLibrary();

  void _shareApp() {
    HapticFeedback.lightImpact();
    ShareService.shareApp(context);
  }

  void _openAccountDetails() {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const AuthGuard(child: AccountDetailsScreen()),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _openSubscription() {
    HapticFeedback.selectionClick();
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                const AuthGuard(child: ManageSubscriptionScreen())));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: ListView(
              scrollCacheExtent: ScrollCacheExtent.pixels(800.0),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Settings',
                      style: FontService.instance.style(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold),
                    ),
                    GestureDetector(
                      onTap: () => _tap(_shareApp),
                      child: AppCard(
                        borderRadius: AppDesignTokens.radius2xl,
                        padding: const EdgeInsets.all(8),
                        child:
                            const Icon(Icons.share_rounded, color: _gold, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildAuthHeader(),
                const SizedBox(height: 20),
                _StatsSection(
                  inProgressCount: _inProgressCount,
                  openWatched: _openWatched,
                  openWatchlist: _openWatchlist,
                  openInProgress: _openInProgress,
                  openDownloads: _openDownloads,
                ),
                const SizedBox(height: 24),
                ListenableBuilder(
                  listenable: PaymentService.instance,
                  builder: (context, _) => _buildActionTile(
                    'Manage subscription',
                    PaymentService.instance.isPremium
                        ? PaymentService.instance.statusLabel
                        : 'Upgrade to Premium · Telebirr, CBE, Card, PayPal',
                    Icons.card_membership_rounded,
                    _openSubscription,
                  ),
                ),
                const SizedBox(height: 16),
                const _SettingsSection(),
                const SizedBox(height: 16),
                _buildSectionTitle('ABOUT & SUPPORT'),
                const _UpdateTile(),
                _buildActionTile(
                    'Help center', 'FAQs and troubleshooting', Icons.help_outline_rounded, _openHelp),
                _buildActionTile(
                    'Send feedback', 'Tell us what to improve', Icons.feedback_outlined, _openFeedback),
                _buildActionTile(
                    'About FEB', 'Version, licenses, credits', Icons.info_outline_rounded, _openAbout),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'Made with ❤️ by Aberham and friends\nVersion 5.5.0',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white30, fontSize: 11, height: 1.5),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingNavBar(currentIndex: 4, onTap: _onNavTapped),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthHeader() {
    return ListenableBuilder(
      listenable: PaymentService.instance,
      builder: (context, _) => StreamBuilder<User?>(
        stream: _authStream,
        builder: (context, snapshot) {
          final currentUser =
              _auth.currentUser ?? (snapshot.hasData ? snapshot.data : null);
          final isUserSignedIn = currentUser != null && !currentUser.isAnonymous;
          final isGuest = currentUser?.isAnonymous == true;
          final displayName = currentUser?.displayName ??
              (_googleUser?.displayName ??
                  (isGuest ? 'Guest User' : 'Mela User'));
          final email = currentUser?.email ??
              (_googleUser?.email ?? (isGuest ? 'Guest Account' : 'No Email'));
          final photoUrl = currentUser?.photoURL ?? _googleUser?.photoUrl;
          return AppCard(
            borderRadius: AppDesignTokens.radius2xl,
            padding: const EdgeInsets.all(16),
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            borderColor: _gold.withValues(alpha: 0.4),
            child: (isUserSignedIn || isGuest)
                ? Row(children: [
                    Hero(
                      tag: 'user_avatar_hero',
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(
                              colors: [Color(0xFFF39C12), _gold]),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: photoUrl != null && photoUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: photoUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) =>
                                      Container(color: Colors.white10),
                                  errorWidget: (_, _, _) => _avatarFallback(
                                      displayName),
                                )
                              : _avatarFallback(displayName),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 6),
                            if (PaymentService.instance.isPremium)
                              _badge('PREMIUM', _gold, _gold)
                            else
                              GestureDetector(
                                onTap: _openSubscription,
                                child: _badge('FREE · UPGRADE',
                                    Colors.white70, Colors.white24),
                              ),
                          ]),
                          const SizedBox(height: 4),
                          Text(email,
                              style: FontService.instance.label(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  letterSpacing: 0.2)),
                          const SizedBox(height: 8),
                          Row(children: [
                            GestureDetector(
                              onTap: _openAccountDetails,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFF22C55E),
                                      width: 0.8),
                                ),
                                child: const Text('ACCOUNT DETAILS',
                                    style: TextStyle(
                                        color: Color(0xFF22C55E),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () async {
                                await _auth.signOut();
                                if (mounted) setState(() {});
                              },
                              child: const Text('LOG OUT',
                                  style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ])
                : Row(children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.person_outline_rounded,
                          color: _gold, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sign in to sync your data',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (_, _, _) => const ActionScreen(),
                                  transitionsBuilder: (_, animation, _, child) =>
                                      FadeTransition(
                                          opacity: animation, child: child),
                                ),
                              );
                            },
                            child: AppCard(
                              borderRadius: AppDesignTokens.radiusLg,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.login_rounded,
                                      color: Color(0xFF22C55E), size: 20),
                                  SizedBox(width: 8),
                                  Text('Sign In / Register',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
          );
        },
      ),
    );
  }

  Widget _avatarFallback(String name) => Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'U',
          style: const TextStyle(
              color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold),
        ),
      );

  Widget _badge(String label, Color fg, Color border) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 0.8),
        ),
        child: Text(label,
            style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.bold)),
      );

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4, top: 4),
      child: Text(title,
          style: FontService.instance.label(
              color: Colors.white38, fontSize: 11, letterSpacing: 1.4)),
    );
  }

  Widget _buildActionTile(
      String title, String subtitle, IconData icon, VoidCallback onTap,
      {bool destructive = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _tap(onTap),
        child: AppCard(
          borderRadius: AppDesignTokens.radiusLg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(icon, color: destructive ? Colors.redAccent : _gold, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: destructive ? Colors.redAccent : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white38, size: 18),
          ]),
        ),
      ),
    );
  }

  void _openAbout() {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('About FEB', style: TextStyle(color: Colors.white)),
        content: const Text(
          'FEB is a movie & series companion built for discovery, offline downloads, and a clean dark experience.\nVersion 5.5.0\nMade with care by FEB and friends.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: _gold))),
        ],
      ),
    );
  }

  void _openHelp() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Help center',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                '• Downloads: open a title → Download, then play offline from Library → Downloads.\n• Lists: save titles from the detail screen, manage them under My Lists.\n• Playback: change quality and speed under General & Playback.\n• Updates: use Check for updates below to install the latest build.',
                style: TextStyle(color: Colors.white70, height: 1.5, fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Got it', style: TextStyle(color: _gold))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFeedback() {
    HapticFeedback.selectionClick();
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send feedback',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'What should we improve?',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.black,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _toast(controller.text.trim().isEmpty
                      ? 'Feedback cancelled'
                      : 'Thanks — feedback noted');
                },
                child:
                    const Text('Submit', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stats + insights: own listeners, isolated rebuilds ───
class _StatsSection extends StatefulWidget {
  final int inProgressCount;
  final VoidCallback openWatched;
  final VoidCallback openWatchlist;
  final VoidCallback openInProgress;
  final VoidCallback openDownloads;
  const _StatsSection({
    required this.inProgressCount,
    required this.openWatched,
    required this.openWatchlist,
    required this.openInProgress,
    required this.openDownloads,
  });
  @override
  State<_StatsSection> createState() => _StatsSectionState();
}

class _StatsSectionState extends State<_StatsSection> {
  late final Listenable _merge = Listenable.merge(
      [UserLibraryService.instance, DownloadService.instance]);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _merge,
      builder: (context, _) {
        final lib = UserLibraryService.instance;
        return Column(
          children: [
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              childAspectRatio: 1.4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _stat(Icons.visibility_rounded, '${lib.watchedCount}', 'WATCHED', widget.openWatched),
                _stat(Icons.bookmark_rounded, '${lib.myListCount}', 'MY LIST', widget.openWatchlist),
                _stat(Icons.watch_later_rounded, '${lib.watchlistCount}', 'WATCHLIST', widget.openWatchlist),
                _stat(Icons.favorite_rounded, '${lib.likedCount}', 'LIKED', widget.openWatchlist),
                _stat(Icons.collections_bookmark_rounded, '${lib.myListCount}', 'LISTS', widget.openWatchlist),
                _stat(Icons.play_circle_outline_rounded, '${widget.inProgressCount}', 'IN PROGRESS',
                    widget.openInProgress),
              ],
            ),
            const SizedBox(height: 20),
            AppCard(
              borderRadius: AppDesignTokens.radius2xl,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Watch Insights',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                      Text('${lib.watchedCount} finished',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _insight(Icons.bookmark_outline_rounded, 'My List',
                          '${lib.myListCount}', widget.openWatchlist),
                      _insight(Icons.check_circle_outline_rounded, 'Finished',
                          '${lib.watchedCount}', widget.openWatched),
                      _insight(Icons.play_circle_outline_rounded, 'In Progress',
                          '${widget.inProgressCount}', widget.openInProgress),
                      _insight(Icons.download_outlined, 'Downloads',
                          '${DownloadService.instance.items.length}',
                          widget.openDownloads),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _stat(IconData icon, String value, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: AppCard(
          borderRadius: AppDesignTokens.radiusLg,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: _gold, size: 18),
              const SizedBox(height: 4),
              Text(value,
                  style: FontService.instance.display(
                      color: _gold, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label,
                  style: FontService.instance.label(
                      color: Colors.white54, fontSize: 9, letterSpacing: 0.8)),
            ],
          ),
        ),
      );

  Widget _insight(IconData icon, String label, String value, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Icon(icon, color: _gold, size: 20),
          const SizedBox(height: 4),
          Text(label,
              style: FontService.instance.label(
                  color: Colors.white54, fontSize: 10, letterSpacing: 0.3)),
          Text(value,
              style: FontService.instance.display(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
      );
}

// ─── Settings body: owns AppSettings/Download/Font listeners ───
class _SettingsSection extends StatefulWidget {
  const _SettingsSection();
  @override
  State<_SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<_SettingsSection> {
  AppSettingsService get _s => AppSettingsService.instance;
  late final Listenable _merge = Listenable.merge([
    AppSettingsService.instance,
    DownloadService.instance,
    FontService.instance,
  ]);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _merge,
      builder: (context, _) => SwitchTheme(
        data: SwitchThemeData(
          thumbColor: WidgetStateProperty.all(_gold),
          trackColor: WidgetStateProperty.all(_gold.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('GENERAL & PLAYBACK'),
            _switch('Autoplay next episode', 'Automatically start next episode',
                _s.autoplayNext, _s.setAutoplayNext,
                icon: Icons.skip_next_rounded),
            _switch('Ask before resuming', 'Prompt start over on watched titles',
                _s.askBeforeResuming, _s.setAskBeforeResuming,
                icon: Icons.restart_alt_rounded),
            _switch('Skip intros when available',
                'Jump past opening credits automatically', _s.skipIntros,
                _s.setSkipIntros,
                icon: Icons.fast_forward_rounded),
            _switch('Autoplay previews', 'Play trailers while browsing',
                _s.autoplayPreviews, _s.setAutoplayPreviews,
                icon: Icons.preview_rounded),
            _value('Default video quality', 'Used when a connection isn\'t specified',
                _s.defaultQuality, () => _pick('Default video quality',
                    const ['Auto', '480p', '720p', '1080p', '4K'],
                    _s.defaultQuality, _s.setDefaultQuality),
                icon: Icons.high_quality_rounded),
            _value('Playback speed', 'Default speed for new titles',
                _s.playbackSpeed, () => _pick('Playback speed',
                    const ['0.5x', '0.75x', '1.0x', '1.25x', '1.5x', '2.0x'],
                    _s.playbackSpeed, _s.setPlaybackSpeed),
                icon: Icons.speed_rounded),
            const SizedBox(height: 16),
            _title('CONTENT FILTERING'),
            _switch('Block adult content (18+)', 'Filter explicit content across app',
                _s.blockAdultContent, _s.setBlockAdultContent,
                icon: Icons.shield_rounded),
            _switch('Hide watched from Home', 'Keep finished titles off the homepage',
                _s.hideWatchedFromHome, _s.setHideWatchedFromHome,
                icon: Icons.visibility_off_rounded),
            _value('Content language', 'Preferred audio/subtitle language',
                _s.contentLanguage, () => _pick('Content language',
                    const ['Any', 'English', 'Spanish', 'French', 'Arabic', 'Amharic'],
                    _s.contentLanguage, _s.setContentLanguage),
                icon: Icons.language_rounded),
            const SizedBox(height: 16),
            _title('CONTENT SOURCES'),
            _action('Add-ons', 'Install add-ons to browse catalogs & play streams',
                Icons.extension_rounded, _openAddons),
            _action('Debrid', 'Play torrent streams instantly via Torbox / Premiumize',
                Icons.bolt_rounded, _openDebrid),
            const SizedBox(height: 16),
            _title('DOWNLOADS & STORAGE'),
            _switch('Data saver', 'Lower stream quality to save bandwidth',
                _s.dataSaver, _s.setDataSaver,
                icon: Icons.data_saver_on_rounded),
            _switch('Download over Wi-Fi only',
                'Avoid using mobile data for downloads', _s.downloadOverWifiOnly,
                _s.setDownloadOverWifiOnly,
                icon: Icons.wifi_rounded),
            _value('Download quality', 'Higher quality uses more storage',
                _s.downloadQuality, () => _pick('Download quality',
                    const ['Standard', 'High', 'Ultra'], _s.downloadQuality,
                    _s.setDownloadQuality),
                icon: Icons.sd_storage_rounded),
            const _CellularTile(),
            _action('Clear all downloads', 'Free up storage on this device',
                Icons.delete_outline_rounded, _clearDownloads,
                destructive: true),
            _action('Clear image cache', 'Free memory used by poster artwork',
                Icons.photo_library_outlined, _clearImageCache),
            const SizedBox(height: 16),
            _title('ADVANCED PLAYBACK'),
            _value('Stream buffer size', 'Larger buffers reduce stalls on slow networks',
                _safeStr('bufferSize', 'Auto'),
                () => _pick('Stream buffer size',
                    const ['Auto', 'Small (5s)', 'Medium (15s)', 'Large (30s)'],
                    _safeStr('bufferSize', 'Auto'),
                    (v) => _safeSet('bufferSize', v, 'setBufferSize')),
                icon: Icons.hourglass_bottom_rounded),
            _value('Preferred subtitle language',
                'Used when multiple tracks are available',
                _safeStr('subtitleLanguage', 'English'),
                () => _pick('Subtitle language',
                    const ['Off', 'English', 'Spanish', 'French', 'Arabic', 'Amharic', 'Auto'],
                    _safeStr('subtitleLanguage', 'English'),
                    (v) => _safeSet('subtitleLanguage', v, 'setSubtitleLanguage')),
                icon: Icons.closed_caption_rounded),
            _switch('Remember playback position',
                'Resume where you left off across sessions',
                _safeBool('rememberPosition', true),
                (v) => _safeSetBool('rememberPosition', v, 'setRememberPosition'),
                icon: Icons.bookmark_added_rounded),
            _switch('Cellular streaming warning',
                'Confirm before streaming on mobile data',
                _safeBool('cellularWarning', true),
                (v) => _safeSetBool('cellularWarning', v, 'setCellularWarning'),
                icon: Icons.signal_cellular_alt_rounded),
            const SizedBox(height: 16),
            _title('NOTIFICATIONS'),
            _switch('New episode alerts', 'Notify when a followed show adds episodes',
                _s.newEpisodeAlerts, _s.setNewEpisodeAlerts,
                icon: Icons.notifications_active_rounded),
            _switch('Recommendation alerts', 'Notify about titles picked for you',
                _s.recommendationAlerts, _s.setRecommendationAlerts,
                icon: Icons.recommend_rounded),
            _switch('Download complete alerts', 'Notify when a download finishes',
                _s.downloadCompleteAlerts, _s.setDownloadCompleteAlerts,
                icon: Icons.download_done_rounded),
            const SizedBox(height: 16),
            _title('APPEARANCE & ACCESSIBILITY'),
            _value('App font', 'Applies across the whole app',
                FontService.instance.current.label, _showFontPicker,
                icon: Icons.font_download_rounded),
            _switch('Haptic feedback', 'Vibration on button taps', _s.hapticFeedback,
                _s.setHapticFeedback,
                icon: Icons.vibration_rounded),
            _switch('Subtitles by default', 'Turn subtitles on automatically',
                _s.subtitlesByDefault, _s.setSubtitlesByDefault,
                icon: Icons.subtitles_rounded),
            _slider('Text size', 'Scales text across the app', _s.textScale,
                _s.setTextScale),
            const SizedBox(height: 16),
            _title('ACCOUNT & PRIVACY'),
            _switch('Share watch activity', 'Let friends see what you\'re watching',
                _s.shareWatchActivity, _s.setShareWatchActivity,
                icon: Icons.share_rounded),
            _action('Terms of Service', 'Read our usage terms',
                Icons.description_outlined, _openTerms),
            _action('Privacy & data',
                'What we collect, GDPR & CCPA rights',
                Icons.privacy_tip_outlined, _openPrivacy),
            const SizedBox(height: 16),
            _title('LIBRARY MAINTENANCE'),
            _action('Clear continue watching', 'Remove all in-progress resume points',
                Icons.history_rounded, _clearContinueWatching,
                destructive: true),
            _action('Reset watch insights',
                'Zero finished / list stats shown above (local only)',
                Icons.restart_alt_rounded, _resetWatchInsights),
          ],
        ),
      ),
    );
  }

  void _openAddons() {
    HapticFeedback.selectionClick();
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AddonsScreen()));
  }

  void _openDebrid() {
    HapticFeedback.selectionClick();
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const DebridScreen()));
  }

  String _safeStr(String field, String fallback) {
    try {
      final dynamic v = _s as dynamic;
      final dynamic val = field == 'bufferSize' ? v.bufferSize : v.subtitleLanguage;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {}
    return fallback;
  }

  bool _safeBool(String field, bool fallback) {
    try {
      final dynamic v = _s as dynamic;
      final dynamic val =
          field == 'rememberPosition' ? v.rememberPosition : v.cellularWarning;
      if (val is bool) return val;
    } catch (_) {}
    return fallback;
  }

  void _safeSet(String field, String value, String method) {
    HapticFeedback.selectionClick();
    try {
      final dynamic v = _s as dynamic;
      switch (method) {
        case 'setBufferSize':
          v.setBufferSize(value);
          break;
        case 'setSubtitleLanguage':
          v.setSubtitleLanguage(value);
          break;
        default:
          v.setSetting(field, value);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _safeSetBool(String field, bool value, String method) {
    HapticFeedback.selectionClick();
    try {
      final dynamic v = _s as dynamic;
      switch (method) {
        case 'setRememberPosition':
          v.setRememberPosition(value);
          break;
        case 'setCellularWarning':
          v.setCellularWarning(value);
          break;
        default:
          v.setSetting(field, value);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _pick(String title, List<String> options, String current,
      ValueChanged<String> onSelected) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            ...options.map((opt) {
              final selected = opt == current;
              return ListTile(
                title: Text(opt,
                    style: TextStyle(
                        color: selected ? _gold : Colors.white,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal)),
                trailing: selected
                    ? const Icon(Icons.check_rounded, color: _gold, size: 20)
                    : null,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelected(opt);
                  Navigator.pop(ctx);
                  if (mounted) setState(() {});
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showFontPicker() {
    HapticFeedback.selectionClick();
    List<String> labels = const ['System', 'Inter', 'Roboto', 'Poppins', 'Space Grotesk'];
    try {
      final dynamic svc = FontService.instance;
      final dynamic avail = svc.availableFonts;
      if (avail is Iterable && avail.isNotEmpty) {
        labels = avail
            .map((f) {
              try {
                return (f.label as String?) ?? f.toString();
              } catch (_) {
                return f.toString();
              }
            })
            .cast<String>()
            .toList();
      }
    } catch (_) {}
    String currentLabel = 'System';
    try {
      currentLabel = FontService.instance.current.label;
    } catch (_) {}
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('App font',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            ...labels.map((label) {
              final selected = label == currentLabel;
              return ListTile(
                title: Text(label,
                    style: TextStyle(
                        color: selected ? _gold : Colors.white,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal)),
                trailing: selected
                    ? const Icon(Icons.check_rounded, color: _gold, size: 20)
                    : null,
                onTap: () async {
                  HapticFeedback.selectionClick();
                  // Capture before any await so we never touch context after
                  // the sheet/State may have been disposed (use_build_context_synchronously).
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(ctx);
                  var applied = false;
                  try {
                    final dynamic svc = FontService.instance;
                    final dynamic avail = svc.availableFonts;
                    if (avail is Iterable) {
                      for (final f in avail) {
                        try {
                          if ((f.label as String?) == label) {
                            await Future.sync(() => svc.setFont(f));
                            applied = true;
                            break;
                          }
                        } catch (_) {}
                      }
                    }
                    if (!applied) {
                      try {
                        await Future.sync(() => svc.setFontByLabel(label));
                        applied = true;
                      } catch (_) {}
                    }
                    if (!applied) {
                      try {
                        await Future.sync(() => svc.setFontFamily(label));
                        applied = true;
                      } catch (_) {}
                    }
                    try {
                      await svc.load();
                    } catch (_) {}
                    try {
                      svc.notifyListeners();
                    } catch (_) {}
                  } catch (_) {}
                  if (!mounted) return;
                  navigator.pop();
                  if (mounted) setState(() {});
                  messenger.showSnackBar(SnackBar(
                    content: Text(applied
                        ? 'Font "$label" applied'
                        : 'Font "$label" selected — restart app if it does not update'),
                    backgroundColor: const Color(0xFF1A1A1A),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(String title, String body, String positive) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(positive, style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _clearDownloads() async {
    HapticFeedback.mediumImpact();
    if (!await _confirm('Clear all downloads?',
        'This removes offline files from this device. You can download them again later.',
        'Clear')) {
      return;
    }
    DownloadService.instance.clearAll();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('All downloads cleared'),
        backgroundColor: Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _clearContinueWatching() async {
    HapticFeedback.mediumImpact();
    if (!await _confirm('Clear continue watching?',
        'This removes all resume positions. Downloads and lists are not affected.',
        'Clear')) {
      return;
    }
    try {
      await ContinueWatchingService.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Continue watching cleared'),
          backgroundColor: Color(0xFF1A1A1A),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {}
  }

  Future<void> _resetWatchInsights() async {
    HapticFeedback.mediumImpact();
    if (!await _confirm('Reset library stats?',
        'Clears local watched / list counters if your library service supports it. This cannot be undone.',
        'Reset')) {
      return;
    }
    try {
      final dynamic lib = UserLibraryService.instance;
      try {
        await lib.clearAllStats();
      } catch (_) {
        try {
          lib.resetStats();
        } catch (_) {}
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _clearImageCache() async {
    HapticFeedback.mediumImpact();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Image cache cleared'),
        backgroundColor: Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _openTerms() {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LegalScreen(initialSection: 'terms'),
      ),
    );
  }

  void _openPrivacy() {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LegalScreen(initialSection: 'privacy'),
      ),
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 4, top: 4),
        child: Text(t,
            style: FontService.instance.label(
                color: Colors.white38, fontSize: 11, letterSpacing: 1.4)),
      );

  Widget _switch(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged,
      {IconData icon = Icons.toggle_on_rounded}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        borderRadius: AppDesignTokens.radiusLg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _gold, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ]),
      ),
    );
  }

  Widget _value(String title, String subtitle, String value, VoidCallback onTap,
      {IconData icon = Icons.tune_rounded}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AppCard(
          borderRadius: AppDesignTokens.radiusLg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _gold, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
            Text(value, style: const TextStyle(color: _gold, fontSize: 12.5)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _action(String title, String subtitle, IconData icon, VoidCallback onTap,
      {bool destructive = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AppCard(
          borderRadius: AppDesignTokens.radiusLg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(icon, color: destructive ? Colors.redAccent : _gold, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: destructive ? Colors.redAccent : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _slider(String title, String subtitle, double value,
      ValueChanged<double> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        borderRadius: AppDesignTokens.radiusLg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            Text(subtitle,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _gold,
                thumbColor: _gold,
                inactiveTrackColor: Colors.white24,
                overlayColor: _gold.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: value,
                min: 0.8,
                max: 1.4,
                divisions: 6,
                label: '${(value * 100).round()}%',
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Cellular data tile (self-contained) ───
class _CellularTile extends StatelessWidget {
  const _CellularTile();
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CellularDataService.instance,
      builder: (context, _) {
        final svc = CellularDataService.instance;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            borderRadius: AppDesignTokens.radiusLg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.signal_cellular_alt_rounded,
                      color: _gold, size: 18),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Cellular data usage',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ),
                  GestureDetector(
                    onTap: () async {
                      HapticFeedback.mediumImpact();
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1A1A1A),
                          title: const Text('Reset data stats?',
                              style: TextStyle(color: Colors.white)),
                          content: const Text(
                            'This clears estimated cellular streaming and download totals on this device.',
                            style: TextStyle(color: Colors.white70),
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel',
                                    style: TextStyle(color: Colors.white54))),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Reset',
                                    style: TextStyle(color: Colors.redAccent))),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await CellularDataService.instance.resetAll();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Cellular data stats reset'),
                            backgroundColor: Color(0xFF1A1A1A),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      }
                    },
                    child: const Text('Reset',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('Today', svc.todayLabel),
                    _stat('This month', svc.monthLabel),
                    _stat('Lifetime', svc.lifetimeLabel),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Estimates from stream quality × time and download sizes. Enable “Cellular streaming warning” to meter mobile sessions.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 10,
                      height: 1.3),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value) => Column(children: [
        Text(value,
            style: const TextStyle(
                color: _gold, fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ]);
}

// ─── Update tile: self-contained state machine ───
class _UpdateTile extends StatefulWidget {
  const _UpdateTile();
  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  bool _checking = false;
  bool _expanded = false;
  bool _downloading = false;
  double _progress = 0.0;
  UpdateInfo? _info;

  @override
  void initState() {
    super.initState();
    _silentCheck();
  }

  Future<void> _silentCheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    final info = await UpdateService.checkForUpdate();
    if (mounted) {
      setState(() {
        _checking = false;
        _info = info;
        if (info != null && info.force) _expanded = true;
      });
    }
  }

  Future<void> _manualCheck() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _expanded = true;
    });
    final info = await UpdateService.checkForUpdate();
    if (mounted) {
      setState(() {
        _checking = false;
        _info = info;
      });
      if (info == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Your app is already up to date.'),
          backgroundColor: Color(0xFF1A1A1A),
          behavior: SnackBarBehavior.floating,
        ));
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _expanded = false);
        });
      }
    }
  }

  Future<void> _download() async {
    if (_info == null || _downloading) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _downloading = true;
      _progress = 0.0;
    });
    final success = await UpdateService.downloadAndInstall(
      url: _info!.downloadUrl,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (mounted) {
      setState(() => _downloading = false);
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Download or installation failed. Please check permissions.'),
          backgroundColor: Color(0xFF1A1A1A),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        borderRadius: AppDesignTokens.radiusLg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                if (_info != null) {
                  setState(() => _expanded = !_expanded);
                } else {
                  _manualCheck();
                }
              },
              child: Row(children: [
                const Icon(Icons.system_update_rounded, color: _gold, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Check for updates',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        _checking
                            ? 'Checking...'
                            : (_info != null
                                ? 'Version ${_info!.version} available'
                                : 'See if a new version is available'),
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                if (_checking)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _gold))
                else
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white38,
                    size: 24,
                  ),
              ]),
            ),
            if (_expanded && _info != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What\'s new',
                        style: FontService.instance.style(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(_info!.changelog,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11, height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_downloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(_gold),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text('${(_progress * 100).toStringAsFixed(0)}% downloaded',
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ),
              ] else
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _download,
                    child: Text('Download & Install Now',
                        style: FontService.instance.style(
                            color: Colors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}