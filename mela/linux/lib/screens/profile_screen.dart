import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/floating_nav_bar.dart';
import '../services/font_service.dart';
import 'search_screen.dart';
import 'library_screen.dart';

const _gold = Color(0xFFD4AF37);
const _bg = Color(0xFF0A0A0A);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ── General & Playback ──────────────────────────────────────────────
  bool _autoplayNext = true;
  bool _askBeforeResuming = false;
  bool _skipIntros = true;
  bool _autoplayPreviews = true;
  String _defaultQuality = 'Auto';
  String _playbackSpeed = '1.0x';

  // ── Content Filtering ────────────────────────────────────────────────
  bool _blockAdultContent = true;
  bool _hideWatchedFromHome = false;
  String _contentLanguage = 'Any';

  // ── Downloads & Storage ─────────────────────────────────────────────
  bool _dataSaver = false;
  bool _downloadOverWifiOnly = true;
  String _downloadQuality = 'High';

  // ── Notifications ───────────────────────────────────────────────────
  bool _newEpisodeAlerts = true;
  bool _recommendationAlerts = false;
  bool _downloadCompleteAlerts = true;

  // ── Accessibility & Appearance ───────────────────────────────────────
  bool _hapticFeedback = true;
  bool _subtitlesByDefault = false;
  double _textScale = 1.0;

  // ── Account & Privacy ────────────────────────────────────────────────
  bool _shareWatchActivity = true;

  // ignore: unused_field
  bool _prefsLoaded = false;

  void _onNavTapped(int index) {
    HapticFeedback.selectionClick();
    if (index == 3) return; // already here

    if (index == 0) {
      Navigator.pop(context);
      return;
    }

    Widget screen;
    if (index == 1) {
      screen = const SearchScreen();
    } else {
      screen = const LibraryScreen();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  void initState() {
    super.initState();
    FontService.instance.load().then((_) {
      if (mounted) setState(() => _prefsLoaded = true);
    });
    FontService.instance.addListener(_onFontChanged);
  }

  @override
  void dispose() {
    FontService.instance.removeListener(_onFontChanged);
    super.dispose();
  }

  void _onFontChanged() {
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _tap(VoidCallback fn) {
    HapticFeedback.selectionClick();
    fn();
  }

  // ── Pickers ──────────────────────────────────────────────────────────

  void _showFontPicker() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('App font',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            ...FontService.fonts.map((f) {
              final selected = FontService.instance.current.id == f.id;
              return ListTile(
                title: Text(
                  f.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: f.isDisplay ? 20 : 16,
                    fontFamily: f.family.isEmpty ? null : f.family,
                  ),
                ),
                subtitle: Text(
                  f.isDisplay ? 'Display font' : 'Body font',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                trailing: selected
                    ? const Icon(Icons.check_circle_rounded, color: _gold)
                    : null,
                onTap: () async {
                  await FontService.instance.setFont(f.id);
                  if (mounted) Navigator.pop(context);
                  _toast('Font set to ${f.label}');
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showChoicePicker({
    required String title,
    required List<String> options,
    required String current,
    required ValueChanged<String> onSelected,
  }) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            ...options.map((o) => ListTile(
                  title:
                      Text(o, style: const TextStyle(color: Colors.white)),
                  trailing: o == current
                      ? const Icon(Icons.check_circle_rounded, color: _gold)
                      : null,
                  onTap: () {
                    onSelected(o);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _confirmLogOut() {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Log out?', style: TextStyle(color: Colors.white)),
        content: const Text('You can log back in anytime.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _toast('Logged out');
              // TODO: wire to your real auth/session clear + navigation.
            },
            child: const Text('Log out',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearDownloads() async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Clear all downloads?',
            style: TextStyle(color: Colors.white)),
        content: const Text('This frees up storage but removes offline files.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // TODO: wire to DownloadService.instance.clearAll()
      _toast('Downloads cleared');
    }
  }

  void _shareApp() {
    HapticFeedback.lightImpact();
    _toast('Share link copied');
    // TODO: wire to share_plus package.
  }

  void _openAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Mela',
      applicationVersion: '5.5.0',
      applicationLegalese: 'Made with ❤️ by Mela and friends',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Screen Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Settings",
                    style: FontService.instance.style(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _tap(_shareApp),
                    child: LiquidGlassContainer(
                      borderRadius: 20,
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.share_rounded,
                          color: _gold, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Deduped user profile header ─────────────────────────
              // (previously showed the name twice — once as the avatar
              // initials label and once again below; now the avatar is
              // purely visual initials and the name appears exactly once)
              LiquidGlassContainer(
                borderRadius: 28,
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                borderColor: _gold.withValues(alpha: 0.4),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF39C12), _gold],
                        ),
                      ),
                      child: const Center(
                        child: Text("F1",
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text("zyrastar07",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _gold.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: _gold, width: 0.8),
                                ),
                                child: const Text("PREMIUM",
                                    style: TextStyle(
                                        color: _gold,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Handle-style text (like "@f1user4331" in the
                          // reference) reads best in the mono font.
                          Text("zyrastar07@gmail.com",
                              style: FontService.instance.label(
                                  color: Colors.white54, fontSize: 12, letterSpacing: 0.2)),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _confirmLogOut,
                            child: const Text("LOG OUT",
                                style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 6-Grid Stats Matrix
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                childAspectRatio: 1.4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStatTile("0", "WATCHED", () => _toast('Open Watched')),
                  _buildStatTile("0", "THIS YEAR", () => _toast('Open This Year')),
                  _buildStatTile("0", "WATCHLIST", () => _toast('Open Watchlist')),
                  _buildStatTile("0", "LIKED", () => _toast('Open Liked')),
                  _buildStatTile("0", "LISTS", () => _toast('Open Lists')),
                  _buildStatTile("0", "REVIEWS", () => _toast('Open Reviews')),
                ],
              ),
              const SizedBox(height: 20),

              // Watch Insights Widget
              LiquidGlassContainer(
                borderRadius: 24,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text("📊 Watch Insights",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        Text("~0.4h Watched",
                            style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildInsightItem(Icons.bookmark_outline_rounded,
                            "My List", "0", () => _toast('Open My List')),
                        _buildInsightItem(Icons.check_circle_outline_rounded,
                            "Finished", "0", () => _toast('Open Finished')),
                        _buildInsightItem(Icons.play_circle_outline_rounded,
                            "In Progress", "3", () => _toast('Open In Progress')),
                        _buildInsightItem(Icons.download_outlined,
                            "Downloads", "0", () => _toast('Open Downloads')),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ═══ 1. GENERAL & PLAYBACK ═══════════════════════════════
              _buildSectionTitle("GENERAL & PLAYBACK"),
              _buildSwitchTile(
                "Autoplay next episode",
                "Automatically start next episode",
                _autoplayNext,
                (v) => setState(() => _autoplayNext = v),
              ),
              _buildSwitchTile(
                "Ask before resuming",
                "Prompt start over on watched titles",
                _askBeforeResuming,
                (v) => setState(() => _askBeforeResuming = v),
              ),
              _buildSwitchTile(
                "Skip intros when available",
                "Jump past opening credits automatically",
                _skipIntros,
                (v) => setState(() => _skipIntros = v),
              ),
              _buildSwitchTile(
                "Autoplay previews",
                "Play trailers while browsing",
                _autoplayPreviews,
                (v) => setState(() => _autoplayPreviews = v),
              ),
              _buildValueTile(
                "Default video quality",
                "Used when a connection isn't specified",
                _defaultQuality,
                () => _showChoicePicker(
                  title: 'Default video quality',
                  options: const ['Auto', '480p', '720p', '1080p', '4K'],
                  current: _defaultQuality,
                  onSelected: (v) => setState(() => _defaultQuality = v),
                ),
              ),
              _buildValueTile(
                "Playback speed",
                "Default speed for new titles",
                _playbackSpeed,
                () => _showChoicePicker(
                  title: 'Playback speed',
                  options: const ['0.5x', '0.75x', '1.0x', '1.25x', '1.5x', '2.0x'],
                  current: _playbackSpeed,
                  onSelected: (v) => setState(() => _playbackSpeed = v),
                ),
              ),
              const SizedBox(height: 16),

              // ═══ 2. CONTENT FILTERING ════════════════════════════════
              _buildSectionTitle("CONTENT FILTERING"),
              _buildSwitchTile(
                "Block adult content (18+)",
                "Filter explicit content across app",
                _blockAdultContent,
                (v) => setState(() => _blockAdultContent = v),
              ),
              _buildSwitchTile(
                "Hide watched from Home",
                "Keep finished titles off the homepage",
                _hideWatchedFromHome,
                (v) => setState(() => _hideWatchedFromHome = v),
              ),
              _buildValueTile(
                "Content language",
                "Preferred audio/subtitle language",
                _contentLanguage,
                () => _showChoicePicker(
                  title: 'Content language',
                  options: const [
                    'Any',
                    'English',
                    'Spanish',
                    'French',
                    'Arabic',
                    'Amharic'
                  ],
                  current: _contentLanguage,
                  onSelected: (v) => setState(() => _contentLanguage = v),
                ),
              ),
              const SizedBox(height: 16),

              // ═══ 3. DOWNLOADS & STORAGE ══════════════════════════════
              _buildSectionTitle("DOWNLOADS & STORAGE"),
              _buildSwitchTile(
                "Data saver",
                "Lower stream quality to save bandwidth",
                _dataSaver,
                (v) => setState(() => _dataSaver = v),
              ),
              _buildSwitchTile(
                "Download over Wi-Fi only",
                "Avoid using mobile data for downloads",
                _downloadOverWifiOnly,
                (v) => setState(() => _downloadOverWifiOnly = v),
              ),
              _buildValueTile(
                "Download quality",
                "Higher quality uses more storage",
                _downloadQuality,
                () => _showChoicePicker(
                  title: 'Download quality',
                  options: const ['Standard', 'High', 'Ultra'],
                  current: _downloadQuality,
                  onSelected: (v) => setState(() => _downloadQuality = v),
                ),
              ),
              _buildActionTile(
                "Clear all downloads",
                "Free up storage on this device",
                Icons.delete_outline_rounded,
                _clearDownloads,
                destructive: true,
              ),
              const SizedBox(height: 16),

              // ═══ 4. NOTIFICATIONS ════════════════════════════════════
              _buildSectionTitle("NOTIFICATIONS"),
              _buildSwitchTile(
                "New episode alerts",
                "Notify when a followed show adds episodes",
                _newEpisodeAlerts,
                (v) => setState(() => _newEpisodeAlerts = v),
              ),
              _buildSwitchTile(
                "Recommendation alerts",
                "Notify about titles picked for you",
                _recommendationAlerts,
                (v) => setState(() => _recommendationAlerts = v),
              ),
              _buildSwitchTile(
                "Download complete alerts",
                "Notify when a download finishes",
                _downloadCompleteAlerts,
                (v) => setState(() => _downloadCompleteAlerts = v),
              ),
              const SizedBox(height: 16),

              // ═══ 5. APPEARANCE & ACCESSIBILITY ═══════════════════════
              _buildSectionTitle("APPEARANCE & ACCESSIBILITY"),
              _buildValueTile(
                "App font",
                "Applies across the whole app",
                FontService.instance.current.label,
                _showFontPicker,
              ),
              _buildSwitchTile(
                "Haptic feedback",
                "Vibration on button taps",
                _hapticFeedback,
                (v) => setState(() => _hapticFeedback = v),
              ),
              _buildSwitchTile(
                "Subtitles by default",
                "Turn subtitles on automatically",
                _subtitlesByDefault,
                (v) => setState(() => _subtitlesByDefault = v),
              ),
              _buildSliderTile(
                "Text size",
                "Scales text across the app",
                _textScale,
                (v) => setState(() => _textScale = v),
              ),
              const SizedBox(height: 16),

              // ═══ 6. ACCOUNT & PRIVACY ════════════════════════════════
              _buildSectionTitle("ACCOUNT & PRIVACY"),
              _buildSwitchTile(
                "Share watch activity",
                "Let friends see what you're watching",
                _shareWatchActivity,
                (v) => setState(() => _shareWatchActivity = v),
              ),
              _buildActionTile(
                "Manage subscription",
                "Change or cancel your Premium plan",
                Icons.card_membership_rounded,
                () => _toast('Opening subscription management'),
              ),
              _buildActionTile(
                "Privacy & data",
                "Review what we collect and why",
                Icons.privacy_tip_outlined,
                () => _toast('Opening privacy settings'),
              ),
              const SizedBox(height: 16),

              // ═══ 7. ABOUT & SUPPORT ══════════════════════════════════
              _buildSectionTitle("ABOUT & SUPPORT"),
              _buildActionTile(
                "Help center",
                "FAQs and troubleshooting",
                Icons.help_outline_rounded,
                () => _toast('Opening help center'),
              ),
              _buildActionTile(
                "Send feedback",
                "Tell us what to improve",
                Icons.feedback_outlined,
                () => _toast('Opening feedback form'),
              ),
              _buildActionTile(
                "About Mela",
                "Version, licenses, credits",
                Icons.info_outline_rounded,
                _openAbout,
              ),
              const SizedBox(height: 24),

              // Footer Branding
              const Center(
                child: Text(
                  "Made with ❤️ by Mela and friends\nVersion 5.5.0",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white30, fontSize: 11, height: 1.5),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      bottomNavigationBar: FloatingNavBar(
        currentIndex: 3,
        onTap: _onNavTapped,
      ),
    );
  }

  Widget _buildStatTile(String value, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: () => _tap(onTap),
      child: LiquidGlassContainer(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Big number stays in the display font — matches the bold
            // "2 / 2 / 0" numbers in the reference stat grid.
            Text(value,
                style: FontService.instance
                    .display(color: _gold, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            // Uppercase label goes monospace — matches "WATCHED",
            // "THIS YEAR", "WATCHLIST" etc. in the reference screenshot.
            Text(label,
                style: FontService.instance
                    .label(color: Colors.white54, fontSize: 9, letterSpacing: 0.8)),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightItem(
      IconData icon, String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: () => _tap(onTap),
      child: Column(
        children: [
          Icon(icon, color: _gold, size: 20),
          const SizedBox(height: 4),
          Text(label,
              style: FontService.instance
                  .label(color: Colors.white54, fontSize: 10, letterSpacing: 0.3)),
          Text(value,
              style: FontService.instance
                  .display(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    // Monospace + uppercase + wide tracking — matches "ACTIVITY", "SAVED",
    // "CREATED" section headers in the reference screenshot.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4, top: 4),
      child: Text(
        title,
        style: FontService.instance
            .label(color: Colors.white38, fontSize: 11, letterSpacing: 1.4),
      ),
    );
  }

  Widget _buildSwitchTile(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: LiquidGlassContainer(
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
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
              activeThumbColor: _gold,
              activeTrackColor: _gold.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  /// A tile that opens a picker and shows the current value, e.g.
  /// "Default video quality" → "Auto".
  Widget _buildValueTile(
      String title, String subtitle, String value, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _tap(onTap),
        child: LiquidGlassContainer(
          borderRadius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
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
                        style:
                            const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ),
              Row(
                children: [
                  Text(value,
                      style: const TextStyle(color: _gold, fontSize: 12.5)),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded,
                      color: Colors.white38, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A tile that just performs an action when tapped (navigate, dialog, etc.)
  Widget _buildActionTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap, {
    bool destructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _tap(onTap),
        child: LiquidGlassContainer(
          borderRadius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon,
                  color: destructive ? Colors.redAccent : _gold, size: 18),
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
                        style:
                            const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white38, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderTile(
      String title, String subtitle, double value, ValueChanged<double> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: LiquidGlassContainer(
        borderRadius: 18,
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