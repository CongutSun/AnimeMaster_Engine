/// Centralised string constants for the AnimeMaster app.
///
/// All user‑facing text lives here so the app is i18n‑ready —
/// swap this file for ARB/flutter_localizations when needed.

class AppStrings {
  AppStrings._();

  // ── Collection status ──
  static const String statusNotCollected = '未收藏';
  static const String statusWish = '想看';
  static const String statusWatched = '看过';
  static const String statusWatching = '在看';
  static const String statusOnHold = '搁置';
  static const String statusDropped = '抛弃';

  // ── Rating ──
  static const String rateNone = '暂不打分';

  // ── Broadcast ──
  static const String notAired = '未开播';
  static const String finished = '已完结';
  static const String airing = '连载中';

  // ── Search ──
  static const String searchNoResultAnime = '未找到相关番剧\n请尝试更换搜索词';
  static const String searchNoResultBook = '未找到相关书籍\n请尝试更换搜索词';
  static const String searchNoMore = '没有更多搜索结果了';
  static const String searchFailed = '搜索失败，请检查网络后重试';

  // ── Detail / Episode ──
  static const String noEpisodeData = '暂无剧集数据。';
  static const String noSummary = '暂无简介';
  static const String noComments = '暂无评论，或加载失败请下拉重试';
  static const String noEpisodeComments = '暂无本集讨论';
  static const String noEpisodeDesc = '暂无本集简介。';
  static const String unnamedEpisode = '未命名剧集';
  static const String episodeChapter = '话';
  static const String episodeUnit = '集';

  // ── Sync ──
  static const String syncSuccess = '云端同步成功';
  static const String syncFailed = '同步失败，请检查网络';
  static const String syncNeedToken = '请先配置 Bgm Token';
  static const String syncNeedStatus = '请选择更新状态';
  static const String syncInProgress = '同步中...';
  static const String saveAndSync = '保存进度并同步云端';

  // ── Playback ──
  static const String preparingPlayback = '正在准备播放...';
  static const String loadingVideo = '正在加载视频...';
  static const String searchingOnline = '正在查找在线播放源...';
  static const String noPlayableSource = '未找到可播放的视频源';
  static const String sourceSearchFailed = '在线播放源搜索失败';

  // ── Download / Magnet ──
  static const String magnetSearch = '全网磁力检索';
  static const String onlinePlay = '在线播放';
  static const String noDownloadableMedia = '该种子内没有可播放的媒体文件。';
  static const String unableToFetchTorrent = '无法获取种子元数据。';

  // ── Settings ──
  static const String settingsSaved = '设置已保存。';
  static const String settingsSaving = '保存中...';
  static const String bangumiLoginSuccess = 'Bangumi 登录成功';
  static const String bangumiLoginFailed = 'Bangumi 登录失败';
  static const String authCleared = 'Bangumi 授权已清除。';
  static const String deleteRssConfirm = '确认删除该 RSS 源？';
  static const String deleteRssMessage = '删除后不可恢复，需要重新添加。';
  static const String deleteConfirm = '确认删除';
  static const String loginServiceUnavailable = '登录服务暂不可用，请稍后再试。';
  static const String settingsTitle = '系统设置';
  static const String settingsSubtitle = '偏好、数据源和播放体验集中管理';
  static const String accountSection = '账号与同步';
  static const String accountSectionDesc = 'Bangumi 登录、授权状态与资料同步';
  static const String appearanceSection = '界面外观';
  static const String appearanceSectionDesc = '主题模式与首页背景';
  static const String playbackSection = '播放体验';
  static const String playbackSectionDesc = '小窗、续播和自动下一集';
  static const String dataSection = '数据与弹幕';
  static const String dataSectionDesc = '弹幕凭据和 RSS 搜索源';
  static const String maintenanceSection = '应用维护';
  static const String maintenanceSectionDesc = '更新检查与版本信息';
  static const String themeModeLabel = '主题模式';
  static const String themeLightTitle = '浅色';
  static const String themeLightDesc = '清爽明亮，适合白天使用';
  static const String themeDarkTitle = '深色';
  static const String themeDarkDesc = '降低夜间亮度，更贴近沉浸播放';
  static const String themeSheetTitle = '选择应用整体明暗风格';
  static const String resumePlaybackLabel = '继续播放';
  static const String resumePlaybackDesc = '打开视频时如何处理上次的观看进度';
  static const String resumeAskTitle = '播放前询问';
  static const String resumeAskDesc = '每次打开视频都询问是否从上次位置继续';
  static const String resumeAutoTitle = '自动续播';
  static const String resumeAutoDesc = '自动从上一次的观看进度继续播放';
  static const String resumeNeverTitle = '始终从头播放';
  static const String resumeNeverDesc = '每次打开视频都从头开始，不记忆进度';
  static const String pipTitle = '离开播放页自动小窗';
  static const String pipDesc = '开启后，在 Android 支持的设备上按主页键会进入画中画播放。';
  static const String autoNextTitle = '自动播放下一集';
  static const String autoNextDesc = '接近片尾或播放结束后显示倒计时，可手动取消。';
  static const String danmakuTitle = '弹弹play 弹幕';
  static const String danmakuDesc = '未填写时会使用 Animeko 公益弹幕源；填写后优先使用弹弹play 聚合弹幕。AppSecret 不会内嵌到 APK。';
  static const String rssTitle = 'RSS 检索源';
  static const String rssUrlHint = '必须包含 {keyword}';
  static const String rssNameLabel = '站点名称';
  static const String rssUrlLabel = 'RSS 地址';
  static const String rssValidationError = 'RSS 名称不能为空，且 URL 必须包含 {keyword}。';
  static const String rssHttpError = '请输入合法的 HTTP 或 HTTPS 地址。';
  static const String appUpdateTitle = '应用更新';
  static const String autoCheckTitle = '启动时检查更新';
  static const String autoCheckDesc = '开启后，应用启动时会自动读取内置更新清单。';
  static const String checkUpdateLabel = '检查更新';
  static const String checkingUpdateLabel = '检查中...';
  static const String aboutTitle = '关于 AnimeMaster';
  static const String noWallpaper = '暂无背景预览';
  static const String wallpaperHint = '留空则使用纯色背景';
  static const String wallpaperLabel = '首页背景';
  static const String wallpaperOnlyHome = '仅首页显示';
  static const String restoreWallpaper = '恢复纯色背景';
  static const String cropWallpaper = '裁剪首页背景';
  static const String noActorAssociated = '暂无关联声优';

