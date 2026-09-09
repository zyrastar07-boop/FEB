import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'design/refresh_rate.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'models/movie.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding/action_screen.dart';
import 'services/app_settings_service.dart';
import 'services/auth_service.dart';
import 'services/auth_session_guard.dart';
import 'services/cellular_data_service.dart';
import 'services/download_notifier.dart';
import 'services/download_service.dart';
import 'services/font_service.dart';
import 'services/review_service.dart';
import 'services/user_library_service.dart';
import 'services/remote_app_config.dart';
import 'services/maintenance_gate.dart';
import '../design/tokens.dart';
import '../utils/image_cache.dart';
import '../widgets/feb_wave_loader.dart';
import '../widgets/legal_consent_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep [RefreshRate.current] fresh so motion, blur, and timing code can
  // adapt to 60 / 90 / 120 Hz panels and stay smooth on every device.
  RefreshRateService.instance.start();

  // Bound in-memory image cache so long scroll sessions don't OOM.
  ImageCacheConfig.apply();

  // Capture silent exceptions so a single bad decode doesn't degrade
  // scroll FPS or break a screen on iOS release builds.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      debugPrint('FlutterError: ${details.exception}\n${details.stack}');
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher error: $error\n$stack');
    return true;
  };

  runApp(const SplashScreen());
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final Future<Map<String, dynamic>> _initFuture = _initializeApp();

  Future<Map<String, dynamic>> _initializeApp() async {
    // 1. Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 2. Hive
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(MovieAdapter());
    }
    try {
      await Hive.openBox<Movie>('continue_watching');
      await Hive.openBox('continue_watching_store');
    } catch (e) {
      debugPrint('Hive error: $e');
    }

    // 3. Services
    await UserLibraryService.instance.init();
    await ReviewService.instance.init();
    await AppSettingsService.instance.init();
    await CellularDataService.instance.init();
    await FontService.instance.load();
    await DownloadNotifier.initialize();
    await DownloadService.instance.ensureLoaded();
    await RemoteAppConfig.instance.load();

    // 4. Permissions (Updated to Permission.videos for modern Android/iOS support)
    await [
      Permission.videos,
      Permission.notification,
    ].request();

    // 5. Auth
    final user = await AuthService().getCurrentUserSession();
    final isFirstLaunch = await OnboardingPrefs.isFirstLaunch();

    return {
      'user': user,
      'isFirstLaunch': isFirstLaunch,
    };
  }

  ThemeData _buildTheme(FontService fontService) => buildAppTheme(fontService);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: FontService.instance,
      builder: (context, child) {
        return MaterialApp(
          home: FutureBuilder<Map<String, dynamic>>(
            future: _initFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  backgroundColor: AppDesignTokens.backgroundCanvas,
                  body: Center(child: WaveLoader()),
                );
              }
              if (snapshot.hasError) {
                return Scaffold(
                  backgroundColor: AppDesignTokens.backgroundCanvas,
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('INIT ERROR', style: AppDesignTokens.microLegal),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          style: AppDesignTokens.caption,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              final data = snapshot.data!;
              final isFirstLaunch = data['isFirstLaunch'];

              return PhonoFilmApp(isFirstLaunch: isFirstLaunch);
            },
          ),
          title: 'FEB',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(FontService.instance),
        );
      },
    );
  }
}

class PhonoFilmApp extends StatefulWidget {
  final bool isFirstLaunch;

  const PhonoFilmApp({super.key, required this.isFirstLaunch});

  @override
  State<PhonoFilmApp> createState() => _PhonoFilmAppState();
}

