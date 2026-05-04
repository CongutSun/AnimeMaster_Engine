import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/dio_client.dart';
import '../models/app_update_info.dart';
import '../utils/app_strings.dart';

class AppUpdateCheckResult {
  final PackageInfo packageInfo;
  final AppUpdateInfo? latest;
  final bool updateAvailable;
  final String message;

  const AppUpdateCheckResult({
    required this.packageInfo,
    required this.latest,
    required this.updateAvailable,
    required this.message,
  });
}

class AppUpdateService {
  const AppUpdateService();

  Future<AppUpdateCheckResult> checkForUpdates(String manifestUrl) async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final String normalizedUrl = manifestUrl.trim();

    if (normalizedUrl.isEmpty) {
      return AppUpdateCheckResult(
        packageInfo: packageInfo,
        latest: null,
        updateAvailable: false,
        message: AppStrings.updateManifestEmpty,
      );
    }

    try {
      final response = await DioClient().dio.get<dynamic>(normalizedUrl);
      final dynamic data = response.data;
      final Map<String, dynamic> json = data is String
          ? Map<String, dynamic>.from(jsonDecode(data) as Map)
          : Map<String, dynamic>.from(data as Map);
      final AppUpdateInfo latest = AppUpdateInfo.fromJson(json);

      if (latest.version.isEmpty || latest.apkUrl.isEmpty) {
        return AppUpdateCheckResult(
          packageInfo: packageInfo,
          latest: null,
          updateAvailable: false,
          message: AppStrings.updateManifestInvalid,
        );
      }

      final bool updateAvailable = _isRemoteNewer(
        localVersion: packageInfo.version,
        localBuild: int.tryParse(packageInfo.buildNumber) ?? 0,
        remoteVersion: latest.version,
        remoteBuild: latest.buildNumber,
      );

      return AppUpdateCheckResult(
        packageInfo: packageInfo,
        latest: latest,
        updateAvailable: updateAvailable,
        message: updateAvailable ? AppStrings.updateAvailable : AppStrings.updateUpToDate,
      );
    } catch (error) {
      debugPrint('[AppUpdateService] checkForUpdates failed: $error');
      return AppUpdateCheckResult(
        packageInfo: packageInfo,
        latest: null,
        updateAvailable: false,
        message: AppStrings.updateCheckFailed,
      );
    }
  }

  Future<bool> openDownloadUrl(AppUpdateInfo updateInfo) async {
    final Uri? uri = Uri.tryParse(_resolveDownloadUrl(updateInfo));
    if (uri == null) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _resolveDownloadUrl(AppUpdateInfo updateInfo) {
    final Map<String, String> urls = updateInfo.apkUrls;
    final String? abiUrl = urls[_currentAndroidAbiKey()];
    if (abiUrl != null && abiUrl.trim().isNotEmpty) {
      return abiUrl.trim();
    }
    final String? universalUrl = urls['universal'];
    if (universalUrl != null && universalUrl.trim().isNotEmpty) {
      return universalUrl.trim();
    }
    return updateInfo.apkUrl;
  }

  String? _resolveSha256(AppUpdateInfo updateInfo) {
    final Map<String, String> sha256s = updateInfo.sha256Map;
    final String? abiSha = sha256s[_currentAndroidAbiKey()];
    if (abiSha != null && abiSha.trim().isNotEmpty) {
      return abiSha.trim();
    }
    final String? universalSha = sha256s['universal'];
    if (universalSha != null && universalSha.trim().isNotEmpty) {
      return universalSha.trim();
    }
    return null;
  }

  String _currentAndroidAbiKey() {
    return switch (Abi.current()) {
      Abi.androidArm => 'android-arm',
      Abi.androidArm64 => 'android-arm64',
      Abi.androidX64 => 'android-x64',
      _ => 'universal',
    };
  }

  Future<void> showUpdateDialog(
    BuildContext context,
    AppUpdateCheckResult result, {
    bool quietIfUpToDate = false,
  }) async {
    if (!context.mounted) {
      return;
    }

    if (!result.updateAvailable || result.latest == null) {
      if (quietIfUpToDate) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text(AppStrings.updateDialogAppTitle),
          content: Text(result.message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(AppStrings.confirm),
            ),
          ],
        ),
      );
      return;
    }

    final AppUpdateInfo latest = result.latest!;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text(AppStrings.updateDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${AppStrings.updateDialogCurrent}：${result.packageInfo.version}'),
            const SizedBox(height: 6),
            Text('${AppStrings.updateDialogLatest}：${latest.version}'),
            if (latest.publishedAt.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text('${AppStrings.updateDialogPublished}：${latest.publishedAt}'),
            ],
            if (_resolveSha256(latest) case final String sha?) ...[
              const SizedBox(height: 12),
              const Text(AppStrings.updateDialogSha256, style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              SelectableText(
                sha,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ],
            if (latest.changeLog.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const Text(AppStrings.updateDialogChangelog, style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(latest.changeLog),
            ],
            const SizedBox(height: 12),
            const Text(
              AppStrings.updateDialogNote,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(AppStrings.updateDialogLater),
          ),
          FilledButton(
            onPressed: () async {
              final bool launched = await openDownloadUrl(latest);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              if (!launched && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text(AppStrings.cannotOpenDownloadUrl)));
              }
            },
            child: const Text(AppStrings.updateDialogDownload),
          ),
        ],
      ),
    );
  }

  bool _isRemoteNewer({
    required String localVersion,
    required int localBuild,
    required String remoteVersion,
    required int remoteBuild,
  }) {
    final int compare = _compareVersions(remoteVersion, localVersion);
    if (compare != 0) {
      return compare > 0;
    }
    return remoteBuild > localBuild;
  }

  int _compareVersions(String left, String right) {
    final List<int> leftParts = _parseVersion(left);
    final List<int> rightParts = _parseVersion(right);
    final int maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (int index = 0; index < maxLength; index++) {
      final int l = index < leftParts.length ? leftParts[index] : 0;
      final int r = index < rightParts.length ? rightParts[index] : 0;
      if (l != r) {
        return l.compareTo(r);
      }
    }
    return 0;
  }

  List<int> _parseVersion(String value) {
    return value
        .split('.')
        .map(
          (String part) =>
              int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        )
        .toList();
  }
}
