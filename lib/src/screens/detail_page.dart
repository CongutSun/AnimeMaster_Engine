import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/settings_provider.dart';
import '../api/bangumi_api.dart';
import 'magnet_config_page.dart';
import 'category_result_page.dart';
import 'episode_watch_page.dart';
import 'role_subjects_page.dart';
import '../utils/image_request.dart';

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

  String currentStatus = '未收藏';
  String currentRate = '暂不打分';
  int currentEp = 0;
  int currentVol = 0;

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
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadTabDataIfNeeded(_tabController.index);
      }
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAllData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    commentController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    final provider = Provider.of<SettingsProvider>(context, listen: false);
    final Future<Map<String, dynamic>?> detailFuture =
        BangumiApi.getAnimeDetail(widget.animeId);
    final Future<Map<String, dynamic>?> collectionFuture = () async {
      await provider.ensureBangumiAccessToken();
      final String bgmUsername = provider.bgmAcc;
      final String bgmToken = provider.bgmToken;
      if (bgmUsername.isEmpty || bgmToken.isEmpty) {
        return null;
      }
      return BangumiApi.getUserCollection(
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
    if (index == 1 && !hasRequestedEpisodes && !isEpisodesLoading) {
      unawaited(_loadEpisodes());
    }
    if (index == 3 && !hasRequestedComments && !isCommentsLoading) {
      unawaited(_loadComments());
    }
  }

  Future<void> _loadSupplementaryData() async {
    unawaited(
      BangumiApi.getSubjectCharacters(widget.animeId).then((
        List<dynamic> data,
      ) {
        if (mounted) {
          setState(() => charactersData = data);
        }
      }),
    );
    unawaited(
      BangumiApi.getSubjectPersons(widget.animeId).then((List<dynamic> data) {
        if (mounted) {
          setState(() => staffData = data);
        }
      }),
    );
    unawaited(
      BangumiApi.getSubjectRelations(widget.animeId).then((List<dynamic> data) {
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
    });
    final List<Map<String, String>> comments =
        await BangumiApi.getSubjectComments(widget.animeId);

    if (!mounted) {
      return;
    }

    setState(() {
      realComments = comments;
      isCommentsLoading = false;
    });
  }

  Future<void> _loadEpisodes() async {
    setState(() {
      hasRequestedEpisodes = true;
      isEpisodesLoading = true;
    });
    final List<Map<String, dynamic>> episodes =
        await BangumiApi.getSubjectEpisodes(widget.animeId);

    if (!mounted) {
      return;
    }

    setState(() {
      episodesData = episodes;
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

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            '选择查看对象',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (id != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RoleSubjectsPage(
                        id: id,
                        name: name,
                        isCharacter: true,
                      ),
                    ),
                  );
                }
              },
              child: Text('角色: $name'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
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
              child: Text('声优: $actorName'),
            ),
          ],
        ),
      );
    } else {
      if (id != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                RoleSubjectsPage(id: id, name: name, isCharacter: isCharacter),
          ),
        );
      }
    }
  }

  Future<void> _syncToCloud() async {
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

    bool collectionSuccess = await BangumiApi.updateCollection(
      widget.animeId,
      bgmToken,
      postData,
    );
    bool episodeSuccess = widget.subjectType != 1 && collectionSuccess
        ? await BangumiApi.updateEpisodeStatus(
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
    Set<String> aliases = {
      if (cnName.isNotEmpty) cnName,
      if (originalName.isNotEmpty) originalName,
    };
    if (detailData?['infobox'] is List) {
      for (var item in detailData!['infobox']) {
        if (item is Map && item['key'] == '别名') {
          if (item['value'] is List) {
            aliases.addAll(
              (item['value'] as List).whereType<Map>().map(
                (v) => v['v'].toString(),
              ),
            );
          } else if (item['value'] is String) {
            aliases.add(item['value'].toString());
          }
        }
      }
    }
    return aliases.where((e) => e.trim().isNotEmpty).toList();
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
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
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
      ],
    );
  }

  Widget _buildProgressAdjuster(
    String title,
    int value,
    VoidCallback onMinus,
    VoidCallback onPlus,
  ) {
    final primaryColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.blueAccent.shade100
        : Colors.blueAccent.shade700;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(
            widget.subjectType == 1 ? Icons.menu_book : Icons.ondemand_video,
            color: Colors.green.shade500,
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

  @override
  Widget build(BuildContext context) {
    final originalName = detailData?['name']?.toString() ?? widget.initialName;
    final cnName = detailData?['name_cn']?.toString() ?? widget.initialName;
    final displayName = cnName.isEmpty ? originalName : cnName;
    final imageUrl = detailData?['images']?['large']?.toString() ?? '';

    final theme = Theme.of(context);
    final highlightOrange = theme.brightness == Brightness.dark
        ? Colors.orangeAccent.shade100
        : Colors.orange.shade700;
    final highlightBlue = theme.brightness == Brightness.dark
        ? Colors.blueAccent.shade100
        : Colors.blueAccent.shade700;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      if (imageUrl.isNotEmpty)
                        Positioned.fill(
                          child: _buildSafeImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                      if (imageUrl.isNotEmpty)
                        Positioned.fill(
                          child: ClipRect(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                              child: Container(
                                color: theme.scaffoldBackgroundColor.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          MediaQuery.of(context).padding.top +
                              kToolbarHeight +
                              10,
                          16,
                          20,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
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
                                    '首播: ${detailData?['date'] ?? '未知'}\n状态: 已出 ${detailData?['eps'] ?? '?'} ${widget.subjectType == 2 ? '集' : '卷/话'}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                      height: 1.5,
                                    ),
                                  ),
                                  if (detailData?['tags'] is List)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
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
                      labelColor: theme.brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                      indicatorColor: theme.brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                      tabs: const [
                        Tab(text: '详情'),
                        Tab(text: '剧集'),
                        Tab(text: '进度'),
                        Tab(text: '吐槽'),
                      ],
                    ),
                  ),
                ),
                _buildActiveTabSliver(highlightBlue, highlightOrange),
              ],
            ),
      bottomNavigationBar: widget.subjectType == 1
          ? null
          : Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom > 0
                    ? MediaQuery.of(context).padding.bottom
                    : 12.0,
                left: 16.0,
                right: 16.0,
                top: 12.0,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
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
                  icon: const Icon(Icons.download_rounded, color: Colors.white),
                  label: const Text(
                    '全网磁力检索',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildActiveTabSliver(Color highlightBlue, Color highlightOrange) {
    switch (_tabController.index) {
      case 0:
        return _buildDetailsSliver();
      case 1:
        return _buildEpisodesSliver(highlightBlue);
      case 2:
        return _buildProgressSliver(highlightBlue, highlightOrange);
      case 3:
        return _buildCommentsSliver(highlightOrange);
      default:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
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
          child: ListView.builder(
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

  Widget _buildEpisodesSliver(Color highlightBlue) {
    if (!hasRequestedEpisodes && !isEpisodesLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !hasRequestedEpisodes && !isEpisodesLoading) {
          unawaited(_loadEpisodes());
        }
      });
    }

    if (isEpisodesLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (episodesData.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(
            child: Text('暂无剧集数据。', style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      sliver: SliverList.separated(
        itemCount: episodesData.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) {
          final Map<String, dynamic> episode = episodesData[index];
          final int episodeNumber = _episodeNumber(episode);
          final bool watched = episodeNumber > 0 && episodeNumber <= currentEp;
          return Card(
            elevation: 0,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: watched
                    ? Colors.green.withValues(alpha: 0.16)
                    : highlightBlue.withValues(alpha: 0.12),
                child: Text(
                  episodeNumber > 0 ? '$episodeNumber' : '?',
                  style: TextStyle(
                    color: watched ? Colors.green.shade700 : highlightBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(
                _episodeTitle(episode),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _episodeMeta(episode),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openEpisodeWatchPage(episode),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEpisodeWatchPage(Map<String, dynamic> episode) async {
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

  int _episodeNumber(Map<String, dynamic> episode) {
    final dynamic ep = episode['ep'] ?? episode['sort'];
    if (ep is int) {
      return ep;
    }
    if (ep is num) {
      return ep.round();
    }
    return int.tryParse(ep?.toString() ?? '') ?? 0;
  }

  String _episodeTitle(Map<String, dynamic> episode) {
    final int number = _episodeNumber(episode);
    final String nameCn = episode['name_cn']?.toString().trim() ?? '';
    final String name = episode['name']?.toString().trim() ?? '';
    final String title = nameCn.isNotEmpty ? nameCn : name;
    if (title.isEmpty) {
      return number > 0 ? '第 $number 集' : '未命名剧集';
    }
    return number > 0 ? '第 $number 集  $title' : title;
  }

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
    setState(() {
      currentEp = episodeNumber;
      if (currentStatus == '未收藏') {
        currentStatus = '在看';
      }
    });
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
                      backgroundColor: Colors.orange.shade700,
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
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(
            child: Text('暂无评论或加载失败', style: TextStyle(color: Colors.grey)),
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
  _SliverAppBarDelegate(this.tabBar);
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: tabBar,
  );
  @override
  bool shouldRebuild(covariant _SliverAppBarDelegate oldDelegate) => false;
}
