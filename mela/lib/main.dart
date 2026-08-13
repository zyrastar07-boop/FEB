import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'models/movie.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding/action_screen.dart';
import 'services/app_settings_service.dart';
import 'services/download_notifier.dart';
import 'services/font_service.dart';
import 'services/review_service.dart';
import 'services/user_library_service.dart';
import 'services/remote_app_config.dart';
import 'services/maintenance_gate.dart';

Future<void> main() async {
  // Always required before calling any async methods or plugins
  WidgetsFlutterBinding.ensureInitialized();

  bool isFirstLaunch = true;

  try {
    // 1. Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 2. Initialize Hive local storage
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(MovieAdapter());
    }

    await Hive.openBox<Movie>('continue_watching');
    await Hive.openBox('continue_watching_store');

    // 3. Initialize app services
    await UserLibraryService.instance.init();
    await ReviewService.instance.init();
    await AppSettingsService.instance.init();
    await FontService.instance.load();
    await DownloadNotifier.initialize();

    // 4. Remote config check
    await RemoteAppConfig.instance.load();

    // 5. Read onboarding status
    final prefs = await SharedPreferences.getInstance();
    isFirstLaunch = prefs.getBool('is_first_launch') ?? true;
  } catch (e) {
    debugPrint('Startup initialization error: $e');
    // Prevents app from sticking on a black screen if network/services throw an error on boot
  }

  runApp(PhonoFilmApp(isFirstLaunch: isFirstLaunch));
}

class PhonoFilmApp extends StatelessWidget {
  final bool isFirstLaunch;

  const PhonoFilmApp({
    super.key,
    required this.isFirstLaunch,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MelaFilm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF101010),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB800),
          surface: Color(0xFF1E1E1E),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: MaintenanceGate(
        child: isFirstLaunch ? const ActionScreen() : const HomeScreen(),
      ),
    );
  }
}