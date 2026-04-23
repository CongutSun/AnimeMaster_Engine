// ignore_for_file: unused_field

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../api/dio_client.dart';
import '../models/online_episode_source.dart';
import '../utils/task_title_parser.dart';

class OnlineEpisodeSourceService {
  OnlineEpisodeSourceService({Dio? dio}) : _dio = dio ?? DioClient().dio;

  static const int maxResults = 30;
  static const int _adapterConcurrency = 5;
  static const int _earlyCloseResultCount = 10;
  static const int _earlyCloseVerifiedCount = 5;
  static const Duration _adapterTimeout = Duration(seconds: 14);
  static const Duration _searchDeadline = Duration(seconds: 20);
  static const Duration _resultCacheTtl = Duration(minutes: 30);
  static final Map<String, List<OnlineEpisodeSourceResult>> _resultCache =
      <String, List<OnlineEpisodeSourceResult>>{};
  static final Map<String, DateTime> _resultCacheTime = <String, DateTime>{};
  final Dio _dio;

  Future<List<OnlineEpisodeSourceResult>> search(
    OnlineEpisodeQuery query,
  ) async {
    List<OnlineEpisodeSourceResult> latest = <OnlineEpisodeSourceResult>[];
    await for (final List<OnlineEpisodeSourceResult> results in searchStream(
      query,
    )) {
      latest = results;
    }
    return latest;
  }

  Stream<List<OnlineEpisodeSourceResult>> searchStream(
    OnlineEpisodeQuery query,
  ) {
    late final StreamController<List<OnlineEpisodeSourceResult>> controller;
    final Map<String, OnlineEpisodeSourceResult> deduplicated =
        <String, OnlineEpisodeSourceResult>{};
    final List<String> subjectNames = _buildSubjectNames(query);
    final List<_OnlineSourceAdapter> adapters = _DirectSiteAdapter.defaults;
    final String cacheKey = _queryCacheKey(query);
    final List<OnlineEpisodeSourceResult>? cachedResults = _readCachedResults(
      cacheKey,
    );
    if (cachedResults != null) {
      for (final OnlineEpisodeSourceResult result in cachedResults) {
        _mergeResult(deduplicated, result);
      }
    }
    int nextAdapterIndex = 0;
    int activeAdapters = 0;
    int completedAdapters = 0;
    bool cancelled = false;
    Timer? deadlineTimer;

    void emit() {
      if (cancelled || controller.isClosed) {
        return;
      }
      final List<OnlineEpisodeSourceResult> results = _sortedResults(
        deduplicated,
      );
      _writeCachedResults(cacheKey, results);
      controller.add(results);
    }

    void closeWithCurrentResults() {
      if (cancelled || controller.isClosed) {
        return;
      }
      cancelled = true;
      deadlineTimer?.cancel();
      if (deduplicated.isEmpty) {
        controller.add(const <OnlineEpisodeSourceResult>[]);
      } else {
        _writeCachedResults(cacheKey, _sortedResults(deduplicated));
      }
      unawaited(controller.close());
    }

    bool hasEnoughResultsForPlayback() {
      final List<OnlineEpisodeSourceResult> results = _sortedResults(
        deduplicated,
      );
      if (results.length >= _earlyCloseResultCount) {
        return true;
      }
      final Iterable<OnlineEpisodeSourceResult> verified = results.where(
        (OnlineEpisodeSourceResult result) => result.verified,
      );
      final int verifiedCount = verified.length;
      final int sourceCount = verified
          .map((OnlineEpisodeSourceResult result) => result.sourceName)
          .toSet()
          .length;
      return verifiedCount >= _earlyCloseVerifiedCount && sourceCount >= 2;
    }

    void maybeClose() {
      if (completedAdapters < adapters.length ||
          cancelled ||
          controller.isClosed) {
        return;
      }
      if (deduplicated.isEmpty) {
        controller.add(const <OnlineEpisodeSourceResult>[]);
      }
      _writeCachedResults(cacheKey, _sortedResults(deduplicated));
      deadlineTimer?.cancel();
      unawaited(controller.close());
    }

    void launchNextAdapters() {
      if (cancelled || controller.isClosed) {
        return;
      }
      while (activeAdapters < _adapterConcurrency &&
          nextAdapterIndex < adapters.length) {
        final _OnlineSourceAdapter adapter = adapters[nextAdapterIndex];
        nextAdapterIndex += 1;
        activeAdapters += 1;
        unawaited(
          _searchAdapter(adapter, query, subjectNames)
              .then((List<OnlineEpisodeSourceResult> batch) {
                bool changed = false;
                for (final OnlineEpisodeSourceResult result in batch) {
                  changed = _mergeResult(deduplicated, result) || changed;
                }
                if (changed) {
                  emit();
                  if (hasEnoughResultsForPlayback()) {
                    closeWithCurrentResults();
                  }
                }
              })
              .whenComplete(() {
                activeAdapters -= 1;
                completedAdapters += 1;
                launchNextAdapters();
                maybeClose();
              }),
        );
      }
      maybeClose();
    }

    controller = StreamController<List<OnlineEpisodeSourceResult>>(
      onListen: () {
        if (adapters.isEmpty) {
          controller.add(const <OnlineEpisodeSourceResult>[]);
          unawaited(controller.close());
          return;
        }
        if (cachedResults != null && cachedResults.isNotEmpty) {
          controller.add(_sortedResults(deduplicated));
        }
        deadlineTimer = Timer(_searchDeadline, () {
          closeWithCurrentResults();
        });
        launchNextAdapters();
      },
      onCancel: () {
        cancelled = true;
        deadlineTimer?.cancel();
      },
    );
    return controller.stream;
  }

  String _queryCacheKey(OnlineEpisodeQuery query) {
    final List<String> parts = <String>[
      query.bangumiSubjectId.toString(),
      query.bangumiEpisodeId.toString(),
      query.episodeNumber.toString(),
      query.subjectTitle,
      query.episodeTitle,
      ...query.aliases.take(3),
    ];
    return parts.map((String value) => value.trim().toLowerCase()).join('|');
  }

  List<OnlineEpisodeSourceResult>? _readCachedResults(String cacheKey) {
    final DateTime? cachedAt = _resultCacheTime[cacheKey];
    final List<OnlineEpisodeSourceResult>? results = _resultCache[cacheKey];
    if (cachedAt == null || results == null) {
      return null;
    }
    if (DateTime.now().difference(cachedAt) > _resultCacheTtl) {
      _resultCache.remove(cacheKey);
      _resultCacheTime.remove(cacheKey);
      return null;
    }
    return results;
  }

  void _writeCachedResults(
    String cacheKey,
    List<OnlineEpisodeSourceResult> results,
  ) {
    if (results.isEmpty) {
      return;
    }
    _resultCache[cacheKey] = List<OnlineEpisodeSourceResult>.unmodifiable(
      results,
    );
    _resultCacheTime[cacheKey] = DateTime.now();
    if (_resultCache.length <= 40) {
      return;
    }
    final String oldestKey = _resultCacheTime.entries.reduce((
      MapEntry<String, DateTime> a,
      MapEntry<String, DateTime> b,
    ) {
      return a.value.isBefore(b.value) ? a : b;
    }).key;
    _resultCache.remove(oldestKey);
    _resultCacheTime.remove(oldestKey);
  }

