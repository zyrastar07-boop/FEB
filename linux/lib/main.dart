import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/movie.dart'; 
import 'screens/home_screen.dart';
import 'services/download_notifier.dart';

void main() async {
  // Ensure widget bindings are initialized before calling async methods
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive (initFlutter handles directory path automatically)
  await Hive.initFlutter();
  
  // Register adapter safely
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(MovieAdapter());
  }
  
  // Open the local storage boxes
  await Hive.openBox<Movie>('continue_watching');
  await Hive.openBox('continue_watching_store');

  // Initialize download background processes and notifications
  await DownloadNotifier.initialize();

  runApp(const PhonoFilmApp());
}

class PhonoFilmApp extends StatelessWidget {
  const PhonoFilmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MelaFilm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF101010),
        // Global fontFamily omitted so standard UI & HomeScreen retain 
        // legibility. Specific movie titles apply 'AstoneNouvea' explicitly.
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB800), // Premium Gold accent
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}