class _PhonoFilmAppState extends State<PhonoFilmApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Downloads:
    // - flushToDisk() on paused/detached so a kill loses at most a few
    //   seconds of segment-level progress. (Already in place — the
    //   per-segment resume logic in DownloadService means the bytes are
    //   already safe on disk before this fires.)
    // - Wake-lock is held while any download is actively transferring
    //   (see DownloadService._syncWakelock), which keeps the CPU awake
    //   while the user is on the screen with the app foregrounded.
    //
    // What is NOT covered here, by design:
    // - True background continuation with the screen *off* and the app
    //   fully backgrounded. That requires a native Android foreground
    //   service (with the FOREGROUND_SERVICE_DATA_SYNC permission that
    //   is already declared in AndroidManifest.xml) and, on iOS, a
    //   background URLSession. Neither can be wired from Dart alone —
    //   flutter_background_service (already a dependency) is the
    //   intended path forward; spinning it up requires moving the
    //   network loop into a separate isolate, which is a non-trivial
    //   refactor and is tracked separately. Until then, jobs that were
    //   mid-download when the app gets killed restore as "Paused —
    //   tap Resume to continue" on next launch, never "Failed —
    //   start over".
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(DownloadService.instance.flushToDisk());
    } else if (state == AppLifecycleState.resumed) {
      // Refresh the cached Firebase ID token if it's near / past its
      // expiry so the next Worker call doesn't 401.
      AuthSessionGuard.instance.onAppResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FEB',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(FontService.instance),
      home: MaintenanceGate(
        child: LegalConsentGate(
          child:
              widget.isFirstLaunch ? const ActionScreen() : const HomeScreen(),
        ),
      ),
    );
  }
}

class OnboardingPrefs {
  static const key = 'is_first_launch';
  static Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? true;
  }
}