  Future<List<OnlineEpisodeSourceResult>> _searchAdapter(
    _OnlineSourceAdapter adapter,
    OnlineEpisodeQuery query,
    List<String> subjectNames,
  ) async {
    try {
      return await adapter
          .search(_dio, query, subjectNames)
          .timeout(
            _adapterTimeout,
            onTimeout: () => <OnlineEpisodeSourceResult>[],
          );
    } catch (error) {
      debugPrint('[OnlineEpisodeSource] ${adapter.name} failed: $error');
      return <OnlineEpisodeSourceResult>[];
    }
  }

  List<String> _buildSubjectNames(OnlineEpisodeQuery query) {
    return <String>[query.subjectTitle, ...query.aliases]
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toSet()
        .take(3)
        .toList();
  }

  String _normalizeResultKey(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return url.trim();
    }
    return uri.replace(fragment: '').toString();
  }

  bool _mergeResult(
    Map<String, OnlineEpisodeSourceResult> target,
    OnlineEpisodeSourceResult result,
  ) {
    if (result.mediaUrl.trim().isEmpty) {
      return false;
    }
    final String key = _normalizeResultKey(result.mediaUrl);
    final OnlineEpisodeSourceResult? existing = target[key];
    if (existing != null) {
      if (existing.verified && !result.verified) {
        return false;
      }
      if (existing.verified == result.verified &&
          existing.score >= result.score) {
        return false;
      }
    }
    target[key] = result;
    return true;
  }

  List<OnlineEpisodeSourceResult> _sortedResults(
    Map<String, OnlineEpisodeSourceResult> source,
  ) {
    final List<OnlineEpisodeSourceResult> results = source.values.toList()
      ..sort((OnlineEpisodeSourceResult a, OnlineEpisodeSourceResult b) {
        if (a.verified != b.verified) {
          return b.verified ? 1 : -1;
        }
        final int byScore = b.score.compareTo(a.score);
        if (byScore != 0) {
          return byScore;
        }
        return a.title.length.compareTo(b.title.length);
      });
    return results.take(maxResults).toList();
  }
}

abstract class _OnlineSourceAdapter {
  String get name;

  Future<List<OnlineEpisodeSourceResult>> search(
    Dio dio,
    OnlineEpisodeQuery query,
    List<String> subjectNames,
  );
}

class _DirectSiteAdapter implements _OnlineSourceAdapter {
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const int _maxResultsPerSite = 4;
  static const int _episodeResolveConcurrency = 3;
  static const Duration _mediaResolveTimeout = Duration(seconds: 6);

  @override
  final String name;
  final String baseUrl;
  final String Function(String keyword) searchPathBuilder;
  final List<String Function(String keyword)> fallbackSearchPathBuilders;
  final bool pathKeyword;
  final String subjectSelector;
  final RegExp subjectHrefPattern;
  final String episodeSelector;
  final RegExp episodeHrefPattern;

  const _DirectSiteAdapter({
    required this.name,
    required this.baseUrl,
    required this.searchPathBuilder,
    this.fallbackSearchPathBuilders = const <String Function(String keyword)>[],
    this.pathKeyword = false,
    required this.subjectSelector,
    required this.subjectHrefPattern,
    required this.episodeSelector,
    required this.episodeHrefPattern,
  });

  static final List<_OnlineSourceAdapter> defaults = <_OnlineSourceAdapter>[
    _DirectSiteAdapter(
      name: 'OmoFun',
      baseUrl: 'https://omofun04.top',
      searchPathBuilder: (String keyword) => '/vod/search.html?wd=$keyword',
      subjectSelector: 'a[href*="/vod/detail/id/"]',
      subjectHrefPattern: RegExp(r'/vod/detail/id/\d+\.html'),
      episodeSelector: 'a[href*="/vod/play/id/"], [data-link*="/vod/play/id/"]',
      episodeHrefPattern: RegExp(r'/vod/play/id/\d+/sid/\d+/nid/\d+\.html'),
    ),
    _DirectSiteAdapter(
      name: 'AGE 动漫',
      baseUrl: 'https://www.agedm.io',
      searchPathBuilder: (String keyword) => '/search?query=$keyword',
      subjectSelector: 'a[href*="/detail/"]',
      subjectHrefPattern: RegExp(r'/detail/\d+'),
      episodeSelector: 'a.video_detail_spisode_link[href*="/play/"]',
      episodeHrefPattern: RegExp(r'/play/\d+/\d+/\d+'),
    ),
    _DirectSiteAdapter(
      name: '橘子动漫',
      baseUrl: 'https://www.mgnacg.com',
      searchPathBuilder: (String keyword) => '/search/$keyword-------------/',
      pathKeyword: true,
      subjectSelector:
          'a[href*="/vod/detail/"], a[href*="/detail/"], a[href*="/vod/"]',
      subjectHrefPattern: RegExp(
        r'/(?:index\.php/)?vod/detail/id/\d+\.html|/detail/\d+\.html|/vod/\d+\.html',
      ),
      episodeSelector:
          'a[href*="/vod/play/"], a[href*="/play/"], [data-link*="/vod/play/"]',
      episodeHrefPattern: RegExp(
        r'/(?:index\.php/)?vod/play/id/\d+/sid/\d+/nid/\d+\.html|/play/\d+-\d+-\d+\.html',
      ),
    ),
    _DirectSiteAdapter(
      name: 'Dodo 动漫',
      baseUrl: 'http://m.dodoge.me',
      searchPathBuilder: (String keyword) => '/vod/search.html?wd=$keyword',
      subjectSelector:
          'a[href*="/vod/detail/"], a[href*="/detail/"], a[href*="/show/"]',
      subjectHrefPattern: RegExp(
        r'/vod/detail/id/\d+\.html|/detail/\d+\.html|/show/\d+',
      ),
      episodeSelector:
          'a[href*="/vod/play/"], a[href*="/play/"], [data-link*="/vod/play/"]',
      episodeHrefPattern: RegExp(
        r'/vod/play/id/\d+/sid/\d+/nid/\d+\.html|/play/\d+',
      ),
    ),
    _DirectSiteAdapter.macCms(name: '嗷呜动漫', baseUrl: 'https://www.aowu.tv'),
  ];

