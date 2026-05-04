import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../api/bangumi_api.dart';
import '../models/anime.dart';
import 'detail_page.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  List<Anime> collectionList = [];
  bool isLoading = true;

  int currentType = 3;
  int currentSubjectType = 2;
  String _lastLoadedAcc = '';

  final Map<int, String> typeMap = {
    1: '想看 (Wish)',
    2: '看过 (Collect)',
    3: '在看 (Do)',
    4: '搁置 (On_hold)',
    5: '抛弃 (Dropped)',
  };

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<SettingsProvider>(context);
    if (provider.isLoaded && provider.bgmAcc != _lastLoadedAcc) {
      _lastLoadedAcc = provider.bgmAcc;
      if (_lastLoadedAcc.isNotEmpty) {
        _loadCollection();
      } else {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadCollection() async {
    setState(() => isLoading = true);

    final username = Provider.of<SettingsProvider>(
      context,
      listen: false,
    ).bgmAcc;

    if (username.isNotEmpty) {
      final rawResults = await BangumiApi.instance.getUserCollectionList(
        username,
        type: currentType,
        subjectType: currentSubjectType,
      );
      if (mounted) {
        setState(() {
          collectionList = rawResults.map((e) => Anime.fromJson(e)).toList();
        });
      }
    }
    if (mounted) setState(() => isLoading = false);
  }

  // ✨ 核心修复：番剧专属的直通更新（结合了你原本创建新实例来规避 final 报错的优秀写法）
  Future<void> _directAddEp(int index) async {
    final SettingsProvider settings = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    await settings.ensureBangumiAccessToken();
    if (!mounted) {
      return;
    }
    final String token = settings.bgmToken;

    if (token.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缺少 Token，请先在设置中配置！')));
      return;
    }

    final anime = collectionList[index];
    int currentEp = anime.epStatus;
    int totalEp = anime.eps;

    if (totalEp > 0 && currentEp >= totalEp) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已经看完啦！')));
      return;
    }

    setState(() {
      collectionList[index] = Anime(
        id: anime.id,
        name: anime.name,
        nameCn: anime.nameCn,
        imageUrl: anime.imageUrl,
        score: anime.score,
        eps: anime.eps,
        epStatus: currentEp + 1,
      );
    });

    bool success = await BangumiApi.instance.updateEpisodeStatus(
      anime.id,
      token,
      currentEp + 1,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 《${anime.displayName}》 进度已更新为 ${currentEp + 1}'),
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      // 失败回滚：把旧的数据还原回去
      setState(() {
        collectionList[index] = anime;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ 同步失败，请检查网络！'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showUpdateBottomSheet(BuildContext context, Anime anime) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UpdateProgressSheet(
        animeId: anime.id,
        animeName: anime.displayName,
        subjectType: currentSubjectType,
      ),
    );

    if (result == true) {
      _loadCollection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SettingsProvider>(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(
          fontFamily: 'Microsoft YaHei',
          fontFamilyFallback: ['PingFang SC', 'sans-serif'],
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            '我的二次元库',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          centerTitle: false,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(
                    value: 2,
                    icon: Icon(Icons.tv_rounded, size: 16),
                    label: Text('番剧'),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    icon: Icon(Icons.menu_book_rounded, size: 16),
                    label: Text('书籍'),
                  ),
                ],
                selected: <int>{currentSubjectType},
                onSelectionChanged: (Set<int> value) {
                  setState(() => currentSubjectType = value.first);
                  _loadCollection();
                },
              ),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        currentSubjectType == 2 ? '追番库' : '书库',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          border: Border.all(color: colors.outlineVariant),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: currentType,
                            borderRadius: BorderRadius.circular(18),
                            dropdownColor: colors.surface,
                            menuMaxHeight: 320,
                            items: typeMap.entries.map((e) {
                              return DropdownMenuItem<int>(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => currentType = val);
                                _loadCollection();
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 38,
                        child: IconButton.filledTonal(
                          tooltip: '刷新',
                          onPressed: _loadCollection,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '点击标题可查看详情或去下载',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : provider.bgmAcc.isEmpty
                  ? const Center(
                      child: Text(
                        '请先在设置中配置 Bgm 账号 🥲',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : collectionList.isEmpty
                  ? const Center(
                      child: Text(
                        '这个状态下空空如也~',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: collectionList.length,
                      itemBuilder: (context, index) {
                        final anime = collectionList[index];
                        String totalEpStr = anime.eps > 0
                            ? anime.eps.toString()
                            : '?';

                        final double progress = anime.eps > 0
                            ? anime.epStatus / anime.eps
                            : 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12.0),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: colors.outlineVariant),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: theme.brightness == Brightness.dark
                                      ? 0.18
                                      : 0.04,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => DetailPage(
                                            animeId: anime.id,
                                            initialName: anime.displayName,
                                            subjectType: currentSubjectType,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      anime.displayName,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: colors.primary,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            currentSubjectType == 2
                                                ? '放送进度 ${anime.epStatus} / $totalEpStr 集'
                                                : '阅读进度 ${anime.epStatus} / $totalEpStr 话(卷)',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ),
                                          if (anime.eps > 0) ...<Widget>[
                                            const SizedBox(height: 8),
                                            LinearProgressIndicator(
                                              value: progress
                                                  .clamp(0.0, 1.0)
                                                  .toDouble(),
                                              minHeight: 5,
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

                                    // ✨ UI 判断：书籍弹出弹窗，番剧直通+1
                                    if (currentSubjectType == 1) ...[
                                      SizedBox(
                                        height: 32,
                                        child: FilledButton.tonalIcon(
                                          onPressed: () =>
                                              _showUpdateBottomSheet(
                                                context,
                                                anime,
                                              ),
                                          icon: const Icon(
                                            Icons.edit_note,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            '快捷更新',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ] else if (currentSubjectType == 2 &&
                                        currentType == 3) ...[
                                      SizedBox(
                                        height: 32,
                                        child: FilledButton.icon(
                                          onPressed:
                                              (anime.eps > 0 &&
                                                  anime.epStatus >= anime.eps)
                                              ? null
                                              : () => _directAddEp(index),
                                          icon: const Icon(
                                            Icons.done_rounded,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            '看完+1',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateProgressSheet extends StatefulWidget {
  final int animeId;
  final String animeName;
  final int subjectType;

  const _UpdateProgressSheet({
    required this.animeId,
    required this.animeName,
    required this.subjectType,
  });

  @override
  State<_UpdateProgressSheet> createState() => _UpdateProgressSheetState();
}

class _UpdateProgressSheetState extends State<_UpdateProgressSheet> {
  bool isLoading = true;
  bool isSyncing = false;

  int currentEp = 0;
  int currentVol = 0;

  dynamic existingType;
  dynamic existingRate;
  dynamic existingComment;

  @override
  void initState() {
    super.initState();
    _fetchCurrentStatus();
  }

  Future<void> _fetchCurrentStatus() async {
    final provider = Provider.of<SettingsProvider>(context, listen: false);
    await provider.ensureBangumiAccessToken();
    final collectionData = await BangumiApi.instance.getUserCollection(
      widget.animeId,
      provider.bgmAcc,
      provider.bgmToken,
    );

    if (mounted) {
      if (collectionData != null) {
        setState(() {
          currentEp = collectionData['ep_status'] ?? 0;
          currentVol = collectionData['vol_status'] ?? 0;
          existingType = collectionData['type'];
          existingRate = collectionData['rate'];
          existingComment = collectionData['comment'];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _syncProgress() async {
    final SettingsProvider settings = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    await settings.ensureBangumiAccessToken();
    final String token = settings.bgmToken;
    if (token.isEmpty) return;

    setState(() => isSyncing = true);

    Map<String, dynamic> postData = {
      'type': existingType ?? 3,
      'ep_status': currentEp,
    };
    // 严格确保只有书籍才发送卷参数
    if (widget.subjectType == 1) {
      postData['vol_status'] = currentVol;
    }
    if (existingRate != null) postData['rate'] = existingRate;
    if (existingComment != null && existingComment.toString().isNotEmpty) {
      postData['comment'] = existingComment;
    }

    bool success = await BangumiApi.instance.updateCollection(
      widget.animeId,
      token,
      postData,
    );

    if (!mounted) return;

    setState(() => isSyncing = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 进度同步成功！'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ 同步失败，请检查网络。'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildProgressAdjuster({
    required String title,
    required int value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    final ThemeData theme = Theme.of(context);
    final Color primaryIconColor = theme.colorScheme.primary;
    final Color iconColor = theme.colorScheme.primary;

    final minusIconColor = value > 0
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Icon(
            widget.subjectType == 1 ? Icons.menu_book : Icons.ondemand_video,
            color: iconColor,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.remove_circle_outline,
              color: minusIconColor,
              size: 28,
            ),
            onPressed: value > 0 ? onMinus : null,
          ),
          SizedBox(
            width: 48,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.add_circle_outline,
              color: primaryIconColor,
              size: 28,
            ),
            onPressed: onPlus,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '更新进度',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              widget.animeName,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),

            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              )
            else ...[
              if (widget.subjectType == 1) ...[
                _buildProgressAdjuster(
                  title: '当前卷 (Vol)',
                  value: currentVol,
                  onMinus: () => setState(() => currentVol--),
                  onPlus: () => setState(() => currentVol++),
                ),
                _buildProgressAdjuster(
                  title: '当前话 (Chap)',
                  value: currentEp,
                  onMinus: () => setState(() => currentEp--),
                  onPlus: () => setState(() => currentEp++),
                ),
              ] else ...[
                _buildProgressAdjuster(
                  title: '当前集数 (Ep)',
                  value: currentEp,
                  onMinus: () => setState(() => currentEp--),
                  onPlus: () => setState(() => currentEp++),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: isSyncing ? null : _syncProgress,
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
                    isSyncing ? '同步中...' : '保存进度',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
