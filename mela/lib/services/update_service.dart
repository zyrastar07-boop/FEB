import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// Remote app update metadata.
class UpdateInfo {
  final String version;
  final String currentVersion;
  final String changelog;
  final String downloadUrl;
  final bool force;

  const UpdateInfo({
    required this.version,
    this.currentVersion = '',
    required this.changelog,
    required this.downloadUrl,
    this.force = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, {String localVersion = ''}) {
    return UpdateInfo(
      version: (json['version'] ?? json['latest_version'] ?? '').toString(),
      currentVersion: localVersion,
      changelog: (json['changelog'] ??
              json['notes'] ??
              'Bug fixes and improvements.')
          .toString(),
      downloadUrl: (json['download_url'] ?? json['url'] ?? '').toString(),
      force: json['force'] == true || json['force_update'] == true,
    );
  }
}

/// Connects application directly to GitHub Releases API.
class UpdateService {
  static const String fallbackAppVersion = '5.5.0';
  static const String githubOwner = 'zyrastar07-boop';
  static const String githubRepo = 'Mirav1';

  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      const current = fallbackAppVersion;

      final url = Uri.parse(
        'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest',
      );

      final res = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github+json',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;

      final remote = json.decode(res.body) as Map<String, dynamic>;

      final tagName = (remote['tag_name'] ?? '').toString().trim();
      if (tagName.isEmpty) return null;

      final latest = tagName.startsWith('v') ? tagName.substring(1) : tagName;

      final changelog = (remote['body'] ?? 'A new version is available.')
          .toString()
          .trim();

      String downloadUrl = '';
      final assets = remote['assets'] as List<dynamic>?;
      if (assets != null && assets.isNotEmpty) {
        final apkAsset = assets.firstWhere(
          (a) => (a['name'] ?? '').toString().endsWith('.apk'),
          orElse: () => assets.first,
        );
        downloadUrl = (apkAsset['browser_download_url'] ?? '').toString();
      }

      if (downloadUrl.isEmpty) {
        downloadUrl = (remote['html_url'] ?? '').toString();
      }

      final force = changelog.contains('[force_update]') ||
          tagName.contains('force');

      if (!_isNewer(latest, current) && !force) return null;
      if (downloadUrl.isEmpty) return null;

      return UpdateInfo(
        version: latest,
        currentVersion: current,
        changelog: changelog.replaceAll('[force_update]', '').trim(),
        downloadUrl: downloadUrl,
        force: force,
      );
    } catch (_) {
      return null;
    }
  }

  /// Downloads the APK directly to the device and launches the OS installer
  static Future<bool> downloadAndInstall({
    required String url,
    required Function(double progress) onProgress,
  }) async {
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);
      final contentLength = response.contentLength ?? 1;

      int downloaded = 0;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/update.apk');
      final sink = file.openWrite();

      await for (var chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        onProgress(downloaded / contentLength);
      }
      
      await sink.close();
      
      // Trigger the Android package installer
      final result = await OpenFilex.open(file.path);
      return result.type == ResultType.done;
    } catch (e) {
      return false;
    }
  }

  static bool _isNewer(String remote, String local) {
    List<int> parts(String v) => v
        .split(RegExp(r'[^0-9]+'))
        .where((s) => s.isNotEmpty)
        .map((s) => int.tryParse(s) ?? 0)
        .toList();

    final a = parts(remote);
    final b = parts(local);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x > y) return true;
      if (x < y) return false;
    }
    return false;
  }
}