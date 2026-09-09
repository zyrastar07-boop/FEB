import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local progress notifications for the download pipeline.
///
/// The download service calls [showProgress] every ~250ms while transferring;
/// Android coalesces the updates into a single ongoing notification per
/// jobId. Every method is fire-and-forget safe: any platform error is
/// swallowed (and logged) so a notification failure can never break or
/// stall an actual download.
class DownloadNotifier {
  DownloadNotifier._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static const String _channelId = 'downloads';
  static const String _channelName = 'Downloads';
  static const String _channelDescription = 'Video download progress';

  /// Must be awaited once during app bootstrap (main.dart splash init).
  /// Safe to call multiple times — only the first call has an effect.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );
      _initialized = ok ?? true;
    } catch (e) {
      debugPrint('DownloadNotifier init failed: $e');
    }
  }

  /// Stable per-job notification id (hash keeps ids within int32).
  static int _idFor(String jobId) => jobId.hashCode & 0x7fffffff;

  /// Show or update the progress notification for [jobId].
  ///
  /// [progress] is 0–100. When [isActive] is false the notification is
  /// rendered as non-ongoing (used for the Paused state).
  static Future<void> showProgress({
    required String jobId,
    required String title,
    required String qualityLabel,
    required int progress,
    required bool isActive,
    String? bodyText,
  }) async {
    if (!_initialized) return;
    try {
      final android = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true,
        ongoing: isActive,
        showProgress: true,
        maxProgress: 100,
        progress: progress.clamp(0, 100),
        indeterminate: false,
      );
      const darwin = DarwinNotificationDetails(
        presentAlert: false,
        presentSound: false,
      );
      await _plugin.show(
        id: _idFor(jobId),
        title: qualityLabel.isEmpty ? title : '$title ($qualityLabel)',
        body: bodyText,
        notificationDetails: NotificationDetails(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );
    } catch (e) {
      debugPrint('DownloadNotifier.showProgress failed: $e');
    }
  }

  /// Final notification for a finished download (dismissable, progress 100).
  static Future<void> showCompleted({
    required String jobId,
    required String title,
    required String qualityLabel,
  }) async {
    if (!_initialized) return;
    try {
      final android = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ongoing: false,
        autoCancel: true,
        showProgress: true,
        maxProgress: 100,
        progress: 100,
        indeterminate: false,
      );
      const darwin = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: false,
      );
      await _plugin.show(
        id: _idFor(jobId),
        title: qualityLabel.isEmpty ? title : '$title ($qualityLabel)',
        body: 'Download complete',
        notificationDetails: NotificationDetails(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );
    } catch (e) {
      debugPrint('DownloadNotifier.showCompleted failed: $e');
    }
  }

  /// Remove the notification for [jobId] (used on cancel / delete).
  static Future<void> cancel(String jobId) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _idFor(jobId));
    } catch (e) {
      debugPrint('DownloadNotifier.cancel failed: $e');
    }
  }
}
