import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/settings_provider.dart';
import '../api/bangumi_api.dart';
import '../utils/app_strings.dart';
import 'magnet_config_page.dart';
import 'category_result_page.dart';
import 'episode_watch_page.dart';
import 'role_subjects_page.dart';
import '../utils/episode_helpers.dart';
import '../utils/image_request.dart';
import '../widgets/selection_dialog.dart';
import '../utils/haptic_helper.dart';

Widget _buildSafeImage({
  required String imageUrl,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget? errorWidget,
}) {
  final secureUrl = normalizeImageUrl(imageUrl);
  if (secureUrl.isEmpty) {
    return errorWidget ??
        Container(
          width: width,
          height: height,
          color: Colors.grey.withValues(alpha: 0.2),
        );
  }
  return CachedNetworkImage(
    imageUrl: secureUrl,
    width: width,
    height: height,
    fit: fit,
    httpHeaders: buildImageHeaders(secureUrl),
    cacheManager: AppImageCacheManager.instance,
    memCacheWidth: width != null ? (width * 3).toInt() : null,
    memCacheHeight: height != null ? (height * 3).toInt() : null,
    placeholder: (context, url) => Container(
      width: width,
      height: height,
      color: Colors.grey.withValues(alpha: 0.2),
    ),
    errorWidget: (context, url, error) =>
        errorWidget ??
        Container(
          width: width,
          height: height,
          color: Colors.grey.withValues(alpha: 0.2),
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
  );
}

class DetailPage extends StatefulWidget {
  final int animeId;
  final String initialName;
  final int subjectType;

  const DetailPage({
    super.key,
    required this.animeId,
    required this.initialName,
    this.subjectType = 2,
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _heroHeaderKey = GlobalKey();
  double _heroHeaderExtent = 0;
  int _activeTabIndex = 0;
  bool _restorePinnedAfterTabChange = false;

  // ── Epic 1: Episode chunking ──
  static const int _episodeChunkSize = 30;
  List<Map<String, dynamic>> _allEpisodes = [];
  List<List<Map<String, dynamic>>> _episodeChunks = const [];
  int _currentChunkIndex = 0;
  final ValueNotifier<Set<int>> _watchedEpisodeIds = ValueNotifier<Set<int>>(
    const <int>{},
  );

  Map<String, dynamic>? detailData;
  List<Map<String, String>> realComments = [];
  List<Map<String, dynamic>> episodesData = [];
  List<dynamic> charactersData = [];
  List<dynamic> staffData = [];
  List<dynamic> relatedData = [];
  bool isSummaryExpanded = false;
  bool isLoading = true;
  bool isCommentsLoading = false;
  bool isEpisodesLoading = false;
  bool hasRequestedComments = false;
  bool hasRequestedEpisodes = false;
  bool isSyncing = false;
  bool hasFetchedPersonalData = false;
  String? commentsErrorMessage;
  String? episodesErrorMessage;

  String currentStatus = '未收藏';
  String currentRate = '暂不打分';
  int currentEp = 0;
  int currentVol = 0;

  bool get _hasEpisodeTab => widget.subjectType == 2;
  int get _progressTabIndex => _hasEpisodeTab ? 2 : 1;
  int get _commentsTabIndex => _hasEpisodeTab ? 3 : 2;

  final TextEditingController commentController = TextEditingController();
  final Map<String, int> statusToInt = {
    '想看': 1,
    '看过': 2,
    '在看': 3,
    '搁置': 4,
    '抛弃': 5,
  };
  final Map<int, String> intToStatus = {
    1: '想看',
    2: '看过',
    3: '在看',
    4: '搁置',
    5: '抛弃',
  };
  final List<String> rateOptions = [
    '暂不打分',
    '1分',
    '2分',
    '3分',
    '4分',
    '5分',
    '6分',
    '7分',
    '8分',
    '9分',
    '10分',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _hasEpisodeTab ? 4 : 3, vsync: this);
    _tabController.addListener(_handleTabControllerTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAllData());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    commentController.dispose();
    _watchedEpisodeIds.dispose();
    super.dispose();
  }

  void _handleTabControllerTick() {
    if (_tabController.indexIsChanging || !mounted) {
      return;
    }

    final int index = _tabController.index;
    _loadTabDataIfNeeded(index);
    if (index == _activeTabIndex) {
      return;
    }

    _activeTabIndex = index;
    setState(() {});
    final SettingsProvider settings = Provider.of<SettingsProvider>(context, listen: false);
    if (settings.enableHapticFeedback) {
      HapticFeedback.lightImpact();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePinnedTabOffsetIfNeeded();
    });
  }

  void _prepareTabSwitch(int targetIndex) {
    if (targetIndex == _tabController.index) {
      return;
    }
    _restorePinnedAfterTabChange = _isTabHeaderPinned;
  }

  bool get _isTabHeaderPinned {
    if (!_scrollController.hasClients) {
      return false;
    }
    return _scrollController.offset >= _tabPinnedOffset - 1;
  }

  double get _tabPinnedOffset {
    if (_heroHeaderExtent > 0) {
      return _heroHeaderExtent;
    }
    final double topInset = MediaQuery.paddingOf(context).top;
    return topInset + kToolbarHeight + 180;
  }

  double get _stableTabFooterExtent {
    return _tabPinnedOffset + MediaQuery.paddingOf(context).bottom + 24;
  }

  void _restorePinnedTabOffsetIfNeeded() {
    if (!_restorePinnedAfterTabChange || !_scrollController.hasClients) {
      _restorePinnedAfterTabChange = false;
      return;
    }
    _restorePinnedAfterTabChange = false;
    final ScrollPosition position = _scrollController.position;
    final double target = _tabPinnedOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((_scrollController.offset - target).abs() > 0.5) {
      _scrollController.jumpTo(target);
    }
  }

  void _scheduleHeroHeaderMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final RenderBox? box =
          _heroHeaderKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        return;
      }
      _heroHeaderExtent = box.size.height;
    });
  }

  Future<void> _loadAllData() async {
    final provider = Provider.of<SettingsProvider>(context, listen: false);
    final Future<Map<String, dynamic>?> detailFuture =
        BangumiApi.instance.getAnimeDetail(widget.animeId);
    final Future<Map<String, dynamic>?> collectionFuture = () async {
      await provider.ensureBangumiAccessToken();
      final String bgmUsername = provider.bgmAcc;
      final String bgmToken = provider.bgmToken;
      if (bgmUsername.isEmpty || bgmToken.isEmpty) {
        return null;
      }
      return BangumiApi.instance.getUserCollection(
        widget.animeId,
        bgmUsername,
        bgmToken,
      );
    }();

    final Map<String, dynamic>? subjectDetail = await detailFuture;
    if (!mounted) {
      return;
    }
    setState(() {
      detailData = subjectDetail;
      isLoading = false;
    });

    unawaited(_applyCollectionData(collectionFuture));
    unawaited(_loadSupplementaryData());
  }

  Future<void> _applyCollectionData(
    Future<Map<String, dynamic>?> collectionFuture,
  ) async {
    final Map<String, dynamic>? collectionData = await collectionFuture;
    if (!mounted || collectionData == null) {
      return;
    }
    setState(() {
      hasFetchedPersonalData = true;
      final int typeInt = collectionData['type'] is int
          ? collectionData['type']
          : int.tryParse(collectionData['type']?.toString() ?? '') ?? 0;
      final int rateInt = collectionData['rate'] is int
          ? collectionData['rate']
          : int.tryParse(collectionData['rate']?.toString() ?? '') ?? 0;

      if (intToStatus.containsKey(typeInt)) {
        currentStatus = intToStatus[typeInt]!;
      }
      if (rateInt > 0) {
        currentRate = '$rateInt分';
      }
      commentController.text = collectionData['comment']?.toString() ?? '';
      currentEp = collectionData['ep_status'] is int
          ? collectionData['ep_status']
          : 0;
      currentVol = collectionData['vol_status'] is int
          ? collectionData['vol_status']
          : 0;
    });
  }

  void _loadTabDataIfNeeded(int index) {
    if (_hasEpisodeTab &&
        index == 1 &&
        !hasRequestedEpisodes &&
        !isEpisodesLoading) {
      unawaited(_loadEpisodes());
    }
    if (index == _commentsTabIndex &&
        !hasRequestedComments &&
        !isCommentsLoading) {
      unawaited(_loadComments());
    }
  }

  Future<void> _loadSupplementaryData() async {
    if (_hasEpisodeTab && !hasRequestedEpisodes && !isEpisodesLoading) {
      unawaited(_loadEpisodes());
    }
    unawaited(
      BangumiApi.instance.getSubjectCharacters(widget.animeId).then((
        List<dynamic> data,
      ) {
        if (mounted) {
          setState(() => charactersData = data);
        }
      }),
    );
    unawaited(
      BangumiApi.instance.getSubjectPersons(widget.animeId).then((List<dynamic> data) {
        if (mounted) {
          setState(() => staffData = data);
        }
      }),
    );
    unawaited(
      BangumiApi.instance.getSubjectRelations(widget.animeId).then((List<dynamic> data) {
        if (mounted) {
          setState(() => relatedData = data);
        }
      }),
    );
  }

  Future<void> _loadComments() async {
    if (hasRequestedComments && realComments.isNotEmpty) {
      return;
    }
    setState(() {
      hasRequestedComments = true;
      isCommentsLoading = true;
      commentsErrorMessage = null;
    });
    try {
      final List<Map<String, String>> comments =
          await BangumiApi.instance.getSubjectComments(widget.animeId);
      if (!mounted) return;
      setState(() {
        realComments = comments;
        isCommentsLoading = false;
        commentsErrorMessage = comments.isEmpty ? '暂无评论' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isCommentsLoading = false;
        commentsErrorMessage = '加载失败：${e.toString().replaceFirst("Exception: ", "")}';
      });
    }
  }

  Future<void> _loadEpisodes() async {
    setState(() {
      hasRequestedEpisodes = true;
      isEpisodesLoading = true;
    });
    final List<Map<String, dynamic>> episodes =
        await BangumiApi.instance.getSubjectEpisodes(widget.animeId);

    if (!mounted) {
      return;
    }

    // ── Epic 1: Chunk episodes by 100 ──
    _allEpisodes = episodes;
    final List<List<Map<String, dynamic>>> chunks =
        <List<Map<String, dynamic>>>[];
    for (int i = 0; i < episodes.length; i += _episodeChunkSize) {
      final int end = (i + _episodeChunkSize).clamp(0, episodes.length);
      chunks.add(episodes.sublist(i, end));
    }
    setState(() {
      episodesData = chunks.isNotEmpty ? chunks[0] : <Map<String, dynamic>>[];
      _episodeChunks = chunks;
      _currentChunkIndex = 0;
      isEpisodesLoading = false;
    });
  }

  void _handlePersonTap(dynamic item, bool isCharacter) {
    if (item is! Map) return;
    String name = item['name']?.toString() ?? '';
    int? id = item['id'] is int
        ? item['id']
        : int.tryParse(item['id']?.toString() ?? '');

    if (isCharacter &&
        item['actors'] is List &&
        (item['actors'] as List).isNotEmpty) {
      var actor = item['actors'][0];
      String actorName = actor is Map
          ? (actor['name']?.toString() ?? '')
          : actor.toString();
      int? actorId = actor is Map
          ? (actor['id'] is int
                ? actor['id']
                : int.tryParse(actor['id']?.toString() ?? ''))
          : null;

      showSelectionSheet(
        context,
        title: '选择查看对象',
        items: <SelectionItem>[
          SelectionItem(
            label: '角色: $name',
            onTap: () {
              if (id != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RoleSubjectsPage(id: id, name: name, isCharacter: true),
                  ),
                );
              }
            },
          ),
          SelectionItem(
            label: '声优: $actorName',
            onTap: () {
              if (actorId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoleSubjectsPage(
                      id: actorId,
                      name: actorName,
                      isCharacter: false,
                    ),
                  ),
                );
              }
            },
          ),
        ],
      );
    } else {
      final String actorLabel = isCharacter ? AppStrings.noActorAssociated : '';
      showSelectionSheet(
        context,
        title: '选择查看对象',
        items: <SelectionItem>[
          SelectionItem(
            label: '${isCharacter ? "角色" : "制作人员"}: $name',
            onTap: () {
              if (id != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RoleSubjectsPage(id: id, name: name, isCharacter: isCharacter),
                  ),
                );
              }
            },
          ),
          if (isCharacter)
            SelectionItem(
              label: '声优: $actorLabel',
              onTap: () {},
              enabled: false,
            ),
        ],
      );
    }
  }

  Future<void> _syncToCloud() async {
    maybeHaptic(context);
    final SettingsProvider settings = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    await settings.ensureBangumiAccessToken();
    if (!mounted) {
      return;
    }
    final String bgmToken = settings.bgmToken;
    if (bgmToken.isEmpty || currentStatus == '未收藏') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(bgmToken.isEmpty ? '请先配置 Bgm Token' : '请选择更新状态'),
        ),
      );
      return;
    }

    setState(() => isSyncing = true);

    Map<String, dynamic> postData = {'type': statusToInt[currentStatus]};
    if (widget.subjectType == 1) {
      postData['ep_status'] = currentEp;
      postData['vol_status'] = currentVol;
    }
    if (currentRate != '暂不打分') {
      postData['rate'] = int.tryParse(currentRate.replaceAll('分', '')) ?? 0;
    }
    if (commentController.text.isNotEmpty) {
      postData['comment'] = commentController.text;
    }

    bool collectionSuccess = await BangumiApi.instance.updateCollection(
      widget.animeId,
      bgmToken,
      postData,
    );
    bool episodeSuccess = widget.subjectType != 1 && collectionSuccess
        ? await BangumiApi.instance.updateEpisodeStatus(
            widget.animeId,
            bgmToken,
            currentEp,
          )
        : true;

    if (!mounted) return;
    setState(() => isSyncing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          collectionSuccess && episodeSuccess ? '云端同步成功' : '同步失败，请检查网络',
        ),
        backgroundColor: collectionSuccess && episodeSuccess
            ? Colors.green
            : Colors.red,
      ),
    );
  }

  List<String> _extractAliases(String cnName, String originalName) {
    return extractAliases(cnName, originalName, detailData);
  }

  Widget _buildDropdownRow(
    String label,
    IconData icon,
    Color iconColor,
    List<String> items,
    String value,
    ValueChanged<String?> onChanged,
  ) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: MenuTheme(
              data: MenuThemeData(
                style: MenuStyle(
                  shape: WidgetStatePropertyAll<OutlinedBorder>(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(14),
                  items: items
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(e, style: const TextStyle(fontSize: 13)),
                        ),
                      )
                      .toList(),
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressAdjuster(
    String title,
    int value,
    VoidCallback onMinus,
    VoidCallback onPlus,
  ) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(
            widget.subjectType == 1 ? Icons.menu_book : Icons.ondemand_video,
            color: primaryColor,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.remove_circle_outline,
              color: value > 0 ? primaryColor : Colors.grey,
            ),
            onPressed: value > 0 ? onMinus : null,
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: Icon(Icons.add_circle_outline, color: primaryColor),
            onPressed: onPlus,
          ),
        ],
      ),
    );
  }

  String _formatAirDate() {
    final String date = detailData?['date']?.toString().trim() ?? '';
    return date.isEmpty ? '未知' : date;
  }

  String _broadcastStatusText() {
    final String unit = widget.subjectType == 2 ? '集' : '话';
    final int total = _subjectEpisodeTotal();
    final int aired = _airedEpisodeCount();
    final bool hasEpisodes = _allEpisodes.isNotEmpty || episodesData.isNotEmpty;
    final DateTime today = _today();
    final DateTime? startDate = _parseDate(detailData?['date']);
    final bool hasStarted = startDate == null || !startDate.isAfter(today);

    if (!hasStarted) {
      return total > 0 ? '未开播 · 全$total$unit' : '未开播';
    }

    if (hasEpisodes) {
      if (total > 0) {
        final int displayAired = aired > total ? total : aired;
        return displayAired > 0
            ? '连载中 · 已出$displayAired/$total$unit'
            : '连载中 · 全$total$unit';
      }
      return aired > 0 ? '连载中 · 已出$aired$unit' : '连载中';
    }

    final int displayTotal = total > 0 ? total : _allEpisodes.length;
    if (displayTotal > 0) {
      return '连载中 · 全$displayTotal$unit';
    }
    return '连载中';
  }

  int _subjectEpisodeTotal() {
    final dynamic eps = detailData?['eps'] ?? detailData?['eps_count'];
    if (eps is int) {
      return eps;
    }
    if (eps is num) {
      return eps.round();
    }
    return int.tryParse(eps?.toString() ?? '') ?? 0;
  }

  int _airedEpisodeCount() {
    int count = 0;
    final DateTime today = _today();
    final List<Map<String, dynamic>> source = _allEpisodes.isNotEmpty
        ? _allEpisodes
        : episodesData;
    for (final Map<String, dynamic> episode in source) {
      final DateTime? airdate = _parseDate(episode['airdate']);
      if (airdate != null && !airdate.isAfter(today)) {
        count += 1;
      }
    }
    return count;
  }

  DateTime _today() {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime? _parseDate(dynamic value) {
    final String raw = value?.toString().trim() ?? '';
    if (raw.isEmpty || raw == '0000-00-00') {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  @override
  Widget build(BuildContext context) {
    final originalName = detailData?['name']?.toString() ?? widget.initialName;
    final cnName = detailData?['name_cn']?.toString() ?? widget.initialName;
    final displayName = cnName.isEmpty ? originalName : cnName;
    final imageUrl = detailData?['images']?['large']?.toString() ?? '';

    final theme = Theme.of(context);
    final Color highlightOrange = const Color(0xFFFF9F0A);
    final Color highlightBlue = theme.colorScheme.primary;
    final double topInset = MediaQuery.paddingOf(context).top;
    final SystemUiOverlayStyle overlayStyle =
        theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: theme.colorScheme.surface,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: theme.colorScheme.surface,
          );

    _scheduleHeroHeaderMeasure();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Stack(
                      key: _heroHeaderKey,
                      children: [
                        if (imageUrl.isNotEmpty)
                          Positioned.fill(
                            child: _buildSafeImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: <Color>[
                                    highlightBlue.withValues(alpha: 0.18),
                                    highlightOrange.withValues(alpha: 0.14),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (imageUrl.isNotEmpty)
                          Positioned.fill(
                            child: ClipRect(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 25,
                                  sigmaY: 25,
                                ),
                                child: Container(
                                  color: theme.scaffoldBackgroundColor
                                      .withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          top: topInset + 12,
                          left: 4,
                          child: IconButton(
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).backButtonTooltip,
                            onPressed: () => Navigator.maybePop(context),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(
                                alpha: 0.18,
                              ),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            topInset + kToolbarHeight + 10,
                            16,
                            20,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _buildSafeImage(
                                  imageUrl: imageUrl,
                                  width: 105,
                                  height: 150,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        height: 1.2,
                                      ),
                                    ),
                                    if (originalName.isNotEmpty &&
                                        originalName != displayName)
                                      Text(
                                        originalName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.star_rounded,
                                          color: Colors.orange,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${detailData?['rating']?['score'] ?? '暂无评分'}',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: highlightOrange,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '首播: ${_formatAirDate()}\n状态: ${_broadcastStatusText()}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                        height: 1.5,
                                      ),
                                    ),
                                    if (detailData?['tags'] is List)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8.0,
                                        ),
                                        child: Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: (detailData!['tags'] as List)
                                              .take(5)
                                              .map((tag) {
                                                String tagName = tag is Map
                                                    ? tag['name']?.toString() ??
                                                          ''
                                                    : tag.toString();
                                                return InkWell(
                                                  onTap: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            CategoryResultPage(
                                                              title:
                                                                  '标签: $tagName',
                                                              searchMode: 'tag',
                                                              query: tagName,
                                                              searchType: widget
                                                                  .subjectType,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: highlightBlue
                                                          .withValues(
                                                            alpha: 0.15,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      border: Border.all(
                                                        color: highlightBlue
                                                            .withValues(
                                                              alpha: 0.3,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      tagName,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: highlightBlue,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              })
                                              .toList(),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SliverAppBarDelegate(
                      TabBar(
                        controller: _tabController,
                        splashFactory: NoSplash.splashFactory,
                        overlayColor: WidgetStateProperty.all<Color>(
                          Colors.transparent,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        indicatorPadding: const EdgeInsets.symmetric(
                          vertical: 4,
                        ),
                        tabs: <Widget>[
                          const Tab(text: '详情'),
                          if (_hasEpisodeTab) const Tab(text: '剧集'),
                          const Tab(text: '进度'),
                          const Tab(text: '吐槽'),
                        ],
                        onTap: _prepareTabSwitch,
                      ),
                      topInset: topInset,
                    ),
                  ),
                  ..._buildActiveTabSlivers(highlightBlue, highlightOrange),
                ],
              ),
        bottomNavigationBar: widget.subjectType == 1
            ? null
            : ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(
                        alpha: theme.brightness == Brightness.dark ? 0.78 : 0.9,
                      ),
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MagnetConfigPage(
                                animeName: displayName,
                                aliases: _extractAliases(cnName, originalName),
                                bangumiSubjectId: widget.animeId,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text(
                            '全网磁力检索',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _buildActiveTabSlivers(
    Color highlightBlue,
    Color highlightOrange,
  ) {
    final int index = _tabController.index;
    if (index == 0) {
      return _withStableTabFooter(<Widget>[_buildDetailsSliver()]);
    }
    if (_hasEpisodeTab && index == 1) {
      return _withStableTabFooter(_buildEpisodesSlivers(highlightBlue));
    }
    if (index == _progressTabIndex) {
      return _withStableTabFooter(<Widget>[
        _buildProgressSliver(highlightBlue, highlightOrange),
      ]);
    }
    if (index == _commentsTabIndex) {
      return _withStableTabFooter(<Widget>[
        _buildCommentsSliver(highlightOrange),
      ]);
    }
    return _withStableTabFooter(<Widget>[
      const SliverToBoxAdapter(child: SizedBox.shrink()),
    ]);
  }

  List<Widget> _withStableTabFooter(List<Widget> slivers) {
    return <Widget>[
      ...slivers,
      SliverToBoxAdapter(child: SizedBox(height: _stableTabFooterExtent)),
    ];
  }

  Widget _buildDetailsSliver() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 16.0,
          bottom: 32.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '剧情简介',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () =>
                  setState(() => isSummaryExpanded = !isSummaryExpanded),
              child: Text(
                detailData?['summary']?.toString() ?? '暂无简介',
                style: const TextStyle(fontSize: 13, height: 1.6),
                maxLines: isSummaryExpanded ? null : 4,
                overflow: isSummaryExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            _buildHorizontalSection('角色', charactersData, true),
            _buildHorizontalSection('制作人员', staffData, false),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalSection(String title, List items, bool isCharacter) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 105,
          child: 
              ListView.builder(
                key: PageStorageKey<String>('detail_${isCharacter ? "characters" : "staff"}'),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                itemBuilder: (ctx, i) {
              final item = items[i];
              return InkWell(
                onTap: () => _handlePersonTap(item, isCharacter),
                child: Container(
                  width: 65,
                  margin: const EdgeInsets.only(right: 8.0),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: ClipOval(
                          child: Container(
                            color: Colors.grey.withValues(alpha: 0.1),
                            child: _buildSafeImage(
                              imageUrl: item['images']?['grid'] ?? '',
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorWidget: const Center(
                                child: Icon(
                                  Icons.person,
                                  color: Colors.grey,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item['name'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildEpisodesSlivers(Color highlightBlue) {
    if (!hasRequestedEpisodes && !isEpisodesLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !hasRequestedEpisodes && !isEpisodesLoading) {
          unawaited(_loadEpisodes());
        }
      });
    }

    if (isEpisodesLoading) {
      return <Widget>[
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }

    if (episodesData.isEmpty) {
      return <Widget>[
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const <Widget>[
                  Icon(Icons.videocam_off_rounded, size: 36, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('暂无剧集数据。', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    final bool useChunking = _allEpisodes.length > _episodeChunkSize;
    final int chunkStart = _currentChunkIndex * _episodeChunkSize + 1;
    final int displayEnd = ((_currentChunkIndex + 1) * _episodeChunkSize).clamp(
      0,
      _allEpisodes.length,
    );

    // ── Short series (≤100): simple dense list, no chunking ──
    if (!useChunking) {
      return <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          sliver: SliverList.separated(
            itemCount: episodesData.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 6),
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> episode = episodesData[index];
              final int epNum = _episodeNumber(episode);
              final bool watched = epNum > 0 && epNum <= currentEp;
              return Card(
                elevation: 0,
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: watched
                        ? Colors.green.withValues(alpha: 0.16)
                        : highlightBlue.withValues(alpha: 0.12),
                    child: Text(
                      epNum > 0 ? '$epNum' : '?',
                      style: TextStyle(
                        fontSize: 13,
                        color: watched ? Colors.green.shade700 : highlightBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    _episodeTitle(episode),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    _episodeMeta(episode),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () => _openEpisodeWatchPage(episode),
                ),
              );
            },
          ),
        ),
      ];
    }

    // ── Long series (>100): separate selector header + grid ──
    final double screenWidth = MediaQuery.of(context).size.width;
    final int cols = screenWidth >= 720 ? 5 : (screenWidth >= 480 ? 4 : 3);

    return <Widget>[
      // ── Chunk selector (fixed above the grid) ──
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: 36,
                child: ListView.separated(
                  key: const PageStorageKey<String>('detail_episode_chunks'),
                  scrollDirection: Axis.horizontal,
                  itemCount: _episodeChunks.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(width: 6),
                  itemBuilder: (BuildContext context, int chunkIdx) {
                    final int start = chunkIdx * _episodeChunkSize + 1;
                    final int end = ((chunkIdx + 1) * _episodeChunkSize).clamp(
                      0,
                      _allEpisodes.length,
                    );
                    return ChoiceChip(
                      selected: _currentChunkIndex == chunkIdx,
                      label: Text('$start-$end'),
                      labelStyle: const TextStyle(fontSize: 12),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) {
                        setState(() {
                          _currentChunkIndex = chunkIdx;
                          episodesData = _episodeChunks[chunkIdx];
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$chunkStart–$displayEnd / ${_allEpisodes.length} 话',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),

      // ── Episode grid ──
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.78,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          delegate: SliverChildBuilderDelegate((
            BuildContext context,
            int index,
          ) {
            if (index >= episodesData.length) return const SizedBox.shrink();
            final Map<String, dynamic> episode = episodesData[index];
            final int epNum = _episodeNumber(episode);
            return ValueListenableBuilder<Set<int>>(
              valueListenable: _watchedEpisodeIds,
              builder:
                  (BuildContext context, Set<int> watchedIds, Widget? child) {
                    final bool watched =
                        (epNum > 0 && epNum <= currentEp) ||
                        watchedIds.contains(episodeId(episode));
                    return Card(
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _openEpisodeWatchPage(episode),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Container(
                                constraints: const BoxConstraints(minWidth: 32),
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: watched
                                      ? Colors.green.withValues(alpha: 0.16)
                                      : highlightBlue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  epNum > 0 ? '$epNum' : '?',
                                  style: TextStyle(
                                    fontSize: epNum >= 1000
                                        ? 11
                                        : (epNum >= 100 ? 14 : 16),
                                    fontWeight: FontWeight.w800,
                                    color: watched
                                        ? Colors.green.shade700
                                        : highlightBlue,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Text(
                                  _episodeTitle(episode),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              Text(
                                episode['airdate']?.toString().isNotEmpty ==
                                        true
                                    ? episode['airdate'].toString()
                                    : '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
            );
          }, childCount: episodesData.length),
        ),
      ),
    ];
  }

  Future<void> _openEpisodeWatchPage(Map<String, dynamic> episode) async {
    maybeHaptic(context);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (BuildContext context) => EpisodeWatchPage(
          animeId: widget.animeId,
          initialName: widget.initialName,
          detailData: detailData,
          episodes: episodesData,
          initialEpisode: episode,
          currentProgress: currentEp,
          onSetProgress: _setProgressToEpisode,
        ),
      ),
    );
  }

  int _episodeNumber(Map<String, dynamic> episode) => episodeNumber(episode);

  String _episodeTitle(Map<String, dynamic> episode) => episodeTitle(episode);

  String _episodeMeta(Map<String, dynamic> episode) {
    final List<String> parts = <String>[
      if ((episode['airdate']?.toString().trim() ?? '').isNotEmpty)
        '放送 ${episode['airdate']}',
      if ((episode['duration']?.toString().trim() ?? '').isNotEmpty)
        episode['duration'].toString(),
      if ((episode['desc']?.toString().trim() ?? '').isNotEmpty)
        episode['desc'].toString(),
    ];
    return parts.isEmpty ? '点击查看集名与讨论' : parts.join('  ·  ');
  }

  Future<void> _setProgressToEpisode(int episodeNumber) async {
    // ── Epic 1: local-only refresh via ValueNotifier ──
    currentEp = episodeNumber;
    if (currentStatus == '未收藏') {
      setState(() => currentStatus = '在看');
    } else {
      // Notify only episode cards to rebuild for watched-state visual update.
      _watchedEpisodeIds.value = <int>{..._watchedEpisodeIds.value};
    }
    await _syncToCloud();
  }

  Widget _buildProgressSliver(Color highlightBlue, Color highlightOrange) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildDropdownRow(
                  '更新状态:',
                  Icons.rocket_launch,
                  highlightBlue,
                  ['未收藏', '想看', '看过', '在看', '搁置', '抛弃'],
                  currentStatus,
                  (v) => setState(() => currentStatus = v!),
                ),
                const SizedBox(height: 12),
                _buildDropdownRow(
                  '打分:',
                  Icons.star,
                  highlightOrange,
                  rateOptions,
                  currentRate,
                  (v) => setState(() => currentRate = v!),
                ),
                const Divider(height: 24),
                if (widget.subjectType == 1)
                  _buildProgressAdjuster(
                    '看到第几卷',
                    currentVol,
                    () => setState(() => currentVol--),
                    () => setState(() => currentVol++),
                  ),
                _buildProgressAdjuster(
                  '看到第几${widget.subjectType == 1 ? '话' : '集'}',
                  currentEp,
                  () => setState(() => currentEp--),
                  () => setState(() => currentEp++),
                ),
                TextField(
                  controller: commentController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: '写句短评...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: isSyncing ? null : _syncToCloud,
                    icon: isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(
                      isSyncing ? '同步中...' : '保存进度并同步云端',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommentsSliver(Color highlightOrange) {
    if (!hasRequestedComments && !isCommentsLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !hasRequestedComments && !isCommentsLoading) {
          unawaited(_loadComments());
        }
      });
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (isCommentsLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (realComments.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  commentsErrorMessage != null && commentsErrorMessage != '暂无评论'
                      ? Icons.cloud_off_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 40,
                  color: Colors.grey,
                ),
                const SizedBox(height: 12),
                Text(
                  commentsErrorMessage ?? AppStrings.noComments,
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                if (commentsErrorMessage != null && commentsErrorMessage != '暂无评论') ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      hasRequestedComments = false;
                      _loadComments();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(AppStrings.retry),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index.isOdd) return const Divider();
          final c = realComments[index ~/ 2];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c['author']!,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    c['rate']!,
                    style: TextStyle(color: highlightOrange, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                c['content']!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  height: 1.4,
                ),
              ),
            ],
          );
        }, childCount: realComments.length * 2 - 1),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final double topInset;
  _SliverAppBarDelegate(this.tabBar, {required this.topInset});

  @override
  double get minExtent => tabBar.preferredSize.height + topInset;

  @override
  double get maxExtent => tabBar.preferredSize.height + topInset;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final ThemeData theme = Theme.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          alignment: Alignment.bottomCenter,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                theme.colorScheme.surface.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.70 : 0.76,
                ),
                theme.colorScheme.surface.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.86 : 0.92,
                ),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(top: topInset),
            child: tabBar,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SliverAppBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar || oldDelegate.topInset != topInset;
  }
}
