import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/dio_client.dart';
import '../models/app_update_info.dart';

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
        message: '尚未配置更新清单地址。',
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
          message: '更新清单缺少 version 或 apkUrl 字段。',
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
        message: updateAvailable ? '发现新版本。' : '当前已经是最新版本。',
      );
    } catch (error) {
      return AppUpdateCheckResult(
        packageInfo: packageInfo,
        latest: null,
        updateAvailable: false,
        message: '检查更新失败：$error',
      );
    }
  }

  Future<bool> openDownloadUrl(AppUpdateInfo updateInfo) async {
    final Uri? uri = Uri.tryParse(updateInfo.apkUrl);
    if (uri == null) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
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
          title: const Text('应用更新'),
          content: Text(result.message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('确定'),
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
        title: const Text('发现新版本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '当前版本：${result.packageInfo.version} (${result.packageInfo.buildNumber})',
            ),
            const SizedBox(height: 6),
            Text('最新版本：${latest.version} (${latest.buildNumber})'),
            if (latest.publishedAt.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text('发布时间：${latest.publishedAt}'),
            ],
            if (latest.changeLog.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const Text('更新内容', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(latest.changeLog),
            ],
            const SizedBox(height: 12),
            const Text(
              '说明：Android 普通应用无法静默强制安装更新，系统会跳转到下载或安装流程，由用户确认覆盖安装。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('稍后'),
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
                ).showSnackBar(const SnackBar(content: Text('无法打开下载地址。')));
              }
            },
            child: const Text('下载更新'),
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