  static final List<_OnlineSourceAdapter>
  allKnownDefaults = <_OnlineSourceAdapter>[
    _DirectSiteAdapter(
      name: 'OmoFun',
      baseUrl: 'https://omofun04.top',
      searchPathBuilder: (String keyword) => '/vod/search.html?wd=$keyword',
      subjectSelector: 'a[href*="/vod/detail/id/"]',
      subjectHrefPattern: RegExp(r'/vod/detail/id/\d+\.html'),
      episodeSelector: 'a[href*="/vod/play/id/"], [data-link*="/vod/play/id/"]',
      episodeHrefPattern: RegExp(r'/vod/play/id/\d+/sid/\d+/nid/\d+\.html'),
    ),
    _DirectSiteAdapter(
      name: 'AGE 动漫',
      baseUrl: 'https://www.agedm.io',
      searchPathBuilder: (String keyword) => '/search?query=$keyword',
      subjectSelector: 'a[href*="/detail/"]',
      subjectHrefPattern: RegExp(r'/detail/\d+'),
      episodeSelector: 'a.video_detail_spisode_link[href*="/play/"]',
      episodeHrefPattern: RegExp(r'/play/\d+/\d+/\d+'),
    ),
    _DirectSiteAdapter(
      name: 'Anime1',
      baseUrl: 'https://anime1.cc',
      searchPathBuilder: (String keyword) => '/search?q=$keyword',
      subjectSelector: 'a[href]',
      subjectHrefPattern: RegExp(r'^/\d+/?$'),
      episodeSelector: 'a.e-aa[href], a.e-ww[href]',
      episodeHrefPattern: RegExp(r'^/\d+-\d+-\d+/?$'),
    ),
    const _Anime1MeAdapter(),
    _DirectSiteAdapter(
      name: '橘子动漫',
      baseUrl: 'https://www.mgnacg.com',
      searchPathBuilder: (String keyword) => '/search/$keyword-------------/',
      pathKeyword: true,
      subjectSelector:
          'a[href*="/vod/detail/"], a[href*="/detail/"], a[href*="/vod/"]',
      subjectHrefPattern: RegExp(
        r'/(?:index\.php/)?vod/detail/id/\d+\.html|/detail/\d+\.html|/vod/\d+\.html',
      ),
      episodeSelector:
          'a[href*="/vod/play/"], a[href*="/play/"], [data-link*="/vod/play/"]',
      episodeHrefPattern: RegExp(
        r'/(?:index\.php/)?vod/play/id/\d+/sid/\d+/nid/\d+\.html|/play/\d+-\d+-\d+\.html',
      ),
    ),
    _DirectSiteAdapter(
      name: 'Dodo 动漫',
      baseUrl: 'http://m.dodoge.me',
      searchPathBuilder: (String keyword) => '/vod/search.html?wd=$keyword',
      subjectSelector:
          'a[href*="/vod/detail/"], a[href*="/detail/"], a[href*="/show/"]',
      subjectHrefPattern: RegExp(
        r'/vod/detail/id/\d+\.html|/detail/\d+\.html|/show/\d+',
      ),
      episodeSelector:
          'a[href*="/vod/play/"], a[href*="/play/"], [data-link*="/vod/play/"]',
      episodeHrefPattern: RegExp(
        r'/vod/play/id/\d+/sid/\d+/nid/\d+\.html|/play/\d+',
      ),
    ),
    _DirectSiteAdapter.macCms(name: '稀饭动漫', baseUrl: 'https://dm.xifanacg.com'),
    _DirectSiteAdapter.macCms(name: '去看吧', baseUrl: 'https://www.qkan8.com'),
    _DirectSiteAdapter.macCms(name: '異世界動畫', baseUrl: 'https://www.dmmiku.com'),
    _DirectSiteAdapter.macCms(name: 'NT 动漫', baseUrl: 'https://www.ntdm9.com'),
    _DirectSiteAdapter.macCms(name: '嗷呜动漫', baseUrl: 'https://www.aowu.tv'),
    _DirectSiteAdapter.macCms(name: 'E-ACG', baseUrl: 'https://www.eacg.net'),
    _DirectSiteAdapter.macCms(name: '七色番', baseUrl: 'https://www.7sefun.top'),
    _DirectSiteAdapter.macCms(name: '5弹幕', baseUrl: 'https://www.5dm.link'),
    _DirectSiteAdapter.macCms(
      name: 'Mutefun',
      baseUrl: 'https://www.91mute.com',
    ),
    _DirectSiteAdapter.macCms(name: '动漫妖', baseUrl: 'https://www.dmyao.com'),
    _DirectSiteAdapter.macCms(name: '樱之空', baseUrl: 'https://www.maigo.cc'),
    _DirectSiteAdapter.macCms(name: '风铃动漫', baseUrl: 'https://www.aafun.cc'),
    _DirectSiteAdapter.macCms(name: '柒番', baseUrl: 'https://www.qifun.cc'),
    _DirectSiteAdapter.macCms(name: '新番组', baseUrl: 'https://bangumi.online'),
    _DirectSiteAdapter.macCms(name: 'Animeo', baseUrl: 'https://animoe.org'),
    _DirectSiteAdapter.macCms(name: 'E站弹幕网', baseUrl: 'https://www.ezdmw.site'),
    _DirectSiteAdapter.macCms(
      name: '西瓜卡通',
      baseUrl: 'https://cn.xgcartoon.com',
    ),
    _DirectSiteAdapter.macCms(name: '萌番', baseUrl: 'https://bilfun.cc'),
    _DirectSiteAdapter.macCms(name: '动漫蛋', baseUrl: 'https://www.dmdm0.com'),
    _DirectSiteAdapter.macCms(name: 'mx动漫', baseUrl: 'https://www.mxdm.xyz'),
    _DirectSiteAdapter.macCms(name: '花子动漫', baseUrl: 'https://www.huazidm.com'),
    _DirectSiteAdapter.macCms(
      name: '嘶哩嘶哩',
      baseUrl: 'https://www.silisilifun.com',
    ),
    _DirectSiteAdapter.macCms(name: 'XDM动漫', baseUrl: 'https://xuandm.com'),
    _DirectSiteAdapter.macCms(name: '蜜桃动漫', baseUrl: 'https://www.mitaodm.com'),
    _DirectSiteAdapter.macCms(name: '怡萱动漫', baseUrl: 'https://www.iyxdm.cn'),
    _DirectSiteAdapter.macCms(name: '小小漫迷', baseUrl: 'https://www.xxmanmi.com'),
    _DirectSiteAdapter.macCms(
      name: 'akianime',
      baseUrl: 'https://www.akianime.cc',
    ),
    _DirectSiteAdapter.macCms(name: '番薯动漫', baseUrl: 'https://www.fsdm02.com'),
    _DirectSiteAdapter.macCms(
      name: 'myself动漫',
      baseUrl: 'https://myself-bbs.com',
    ),
    _DirectSiteAdapter.macCms(
      name: 'girlgirl爱动漫',
      baseUrl: 'https://bgm.girigirilove.com',
    ),
    _DirectSiteAdapter.macCms(name: '囧次元', baseUrl: 'https://www.jcydm1.com'),
    _DirectSiteAdapter.macCms(name: '4K动漫', baseUrl: 'https://cn.agekkkk.com'),
    _DirectSiteAdapter.macCms(name: '动漫巴士', baseUrl: 'https://dm84.tv'),
    _DirectSiteAdapter.macCms(
      name: '奇米奇米',
      baseUrl: 'https://www.qimiqimi.net',
    ),
    _DirectSiteAdapter.macCms(name: 'clicli', baseUrl: 'https://www.clicli.cc'),
    _DirectSiteAdapter.macCms(name: '哈哩哈哩', baseUrl: 'https://halihali1.com'),
    _DirectSiteAdapter.macCms(
      name: '动漫看看',
      baseUrl: 'https://www.dongmankk.com',
    ),
    _DirectSiteAdapter.macCms(name: '樱花动漫备用', baseUrl: 'https://yinghuacd.com'),
    _DirectSiteAdapter.macCms(name: '路漫漫', baseUrl: 'https://www.lmm52.com'),
    _DirectSiteAdapter.macCms(name: '久久动漫', baseUrl: 'https://www.995dm.com'),
    _DirectSiteAdapter.macCms(name: '次元方舟', baseUrl: 'https://cyfz.vip'),
    _DirectSiteAdapter.macCms(name: '樱花动漫网', baseUrl: 'https://www.vdm8.com'),
    _DirectSiteAdapter.macCms(name: '金阿尼动画', baseUrl: 'https://kimani22.com'),
    _DirectSiteAdapter.macCms(name: 'AGE 备用', baseUrl: 'https://agefans.top'),
    _DirectSiteAdapter.macCms(
      name: '修罗动漫',
      baseUrl: 'https://www.xiuluodm.com',
    ),
    _DirectSiteAdapter.macCms(name: '樱花动漫 74fan', baseUrl: 'https://74fan.com'),
    _DirectSiteAdapter.macCms(
      name: '樱花动漫 qdtsdp',
      baseUrl: 'https://qdtsdp.com',
    ),
    _DirectSiteAdapter.macCms(
      name: '樱花动漫 YHDMW',
      baseUrl: 'https://www.yhdmw.cc',
    ),
    _DirectSiteAdapter.macCms(
      name: '樱花动漫 iyinghua',
      baseUrl: 'https://www.iyinghua.io',
    ),
    _DirectSiteAdapter.macCms(
      name: '樱花动漫 yhdmoe',
      baseUrl: 'https://yhdmoe.com',
    ),
    _DirectSiteAdapter.macCms(
      name: '樱花动漫 xdm5',
      baseUrl: 'https://www.xdm5.com',
    ),
    _DirectSiteAdapter.macCms(
      name: '樱花动漫 yhdm60',
      baseUrl: 'https://yhdm60.com',
    ),
    _DirectSiteAdapter.macCms(name: '大咖动漫', baseUrl: 'https://www.dk95.com'),
    _DirectSiteAdapter.macCms(name: '米粒米粒', baseUrl: 'https://milimili.nl'),
    _DirectSiteAdapter.macCms(
      name: '星易次元',
      baseUrl: 'https://www.xingyiying.com',
    ),
    _DirectSiteAdapter.macCms(
      name: '好看的动漫',
      baseUrl: 'https://www.socomic.com',
    ),
    _DirectSiteAdapter.macCms(
      name: '品新番动漫网',
      baseUrl: 'https://www.pinxinfan.com',
    ),
    _DirectSiteAdapter.macCms(
      name: '次元城动画',
      baseUrl: 'https://www.cycdm01.top',
    ),
    _DirectSiteAdapter.macCms(name: '动漫岛', baseUrl: 'https://www.dmand5.com'),
    _DirectSiteAdapter.macCms(
      name: '囧次元备用',
      baseUrl: 'https://www.9ciyuan.com',
    ),
    _DirectSiteAdapter.macCms(name: '风车动漫', baseUrl: 'https://www.5ao7.com'),
    _DirectSiteAdapter.macCms(name: '嘀哩嘀哩', baseUrl: 'https://dilidili.online'),
    _DirectSiteAdapter.macCms(
      name: '哔咪动漫',
      baseUrl: 'https://www.bimiacg10.net',
    ),
    _DirectSiteAdapter.macCms(name: '第一动漫', baseUrl: 'https://d1-dm.online'),
    _DirectSiteAdapter.macCms(name: 'GA 动漫', baseUrl: 'https://www.gadm.cc'),
    _DirectSiteAdapter.macCms(name: '番茄动漫', baseUrl: 'https://www.fqdm.cc'),
    _DirectSiteAdapter.macCms(name: '虾皮动漫', baseUrl: 'https://xiapidm.com'),
    _DirectSiteAdapter.macCms(
      name: 'pilipili',
      baseUrl: 'https://tv.pilipili6.top',
    ),
    _DirectSiteAdapter.macCms(name: '动漫窝', baseUrl: 'https://www.dmwo.cc'),
    _DirectSiteAdapter.macCms(
      name: '小蛮兔动漫',
      baseUrl: 'https://www.xiaomantu.com',
    ),
    _DirectSiteAdapter.macCms(
      name: 'SSRFun',
      baseUrl: 'https://www.ssrfun.com',
    ),
    _DirectSiteAdapter.macCms(
      name: 'OMOFun 备用',
      baseUrl: 'https://www.omofuns.cc',
    ),
    _DirectSiteAdapter.macCms(name: '樱花动漫', baseUrl: 'https://www.yhdm555.com'),
  ];

