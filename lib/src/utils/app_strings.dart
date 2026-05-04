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
  static const String noDownloadableMedia = '该种子内没有可播放的媒体文件。';
  static const String unableToFetchTorrent = '无法获取种子元数据。';

  // ── Settings ──
  static const String settingsSaved = '设置已保存。';
  static const String settingsSaving = '保存中...';
  static const String bangumiLoginSuccess = 'Bangumi 登录成功';
  static const String bangumiLoginFailed = 'Bangumi 登录失败';
  static const String authCleared = 'Bangumi 授权已清除。';

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

  // ── Units ──
  static List<String> get collectionStatuses =>
      const <String>[statusNotCollected, statusWish, statusWatched, statusWatching, statusOnHold, statusDropped];

  static List<String> get rateOptions => const <String>[
    rateNone,
    '1分', '2分', '3分', '4分', '5分',
    '6分', '7分', '8分', '9分', '10分',
  ];
}
