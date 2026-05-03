import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../core/service_locator.dart';
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

    final AppUpdateService updateService = ServiceLocator.appUpdateService;
    final AppUpdateCheckResult result = await updateService
        .checkForUpdates(settings.appUpdateFeedUrl);

    if (!mounted) {
      return;
    }

    setState(() {
      _isCheckingUpdate = false;
    });

    await updateService.showUpdateDialog(context, result);
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
                    version: '2.3.1',
                    items: <String>[
                      '优化详情页状态栏过渡：头图毛玻璃延伸到系统栏，置顶 TabBar 使用半透明渐变隔离，不再出现突兀白条。',
                      '稳定详情页“详情 / 剧集 / 进度 / 吐槽”切换时的滚动位置，TabBar 已置顶时切换板块不再带动整页上下跳动。',
                      '修复番剧播放页本集讨论的楼中楼解析重复问题，避免同一条嵌套回复被当成多条评论显示。',
                      '修正番剧和书籍详情页顶部 TabBar 的安全区与返回按钮命中区域，置顶后不再多出空白、闪移或挡住切换。',
                      '二次元库状态切换菜单补齐圆角，与应用内弹窗和控件风格保持一致。',
                      '修复搜索结果页番剧/书籍类型切换只能稳定生效一次的问题，切换时会重置分页和滚动位置。',
                      '修复千集长连载番剧“已出 xx/xxx 集”只统计当前 100 集分片的问题。',
                      '引入 Drift/SQLite 本地数据库，建立番剧、剧集、下载任务和播放进度的独立表结构。',
                      '下载任务从 SharedPreferences 巨型 JSON 迁移为按 hash 主键增量更新，并保留旧数据自动迁移。',
                      '播放进度迁移到独立数据库表，和番剧元数据、剧集状态解耦。',
                      '首页和搜索页拆出 Repository / ViewModel 边界，缓存解析与列表映射下放后台线程。',
                      '加固 FFI 临时内存、播放器生命周期和 Dio 指数退避重试，并补齐骨架屏与全局弹窗设计 Token。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.2.9',
                    items: <String>[
                      '移除首页搜索栏中冗余的蓝色箭头按钮，搜索改由键盘搜索动作提交，减少视觉噪音和误触点。',
                      '修复系统设置概览中长版本信息超出圆角标签的问题，版本文本会在可用宽度内省略显示。',
                      '主题模式选择改为圆角底部面板，和新版设置页的圆润、轻盈风格保持一致。',
                      '补齐应用内更新日志，并同步更新线上自动检查更新清单。',
                      '优化全屏播放拖动进度和切换倍速后的弹幕同步，长按 2.0x 与恢复原倍速时会重新对齐当前播放位置。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.2.8',
                    items: <String>[
                      '重做系统设置页为纵向分组结构，账号、外观、播放、数据和维护入口更接近成熟软件设置体验。',
                      '优化首页搜索框展开和收起动画，搜索状态下隐藏其他操作按钮，减少误触并提升过渡质感。',
                      '播放页支持横向滑动调整进度，竖屏小窗和横屏全屏均可用，并在松手后写入播放进度。',
                      '播放页支持按住屏幕临时 2.0x 倍速播放，松手后自动恢复原倍速。',
                      '移除跳过 OP/ED 功能，保留续播、自动下一集和播放进度记忆链路。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.2.7',
                    items: <String>[
                      '修复番剧、书籍详情页“吐槽”和剧集播放页“本集讨论”无法正常加载的问题，Bangumi HTML 抓取统一使用浏览器请求头并自动在 chii.in / bgm.tv 间兜底。',
                      '书籍详情页不再显示不需要的“剧集”分支。',
                      '修正 Android 自动小窗触发条件：只在应用退到桌面且仍在后台播放时进入画中画，进入全屏、旋转或切换播放路由不再误触发。',
                      '重排全屏播放控制台，底部聚焦弹幕开关、弹幕设置、倍速和线路/画质，选集、小窗和全屏等操作移到顶部。',
                      '优化历史进度恢复，黑屏加载和缓冲阶段不再提前显示上次进度，也不会在恢复完成前覆盖已有历史。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.2.6',
                    items: <String>[
                      '精简全屏播放控制台，减少选集、换源和弹幕样式入口重复。',
                      '修复开启自动小窗后从播放页回到桌面不会自动进入画中画的问题。',
                      '修复恢复历史播放进度时 UI 显示正确但播放器实际从头播放的问题。',
                      '修复手动进入小窗瞬间可能压缩显示全屏控制台的问题。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.2.5',
                    items: <String>[
                      '修复从播放页切到全屏时可能出现白屏的问题。',
                      '修复刚进入视频播放页时进度条在初始位置、旧位置和恢复进度之间来回跳动的问题。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.2.4',
                    items: <String>[
                      '修复在线播放从小屏进入全屏后进度条可能无法拖动的问题。',
                      '扩大在线播放源搜索范围，启用已内置的更多资源站点，并优化早停策略减少只返回少数源的情况。',
                      '小屏在线播放也会记忆上次播放进度，换源、切集、退出后可继续播放。',
                      '新增 Android 小窗播放能力，可在设置中开启离开播放页自动画中画。',
                      '优化全屏播放控制台，进度条移到按钮上方，并避免控制台展开时双击播放/暂停浮层重叠。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.2.3',
                    items: <String>[
                      '加固 Bangumi 登录链路，授权回调改为一次性交换，降低会话泄露后的风险。',
                      '修复 release 构建签名校验，避免误发 debug 签名包导致后续无法覆盖升级。',
                      '收紧 Android 明文流量策略，仅保留本地播放流和必要 HTTP 资源站、Tracker 白名单。',
                      '修复原生目录扫描修改时间戳恒为 0 的问题，本地文件排序和缓存判断更准确。',
                      '清理 Wrangler 本地缓存入库，避免部署账号信息出现在仓库中。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.2.2',
                    items: <String>[
                      '修复在线播放 HLS 源无法正常拖动进度条的问题，播放器会在必要时解析播放列表时长作为兜底。',
                      '修复在线播放进度条末端不显示总时长的问题，小屏和全屏播放器都会显示当前进度与总时长。',
                      '优化剧集标题显示，去除标题开头重复的集数前缀，避免出现“01 1 标题”这类重复信息。',
                      '修正番剧详情页放送状态展示，不再把总集数误显示为已出集数，连载番剧会显示已出/总集数。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.2.1',
                    items: <String>[
                      '优化在线播放搜索策略，优先使用稳定直链源，减少无效站点请求。',
                      '单站内部改为小批量并发解析，并在获得足够可播线路后提前结束搜索。',
                      '提升 OmoFun 直链源优先级，过滤广告片段并降低慢线路自动选择权重。',
                      '提高在线播放播放器缓冲区，降低 HLS 在线源播放时的卡顿和缓冲抖动。',
                      '保留在线播放短期缓存，重复进入同一集时可更快展示已解析线路。',
                    ],
                  ),
                  SizedBox(height: 14),
                  _LogEntry(
                    version: '2.1.13',
                    items: <String>[
                      '番剧详情页的剧集面板新增本地缓存播放入口，可按条目与集数匹配已缓存任务。',
                      '在线播放限定为内置站点适配器，移除 WebView 捕获页和 Bing 搜索兜底。',
                      '查找在线播放会自动选择优先级最高的直连源开始播放，播放器控制栏可继续换源。',
                      '播放器新增在线选集入口，可在播放中切换当前番剧的全部剧集。',
                      '剧集点击改为进入独立播放详情页，上方非全屏播放，下方展示剧情介绍、本集讨论和剧集列表。',
                      '播放详情页优先播放本地缓存，并支持在缓存与在线播放源之间切换。',
                      '优化剧集播放详情页布局，移除小屏中央大暂停按钮，压缩数据源和剧集列表区域。',
                      '小屏进入全屏改为复用同一个播放器会话，避免重复加载同一视频源。',
                      '统一小屏与全屏手势：单击只显示或隐藏控制层，双击只负责播放或暂停。',
                      '从剧集小屏进入全屏时保持横屏显示，退出全屏后直接回到竖屏。',
                      '换源面板按站点分组展示多线路，并标注优先、可用、备用源级别。',
                      '在线源搜索改为 10 个大陆网络优先源，单站最长等待调整为 8 秒，并对直链做轻量可播放探测。',
                      '移除咕咕番在线源，避免展示已搜索到但无法播放的线路。',
                      '优化本集讨论显示，回复保留缩进层次但不再显示“楼中楼”文案。',
                      '播放器新增双击播放/暂停，左侧上下滑调亮度，右侧上下滑调音量。',
                      '在线源搜索改为流式返回，已解析的源会先展示，不再等待所有站点搜索结束。',
                      '扩展内置资源站点，稳定直链源优先，其它站点作为候选补充。',
                      '在线源搜索改为分批并发，避免大量站点同时请求导致搜索变慢或界面卡顿。',
                      '在线播放结果加入短期缓存，返回剧集页或重复切换同一集时可立即展示已解析源。',
                      '修复剧集切换搜索期间上一集继续播放的问题，切集时会先停止当前播放器。',
                      '修复小屏进入全屏后控制栏仍显示“全屏”的状态错误。',
                      '详情页先显示番剧主体信息，再异步补齐账号进度、角色、制作人员和相关条目。',
                      '首页年度榜单和每日放送增加内存缓存，减少重复进入时的网络等待。',
                    ],
                  ),
                  SizedBox(height: 14),
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
