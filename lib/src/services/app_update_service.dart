import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
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

class AppUpdateInstallResult {
  final bool success;
  final String message;

  const AppUpdateInstallResult({required this.success, required this.message});
}

class AppUpdateService {
  const AppUpdateService();

  static const MethodChannel _installerChannel = MethodChannel(
    'com.animemaster.app/app_update',
  );
  static const int _maximumApkBytes = 300 * 1024 * 1024;

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
    final Uri? manifestUri = Uri.tryParse(normalizedUrl);
    if (!_isTrustedHttpsUri(manifestUri)) {
      return AppUpdateCheckResult(
        packageInfo: packageInfo,
        latest: null,
        updateAvailable: false,
        message: AppStrings.updateHttpsRequired,
      );
    }

    try {
      final response = await DioClient().dio.get<dynamic>(normalizedUrl);
      if (!_isTrustedHttpsUri(response.realUri)) {
        return AppUpdateCheckResult(
          packageInfo: packageInfo,
          latest: null,
          updateAvailable: false,
          message: AppStrings.updateHttpsRequired,
        );
      }
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

      final bool updateAvailable = debugIsRemoteNewer(
        localVersion: packageInfo.version,
        localBuild: int.tryParse(packageInfo.buildNumber) ?? 0,
        remoteVersion: latest.version,
        remoteBuild: latest.buildNumber,
      );

      return AppUpdateCheckResult(
        packageInfo: packageInfo,
        latest: latest,
        updateAvailable: updateAvailable,
        message: updateAvailable
            ? AppStrings.updateAvailable
            : AppStrings.updateUpToDate,
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
    final Uri? uri = Uri.tryParse(resolveDownloadUrl(updateInfo));
    if (!_isTrustedHttpsUri(uri)) {
      return false;
    }
    return launchUrl(uri!, mode: LaunchMode.externalApplication);
  }

  @visibleForTesting
  String resolveDownloadUrl(AppUpdateInfo updateInfo) {
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

  @visibleForTesting
  String? resolveSha256(AppUpdateInfo updateInfo) {
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

  Future<AppUpdateInstallResult> downloadAndInstall(
    AppUpdateInfo updateInfo,
  ) async {
    if (!Platform.isAndroid) {
      final bool launched = await openDownloadUrl(updateInfo);
      return AppUpdateInstallResult(
        success: launched,
        message: launched
            ? AppStrings.updateExternalDownloadOpened
            : AppStrings.cannotOpenDownloadUrl,
      );
    }

    final Uri? downloadUri = Uri.tryParse(resolveDownloadUrl(updateInfo));
    if (!_isTrustedHttpsUri(downloadUri)) {
      return const AppUpdateInstallResult(
        success: false,
        message: AppStrings.updateHttpsRequired,
      );
    }

    final String expectedSha256 =
        resolveSha256(updateInfo)?.toLowerCase() ?? '';
    if (!isValidSha256(expectedSha256)) {
      return const AppUpdateInstallResult(
        success: false,
        message: AppStrings.updateChecksumMissing,
      );
    }

    File? apkFile;
    bool rejectedForSize = false;
    try {
      final Directory cacheRoot = await getTemporaryDirectory();
      final Directory updateDirectory = Directory(
        '${cacheRoot.path}${Platform.pathSeparator}updates',
      );
      await updateDirectory.create(recursive: true);
      await _removeOldUpdateFiles(updateDirectory);

      final String safeVersion = updateInfo.version.replaceAll(
        RegExp(r'[^0-9A-Za-z._-]'),
        '_',
      );
      apkFile = File(
        '${updateDirectory.path}${Platform.pathSeparator}'
        'animemaster-$safeVersion-${updateInfo.buildNumber}.apk',
      );

      final CancelToken cancelToken = CancelToken();
      final Response<dynamic> response = await DioClient().dio.download(
        downloadUri!.toString(),
        apkFile.path,
        cancelToken: cancelToken,
        onReceiveProgress: (int received, int total) {
          if (received > _maximumApkBytes || total > _maximumApkBytes) {
            rejectedForSize = true;
            cancelToken.cancel('Update package exceeds the size limit.');
          }
        },
      );
      if (!_isTrustedHttpsUri(response.realUri)) {
        await apkFile.delete().catchError((_) => apkFile!);
        return const AppUpdateInstallResult(
          success: false,
          message: AppStrings.updateHttpsRequired,
        );
      }

      final int fileLength = await apkFile.length();
      if (fileLength <= 0 || fileLength > _maximumApkBytes) {
        await apkFile.delete();
        return const AppUpdateInstallResult(
          success: false,
          message: AppStrings.updatePackageInvalid,
        );
      }

      final Digest digest = await sha256.bind(apkFile.openRead()).first;
      if (digest.toString().toLowerCase() != expectedSha256) {
        await apkFile.delete();
        return const AppUpdateInstallResult(
          success: false,
          message: AppStrings.updateChecksumMismatch,
        );
      }

      await _installerChannel.invokeMethod<void>(
        'installUpdate',
        <String, Object>{
          'path': apkFile.path,
          'expectedVersionCode': updateInfo.buildNumber,
        },
      );
      return const AppUpdateInstallResult(
        success: true,
        message: AppStrings.updateInstallerOpened,
      );
    } on DioException catch (error) {
      debugPrint('[AppUpdateService] update download failed: ${error.type}');
      if (apkFile != null && await apkFile.exists()) {
        await apkFile.delete().catchError((_) => apkFile!);
      }
      return AppUpdateInstallResult(
        success: false,
        message: rejectedForSize
            ? AppStrings.updatePackageInvalid
            : AppStrings.updateDownloadFailed,
      );
    } on PlatformException catch (error) {
      debugPrint('[AppUpdateService] installer rejected update: ${error.code}');
      return AppUpdateInstallResult(
        success: false,
        message: error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : AppStrings.updatePackageInvalid,
      );
    } catch (error) {
      debugPrint('[AppUpdateService] secure update failed: $error');
      if (apkFile != null && await apkFile.exists()) {
        await apkFile.delete().catchError((_) => apkFile!);
      }
      return const AppUpdateInstallResult(
        success: false,
        message: AppStrings.updateDownloadFailed,
      );
    }
  }

  @visibleForTesting
  bool isValidSha256(String value) =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

  bool _isTrustedHttpsUri(Uri? uri) =>
      uri != null && uri.scheme.toLowerCase() == 'https' && uri.host.isNotEmpty;

  Future<void> _removeOldUpdateFiles(Directory directory) async {
    await for (final FileSystemEntity entity in directory.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
        await entity.delete();
      }
    }
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
            Text(
              '${AppStrings.updateDialogCurrent}：${result.packageInfo.version}',
            ),
            const SizedBox(height: 6),
            Text('${AppStrings.updateDialogLatest}：${latest.version}'),
            if (latest.publishedAt.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text('${AppStrings.updateDialogPublished}：${latest.publishedAt}'),
            ],
            if (resolveSha256(latest) case final String sha?) ...[
              const SizedBox(height: 12),
              const Text(
                AppStrings.updateDialogSha256,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              SelectableText(
                sha,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ],
            if (latest.changeLog.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const Text(
                AppStrings.updateDialogChangelog,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
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
              Navigator.pop(dialogContext);
              await _runSecureUpdateFlow(context, latest);
            },
            child: const Text(AppStrings.updateDialogDownload),
          ),
        ],
      ),
    );
  }

  Future<void> _runSecureUpdateFlow(
    BuildContext context,
    AppUpdateInfo updateInfo,
  ) async {
    if (!context.mounted) {
      return;
    }
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => const AlertDialog(
          content: Row(
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text(AppStrings.updateDownloadingAndVerifying)),
            ],
          ),
        ),
      ),
    );

    final AppUpdateInstallResult installResult = await downloadAndInstall(
      updateInfo,
    );
    if (!context.mounted) {
      return;
    }
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(installResult.message),
        backgroundColor: installResult.success ? null : Colors.redAccent,
      ),
    );
  }

  @visibleForTesting
  bool debugIsRemoteNewer({
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
              int.tryParse(RegExp(r'^\d+').firstMatch(part)?.group(0) ?? '') ??
              0,
        )
        .toList();
  }
}
