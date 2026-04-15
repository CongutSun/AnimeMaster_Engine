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
    5: '抛弃 (Dropped)'
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
    
    final username = Provider.of<SettingsProvider>(context, listen: false).bgmAcc;

    if (username.isNotEmpty) {
      final rawResults = await BangumiApi.getUserCollectionList(username, type: currentType, subjectType: currentSubjectType);
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
    final token = Provider.of<SettingsProvider>(context, listen: false).bgmToken;

    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('缺少 Token，请先在设置中配置！')));
      return;
    }

    final anime = collectionList[index];
    int currentEp = anime.epStatus;
    int totalEp = anime.eps;

    if (totalEp > 0 && currentEp >= totalEp) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已经看完啦！')));
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

    bool success = await BangumiApi.updateEpisodeStatus(anime.id, token, currentEp + 1);
    
    if (!mounted) return; 

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ 《${anime.displayName}》 进度已更新为 ${currentEp + 1}'), duration: const Duration(seconds: 1)),
      );
    } else {
      // 失败回滚：把旧的数据还原回去
      setState(() {
        collectionList[index] = anime;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ 同步失败，请检查网络！'), backgroundColor: Colors.red));
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

    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(
          fontFamily: 'Microsoft YaHei',
          fontFamilyFallback: ['PingFang SC', 'sans-serif'],
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的二次元库', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Microsoft YaHei')),
          elevation: 1,
          centerTitle: false,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: ToggleButtons(
                constraints: const BoxConstraints(minHeight: 32, minWidth: 60),
                borderRadius: BorderRadius.circular(8),
                isSelected: [currentSubjectType == 2, currentSubjectType == 1],
                onPressed: (index) {
                  setState(() => currentSubjectType = index == 0 ? 2 : 1);
                  _loadCollection();
                },
                children: const [Text('📺 番剧', style: TextStyle(fontSize: 12)), Text('📚 书籍', style: TextStyle(fontSize: 12))],
              ),
            )
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: theme.cardColor, 
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(currentSubjectType == 2 ? '追番库' : '书库', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(4)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: currentType,
                            items: typeMap.entries.map((e) {
                              return DropdownMenuItem<int>(
                                value: e.key,
                                child: Text(e.value, style: const TextStyle(fontSize: 13, fontFamily: 'Microsoft YaHei')),
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
                        height: 32,
                        child: ElevatedButton.icon(
                          onPressed: _loadCollection,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('刷新', style: TextStyle(fontFamily: 'Microsoft YaHei')),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('💡 提示: 点击标题可查看详情或去下载。', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: theme.dividerColor), 
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : provider.bgmAcc.isEmpty 
                      ? const Center(child: Text('请先在设置中配置 Bgm 账号 🥲', style: TextStyle(color: Colors.grey)))
                      : collectionList.isEmpty
                          ? const Center(child: Text('这个状态下空空如也~', style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16.0),
                              itemCount: collectionList.length,
                              itemBuilder: (context, index) {
                                final anime = collectionList[index];
                                String totalEpStr = anime.eps > 0 ? anime.eps.toString() : '?';

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12.0),
                                  decoration: BoxDecoration(
                                    color: theme.cardColor, 
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: theme.dividerColor),
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
                                              Navigator.push(context, MaterialPageRoute(builder: (context) => DetailPage(
                                                animeId: anime.id, 
                                                initialName: anime.displayName,
                                                subjectType: currentSubjectType,
                                              )));
                                            },
                                            child: Text(
                                              anime.displayName,
                                              style: TextStyle(
                                                fontSize: 15, 
                                                fontWeight: FontWeight.bold, 
                                                color: Colors.blue.shade500,
                                                height: 1.4, 
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              currentSubjectType == 2 
                                                  ? '放送进度: ${anime.epStatus} / $totalEpStr 集'
                                                  : '阅读进度: ${anime.epStatus} / $totalEpStr 话(卷)',
                                              style: const TextStyle(fontSize: 13), 
                                            ),
                                            
                                            // ✨ UI 判断：书籍弹出弹窗，番剧直通+1
                                            if (currentSubjectType == 1) ...[
                                              SizedBox(
                                                height: 32,
                                                child: ElevatedButton.icon(
                                                  onPressed: () => _showUpdateBottomSheet(context, anime),
                                                  icon: const Icon(Icons.edit_note, size: 18),
                                                  label: const Text('快捷更新', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Microsoft YaHei')),
                                                  style: ElevatedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                                    backgroundColor: Colors.orange.shade600,
                                                    foregroundColor: Colors.white,
                                                    elevation: 0,
                                                  ),
                                                ),
                                              ),
                                            ] else if (currentSubjectType == 2 && currentType == 3) ...[
                                              SizedBox(
                                                height: 32,
                                                child: ElevatedButton.icon(
                                                  onPressed: (anime.eps > 0 && anime.epStatus >= anime.eps) ? null : () => _directAddEp(index),
                                                  icon: const Icon(Icons.add, size: 18),
                                                  label: const Text('看完 +1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Microsoft YaHei')),
                                                  style: ElevatedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                                    backgroundColor: Colors.blue.shade600,
                                                    foregroundColor: Colors.white,
                                                    disabledBackgroundColor: Colors.grey.shade600,
                                                    elevation: 0,
                                                  ),
                                                ),
                                              ),
                                            ]
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
    final collectionData = await BangumiApi.getUserCollection(widget.animeId, provider.bgmAcc, provider.bgmToken);
    
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
    final token = Provider.of<SettingsProvider>(context, listen: false).bgmToken;
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

    bool success = await BangumiApi.updateCollection(widget.animeId, token, postData);

    if (!mounted) return;
    
    setState(() => isSyncing = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 进度同步成功！'), backgroundColor: Colors.green));
      Navigator.pop(context, true); 
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ 同步失败，请检查网络。'), backgroundColor: Colors.red));
    }
  }

  Widget _buildProgressAdjuster({required String title, required int value, required VoidCallback onMinus, required VoidCallback onPlus}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryIconColor = isDarkMode ? Colors.blue.shade400 : Theme.of(context).primaryColor;
    final iconColor = isDarkMode ? Colors.green.shade400 : Colors.green;
    
    final minusIconColor = value > 0 
        ? (isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700)
        : (isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Icon(widget.subjectType == 1 ? Icons.menu_book : Icons.ondemand_video, color: iconColor, size: 22),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.remove_circle_outline, color: minusIconColor, size: 28),
            onPressed: value > 0 ? onMinus : null,
          ),
          SizedBox(
            width: 48,
            child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: Icon(Icons.add_circle_outline, color: primaryIconColor, size: 28),
            onPressed: onPlus,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20, 
        right: 20, 
        top: 16, 
        bottom: MediaQuery.of(context).viewInsets.bottom + 24 
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('更新进度', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(widget.animeName, style: const TextStyle(fontSize: 13, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 24),
            
            if (isLoading)
              const Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator())
            else ...[
              if (widget.subjectType == 1) ...[ 
                _buildProgressAdjuster(
                  title: '当前卷 (Vol)', 
                  value: currentVol, 
                  onMinus: () => setState(() => currentVol--), 
                  onPlus: () => setState(() => currentVol++)
                ),
                _buildProgressAdjuster(
                  title: '当前话 (Chap)', 
                  value: currentEp, 
                  onMinus: () => setState(() => currentEp--), 
                  onPlus: () => setState(() => currentEp++)
                ),
              ] else ...[ 
                _buildProgressAdjuster(
                  title: '当前集数 (Ep)', 
                  value: currentEp, 
                  onMinus: () => setState(() => currentEp--), 
                  onPlus: () => setState(() => currentEp++)
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: isSyncing ? null : _syncProgress,
                  icon: isSyncing 
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.cloud_upload),
                  label: Text(isSyncing ? '同步中...' : '保存进度', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}