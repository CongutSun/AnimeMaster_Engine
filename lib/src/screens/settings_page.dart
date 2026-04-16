import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/app_update_service.dart';
import '../services/bangumi_auth_gateway_service.dart';
import '../services/bangumi_oauth_service.dart';
import 'about_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController bgController = TextEditingController();
  final TextEditingController dandanAppIdController = TextEditingController();
  final TextEditingController dandanAppSecretController =
      TextEditingController();
  final TextEditingController rssNameController = TextEditingController();
  final TextEditingController rssUrlController = TextEditingController();

  String themeMode = 'Light';
  int selectedRssIndex = -1;
  bool autoCheckUpdates = true;
  bool isSaving = false;
  bool isAuthorizingBangumi = false;
  bool isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncControllers(context.read<SettingsProvider>());
    });
  }

  @override
  void dispose() {
    bgController.dispose();
    dandanAppIdController.dispose();
    dandanAppSecretController.dispose();
    rssNameController.dispose();
    rssUrlController.dispose();
    super.dispose();
  }

  void _syncControllers(SettingsProvider provider) {
    bgController.text = provider.customBgPath;
    dandanAppIdController.text = provider.dandanplayAppId;
    dandanAppSecretController.text = provider.dandanplayAppSecret;

    if (mounted) {
      setState(() {
        themeMode = provider.themeMode;
        autoCheckUpdates = provider.autoCheckUpdates;
      });
    }
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

    setState(() {
      bgController.text = croppedFile.path;
    });
  }

  Future<void> _saveSettings() async {
    if (isSaving) {
      return;
    }

    setState(() {
      isSaving = true;
    });

    final SettingsProvider provider = context.read<SettingsProvider>();
    await provider.updateDandanplayCredentials(
      dandanAppIdController.text,
      dandanAppSecretController.text,
    );
    await provider.updateAppearance(
      provider.closeAction,
      themeMode,
      bgController.text,
    );
    await provider.updateDistribution(autoCheckUpdates);

    if (!mounted) {
      return;
    }

    setState(() {
      isSaving = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('设置已保存。')));
  }

  Future<void> _checkForUpdates() async {
    if (isCheckingUpdate) {
      return;
    }

    setState(() {
      isCheckingUpdate = true;
    });

    final SettingsProvider provider = context.read<SettingsProvider>();
    final AppUpdateCheckResult result = await const AppUpdateService()
        .checkForUpdates(provider.appUpdateFeedUrl);

    if (!mounted) {
      return;
    }

    setState(() {
      isCheckingUpdate = false;
    });
    await const AppUpdateService().showUpdateDialog(context, result);
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
      final start = await gateway.startAuthorization(
        callbackScheme: BangumiOAuthService.callbackScheme,
      );
      final String callback = await FlutterWebAuth2.authenticate(
        url: start.authorizationUrl,
        callbackUrlScheme: BangumiOAuthService.callbackScheme,
      );
      final Uri callbackUri = Uri.parse(callback);
      final String sessionId =
          callbackUri.queryParameters['session_id']?.trim() ?? '';

      if (sessionId.isEmpty) {
        throw Exception('授权回调缺少会话信息。');
      }

      final session = await gateway.fetchSession(sessionId);
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

  void _addRss(SettingsProvider provider) {
    final String name = rssNameController.text.trim();
    final String url = rssUrlController.text.trim();

    if (name.isEmpty || !url.contains('{keyword}')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RSS 名称不能为空，且 URL 必须包含 {keyword}。')),
      );
      return;
    }

    final Uri? uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入合法的 HTTP 或 HTTPS 地址。')));
      return;
    }

    provider.addRssSource(name, url);
    rssNameController.clear();
    rssUrlController.clear();
  }

  void _deleteRss(SettingsProvider provider) {
    if (selectedRssIndex >= 0) {
      provider.removeRssSource(selectedRssIndex);
      setState(() {
        selectedRssIndex = -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettingsProvider provider = context.watch<SettingsProvider>();
    if (!provider.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('系统设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _buildBangumiCard(provider),
          const SizedBox(height: 12),
          _buildAppearanceCard(),
          const SizedBox(height: 12),
          _buildDandanplayCard(provider),
          const SizedBox(height: 12),
          _buildRssCard(provider),
          const SizedBox(height: 12),
          _buildUpdateCard(),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
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
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: isSaving ? null : _saveSettings,
          icon: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(isSaving ? '保存中...' : '保存设置'),
        ),
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
                              ? Colors.green
                              : Colors.grey,
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
                        ? NetworkImage(provider.bgmAvatarUrl)
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

  Widget _buildAppearanceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '界面外观',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: themeMode,
              decoration: const InputDecoration(labelText: '主题模式'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'Light', child: Text('浅色 (Light)')),
                DropdownMenuItem(value: 'Dark', child: Text('深色 (Dark)')),
              ],
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  themeMode = value;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bgController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: '首页背景',
                hintText: '仅首页使用这张背景图',
                suffixIcon: IconButton(
                  onPressed: _pickAndCropImage,
                  icon: const Icon(Icons.image_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.blueGrey.shade700,
                image:
                    bgController.text.isNotEmpty &&
                        File(bgController.text).existsSync()
                    ? DecorationImage(
                        image: FileImage(File(bgController.text)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              alignment: Alignment.center,
              child: bgController.text.isEmpty
                  ? const Text(
                      '暂无背景预览',
                      style: TextStyle(color: Colors.white70),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: const Text(
                        '仅首页显示',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
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
            const SizedBox(height: 12),
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
          ],
        ),
      ),
    );
  }

  Widget _buildRssCard(SettingsProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'RSS 检索源',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: provider.rssSources.length,
                itemBuilder: (BuildContext context, int index) {
                  final Map<String, String> item = provider.rssSources[index];
                  final bool isSelected = selectedRssIndex == index;
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: Colors.blueAccent.withValues(
                      alpha: 0.08,
                    ),
                    title: Text(item['name'] ?? '未知源'),
                    subtitle: Text(item['url'] ?? ''),
                    onTap: () {
                      setState(() {
                        selectedRssIndex = index;
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rssNameController,
              decoration: const InputDecoration(labelText: '站点名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rssUrlController,
              decoration: const InputDecoration(
                labelText: 'RSS 地址',
                hintText: '必须包含 {keyword}',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => _deleteRss(provider),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _addRss(provider),
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
                setState(() {
                  autoCheckUpdates = value;
                });
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
