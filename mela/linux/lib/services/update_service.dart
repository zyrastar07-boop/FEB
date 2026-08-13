import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
// Note: Use package_info_plus to get current app version dynamically

class ReleaseAsset {
  final String name;
  final String browserDownloadUrl;
  final int size;
  final String contentType;

  ReleaseAsset.fromJson(Map<String, dynamic> json)
      : name = json['name'],
        browserDownloadUrl = json['browser_download_url'],
        size = json['size'] ?? 0,
        contentType = json['content_type'] ?? '';
}

class GitHubRelease {
  final String tagName;
  final String name;
  final String body;
  final String publishedAt;
  final String htmlUrl;
  final List<ReleaseAsset> assets;
  final bool prerelease;
  final bool draft;

  GitHubRelease.fromJson(Map<String, dynamic> json)
      : tagName = json['tag_name'],
        name = json['name'] ?? '',
        body = json['body'] ?? '',
        publishedAt = json['published_at'] ?? '',
        htmlUrl = json['html_url'] ?? '',
        assets = (json['assets'] as List? ?? [])
            .map((a) => ReleaseAsset.fromJson(a))
            .toList(),
        prerelease = json['prerelease'] ?? false,
        draft = json['draft'] ?? false;
}

class UpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String releaseName;
  final String releaseDate;
  final String? downloadUrl;
  final String releaseUrl;
  final int? assetSize;

  UpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.releaseName,
    required this.releaseDate,
    required this.downloadUrl,
    required this.releaseUrl,
    required this.assetSize,
  });
}

class UpdateService {
  final String owner;
  final String repo;
  final String currentVersion;

  UpdateService({
    required this.owner,
    required this.repo,
    required this.currentVersion,
  });

  int _parseVersion(String version) {
    final clean = version.replaceAll(RegExp(r'^v'), '').split('-')[0];
    final parts = clean.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts[0] * 1_000_000 + parts[1] * 1_000 + parts[2];
  }

  int compareVersions(String a, String b) {
    final pa = _parseVersion(a);
    final pb = _parseVersion(b);
    if (pa > pb) return 1;
    if (pa < pb) return -1;
    return 0;
  }

  ReleaseAsset? _findApkAsset(List<ReleaseAsset> assets) {
    return assets.cast<ReleaseAsset?>().firstWhere(
          (a) =>
              a != null &&
              a.name.endsWith('.apk') &&
              (a.name.contains('release') ||
                  a.name.contains('universal') ||
                  !a.name.contains('debug')),
          orElse: () => assets.cast<ReleaseAsset?>().firstWhere(
                (a) => a != null && a.name.endsWith('.apk'),
                orElse: () => null,
              ),
        );
  }

  Future<GitHubRelease?> getLatestRelease() async {
    final url = Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest');
    try {
      final res = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'Flutter-App',
      });
      if (res.statusCode != 200) return null;
      return GitHubRelease.fromJson(jsonDecode(res.body));
    } catch (e) {
      return null;
    }
  }

  Future<UpdateInfo> checkForUpdates() async {
    final latestRelease = await getLatestRelease();
    if (latestRelease == null) {
      return UpdateInfo(
        hasUpdate: false,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        releaseNotes: '',
        releaseName: '',
        releaseDate: '',
        downloadUrl: null,
        releaseUrl: '',
        assetSize: null,
      );
    }

    final latestVersion = latestRelease.tagName.replaceAll(RegExp(r'^v'), '');
    final hasUpdate = compareVersions(latestVersion, currentVersion) > 0;

    String? downloadUrl;
    int? assetSize;
    if (Platform.isAndroid) {
      final apk = _findApkAsset(latestRelease.assets);
      if (apk != null) {
        downloadUrl = apk.browserDownloadUrl;
        assetSize = apk.size;
      }
    }

    return UpdateInfo(
      hasUpdate: hasUpdate,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseNotes: latestRelease.body,
      releaseName: latestRelease.name,
      releaseDate: latestRelease.publishedAt,
      downloadUrl: downloadUrl,
      releaseUrl: latestRelease.htmlUrl,
      assetSize: assetSize,
    );
  }
}