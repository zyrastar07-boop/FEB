import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// System notifications for download progress / completion.
/// Compatible with flutter_local_notifications v17+ (named parameters).
class DownloadNotifier {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'downloads',
    'Downloads',
    description: 'Movie & episode download progress',
    importance: Importance.low,
    showBadge: false,
  );

  static Future<void> initialize() async {
    if (_ready) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    // v17+ : named parameter `settings`
    await _plugin.initialize(settings: initSettings);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    await android?.requestNotificationsPermission();

    _ready = true;
    if (kDebugMode) print('DownloadNotifier initialized');
  }

  static int _notifId(String jobId) => jobId.hashCode & 0x7fffffff;

  static void showProgress({
    required String jobId,
    required String title,
    required String qualityLabel,
    required int progress,
    required bool isActive,
    String? bodyText,
  }) {
    if (!_ready) {
      if (kDebugMode) {
        print(
          'Download [$jobId] $title ($qualityLabel): $progress% - ${bodyText ?? (isActive ? "Downloading" : "Paused")}',
        );
      }
      return;
    }

    final body = bodyText ??
        (isActive
            ? 'Downloading $qualityLabel · $progress%'
            : 'Paused · $progress%');

    // v17+ : all named parameters
    _plugin.show(
      id: _notifId(jobId),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          showProgress: true,
          maxProgress: 100,
          progress: progress.clamp(0, 100),
          ongoing: isActive,
          autoCancel: !isActive,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: false,
          presentSound: false,
        ),
      ),
    );
  }

  static Future<void> showCompleted({
    required String jobId,
    required String title,
    required String qualityLabel,
  }) async {
    if (!_ready) {
      if (kDebugMode) print('Download Completed: $title ($qualityLabel)');
      return;
    }

    await _plugin.show(
      id: _notifId(jobId),
      title: 'Download complete',
      body: '$title · $qualityLabel is ready offline',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          onlyAlertOnce: true,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  static void cancel(String jobId) {
    if (_ready) {
      // v17+ : named parameter `id`
      _plugin.cancel(id: _notifId(jobId));
    } else if (kDebugMode) {
      print('Download Cancelled: $jobId');
    }
  }
}