import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows download progress in the system notification shade.
class DownloadNotifier {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'flick-downloads';
  static const String channelName = 'Downloads';
  static const String alertChannelId = 'flick-alerts';

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);
 
    // Android 13+ runtime notification permission
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestNotificationsPermission();

      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: 'Active media downloads',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );

      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          alertChannelId,
          'Download Alerts',
          description: 'Completed / failed downloads',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    _initialized = true;
    debugPrint('[DownloadNotifier] initialized');
  }

  /// Ongoing progress notification (updates in place while downloading).
  static Future<void> showProgress({
    required String jobId,
    required String title,
    required String qualityLabel,
    required int progress,
    required bool isActive,
    String? bodyText,
  }) async {
    if (!_initialized) await initialize();

    final clamped = progress.clamp(0, 100);

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Active media downloads',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: isActive,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: clamped,
      indeterminate: clamped == 0 && isActive,
      autoCancel: !isActive,
      category: AndroidNotificationCategory.progress,
      visibility: NotificationVisibility.public,
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      await _notifications.show(
        jobId.hashCode & 0x7FFFFFFF, // keep positive 32-bit id
        '$title — $qualityLabel',
        bodyText ?? (isActive ? '$clamped%' : 'Paused · $clamped%'),
        details,
      );
    } catch (e) {
      debugPrint('[DownloadNotifier] showProgress error: $e');
    }
  }

  static Future<void> showCompleted({
    required String jobId,
    required String title,
    required String qualityLabel,
  }) async {
    if (!_initialized) await initialize();
    await cancel(jobId);

    const androidDetails = AndroidNotificationDetails(
      alertChannelId,
      'Download Alerts',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
    );

    try {
      await _notifications.show(
        (jobId.hashCode + 999) & 0x7FFFFFFF,
        'Download Complete',
        '$title ($qualityLabel) is ready to watch offline.',
        const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('[DownloadNotifier] showCompleted error: $e');
    }
  }

  static Future<void> showFailed({
    required String jobId,
    required String title,
    String? reason,
  }) async {
    if (!_initialized) await initialize();
    await cancel(jobId);

    const androidDetails = AndroidNotificationDetails(
      alertChannelId,
      'Download Alerts',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    try {
      await _notifications.show(
        (jobId.hashCode + 998) & 0x7FFFFFFF,
        'Download Failed',
        reason ?? 'Could not download "$title". Tap to retry.',
        const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('[DownloadNotifier] showFailed error: $e');
    }
  }

  static Future<void> cancel(String jobId) async {
    try {
      await _notifications.cancel(jobId.hashCode & 0x7FFFFFFF);
    } catch (_) {}
  }
}