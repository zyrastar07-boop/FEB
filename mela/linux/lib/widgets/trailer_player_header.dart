import 'package:flutter/material.dart';
// Note: Add youtube_player_flutter to pubspec.yaml for playback functionality

class TrailerPlayerHeader extends StatelessWidget {
  final String? youtubeKey;

  const TrailerPlayerHeader({super.key, this.youtubeKey});

  @override
  Widget build(BuildContext context) {
    if (youtubeKey == null) {
      return Container(
        height: 220,
        color: Colors.black,
        child: const Center(child: Text("No Trailer Available", style: TextStyle(color: Colors.white54))),
      );
    }

    // Insert your YouTube Player widget implementation here
    return Container(
      height: 250,
      width: double.infinity,
      color: Colors.black,
      child: Center(
        child: Text(
          "Trailer Playing (Key: $youtubeKey)",
          style: const TextStyle(color: Color(0xFFD4AF37)),
        ),
      ),
    );
  }
}