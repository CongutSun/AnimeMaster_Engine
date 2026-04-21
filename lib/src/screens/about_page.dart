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
                    version: '2.1.12',
                    items: <String>[
                      '修复 Bangumi 本集讨论解析错乱，避免楼中楼回复被拆成错误评论。',
                      '优化本集讨论展示样式，作者、时间和正文改为自适应卡片布局，减少大空白和文字错位。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.1.11',
                    items: <String>[
                      '修复启动后自动检查更新不弹窗的问题，应用打开后会按设置自动提示可用新版本。',
                      '播放器新增播放进度记忆，退出后再次进入同一文件会从上次进度继续播放。',
                      '弹幕样式新增字号、透明度、速度、显示区域、描边和底色调整。',
                      '番剧详情新增剧集列表、单集讨论查看，并支持点击剧集直接同步观看进度。',
                      '番剧吐槽改为进入吐槽页签后懒加载，降低详情页首屏请求压力。',
                      '缓存中心和播放页增强 Bangumi 剧集识别，尽量显示具体集数和集名。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.1.10',
                    items: <String>[
                      '下载调度改为单主任务优先，减少多个任务同时下载造成的卡顿、发热和磁盘争用。',
                      '增加活跃 Peer 上限和低质量连接清理，降低下载与做种时的后台负载。',
                      '下载末段自动增强 DHT 与 Tracker 补偿，缓解最后 10% 因稀缺分片导致的速度骤降。',
                      '优化下载速度统计和缓存中心刷新节流，减少无意义的全页面重建。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.1.9',
                    items: <String>[
                      '修复缓存中心手动添加任务弹窗被输入法重复挤压，导致资源链接无法正常输入的问题。',
                      '资源链接输入框增加键盘滚动留白，保持输入区和底部操作按钮可用。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.1.8',
                    items: <String>[
                      '缓存中心增加下载和做种并发调度，降低多个任务同时下载或做种时的卡顿与发热。',
                      '边下边播改为播放优先分片下载，修复 .torrent 直链播放失败和磁力播放进度条跳动。',
                      '修复缓存中心添加任务按钮遮挡播放、暂停、删除按钮，以及首页自定义背景底部裁切。',
                      '自动更新改为启动后自动检查并弹出提示，APK 下载改走 AnimeMaster 网关，减少 GitHub 直连失败。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.1.7',
                    items: <String>[
                      '资源搜索和 .torrent 下载增加 AnimeMaster 网关兜底，直连 Mikan/DMHY 超时后会自动重试。',
                      '放宽 Mikan RSS 与种子下载超时，并加入 mikanani.me / mikanime.tv 双域名互换重试。',
                      '修复部分网络环境下不开代理无法添加播放或下载资源的问题。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.1.6',
                    items: <String>[
                      '优化边下边播本地代理读取策略，减少未缓存片段导致的播放器重试和进度条跳动。',
                      '下载和做种期间启用 Android 前台服务与唤醒锁，降低切到后台后任务停止的概率。',
                      '下载完成后不再自动停止任务，默认进入做种状态，并在缓存中心显示上传速度。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.1.5',
                    items: <String>[
                      '弹幕加载支持无弹弹play凭证时自动回退到 Animeko 公益弹幕源。',
                      '播放任务开始携带 Bangumi 条目 ID，并可按标题和集数推断 Bangumi 剧集 ID。',
                      '弹弹play 手动匹配保留为高级兜底，未配置凭证时不再阻断弹幕入口。',
                      '修复缓存中心手动添加任务时输入法挤压按钮导致重叠的问题。',
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