  factory _DirectSiteAdapter.macCms({
    required String name,
    required String baseUrl,
  }) {
    return _DirectSiteAdapter(
      name: name,
      baseUrl: baseUrl,
      searchPathBuilder: (String keyword) => '/vod/search.html?wd=$keyword',
      fallbackSearchPathBuilders: <String Function(String keyword)>[
        (String keyword) => '/index.php/vod/search/wd/$keyword.html',
        (String keyword) => '/vodsearch/-------------.html?wd=$keyword',
        (String keyword) => '/search/$keyword-------------/',
        (String keyword) => '/search?query=$keyword',
      ],
      pathKeyword: true,
      subjectSelector:
          'a[href*="/vod/detail/"], a[href*="/detail/"], a[href*="/show/"]',
      subjectHrefPattern: RegExp(
        r'/(?:index\.php/)?vod/detail/id/\d+\.html|/detail/\d+\.html|/show/\d+',
      ),
      episodeSelector:
          'a[href*="/vod/play/"], a[href*="/play/"], [data-link*="/vod/play/"]',
      episodeHrefPattern: RegExp(
        r'/(?:index\.php/)?vod/play/id/\d+/sid/\d+/nid/\d+\.html|/play/\d+(?:[-/]\d+){0,2}(?:\.html)?',
      ),
    );
  }

  static int sourcePriorityFor(String sourceName) {
    final String normalized = sourceName.toLowerCase();
    if (normalized.contains('omofun')) {
      return 60;
    }
    if (normalized.contains('age')) {
      return 50;
    }
    if (normalized.contains('橘子')) {
      return 42;
    }
    if (normalized.contains('dodo')) {
      return 38;
    }
    if (normalized.contains('风铃')) {
      return 34;
    }
    if (normalized.contains('稀饭')) {
      return 30;
    }
    if (normalized.contains('去看')) {
      return 26;
    }
    if (normalized.contains('nt')) {
      return 22;
    }
    if (normalized.contains('嗷呜')) {
      return 18;
    }
    if (normalized.contains('mutefun')) {
      return 14;
    }
    return 4;
  }

