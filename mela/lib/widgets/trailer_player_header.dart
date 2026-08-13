import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class TrailerPlayerHeader extends StatefulWidget {
  final String? youtubeKey;

  const TrailerPlayerHeader({super.key, this.youtubeKey});

  @override
  State<TrailerPlayerHeader> createState() => _TrailerPlayerHeaderState();
}

class _TrailerPlayerHeaderState extends State<TrailerPlayerHeader> {
  YoutubePlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(covariant TrailerPlayerHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeKey != widget.youtubeKey) {
      _initPlayer();
    }
  }

  void _initPlayer() {
    final key = widget.youtubeKey;
    if (key != null && key.isNotEmpty) {
      _controller?.dispose();
      _controller = YoutubePlayerController(
        initialVideoId: key,
        flags: const YoutubePlayerFlags(
          autoPlay: false,
          mute: false,
          enableCaption: false,
          isLive: false,
          forceHD: false,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.youtubeKey == null || widget.youtubeKey!.isEmpty) {
      return Container(
        height: 230,
        color: Colors.black,
        child: const Center(
          child: Text(
            "No Trailer Available",
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ),
      );
    }

    if (_controller == null) {
      return Container(
        height: 230,
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFB800)),
        ),
      );
    }

    return SizedBox(
      height: 230,
      width: double.infinity,
      child: YoutubePlayer(
        controller: _controller!,
        showVideoProgressIndicator: true,
        progressIndicatorColor: const Color(0xFFFFB800),
        progressColors: const ProgressBarColors(
          playedColor: Color(0xFFFFB800),
          handleColor: Color(0xFFFFB800),
        ),
      ),
    );
  }
}