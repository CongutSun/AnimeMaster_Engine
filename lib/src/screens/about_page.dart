import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/app_update_service.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _packageInfo;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    if (!mounted) {
      return;
    }
    setState(() {
      _packageInfo = info;
    });
  }

  Future<void> _checkForUpdates(SettingsProvider settings) async {
    if (_isCheckingUpdate) {
      return;
    }

    setState(() {
      _isCheckingUpdate = true;
    });

    final AppUpdateCheckResult result = await const AppUpdateService()
        .checkForUpdates(settings.appUpdateFeedUrl);

    if (!mounted) {
      return;
    }

    setState(() {
      _isCheckingUpdate = false;
    });

    await const AppUpdateService().showUpdateDialog(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settings = context.watch<SettingsProvider>();
    final PackageInfo? packageInfo = _packageInfo;

    return Scaffold(
      appBar: AppBar(title: const Text('关于 AnimeMaster')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '应用信息',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: '应用名称',
                    value: packageInfo?.appName ?? 'AnimeMaster',
                  ),
                  _InfoRow(
                    label: '版本号',
                    value: packageInfo?.version ?? '读取中...',
                  ),
                  _InfoRow(
                    label: '包名',
                    value: packageInfo?.packageName ?? '读取中...',
                  ),
                  _InfoRow(label: '引擎版本', value: settings.coreEngineVersion),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '应用更新',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: '启动检查',
                    value: settings.autoCheckUpdates ? '已开启' : '已关闭',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isCheckingUpdate
                          ? null
                          : () => _checkForUpdates(settings),
                      icon: _isCheckingUpdate
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.system_update_alt_rounded),
                      label: Text(_isCheckingUpdate ? '检查中...' : '检查更新'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '说明：侧载 APK 用户只能通过应用内检测后跳转下载覆盖安装，系统不会允许静默升级。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const <Widget>[
                  Text(
                    '更新日志',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  _LogEntry(
                    version: '2.1.5',
                    items: <String>[
                      '弹幕加载支持无弹弹play凭证时自动回退到 Animeko 公益弹幕源。',
                      '播放任务开始携带 Bangumi 条目 ID，并可按标题和集数推断 Bangumi 剧集 ID。',
                      '弹弹play 手动匹配保留为高级兜底，未配置凭证时不再阻断弹幕入口。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.1.4',
                    items: <String>[
                      '恢复“添加与播放”的 3% 起播缓冲，降低未缓存片段导致的花屏和噪点。',
                      '优化边下边播流式读取，遇到未写入片段时等待可读数据。',
                      '优化下载任务恢复、DHT 节点引导和 Tracker Peer 发现预热。',
                      '优化番剧详情页首屏加载，同类作品结果增加本地缓存。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.1.3',
                    items: <String>[
                      '新增 GitHub 更新清单和应用内检查更新入口。',
                      '支持 ABI 分包构建，减少 Android 下载体积。',
                      '优化缓存中心任务标题和下载恢复逻辑。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.1.0',
                    items: <String>[
                      '新增播放器选集、倍速以及 10 秒快进快退。',
                      '新增应用更新清单地址、启动检查和关于页手动检查更新入口。',
                      '磁力播放链路支持多文件枚举，可在一个种子内切换具体视频文件。',
                      '继续保持缓存中心、检索结果与播放入口的标题和集数联动。',
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _LogEntry extends StatelessWidget {
  final String version;
  final List<String> items;

  const _LogEntry({required this.version, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'v$version',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...items.map(
          (String item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('• '),
                Expanded(child: Text(item)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