  @override
  Future<List<OnlineEpisodeSourceResult>> search(
    Dio dio,
    OnlineEpisodeQuery query,
    List<String> subjectNames,
  ) async {
    final Map<String, OnlineEpisodeSourceResult> results =
        <String, OnlineEpisodeSourceResult>{};

    final List<String Function(String keyword)> searchPathBuilders =
        <String Function(String keyword)>[
          searchPathBuilder,
          ...fallbackSearchPathBuilders,
        ];

    for (final String subjectName in subjectNames) {
      final String keyword = pathKeyword
          ? Uri.encodeComponent(_compactKeyword(subjectName))
          : Uri.encodeQueryComponent(_compactKeyword(subjectName));
      for (final String Function(String keyword) pathBuilder
          in searchPathBuilders) {
        try {
          final Uri searchUri = Uri.parse(
            baseUrl,
          ).resolve(pathBuilder(keyword));
          final dom.Document searchDocument = await _loadDocument(
            dio,
            searchUri,
          );
          final List<_SubjectHit> subjects = _parseSubjects(
            searchDocument,
            query,
            subjectNames,
          );

          for (final _SubjectHit subject in subjects.take(3)) {
            final dom.Document detailDocument = await _loadDocument(
              dio,
              Uri.parse(subject.url),
              referer: searchUri.toString(),
            );
            final List<_EpisodeHit> episodes = _parseEpisodes(
              detailDocument,
              query,
            );

            for (
              int start = 0;
              start < episodes.length && results.length < _maxResultsPerSite;
              start += _episodeResolveConcurrency
            ) {
              final List<_EpisodeHit> batch = episodes
                  .skip(start)
                  .take(_episodeResolveConcurrency)
                  .toList();
              final List<OnlineEpisodeSourceResult?> resolved =
                  await Future.wait(
                    batch.map((_EpisodeHit episode) async {
                      try {
                        final _ResolvedMedia? media = await _resolveMedia(
                          dio,
                          episode.url,
                          referer: subject.url,
                        ).timeout(_mediaResolveTimeout);
                        if (media == null) {
                          return null;
                        }
                        final String key = _normalizeUrl(media.url);
                        final int score =
                            subject.score +
                            episode.score +
                            media.score +
                            sourcePriorityFor(name) +
                            80;
                        return OnlineEpisodeSourceResult(
                          title: '${subject.title} ${episode.title}'.trim(),
                          pageUrl: episode.url,
                          mediaUrl: key,
                          sourceName: name,
                          snippet: media.verified
                              ? '已验证直连视频流，${query.episodeLabel}'
                              : '已解析直连视频流，待播放器确认，${query.episodeLabel}',
                          headers: media.headers,
                          score: score,
                          verified: media.verified,
                        );
                      } catch (_) {
                        return null;
                      }
                    }),
                  );
              for (final OnlineEpisodeSourceResult? result in resolved) {
                if (result == null) {
                  continue;
                }
                final OnlineEpisodeSourceResult? existing =
                    results[result.mediaUrl];
                if (existing == null || result.score > existing.score) {
                  results[result.mediaUrl] = result;
                }
              }
            }
            if (results.length >= _maxResultsPerSite) {
              break;
            }
          }
          if (results.length >= _maxResultsPerSite) {
            break;
          }
        } catch (error) {
          debugPrint('[OnlineEpisodeSource] $name path failed: $error');
        }
        if (results.length >= _maxResultsPerSite) {
          break;
        }
      }
      if (results.length >= _maxResultsPerSite) {
        break;
      }
    }
    return results.values.toList();
  }

  Future<dom.Document> _loadDocument(
    Dio dio,
    Uri uri, {
    String? referer,
  }) async {
    final String html = await _loadText(dio, uri, referer: referer);
    return parser.parse(html);
  }

