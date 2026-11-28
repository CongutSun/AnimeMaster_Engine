import '../widgets/app_feedback.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../api/bangumi_api.dart';
import '../models/anime.dart';
import '../widgets/anime_card.dart';
import 'detail_page.dart';
import '../widgets/rss_inbox_entry_point.dart';

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
  int _loadGeneration = 0;
  String? _loadError;
  int? _nextOffset;
  bool _loadingMore = false;
  final Set<int> _updatingIds = <int>{};

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
    if (provider.isLoaded &&
        (provider.bgmAcc != _lastLoadedAcc || _loadGeneration == 0)) {
      _lastLoadedAcc = provider.bgmAcc;
      if (_lastLoadedAcc.isNotEmpty) {
        _loadCollection();
      } else {
        _loadGeneration++;
        setState(() {
          isLoading = false;
          collectionList = [];
        });
      }
    }
  }

  Future<void> _loadCollection({bool more = false}) async {
    if (!mounted ||
        (more && (isLoading || _loadingMore || _nextOffset == null))) {
      return;
    }
    final generation = ++_loadGeneration;
    final settings = context.read<SettingsProvider>();
    final username = settings.bgmAcc;
    final offset = more ? _nextOffset! : 0;
    final type = currentType;
    final subjectType = currentSubjectType;
    setState(() {
      if (!more) {
        collectionList = [];
        _nextOffset = null;
      }
      isLoading = !more;
      _loadingMore = more;
      _loadError = null;
    });
    bool current() =>
        mounted && generation == _loadGeneration && settings.bgmAcc == username;
    try {
      await settings.ensureBangumiAccessToken();
      if (!current()) return;
      final page = await BangumiApi.instance.getUserCollectionPage(
        username,
        offset: offset,
        type: type,
        subjectType: subjectType,
        token: settings.bgmToken,
      );
      if (!current()) return;
      final seen = collectionList.map((a) => a.id).toSet();
      final additions = page.items
          .map((e) => Anime.fromJson(e))
          .where((anime) => seen.add(anime.id))
          .toList();
      if (page.nextOffset != null && additions.isEmpty) {
        throw StateError('重复收藏分页');
      }
      setState(() {
        collectionList.addAll(additions);
        _nextOffset = page.nextOffset;
      });
    } catch (_) {
      if (current()) {
        setState(
          () => _loadError = more ? '下一页加载失败，点击重试。' : '收藏加载失败，请检查网络后重试。',
        );
      }
    } finally {
      if (current()) {
        setState(() {
          isLoading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _directAddEp(int subjectId) async {
    if (!_updatingIds.add(subjectId)) return;
    setState(() {});
    try {
      final SettingsProvider settings = Provider.of<SettingsProvider>(
        context,
        listen: false,
      );
      final account = settings.bgmAcc;
      await settings.ensureBangumiAccessToken();
      if (!mounted || settings.bgmAcc != account) {
        return;
      }
      final String token = settings.bgmToken;

      if (token.isEmpty) {
        AppFeedback.show(
          context,
          const SnackBar(content: Text('缺少 Token，请先在设置中配置！')),
        );
        return;
      }

      final index = collectionList.indexWhere((item) => item.id == subjectId);
      if (index < 0) return;
      final anime = collectionList[index];
      int currentEp = anime.epStatus;
      int totalEp = anime.eps;

      if (totalEp > 0 && currentEp >= totalEp) {
        AppFeedback.show(context, const SnackBar(content: Text('已经看完啦！')));
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

      if (!mounted || settings.bgmAcc != account) return;

      if (success) {
        AppFeedback.show(
          context,
          SnackBar(
            content: Text('✅ 《${anime.displayName}》 进度已更新为 ${currentEp + 1}'),
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        // 失败回滚：把旧的数据还原回去
        setState(() {
          final rollbackIndex = collectionList.indexWhere(
            (item) => item.id == subjectId,
          );
          if (rollbackIndex >= 0) collectionList[rollbackIndex] = anime;
        });
        AppFeedback.show(
          context,
          const SnackBar(
            content: Text('❌ 同步失败，请检查网络！'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        AppFeedback.show(context, const SnackBar(content: Text('同步失败，请重试。')));
      }
    } finally {
      if (mounted) await _loadCollection();
      _updatingIds.remove(subjectId);
      if (mounted) setState(() {});
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
      await _loadCollection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SettingsProvider>(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: RssInboxEntryPoint()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 2, label: Text('番剧')),
                      ButtonSegment(value: 1, label: Text('书籍')),
                    ],
                    selected: {currentSubjectType},
                    onSelectionChanged: (v) {
                      setState(() => currentSubjectType = v.first);
                      _loadCollection();
                    },
                  ),
                  DropdownButton<int>(
                    value: currentType,
                    items: typeMap.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value.split(' ').first),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => currentType = v);
                        _loadCollection();
                      }
                    },
                  ),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _loadCollection,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
          ),
          if (isLoading || provider.bgmAcc.isEmpty || collectionList.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: isLoading
                    ? const CircularProgressIndicator()
                    : provider.bgmAcc.isEmpty
                    ? const Text('登录 Bangumi 后可查看收藏')
                    : _loadError == null
                    ? const Text('这个分类下还没有收藏')
                    : TextButton(
                        onPressed: _loadCollection,
                        child: Text(_loadError!),
                      ),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context);
                  final minWidth = 108 * (scale.scale(16) / 16).clamp(1.0, 2.0);
                  final count =
                      ((constraints.crossAxisExtent + 12) / (minWidth + 12))
                          .floor()
                          .clamp(1, 8);
                  final width =
                      (constraints.crossAxisExtent - (count - 1) * 12) / count;
                  return SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      mainAxisExtent:
                          width * 1.5 +
                          scale.scale(16) * 2.8 +
                          scale.scale(14) * 3.4 +
                          82,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: collectionList.length,
                    itemBuilder: (context, i) {
                      final anime = collectionList[i];
                      final book = currentSubjectType == 1;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimeCard(
                            anime: anime,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DetailPage(
                                    animeId: anime.id,
                                    initialName: anime.displayName,
                                    subjectType: currentSubjectType,
                                  ),
                                ),
                              );
                              if (mounted) await _loadCollection();
                            },
                          ),
                          Text(
                            '${anime.epStatus} / ${anime.eps > 0 ? anime.eps : '?'} ${book ? '话' : '集'}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (book || currentType == 3)
                            TextButton(
                              onPressed: book
                                  ? () => _showUpdateBottomSheet(context, anime)
                                  : _updatingIds.contains(anime.id) ||
                                        (anime.eps > 0 &&
                                            anime.epStatus >= anime.eps)
                                  ? null
                                  : () => _directAddEp(anime.id),
                              child: Text(book ? '快捷更新' : '看完+1'),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            if (_nextOffset != null)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: _loadingMore
                      ? null
                      : () => _loadCollection(more: true),
                  child: Text(_loadingMore ? '正在加载…' : _loadError ?? '加载更多'),
                ),
              ),
          ],
        ],
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
      AppFeedback.show(
        context,
        const SnackBar(
          content: Text('✅ 进度同步成功！'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } else {
      AppFeedback.show(
        context,
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
