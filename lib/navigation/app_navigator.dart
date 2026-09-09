import 'package:flutter/material.dart';
import '../models/movie.dart';
import '../screens/detail_screen.dart';
import '../screens/actor_detail_screen.dart';
import '../design/motion.dart';

/// Shared navigation helpers to avoid circular imports between
/// detail_screen.dart and actor_detail_screen.dart.
class AppNavigator {
  AppNavigator._();

  static Future<void> openActor(BuildContext context, int actorId) {
    return Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: AppMotion.scaled(context, AppMotion.medium),
        pageBuilder: (_, _, _) => ActorDetailScreen(actorId: actorId),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
      ),
    );
  }

  static Future<void> openDetail(
    BuildContext context,
    Movie movie, {
    bool isTv = false,
  }) {
    return Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: AppMotion.scaled(context, AppMotion.medium),
        pageBuilder: (_, _, _) => DetailScreen(movie: movie, isTv: isTv),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
      ),
    );
  }
}