  Future<String> _loadText(Dio dio, Uri uri, {String? referer}) async {
    final Map<String, String> headers = <String, String>{
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'User-Agent': _browserUserAgent,
      if (referer != null && referer.isNotEmpty) 'Referer': referer,
    };
    final Response<String> response = await dio.get<String>(
      uri.toString(),
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: headers,
      ),
    );
    return response.data ?? '';
  }

  List<_SubjectHit> _parseSubjects(
    dom.Document document,
    OnlineEpisodeQuery query,
    List<String> subjectNames,
  ) {
    final Map<String, _SubjectHit> hits = <String, _SubjectHit>{};
    for (final dom.Element link in document.querySelectorAll(subjectSelector)) {
      final String href = link.attributes['href']?.trim() ?? '';
      if (!subjectHrefPattern.hasMatch(href)) {
        continue;
      }
      final String title = _normalizeText(
        link.attributes['title'] ??
            link.querySelector('h3, .title')?.text ??
            link.text,
      );
      final int score = _scoreSubject(title, subjectNames);
      if (score <= 0) {
        continue;
      }
      final String url = _normalizeUrl(href);
      final _SubjectHit? existing = hits[url];
      if (existing == null || score > existing.score) {
        hits[url] = _SubjectHit(
          title: title.isEmpty ? query.subjectTitle : title,
          url: url,
          score: score,
        );
      }
    }
    final List<_SubjectHit> sorted = hits.values.toList()
      ..sort((_SubjectHit a, _SubjectHit b) => b.score.compareTo(a.score));
    return sorted;
  }

  List<_EpisodeHit> _parseEpisodes(
    dom.Document document,
    OnlineEpisodeQuery query,
  ) {
    final Map<String, _EpisodeHit> hits = <String, _EpisodeHit>{};
    for (final dom.Element link in document.querySelectorAll(episodeSelector)) {
      final String rawHref =
          link.attributes['href']?.trim() ??
          link.attributes['data-link']?.trim() ??
          '';
      if (!episodeHrefPattern.hasMatch(rawHref)) {
        continue;
      }
      final String title = _normalizeText(link.text);
      final int? number = _episodeNumberFrom(title, rawHref);
      if (query.episodeNumber > 0 && number != query.episodeNumber) {
        continue;
      }

      final String url = _normalizeUrl(rawHref);
      final int score =
          (number == query.episodeNumber ? 40 : 10) +
          _episodeSourcePriority(rawHref);
      final _EpisodeHit next = _EpisodeHit(
        title: title.isEmpty ? query.episodeLabel : title,
        url: url,
        score: score,
      );
      final _EpisodeHit? existing = hits[url];
      if (existing == null || next.score > existing.score) {
        hits[url] = next;
      }
    }
    final List<_EpisodeHit> sorted = hits.values.toList()
      ..sort((_EpisodeHit a, _EpisodeHit b) => b.score.compareTo(a.score));
    return sorted.take(_maxResultsPerSite + 1).toList();
  }

  Future<_ResolvedMedia?> _resolveMedia(
    Dio dio,
    String playPageUrl, {
    String? referer,
  }) async {
    final Uri playUri = Uri.parse(playPageUrl);
    final String playHtml = await _loadText(
      dio,
      playUri,
      referer: referer ?? baseUrl,
    );

    final String? directFromPage = _extractDirectMediaUrl(playHtml, playUri);
    if (directFromPage != null) {
      return _validatedMedia(
        dio,
        url: directFromPage,
        headers: _mediaHeaders(referer: playPageUrl),
        score: 20,
      );
    }

    final String? iframeUrl = _extractIframeUrl(playHtml, playUri);
    if (iframeUrl == null) {
      return null;
    }

    final String? directFromIframeUrl = _extractDirectMediaUrl(
      iframeUrl,
      playUri,
    );
    if (directFromIframeUrl != null) {
      return _validatedMedia(
        dio,
        url: directFromIframeUrl,
        headers: _mediaHeaders(referer: playPageUrl),
        score: 18,
      );
    }

    final Uri iframeUri = Uri.parse(iframeUrl);
    final String iframeHtml = await _loadText(
      dio,
      iframeUri,
      referer: playPageUrl,
    );
    final String? directFromIframe = _extractDirectMediaUrl(
      iframeHtml,
      iframeUri,
    );
    if (directFromIframe != null) {
      return _validatedMedia(
        dio,
        url: directFromIframe,
        headers: _mediaHeaders(referer: iframeUrl),
        score: 16,
      );
    }

    final String? nestedIframeUrl = _extractIframeUrl(iframeHtml, iframeUri);
    if (nestedIframeUrl == null) {
      return null;
    }
    final String nestedHtml = await _loadText(
      dio,
      Uri.parse(nestedIframeUrl),
      referer: iframeUrl,
    );
    final String? directFromNested = _extractDirectMediaUrl(
      nestedHtml,
      Uri.parse(nestedIframeUrl),
    );
    if (directFromNested == null) {
      return null;
    }
    return _validatedMedia(
      dio,
      url: directFromNested,
      headers: _mediaHeaders(referer: nestedIframeUrl),
      score: 14,
    );
  }

  Future<_ResolvedMedia?> _validatedMedia(
    Dio dio, {
    required String url,
    required Map<String, String> headers,
    required int score,
  }) async {
    final bool reachable = await _isMediaReachable(dio, url, headers);
    return _ResolvedMedia(
      url: url,
      headers: headers,
      score: score + (reachable ? 10 : -8) + _mediaQualityScore(url),
      verified: reachable,
    );
  }

  Future<bool> _isMediaReachable(
    Dio dio,
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final bool isPlaylist = url.toLowerCase().contains('.m3u8');
      final Response<dynamic> response = await dio.get<dynamic>(
        url,
        options: Options(
          responseType: isPlaylist ? ResponseType.plain : ResponseType.bytes,
          followRedirects: true,
          sendTimeout: const Duration(seconds: 2),
          receiveTimeout: const Duration(seconds: 2),
          headers: <String, String>{
            ...headers,
            if (!isPlaylist) 'Range': 'bytes=0-2047',
            'Accept': isPlaylist
                ? 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*'
                : '*/*',
          },
          validateStatus: (int? status) =>
              status != null && status >= 200 && status < 500,
        ),
      );
      final int statusCode = response.statusCode ?? 0;
      if (statusCode >= 400) {
        return false;
      }
      if (isPlaylist) {
        final String text = response.data?.toString() ?? '';
        return text.contains('#EXTM3U') || text.contains('.ts');
      }
      final Object? data = response.data;
      return statusCode == 206 ||
          statusCode == 200 ||
          (data is List<int> && data.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  String? _extractIframeUrl(String html, Uri baseUri) {
    final dom.Document document = parser.parse(html);
    final dom.Element? iframe = document.querySelector('iframe[src]');
    final String? src = iframe?.attributes['src']?.trim();
    if (src != null && src.isNotEmpty) {
      return _normalizeAbsoluteUrl(src, baseUri);
    }

    final RegExpMatch? match = RegExp(
      r'''<iframe[^>]+src\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    final String? raw = match?.group(1)?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return _normalizeAbsoluteUrl(raw, baseUri);
  }

  String? _extractDirectMediaUrl(String value, Uri baseUri) {
    final String normalized = value
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u002F', '/')
        .replaceAll('&amp;', '&');

    final Uri? asUri = Uri.tryParse(normalized);
    if (asUri != null && asUri.hasScheme) {
      for (final String parameter in <String>['url', 'src', 'video']) {
        final String? raw = asUri.queryParameters[parameter];
        if (raw == null || raw.isEmpty) {
          continue;
        }
        final String? media = _sanitizeMediaUrl(raw, baseUri);
        if (media != null) {
          return media;
        }
      }
    }

    final List<RegExp> patterns = <RegExp>[
      RegExp(
        r'''https?:/{2}[^"'<>\s\\]+?\.(?:m3u8|mp4)(?:[^"'<>\s\\]*)?''',
        caseSensitive: false,
      ),
      RegExp(
        r'''https?:\\/{2}[^"'<>\s]+?\.(?:m3u8|mp4)(?:[^"'<>\s]*)?''',
        caseSensitive: false,
      ),
      RegExp(r'''["']([^"']+\.(?:m3u8|mp4)[^"']*)["']''', caseSensitive: false),
      RegExp(
        r'''(?:url|playurl|source|src)\s*[:=]\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
    ];

    for (final RegExp pattern in patterns) {
      for (final RegExpMatch match in pattern.allMatches(normalized)) {
        final String candidate =
            match.group(match.groupCount >= 1 ? 1 : 0) ?? '';
        final String? media = _sanitizeMediaUrl(candidate, baseUri);
        if (media != null) {
          return media;
        }
      }
    }
    return null;
  }

  String? _sanitizeMediaUrl(String value, Uri baseUri) {
    String url = value
        .trim()
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u002F', '/')
        .replaceAll('&amp;', '&');
    if (url.isEmpty) {
      return null;
    }

    final List<String> cutMarkers = <String>[
      '&subsurl=',
      '&type=',
      '&vtt=',
      '"',
      "'",
      '<',
      '>',
      '\\',
    ];
    for (final String marker in cutMarkers) {
      final int index = url.indexOf(marker);
      if (index > 0) {
        url = url.substring(0, index);
      }
    }

    if (url.startsWith('//')) {
      url = 'https:$url';
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = baseUri.resolve(url).toString();
    }

    final Uri? uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    final String lower = url.toLowerCase();
    if (!lower.contains('.m3u8') && !lower.contains('.mp4')) {
      return null;
    }
    if (lower.contains('adposter') || lower.contains('/poster')) {
      return null;
    }
    return uri.replace(fragment: '').toString();
  }

  String _normalizeAbsoluteUrl(String value, Uri baseUri) {
    String url = value
        .trim()
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u002F', '/')
        .replaceAll('&amp;', '&');
    if (url.startsWith('//')) {
      url = '${baseUri.scheme}:$url';
    }
    return baseUri.resolve(url).toString();
  }

  Map<String, String> _mediaHeaders({required String referer}) {
    final Map<String, String> headers = <String, String>{
      'Accept': '*/*',
      'User-Agent': _browserUserAgent,
      'Referer': referer,
    };
    final Uri? refererUri = Uri.tryParse(referer);
    if (refererUri != null &&
        refererUri.hasScheme &&
        refererUri.host.isNotEmpty) {
      headers['Origin'] = '${refererUri.scheme}://${refererUri.host}';
    }
    return headers;
  }

  int _mediaQualityScore(String url) {
    final String lower = url.toLowerCase();
    if (lower.contains('adposter') || lower.contains('/poster')) {
      return -100;
    }
    if (lower.contains('modujx')) {
      return 20;
    }
    if (lower.contains('bfvvs')) {
      return 18;
    }
    if (lower.contains('wlcdn')) {
      return 14;
    }
    if (lower.contains('lzcdn')) {
      return 10;
    }
    if (lower.contains('ppqrrs')) {
      return 8;
    }
    if (lower.contains('yuglf') || lower.contains('ffzy')) {
      return -6;
    }
    if (lower.contains('dytt') || lower.contains('175.178.')) {
      return -16;
    }
    return 0;
  }

  int _scoreSubject(String title, List<String> subjectNames) {
    final String normalizedTitle = _normalizeComparable(title);
    int best = 0;
    for (final String name in subjectNames) {
      final String normalizedName = _normalizeComparable(name);
      if (normalizedName.isEmpty) {
        continue;
      }
      if (normalizedTitle == normalizedName) {
        best = best < 70 ? 70 : best;
      } else if (normalizedTitle.contains(normalizedName) ||
          normalizedName.contains(normalizedTitle)) {
        best = best < 48 ? 48 : best;
      }
    }
    return best;
  }

  int? _episodeNumberFrom(String title, String href) {
    final int? fromTitle = TaskTitleParser.extractEpisodeNumber(title);
    if (fromTitle != null) {
      return fromTitle;
    }
    final RegExpMatch? ageMatch = RegExp(
      r'/play/\d+/\d+/(\d+)',
    ).firstMatch(href);
    if (ageMatch != null) {
      return int.tryParse(ageMatch.group(1) ?? '');
    }
    final RegExpMatch? anime1Match = RegExp(r'-(\d{1,4})/?$').firstMatch(href);
    if (anime1Match != null) {
      return int.tryParse(anime1Match.group(1) ?? '');
    }
    final RegExpMatch? macMatch = RegExp(r'/nid/(\d+)\.html').firstMatch(href);
    if (macMatch != null) {
      return int.tryParse(macMatch.group(1) ?? '');
    }
    return null;
  }

  int _episodeSourcePriority(String href) {
    final RegExpMatch? ageMatch = RegExp(
      r'/play/\d+/(\d+)/\d+',
    ).firstMatch(href);
    if (ageMatch != null) {
      final int source = int.tryParse(ageMatch.group(1) ?? '') ?? 0;
      if (source == 2) {
        return 30;
      }
      if (source > 2) {
        return 20;
      }
      return 0;
    }

    final RegExpMatch? macMatch = RegExp(
      r'/sid/(\d+)/nid/\d+',
    ).firstMatch(href);
    if (macMatch != null) {
      final int source = int.tryParse(macMatch.group(1) ?? '') ?? 0;
      return source > 1 ? 10 : 0;
    }
    return 0;
  }

  String _normalizeUrl(String value) {
    final Uri base = Uri.parse(baseUrl);
    final String resolved = base.resolve(value).toString();
    return resolved.replaceFirst('http://www.agedm.io', 'https://www.agedm.io');
  }

  String _compactKeyword(String value) {
    return value
        .replaceAll(RegExp(r'第\s*\d+\s*[季期].*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _normalizeText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalizeComparable(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s·・:：,，.。!！?？_\-—+]+'), '')
        .trim();
  }
}

class _Anime1MeAdapter implements _OnlineSourceAdapter {
  static const String _baseUrl = 'https://anime1.me';
  static const String _apiUrl = 'https://v.anime1.me/api';

  const _Anime1MeAdapter();

  @override
  String get name => 'Anime1.me';

  @override
  Future<List<OnlineEpisodeSourceResult>> search(
    Dio dio,
    OnlineEpisodeQuery query,
    List<String> subjectNames,
  ) async {
    final Map<String, OnlineEpisodeSourceResult> results =
        <String, OnlineEpisodeSourceResult>{};

    for (final String subjectName in subjectNames) {
      final Uri searchUri = Uri.parse(
        '$_baseUrl/?s=${Uri.encodeQueryComponent(_compactKeyword(subjectName))}',
      );
      final dom.Document searchDocument = await _loadDocument(dio, searchUri);
      final List<_Anime1CategoryHit> categories = _parseCategoryHits(
        searchDocument,
        subjectNames,
      );

      for (final _Anime1CategoryHit category in categories.take(2)) {
        final dom.Document categoryDocument = await _loadDocument(
          dio,
          Uri.parse(category.url),
          referer: searchUri.toString(),
        );
        final List<_Anime1PostHit> posts = _selectPosts(
          _parsePostHits(categoryDocument),
          query,
        );

        for (final _Anime1PostHit post in posts.take(3)) {
          final _ResolvedMedia? media = await _resolvePlayMedia(
            dio,
            post.url,
            referer: category.url,
          );
          if (media == null) {
            continue;
          }

          final String key = _normalizeAbsoluteUrl(
            media.url,
            Uri.parse(_baseUrl),
          );
          final OnlineEpisodeSourceResult result = OnlineEpisodeSourceResult(
            title: post.title,
            pageUrl: post.url,
            mediaUrl: key,
            sourceName: name,
            snippet: media.verified
                ? '已验证直连视频流，${query.episodeLabel}'
                : '已解析直连视频流，待播放器确认，${query.episodeLabel}',
            headers: media.headers,
            score:
                category.score +
                post.score +
                media.score +
                _DirectSiteAdapter.sourcePriorityFor(name) +
                80,
            verified: media.verified,
          );
          final OnlineEpisodeSourceResult? existing = results[key];
          if (existing == null || result.score > existing.score) {
            results[key] = result;
          }
        }
      }

      if (results.isEmpty) {
        for (final _Anime1PostHit post in _selectPosts(
          _parsePostHits(searchDocument),
          query,
          allowIndexFallback: false,
        ).take(3)) {
          final _ResolvedMedia? media = await _resolvePlayMedia(
            dio,
            post.url,
            referer: searchUri.toString(),
          );
          if (media == null) {
            continue;
          }

          final String key = _normalizeAbsoluteUrl(
            media.url,
            Uri.parse(_baseUrl),
          );
          final OnlineEpisodeSourceResult result = OnlineEpisodeSourceResult(
            title: post.title,
            pageUrl: post.url,
            mediaUrl: key,
            sourceName: name,
            snippet: media.verified
                ? '已验证直连视频流，${query.episodeLabel}'
                : '已解析直连视频流，待播放器确认，${query.episodeLabel}',
            headers: media.headers,
            score:
                post.score +
                media.score +
                _DirectSiteAdapter.sourcePriorityFor(name) +
                70,
            verified: media.verified,
          );
          final OnlineEpisodeSourceResult? existing = results[key];
          if (existing == null || result.score > existing.score) {
            results[key] = result;
          }
        }
      }

      if (results.length >= _DirectSiteAdapter._maxResultsPerSite) {
        break;
      }
    }
    return results.values.toList();
  }

  Future<dom.Document> _loadDocument(
    Dio dio,
    Uri uri, {
    String? referer,
  }) async {
    final String html = await _loadText(dio, uri, referer: referer);
    return parser.parse(html);
  }

  Future<String> _loadText(Dio dio, Uri uri, {String? referer}) async {
    final Response<String> response = await dio.get<String>(
      uri.toString(),
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        headers: <String, String>{
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'User-Agent': _DirectSiteAdapter._browserUserAgent,
          if (referer != null && referer.isNotEmpty) 'Referer': referer,
        },
      ),
    );
    return response.data ?? '';
  }

  List<_Anime1CategoryHit> _parseCategoryHits(
    dom.Document document,
    List<String> subjectNames,
  ) {
    final Map<String, _Anime1CategoryHit> hits = <String, _Anime1CategoryHit>{};
    final List<dom.Element> roots = document.querySelectorAll('article').isEmpty
        ? <dom.Element>[document.documentElement ?? document.body!]
        : document.querySelectorAll('article');

    for (final dom.Element root in roots) {
      final String rootText = _normalizeText(root.text);
      for (final dom.Element link in root.querySelectorAll(
        'a[href*="/category/"]',
      )) {
        final String href = link.attributes['href']?.trim() ?? '';
        if (href.isEmpty) {
          continue;
        }
        final String title = _normalizeText(link.text);
        final int score = _scoreSubject('$rootText $title', subjectNames);
        if (score <= 0) {
          continue;
        }
        final String url = _normalizeAbsoluteUrl(href, Uri.parse(_baseUrl));
        final _Anime1CategoryHit next = _Anime1CategoryHit(
          title: title.isEmpty ? rootText : title,
          url: url,
          score: score,
        );
        final _Anime1CategoryHit? existing = hits[url];
        if (existing == null || next.score > existing.score) {
          hits[url] = next;
        }
      }
    }

    final List<_Anime1CategoryHit> sorted = hits.values.toList()
      ..sort(
        (_Anime1CategoryHit a, _Anime1CategoryHit b) =>
            b.score.compareTo(a.score),
      );
    return sorted;
  }

  List<_Anime1PostHit> _parsePostHits(dom.Document document) {
    final Map<String, _Anime1PostHit> hits = <String, _Anime1PostHit>{};
    final Iterable<dom.Element> links = document.querySelectorAll(
      'article h2 a[href], article .entry-title a[href], h2.entry-title a[href]',
    );

    for (final dom.Element link in links) {
      final String href = link.attributes['href']?.trim() ?? '';
      final Uri? uri = Uri.tryParse(href);
      if (uri == null ||
          uri.host != 'anime1.me' ||
          !RegExp(r'^/\d+/?$').hasMatch(uri.path)) {
        continue;
      }

      final String title = _normalizeText(link.text);
      if (title.isEmpty) {
        continue;
      }
      final int? globalEpisode = _episodeNumberFromPostTitle(title);
      final _Anime1PostHit next = _Anime1PostHit(
        title: title,
        url: uri.replace(fragment: '').toString(),
        globalEpisode: globalEpisode,
        score: globalEpisode == null ? 10 : 20,
      );
      final _Anime1PostHit? existing = hits[next.url];
      if (existing == null || next.score > existing.score) {
        hits[next.url] = next;
      }
    }

    return hits.values.toList();
  }

  List<_Anime1PostHit> _selectPosts(
    List<_Anime1PostHit> posts,
    OnlineEpisodeQuery query, {
    bool allowIndexFallback = true,
  }) {
    if (posts.isEmpty) {
      return const <_Anime1PostHit>[];
    }
    if (query.episodeNumber <= 0) {
      return posts.take(4).toList();
    }

    final List<_Anime1PostHit> exact = posts
        .where(
          (_Anime1PostHit post) => post.globalEpisode == query.episodeNumber,
        )
        .toList();
    if (exact.isNotEmpty) {
      return exact;
    }
    if (!allowIndexFallback) {
      return const <_Anime1PostHit>[];
    }

    final List<_Anime1PostHit> ascending = posts.reversed.toList();
    final int index = query.episodeNumber - 1;
    if (index >= 0 && index < ascending.length) {
      final _Anime1PostHit post = ascending[index];
      return <_Anime1PostHit>[
        _Anime1PostHit(
          title: post.title,
          url: post.url,
          globalEpisode: post.globalEpisode,
          score: post.score + 35,
        ),
      ];
    }
    return const <_Anime1PostHit>[];
  }

  Future<_ResolvedMedia?> _resolvePlayMedia(
    Dio dio,
    String playPageUrl, {
    String? referer,
  }) async {
    final String html = await _loadText(
      dio,
      Uri.parse(playPageUrl),
      referer: referer ?? _baseUrl,
    );
    final String? apiRequest = _extractApiRequest(html);
    if (apiRequest == null) {
      return null;
    }

    final String body = apiRequest.startsWith('{')
        ? 'd=${Uri.encodeQueryComponent(apiRequest)}'
        : 'd=$apiRequest';
    final Response<String> response = await dio.post<String>(
      _apiUrl,
      data: body,
      options: Options(
        responseType: ResponseType.plain,
        headers: <String, String>{
          'Accept': 'application/json, text/javascript, */*; q=0.01',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Origin': _baseUrl,
          'Referer': playPageUrl,
          'User-Agent': _DirectSiteAdapter._browserUserAgent,
          'X-Requested-With': 'XMLHttpRequest',
        },
      ),
    );

    final Object? decoded = jsonDecode(response.data ?? '{}');
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final Object? sources = decoded['s'];
    String? rawUrl;
    if (sources is String) {
      rawUrl = sources;
    } else if (sources is List && sources.isNotEmpty) {
      final Object? first = sources.first;
      if (first is Map) {
        rawUrl = first['src']?.toString();
      } else {
        rawUrl = first.toString();
      }
    }
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return null;
    }

    final String mediaUrl = _normalizeAbsoluteUrl(rawUrl, Uri.parse(_baseUrl));
    final Map<String, String> mediaHeaders = <String, String>{
      'User-Agent': _DirectSiteAdapter._browserUserAgent,
      'Referer': playPageUrl,
      'Origin': _baseUrl,
    };
    final bool reachable = await _isMediaReachable(dio, mediaUrl, mediaHeaders);
    return _ResolvedMedia(
      url: mediaUrl,
      headers: mediaHeaders,
      score: reachable ? 36 : 20,
      verified: reachable,
    );
  }

  Future<bool> _isMediaReachable(
    Dio dio,
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final bool isPlaylist = url.toLowerCase().contains('.m3u8');
      final Response<dynamic> response = await dio.get<dynamic>(
        url,
        options: Options(
          responseType: isPlaylist ? ResponseType.plain : ResponseType.bytes,
          followRedirects: true,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
          headers: <String, String>{
            ...headers,
            if (!isPlaylist) 'Range': 'bytes=0-2047',
            'Accept': isPlaylist
                ? 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*'
                : '*/*',
          },
          validateStatus: (int? status) =>
              status != null && status >= 200 && status < 500,
        ),
      );
      final int statusCode = response.statusCode ?? 0;
      if (statusCode >= 400) {
        return false;
      }
      if (isPlaylist) {
        final String text = response.data?.toString() ?? '';
        return text.contains('#EXTM3U') || text.contains('.ts');
      }
      final Object? data = response.data;
      return statusCode == 206 ||
          statusCode == 200 ||
          (data is List<int> && data.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  String? _extractApiRequest(String html) {
    final RegExpMatch? match = RegExp(
      r'''data-apireq\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    final String? raw = match?.group(1)?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return raw.replaceAll('&amp;', '&');
  }

  int? _episodeNumberFromPostTitle(String title) {
    final RegExpMatch? match = RegExp(r'[\[【](\d{1,4})[\]】]').firstMatch(title);
    if (match == null) {
      return TaskTitleParser.extractEpisodeNumber(title);
    }
    return int.tryParse(match.group(1) ?? '');
  }

  int _scoreSubject(String value, List<String> subjectNames) {
    final String normalizedValue = _normalizeComparable(value);
    int best = 0;
    for (final String name in subjectNames) {
      final String normalizedName = _normalizeComparable(name);
      if (normalizedName.isEmpty) {
        continue;
      }
      if (normalizedValue.contains(normalizedName)) {
        best = best < 52 ? 52 : best;
      }
    }
    return best;
  }

  String _compactKeyword(String value) {
    return value
        .replaceAll(RegExp(r'第\s*\d+\s*[季期].*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _normalizeAbsoluteUrl(String value, Uri baseUri) {
    String url = value
        .trim()
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u002F', '/')
        .replaceAll('&amp;', '&');
    if (url.startsWith('//')) {
      url = '${baseUri.scheme}:$url';
    }
    return baseUri.resolve(url).replace(fragment: '').toString();
  }

  String _normalizeText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalizeComparable(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s·・:：,，.。!！?？_\-—+]+'), '')
        .trim();
  }
}

class _Anime1CategoryHit {
  final String title;
  final String url;
  final int score;

  const _Anime1CategoryHit({
    required this.title,
    required this.url,
    required this.score,
  });
}

class _Anime1PostHit {
  final String title;
  final String url;
  final int? globalEpisode;
  final int score;

  const _Anime1PostHit({
    required this.title,
    required this.url,
    required this.globalEpisode,
    required this.score,
  });
}

class _SubjectHit {
  final String title;
  final String url;
  final int score;

  const _SubjectHit({
    required this.title,
    required this.url,
    required this.score,
  });
}

class _EpisodeHit {
  final String title;
  final String url;
  final int score;

  const _EpisodeHit({
    required this.title,
    required this.url,
    required this.score,
  });
}

class _ResolvedMedia {
  final String url;
  final Map<String, String> headers;
  final int score;
  final bool verified;

  const _ResolvedMedia({
    required this.url,
    required this.headers,
    required this.score,
    required this.verified,
  });
}