  // ── Toolbar ──
  static const String toolbarCollection = '收藏';
  static const String toolbarDownloadCenter = '缓存中心';
  static const String toolbarSettings = '设置';
  static const String toolbarClear = '清空';
  static const String toolbarSearch = '搜索番剧或书籍';

  // ── Generic ──
  static const String noData = '暂无数据';
  static const String retry = '重试';
  static const String refresh = '重新加载';
  static const String confirm = '确认';
  static const String cancel = '取消';
  static const String unknown = '未知';
  static const String loadFailed = '数据加载失败，请下拉重试或检查网络状态';
  static const String networkError = '网络连接异常，请检查后重试';

  // ── Collection ──
  static const String collectionEmpty = '已经看完啦！';

  // ── Download ──
  static const String downloadNoTasks = '暂无下载任务';
  static const String downloadCompleted = '已完成';
  static const String downloadPaused = '已暂停';
  static const String downloadActive = '下载中';

  // ── Error messages (user-facing, no internal details) ──
  static const String updateCheckFailed = '检查更新失败，请稍后重试。';
  static const String updateManifestInvalid = '更新清单缺少必要字段。';
  static const String updateManifestEmpty = '尚未配置更新清单地址。';
  static const String updateUpToDate = '当前已经是最新版本。';
  static const String updateAvailable = '发现新版本。';
  static const String cannotOpenDownloadUrl = '无法打开下载地址。';

  // ── Update dialog ──
  static const String updateDialogTitle = '发现新版本';
  static const String updateDialogCurrent = '当前版本';
  static const String updateDialogLatest = '最新版本';
  static const String updateDialogPublished = '发布时间';
  static const String updateDialogSha256 = 'SHA256 校验';
  static const String updateDialogChangelog = '更新内容';
  static const String updateDialogNote = '说明：Android 普通应用无法静默强制安装更新，系统会跳转到下载或安装流程，由用户确认覆盖安装。';
  static const String updateDialogLater = '稍后';
  static const String updateDialogDownload = '下载更新';
  static const String updateDialogAppTitle = '应用更新';

  // ── Bottom navigation ──
  static const String navHome = '首页';
  static const String navCollection = '收藏';
  static const String navDownloads = '下载';
  static const String navSettings = '设置';

  // ── Onboarding ──
  static const String onboardingSkip = '跳过';
  static const String onboardingNext = '下一步';
  static const String onboardingDone = '开始使用';
  static const String onboardingTitle1 = '发现好番';
  static const String onboardingDesc1 = '浏览 Bangumi 新番放送、年度排行，搜索你感兴趣的动漫作品，查看角色、声优和评价。';
  static const String onboardingTitle2 = '追番管理';
  static const String onboardingDesc2 = '登录 Bangumi 账号同步收藏进度，标记已看剧集，让你的追番列表始终保持最新。';
  static const String onboardingTitle3 = '资源下载与播放';
  static const String onboardingDesc3 = '通过磁力/RSS 检索资源，边下边播，支持弹幕、倍速、画中画等丰富的播放体验。';

  // ── Back button ──
  static const String backTooltip = '返回';

  // ── Units ──
  static List<String> get collectionStatuses =>
      const <String>[statusNotCollected, statusWish, statusWatched, statusWatching, statusOnHold, statusDropped];

  static List<String> get rateOptions => const <String>[
    rateNone,
    '1分', '2分', '3分', '4分', '5分',
    '6分', '7分', '8分', '9分', '10分',
  ];
}
