import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/service_locator.dart';
import '../theme/app_theme.dart';
import '../services/background_download_service.dart';
import '../services/bilibili_auth_service.dart';
import '../managers/download_manager.dart';
import '../config/app_release.dart';
import 'bilibili_login_page.dart';
import 'rss_inbox_page.dart';
import '../providers/settings_provider.dart';
import '../services/app_update_service.dart';
import '../services/bangumi_auth_gateway_service.dart';
import '../services/bangumi_oauth_service.dart';
import '../widgets/rss_sources_card.dart';
import '../utils/haptic_helper.dart';
import '../utils/image_request.dart';
import 'about_page.dart';
import 'dandanplay_discovery_page.dart';

enum SettingsSection {
  appearance('外观与操作', Icons.palette_outlined),
  playback('播放与弹幕', Icons.play_circle_outline),
  download('下载与后台', Icons.download_outlined),
  accounts('账号与同步', Icons.person_outline),
  feeds('资源订阅', Icons.rss_feed),
  about('关于与更新', Icons.info_outline);

  const SettingsSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.section});
  final SettingsSection? section;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController dandanAppIdController = TextEditingController();
  final TextEditingController dandanAppSecretController =
      TextEditingController();

  bool autoCheckUpdates = true;
  bool enablePictureInPicture = false;
  String resumePlaybackBehavior = 'ask';
  bool autoPlayNextEpisode = false;
  bool isSaving = false;
  bool isAuthorizingBangumi = false;
  bool isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    if (widget.section == null || widget.section == SettingsSection.accounts) {
      unawaited(BilibiliAuthService.instance.initialize().catchError((_) {}));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncControllers(context.read<SettingsProvider>());
    });
  }

  @override
  void dispose() {
    dandanAppIdController.dispose();
    dandanAppSecretController.dispose();
    super.dispose();
  }

  void _syncControllers(SettingsProvider provider) {
    dandanAppIdController.text = provider.customDandanplayAppId;
    dandanAppSecretController.text = provider.customDandanplayAppSecret;

    if (mounted) {
      setState(() {
        autoCheckUpdates = provider.autoCheckUpdates;
        enablePictureInPicture = provider.enablePictureInPicture;
        resumePlaybackBehavior = provider.resumePlaybackBehavior;
        autoPlayNextEpisode = provider.autoPlayNextEpisode;
      });
    }
  }

  String _resumeBehaviorLabel(String behavior) {
    return switch (behavior) {
      'auto' => '自动续播',
      'never' => '始终从头播放',
      _ => '播放前询问',
    };
  }

  Future<void> _showResumeBehaviorSheet() async {
    final String? selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        final ColorScheme colors = theme.colorScheme;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '继续播放',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '打开视频时如何处理上次的观看进度',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                _ThemeModeOption(
                  icon: Icons.help_outline_rounded,
                  title: '播放前询问',
                  subtitle: '每次打开视频都询问是否从上次位置继续',
                  selected: resumePlaybackBehavior == 'ask',
                  onTap: () => Navigator.pop(sheetContext, 'ask'),
                ),
                const SizedBox(height: 10),
                _ThemeModeOption(
                  icon: Icons.skip_next_rounded,
                  title: '自动续播',
                  subtitle: '自动从上一次的观看进度继续播放',
                  selected: resumePlaybackBehavior == 'auto',
                  onTap: () => Navigator.pop(sheetContext, 'auto'),
                ),
                const SizedBox(height: 10),
                _ThemeModeOption(
                  icon: Icons.replay_rounded,
                  title: '始终从头播放',
                  subtitle: '每次打开视频都从头开始，不记忆进度',
                  selected: resumePlaybackBehavior == 'never',
                  onTap: () => Navigator.pop(sheetContext, 'never'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null || selected == resumePlaybackBehavior) {
      return;
    }
    setState(() => resumePlaybackBehavior = selected);
    unawaited(
      context.read<SettingsProvider>().updatePlaybackOptions(
        enablePictureInPicture: enablePictureInPicture,
        resumePlaybackBehavior: selected,
      ),
    );
  }

  Future<void> _pickAndCropImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile == null) {
      return;
    }

    final CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 9, ratioY: 16),
      uiSettings: <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle: '裁剪首页背景',
          toolbarColor: Colors.blueGrey.shade700,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
        ),
        IOSUiSettings(title: '裁剪首页背景', aspectRatioLockEnabled: true),
      ],
    );

    if (croppedFile == null || !mounted) {
      return;
    }

    if (!mounted) return;
    await _write(
      context.read<SettingsProvider>().setHomeBackground(croppedFile.path),
    );
  }

  Future<void> _write(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设置未保存，请重试。')));
      }
    }
  }

  Future<void> _saveSettings() async {
    if (isSaving) return;
    setState(() => isSaving = true);
    try {
      await context.read<SettingsProvider>().updateDandanplayCredentials(
        dandanAppIdController.text,
        dandanAppSecretController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('自定义接入已保存。')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> _checkForUpdates() async {
    if (isCheckingUpdate) {
      return;
    }

    setState(() {
      isCheckingUpdate = true;
    });

    final SettingsProvider provider = context.read<SettingsProvider>();
    final AppUpdateService updateService = ServiceLocator.appUpdateService;
    final AppUpdateCheckResult result = await updateService.checkForUpdates(
      provider.appUpdateFeedUrl,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      isCheckingUpdate = false;
    });
    await updateService.showUpdateDialog(context, result);
  }

  Future<void> _startBangumiOAuthLogin() async {
    final SettingsProvider provider = context.read<SettingsProvider>();
    final String gatewayUrl = provider.bgmAuthGatewayUrl.trim();
    if (gatewayUrl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('登录服务暂不可用，请稍后再试。')));
      return;
    }

    setState(() {
      isAuthorizingBangumi = true;
    });

    try {
      final BangumiAuthGatewayService gateway = BangumiAuthGatewayService(
        baseUrl: gatewayUrl,
      );
      final proof = BangumiLoginProof();
      final start = await gateway.startAuthorization(
        proof: proof,
        callbackScheme: BangumiOAuthService.callbackScheme,
      );
      final String callback = await FlutterWebAuth2.authenticate(
        url: start.authorizationUrl,
        callbackUrlScheme: BangumiOAuthService.callbackScheme,
      );
      final Uri callbackUri = Uri.parse(callback);
      final String sessionId =
          callbackUri.queryParameters['session_id']?.trim() ?? '';
      final String callbackRequestId =
          callbackUri.queryParameters['request_id']?.trim() ?? '';

      if (callbackUri.scheme != BangumiOAuthService.callbackScheme ||
          callbackUri.host != 'callback' ||
          sessionId.isEmpty ||
          callbackRequestId.isEmpty ||
          callbackRequestId != start.requestId) {
        throw Exception('授权回调缺少会话信息。');
      }

      final session = await gateway.fetchSession(sessionId, proof: proof);
      await provider.bindBangumiGatewaySession(session, gatewayUrl: gatewayUrl);
      _syncControllers(provider);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bangumi 登录成功：${provider.bangumiDisplayName.isNotEmpty ? provider.bangumiDisplayName : provider.bgmAcc}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bangumi 登录失败：${_formatBangumiLoginError(error, gatewayUrl)}',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isAuthorizingBangumi = false;
        });
      }
    }
  }

  String _formatBangumiLoginError(Object error, String gatewayUrl) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.connectionError) {
        final String healthUrl =
            '${gatewayUrl.trim().replaceAll(RegExp(r'/+$'), '')}/health';
        return '无法连接登录服务。请先用手机浏览器打开 $healthUrl 测试网络；如果打不开，请切换网络。';
      }
      final int? statusCode = error.response?.statusCode;
      if (statusCode != null) {
        return '登录服务返回异常状态码：$statusCode';
      }
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _clearBangumiAuthorization() async {
    await context.read<SettingsProvider>().clearBangumiAuthorization();

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Bangumi 授权已清除。')));
  }

  @override
  Widget build(BuildContext context) {
    final SettingsProvider provider = context.watch<SettingsProvider>();
    if (!provider.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final section = widget.section;
    final auth = BilibiliAuthService.instance;
    final downloads = DownloadManager();
    final palette = AppPalette.parse(provider.palette);
    final modeLabel = switch (provider.themeMode) {
      'Light' => '浅色',
      'Dark' => '深色',
      _ => '跟随系统',
    };
    final rows = <Widget>[];
    switch (section) {
      case null:
        return Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: ListenableBuilder(
            listenable: Listenable.merge([downloads, auth]),
            builder: (context, _) => ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final item in SettingsSection.values)
                  ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.label),
                    subtitle: Text(switch (item) {
                      SettingsSection.appearance =>
                        '${palette.label} · $modeLabel',
                      SettingsSection.playback => _resumeBehaviorLabel(
                        provider.resumePlaybackBehavior,
                      ),
                      SettingsSection.download =>
                        downloads.seedingEnabled ? '空闲时做种' : '完成后停止做种',
                      SettingsSection.accounts =>
                        'Bangumi ${provider.isBangumiAuthorized ? "已登录" : "未登录"} · B站 ${auth.account != null ? "已登录" : "未登录"}',
                      SettingsSection.feeds =>
                        '已启用 ${provider.rssSources.where((s) => s['enabled'] != 'false').length} 个来源',
                      SettingsSection.about => AppRelease.version,
                    }),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsPage(section: item),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      case SettingsSection.appearance:
        rows.add(_appearance(provider));
        break;
      case SettingsSection.playback:
        rows.addAll([_buildPlaybackCard(), _buildDandanplayCard(provider)]);
        break;
      case SettingsSection.accounts:
        rows.addAll([
          _buildBangumiCard(provider),
          ListenableBuilder(
            listenable: auth,
            builder: (_, _) => ListTile(
              title: const Text('B站账号'),
              subtitle: Text(auth.account?.name ?? '未登录'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BilibiliLoginPage(auth: auth),
                ),
              ),
            ),
          ),
        ]);
        break;
      case SettingsSection.download:
        rows.addAll([
          ListenableBuilder(
            listenable: downloads,
            builder: (_, _) => SwitchListTile(
              title: const Text('空闲时做种'),
              subtitle: const Text('仅适用于 BT 下载'),
              value: downloads.seedingEnabled,
              onChanged: (v) => _write(downloads.setSeedingEnabled(v)),
            ),
          ),
          if (Platform.isAndroid)
            const ListTile(
              title: Text('后台运行与通知'),
              subtitle: Text('打开系统应用设置，管理通知和电池用量。'),
              onTap: BackgroundDownloadService.openSettings,
            ),
        ]);
        break;
      case SettingsSection.feeds:
        rows.addAll([
          _buildRssCard(provider),
          ListTile(
            title: const Text('订阅收件箱'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RssInboxPage()),
            ),
          ),
        ]);
        break;
      case SettingsSection.about:
        rows.addAll([_buildUpdateCard(), _buildAboutCard(provider)]);
        break;
    }
    return Scaffold(
      appBar: AppBar(title: Text(section.label)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            for (final row in rows)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: row),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard(SettingsProvider provider) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: const Icon(Icons.info_outline),
        title: const Text('关于 AnimeMaster'),
        subtitle: Text(provider.coreEngineVersion),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const AboutPage()),
          );
        },
      ),
    );
  }

  Widget _buildBangumiCard(SettingsProvider provider) {
    final DateTime? expiresAt = provider.bgmTokenExpiresAt;
    final String status = provider.isBangumiAuthorized
        ? '已登录${expiresAt != null ? '，授权有效期至 ${_formatLocalDateTime(expiresAt)}' : ''}'
        : '未登录';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.account_circle_outlined),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Bangumi 账号',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: provider.isBangumiAuthorized
                              ? AppTheme.success(context)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (provider.hasBangumiProfile) ...<Widget>[
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: provider.bgmAvatarUrl.trim().isNotEmpty
                        ? NetworkImage(
                            normalizeImageUrl(provider.bgmAvatarUrl),
                            headers: buildImageHeaders(provider.bgmAvatarUrl),
                          )
                        : null,
                    child: provider.bgmAvatarUrl.trim().isEmpty
                        ? const Icon(Icons.person_rounded)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          provider.bangumiDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (provider.bgmAcc.trim().isNotEmpty)
                          Text(
                            '@${provider.bgmAcc}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        if (provider.bgmBio.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              provider.bgmBio,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: provider.isBangumiAuthorized
                        ? () async {
                            await provider.refreshBangumiProfile();
                            if (mounted) {
                              _syncControllers(provider);
                            }
                          }
                        : null,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: '刷新资料',
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isAuthorizingBangumi
                        ? null
                        : _startBangumiOAuthLogin,
                    icon: isAuthorizingBangumi
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login_rounded),
                    label: Text(isAuthorizingBangumi ? '授权中...' : '网页登录'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: provider.isBangumiAuthorized
                      ? _clearBangumiAuthorization
                      : null,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('退出'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatLocalDateTime(DateTime value) {
    final DateTime local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  Widget _appearance(SettingsProvider p) {
    final theme = Theme.of(context);
    final bg = p.customBgPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('明暗模式', style: theme.textTheme.titleMedium),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in const {
              'System': '跟随系统',
              'Light': '浅色',
              'Dark': '深色',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: p.themeMode == entry.key,
                onSelected: (_) => _write(p.setDisplayMode(entry.key)),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text('主题配色', style: theme.textTheme.titleMedium),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final option in AppPalette.values)
              ChoiceChip(
                avatar: _PaletteSample(
                  theme.brightness == Brightness.dark
                      ? option.night
                      : option.day,
                ),
                label: Text(option.label),
                selected: AppPalette.parse(p.palette) == option,
                onSelected: (_) => _write(p.setPalette(option.name)),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text('作品标题', style: theme.textTheme.titleMedium),
        Wrap(
          spacing: 8,
          children: [
            for (final serif in [false, true])
              ChoiceChip(
                label: Text(serif ? '宋体标题' : '系统字体'),
                selected: p.serifTitles == serif,
                onSelected: (_) => _write(p.setSerifTitles(serif)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('海边来信', style: theme.textTheme.headlineLarge),
                const SizedBox(height: 4),
                const Text('第 06 话 · 夏日终点'),
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    child: Text(
                      '继续看第 6 集',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('首页背景'),
          subtitle: Text(bg.isEmpty ? '纯色' : '自定义图片'),
          onTap: _pickAndCropImage,
          leading: bg.isEmpty
              ? null
              : Image.file(
                  File(bg),
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined),
                ),
          trailing: bg.isEmpty
              ? const Icon(Icons.image_outlined)
              : IconButton(
                  tooltip: '恢复纯色背景',
                  icon: const Icon(Icons.close),
                  onPressed: () => _write(p.setHomeBackground('')),
                ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('操作触感'),
          value: p.enableHapticFeedback,
          onChanged: (value) async {
            await _write(p.updateHapticFeedback(value));
            HapticNavigatorObserver.syncFromSettings(p.enableHapticFeedback);
            if (p.enableHapticFeedback) quickHaptic();
          },
        ),
      ],
    );
  }

  Widget _buildPlaybackCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '播放体验',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('离开播放页自动小窗'),
              subtitle: const Text('开启后，在 Android 支持的设备上按主页键会进入画中画播放。'),
              value: enablePictureInPicture,
              onChanged: (bool value) {
                setState(() {
                  enablePictureInPicture = value;
                });
                unawaited(
                  context.read<SettingsProvider>().updatePlaybackOptions(
                    enablePictureInPicture: value,
                  ),
                );
              },
            ),
            const Divider(height: 18),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showResumeBehaviorSheet,
                borderRadius: BorderRadius.circular(18),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? 0.48
                              : 0.7,
                        ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      const _SettingsIconBadge(
                        icon: Icons.replay_rounded,
                        compact: true,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              '继续播放',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _resumeBehaviorLabel(resumePlaybackBehavior),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动播放下一集'),
              subtitle: const Text('接近片尾或播放结束后显示倒计时，可手动取消。'),
              value: autoPlayNextEpisode,
              onChanged: (bool value) {
                setState(() {
                  autoPlayNextEpisode = value;
                });
                unawaited(
                  context.read<SettingsProvider>().updatePlaybackOptions(
                    enablePictureInPicture: enablePictureInPicture,
                    autoPlayNextEpisode: value,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDandanplayCard(SettingsProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '弹弹play 弹幕',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              '已内置弹弹play 接入，无需填写密钥。支持自动识别、手动匹配和弹幕缓存；服务不可用时尝试备用弹幕源。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.local_fire_department_outlined),
              title: const Text('热播与新番'),
              subtitle: const Text('热播榜、飙升榜与新番列表'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DandanplayDiscoveryPage(),
                ),
              ),
            ),
            const Text(
              '播放匹配成功后可发送弹幕。当前发送额度由全应用共享：每日 10 条、每月 240 条。弹弹play 账号同步暂未开放。',
              style: TextStyle(fontSize: 12),
            ),
            ExpansionTile(
              title: const Text('自定义接入（可选）'),
              subtitle: const Text('仅供拥有个人应用凭据的用户使用'),
              children: [
                TextField(
                  controller: dandanAppIdController,
                  decoration: const InputDecoration(labelText: 'AppId'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dandanAppSecretController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'AppSecret'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: isSaving ? null : _saveSettings,
                    icon: isSaving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(isSaving ? '保存中…' : '保存自定义接入'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRssCard(SettingsProvider provider) => const RssSourcesCard();

  Widget _buildUpdateCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '应用更新',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启动时检查更新'),
              subtitle: const Text('开启后，应用启动时会自动读取内置更新清单。'),
              value: autoCheckUpdates,
              onChanged: (bool value) {
                setState(() => autoCheckUpdates = value);
                unawaited(
                  context.read<SettingsProvider>().updateDistribution(value),
                );
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isCheckingUpdate ? null : _checkForUpdates,
                icon: isCheckingUpdate
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt_rounded),
                label: Text(isCheckingUpdate ? '检查中...' : '检查更新'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: 0.12)
                : colors.surfaceContainerHighest.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.44 : 0.66,
                  ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
            ),
          ),
          child: Row(
            children: <Widget>[
              _SettingsIconBadge(icon: icon, compact: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedScale(
                scale: selected ? 1 : 0.78,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? colors.primary : colors.outlineVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsIconBadge extends StatelessWidget {
  final IconData icon;
  final bool compact;

  const _SettingsIconBadge({required this.icon, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final double size = compact ? 32 : 42;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
      ),
      child: Icon(icon, color: colors.primary, size: compact ? 18 : 22),
    );
  }
}

class _PaletteSample extends StatelessWidget {
  const _PaletteSample(this.tones);
  final ThemeTones tones;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: Row(
      children: [
        for (final color in [tones.background, tones.surface, tones.primary])
          Expanded(
            child: ColoredBox(
              color: Color(color),
              child: const SizedBox.expand(),
            ),
          ),
      ],
    ),
  );
}