ThemeData buildAppTheme(FontService fontService) {
  return ThemeData(
    useMaterial3: false,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppDesignTokens.backgroundCanvas,
    colorScheme: const ColorScheme.dark(
      primary: AppDesignTokens.gold,
      secondary: AppDesignTokens.textCream,
      surface: AppDesignTokens.surfaceElevated,
      error: AppDesignTokens.error,
      onPrimary: AppDesignTokens.textOnGold,
      onSecondary: AppDesignTokens.backgroundCanvas,
      onSurface: AppDesignTokens.textCream,
      onError: AppDesignTokens.textCream,
    ),
    textTheme: TextTheme(
      displayLarge: AppDesignTokens.body,
      displayMedium: AppDesignTokens.body,
      displaySmall: AppDesignTokens.body,
      headlineLarge: AppDesignTokens.heading,
      headlineMedium: AppDesignTokens.heading,
      headlineSmall: AppDesignTokens.heading,
      titleLarge: AppDesignTokens.navLabel,
      titleMedium: AppDesignTokens.navLabel,
      titleSmall: AppDesignTokens.navLabel,
      bodyLarge: AppDesignTokens.body,
      bodyMedium: AppDesignTokens.body,
      bodySmall: AppDesignTokens.caption,
      labelLarge: AppDesignTokens.navLabel,
      labelMedium: AppDesignTokens.navLabel,
      labelSmall: AppDesignTokens.microLegal,
    ).apply(fontFamily: fontService.bodyFamily),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppDesignTokens.backgroundCanvas,
      foregroundColor: AppDesignTokens.textCream,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppDesignTokens.heading,
      iconTheme: IconThemeData(color: AppDesignTokens.textCream, size: 22),
    ),
    cardTheme: CardThemeData(
      color: AppDesignTokens.surfaceElevated,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppDesignTokens.radiusMd,
        side: const BorderSide(color: AppDesignTokens.borderCork, width: 1),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppDesignTokens.borderCork,
      thickness: 1,
      space: 1,
      indent: 0,
      endIndent: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      border: UnderlineInputBorder(
        borderSide: const BorderSide(color: AppDesignTokens.textCream, width: 1),
        borderRadius: AppDesignTokens.radiusZero,
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: const BorderSide(color: AppDesignTokens.textCream, width: 1),
        borderRadius: AppDesignTokens.radiusZero,
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: const BorderSide(color: AppDesignTokens.gold, width: 1),
        borderRadius: AppDesignTokens.radiusZero,
      ),
      errorBorder: UnderlineInputBorder(
        borderSide: const BorderSide(color: AppDesignTokens.error, width: 1),
        borderRadius: AppDesignTokens.radiusZero,
      ),
      hintStyle: AppDesignTokens.caption.copyWith(color: AppDesignTokens.muted),
      labelStyle: AppDesignTokens.caption,
      errorStyle: AppDesignTokens.microLegal.copyWith(color: AppDesignTokens.error),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppDesignTokens.surfaceElevated,
        foregroundColor: AppDesignTokens.textCream,
        elevation: 0,
        // Compact, consistent button geometry across the app.
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: AppDesignTokens.radiusPill,
        ),
        textStyle: AppDesignTokens.navLabel,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppDesignTokens.textCream,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: AppDesignTokens.radiusGhost,
          side: const BorderSide(color: AppDesignTokens.textCream, width: 1),
        ),
        textStyle: AppDesignTokens.navLabel,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppDesignTokens.textCream,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: AppDesignTokens.radiusZero,
        ),
        textStyle: AppDesignTokens.navLabel,
      ),
    ),
    iconTheme: const IconThemeData(
      color: AppDesignTokens.textCream,
      size: 20,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppDesignTokens.surfaceElevated,
      labelStyle: AppDesignTokens.navLabel,
      secondaryLabelStyle: AppDesignTokens.navLabel,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: AppDesignTokens.radiusMd,
        side: const BorderSide(color: AppDesignTokens.borderCork, width: 1),
      ),
      side: const BorderSide(color: AppDesignTokens.borderCork, width: 1),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppDesignTokens.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppDesignTokens.radiusMd,
        side: const BorderSide(color: AppDesignTokens.borderCork, width: 1),
      ),
      titleTextStyle: AppDesignTokens.heading,
      contentTextStyle: AppDesignTokens.caption,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppDesignTokens.surfaceElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppDesignTokens.radiusMd,
        side: const BorderSide(color: AppDesignTokens.borderCork, width: 1),
      ),
      textStyle: AppDesignTokens.caption,
      mouseCursor: WidgetStateProperty.all(SystemMouseCursors.basic),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppDesignTokens.surfaceElevated,
      contentTextStyle: AppDesignTokens.caption,
      shape: RoundedRectangleBorder(
        borderRadius: AppDesignTokens.radiusMd,
        side: const BorderSide(color: AppDesignTokens.borderCork, width: 1),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppDesignTokens.textCream,
      linearTrackColor: AppDesignTokens.surfaceElevated,
      circularTrackColor: AppDesignTokens.surfaceElevated,
      strokeCap: StrokeCap.round,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppDesignTokens.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: const BorderSide(color: AppDesignTokens.borderCork, width: 1),
      ),
      dragHandleColor: AppDesignTokens.textCream.withValues(alpha: 0.4),
      dragHandleSize: const Size(36, 4),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: AppDesignTokens.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: const BorderSide(color: AppDesignTokens.borderCork, width: 1),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppDesignTokens.textCream;
        }
        return AppDesignTokens.textCream.withValues(alpha: 0.5);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppDesignTokens.textCream.withValues(alpha: 0.35);
        }
        return AppDesignTokens.textCream.withValues(alpha: 0.12);
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      splashRadius: 16,
    ),
    toggleButtonsTheme: ToggleButtonsThemeData(
      selectedColor: AppDesignTokens.textCream,
      borderColor: AppDesignTokens.borderCork,
      borderRadius: AppDesignTokens.radiusMd,
      textStyle: AppDesignTokens.navLabel,
    ),
    dividerColor: AppDesignTokens.borderCork,
    hoverColor: AppDesignTokens.surfaceElevated,
    focusColor: AppDesignTokens.textCream.withValues(alpha: 0.4),
    highlightColor: AppDesignTokens.textCream.withValues(alpha: 0.15),
  );
}