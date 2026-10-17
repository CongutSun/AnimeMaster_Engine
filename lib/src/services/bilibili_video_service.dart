import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;

import '../models/bilibili_video.dart';
import '../models/playable_media.dart';
import 'bilibili_auth_service.dart';

class BilibiliVideoException implements Exception {
  final String message;

  const BilibiliVideoException(this.message);

  @override
  String toString() => message;
}

class BilibiliWbiSigner {
  static const List<int> _mixinTable = <int>[
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    16,
    24,
    55,
    40,
    61,
    26,
    17,
    0,
    1,
    60,
    51,
    30,
    4,
    22,
    25,
    54,
    21,
    56,
    59,
    6,
    63,
    57,
    62,
    11,
    36,
    20,
    34,
    44,
    52,
  ];

  static String sign(
    Map<String, String> parameters, {
    required String imgKey,
    required String subKey,
    required int timestamp,
  }) {
    final String rawKey = imgKey + subKey;
    if (rawKey.length != 64) {
      throw const BilibiliVideoException('播放签名暂不可用，请稍后重试。');
    }
    final String mixin = _mixinTable.take(32).map((int i) => rawKey[i]).join();
    final Map<String, String> params = <String, String>{
      ...parameters,
      'wts': timestamp.toString(),
    }..remove('w_rid');
    final List<String> keys = params.keys.toList()..sort();
    final String query = keys
        .map((String key) {
          final String value = params[key]!.replaceAll(RegExp(r"[!'()*]"), '');
          return '${Uri.encodeComponent(key)}=${Uri.encodeComponent(value)}';
        })
        .join('&');
    final String signature = md5.convert(utf8.encode(query + mixin)).toString();
    return '$query&w_rid=$signature';
  }
}

class BilibiliVideoService {
  BilibiliVideoService({
    Dio? dio,
    DateTime Function()? clock,
    Future<String> Function()? cookieProvider,
    BilibiliAuthService? auth,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 15),
             ),
           ),
       _clock = clock ?? DateTime.now,
       _auth = cookieProvider == null
           ? (auth ?? BilibiliAuthService.instance)
           : null,
       _cookieProvider =
           cookieProvider ??
           (auth ?? BilibiliAuthService.instance).cookieHeader;

  final Dio _dio;
  final DateTime Function() _clock;
  final Future<String> Function() _cookieProvider;
  final BilibiliAuthService? _auth;
  String _visitorCookie = '';
  String? _imgKey;
  String? _subKey;
  DateTime? _keyExpiresAt;

  static const Map<String, String> _headers = <String, String>{
    'Referer': 'https://www.bilibili.com/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };
  static final RegExp _bv = RegExp(r'^BV[0-9A-Za-z]{10}$');

  static String parseBvid(String input) {
    final String value = input.trim();
    if (_bv.hasMatch(value)) return value;
    final Uri? uri = Uri.tryParse(value);
    if (uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'bilibili.com' ||
            uri.host == 'www.bilibili.com' ||
            uri.host == 'm.bilibili.com') &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'video' &&
        _bv.hasMatch(uri.pathSegments[1])) {
      return uri.pathSegments[1];
    }
    throw const BilibiliVideoException('请输入完整的 BV 号或 B站视频 HTTPS 链接。');
  }

  Future<BilibiliVideo> loadVideo(String input) async {
    final String bvid = parseBvid(input);
    final Map<String, dynamic> response = await _get(
      '/x/web-interface/view',
      parameters: <String, String>{'bvid': bvid},
    );
    final Map<String, dynamic> data = _data(response);
    final List<BilibiliPart> parts = <BilibiliPart>[];
    for (final Map<String, dynamic> page in _objects(data['pages'])) {
      final int cid = _integer(page['cid']);
      final int number = _integer(page['page']);
      if (cid <= 0 || number <= 0) continue;
      parts.add(
        BilibiliPart(
          cid: cid,
          page: number,
          title: _text(page['part']).isEmpty
              ? '分 P $number'
              : _text(page['part']),
          duration: Duration(seconds: _integer(page['duration'])),
        ),
      );
    }
    if (parts.isEmpty) {
      throw const BilibiliVideoException('这个视频没有可播放的分 P。');
    }
    return BilibiliVideo(
      bvid: bvid,
      title: _text(data['title']).isEmpty ? bvid : _text(data['title']),
      parts: parts,
    );
  }

  Future<PlayableMedia> resolvePart(
    BilibiliVideo video,
    BilibiliPart part, {
    int? preferredQuality,
  }) async {
    if (!video.parts.any(
      (BilibiliPart item) => item.cid == part.cid && item.page == part.page,
    )) {
      throw const BilibiliVideoException('分 P 与当前视频不匹配，请重新读取。');
    }
    await _loadKeys();
    Map<String, dynamic>? response;
    for (int attempt = 0; attempt < 2; attempt++) {
      final String query = BilibiliWbiSigner.sign(
        <String, String>{
          'bvid': video.bvid,
          'cid': part.cid.toString(),
          'qn': '80',
          'fnval': '16',
          'fnver': '0',
          'fourk': '0',
        },
        imgKey: _imgKey!,
        subKey: _subKey!,
        timestamp: _clock().millisecondsSinceEpoch ~/ 1000,
      );
      response = await _get('/x/player/wbi/playurl?$query');
      final Map<String, dynamic> data = _map(response['data']);
      if (attempt == 0 &&
          (_integer(response['code']) == -403 ||
              data.containsKey('v_voucher'))) {
        await _loadKeys(force: true);
        continue;
      }
      break;
    }
    final Map<String, dynamic> data = _data(response!);
    final Map<String, dynamic> dash = _map(data['dash']);
    String videoUrl;
    String? audioUrl;
    int quality;
    List<BilibiliQuality> qualities = <BilibiliQuality>[];
    if (dash.isNotEmpty) {
      final List<Map<String, dynamic>> videos = _objects(dash['video'])
          .where(
            (Map<String, dynamic> track) =>
                <int>{6, 16, 32, 64, 80}.contains(_integer(track['id'])) &&
                _isAvc(track) &&
                _streamUrl(track).isNotEmpty,
          )
          .toList();
      final List<Map<String, dynamic>> audios = _objects(dash['audio'])
          .where((Map<String, dynamic> track) => _streamUrl(track).isNotEmpty)
          .toList();
      if (videos.isEmpty || audios.isEmpty) {
        throw const BilibiliVideoException('没有兼容的完整音视频流，请在 B站客户端播放。');
      }
      videos.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        final int byQuality = _integer(b['id']).compareTo(_integer(a['id']));
        if (byQuality != 0) return byQuality;
        return _integer(b['bandwidth']).compareTo(_integer(a['bandwidth']));
      });
      final List<int> ids =
          videos.map((track) => _integer(track['id'])).toSet().toList()
            ..sort((a, b) => b.compareTo(a));
      qualities = ids
          .map((id) => BilibiliQuality(id, _qualityLabel(id)))
          .toList();
      final int requested = preferredQuality != null && preferredQuality > 0
          ? preferredQuality.clamp(6, 80)
          : 80;
      final Map<String, dynamic> selected = videos.firstWhere(
        (track) => _integer(track['id']) <= requested,
        orElse: () => videos.last,
      );
      audios.sort(
        (Map<String, dynamic> a, Map<String, dynamic> b) =>
            _integer(b['bandwidth']).compareTo(_integer(a['bandwidth'])),
      );
      videoUrl = _streamUrl(selected);
      audioUrl = _streamUrl(audios.first);
      quality = _integer(selected['id']);
    } else {
      final List<Map<String, dynamic>> streams = _objects(data['durl']);
      if (streams.length != 1 || _streamUrl(streams.first).isEmpty) {
        throw const BilibiliVideoException('这个视频暂时没有可播放的完整流。');
      }
      videoUrl = _streamUrl(streams.first);
      quality = _integer(data['quality']);
    }
    final String qualityLabel = _qualityLabel(quality);
    if (qualities.isEmpty) {
      qualities = <BilibiliQuality>[BilibiliQuality(quality, qualityLabel)];
    }
    return PlayableMedia(
      title: '${video.title} · ${part.label}',
      subjectTitle: video.title,
      episodeLabel: part.label,
      url: videoUrl,
      audioUrl: audioUrl,
      headers: _headers,
      bilibili: BilibiliPlayback(
        video: video,
        part: part,
        qualityLabel: qualityLabel,
        qualityId: quality,
        qualities: List<BilibiliQuality>.unmodifiable(qualities),
      ),
    );
  }

  static String _qualityLabel(int quality) => switch (quality) {
    6 => '240P',
    16 => '360P',
    32 => '480P',
    64 => '720P',
    80 => '1080P',
    _ => '默认画质',
  };

  Future<BilibiliSearchPage> searchVideos(
    String keyword, {
    int page = 1,
  }) async {
    final String term = keyword.trim();
    if (term.length < 2 || term.length > 100) {
      throw const BilibiliVideoException('请输入 2 至 100 个字符的搜索关键词。');
    }
    if (page < 1 || page > 50) throw const BilibiliVideoException('搜索页码无效。');
    await _loadKeys();
    if (_visitorCookie.isEmpty) {
      final Map<String, dynamic> visitor = _data(
        await _get('/x/frontend/finger/spi'),
      );
      final String buvid = _text(visitor['b_3']);
      if (buvid.isEmpty || RegExp(r'[;\r\n]').hasMatch(buvid)) {
        throw const BilibiliVideoException('搜索会话暂不可用，请稍后重试。');
      }
      _visitorCookie = 'buvid3=$buvid';
    }
    final String signed = BilibiliWbiSigner.sign(
      <String, String>{
        'search_type': 'video',
        'keyword': term,
        'page': '$page',
        'order': 'totalrank',
      },
      imgKey: _imgKey!,
      subKey: _subKey!,
      timestamp: _clock().millisecondsSinceEpoch ~/ 1000,
    );
    final Map<String, dynamic> data = _data(
      await _get('/x/web-interface/wbi/search/type?$signed'),
    );
    final List<BilibiliSearchHit> videos = <BilibiliSearchHit>[];
    for (final item in _objects(data['result'])) {
      final String bvid = _text(item['bvid']);
      if (!_bv.hasMatch(bvid)) continue;
      final String title = html.parseFragment(_text(item['title'])).text ?? '';
      int seconds = 0;
      for (final String piece in _text(item['duration']).split(':')) {
        seconds = seconds * 60 + (int.tryParse(piece) ?? 0);
      }
      int score = title.toLowerCase().contains(term.toLowerCase()) ? 80 : 55;
      if (seconds >= 900) score += 10;
      if (RegExp(
        r'解说|吐槽|MAD|AMV|混剪|盘点|片段|预告',
        caseSensitive: false,
      ).hasMatch(title)) {
        score -= 35;
      }
      videos.add(
        BilibiliSearchHit(
          bvid: bvid,
          title: title,
          author: _text(item['author']),
          duration: Duration(seconds: seconds),
          score: score,
        ),
      );
    }
    videos.sort((a, b) => b.score.compareTo(a.score));
    return BilibiliSearchPage(
      videos: List<BilibiliSearchHit>.unmodifiable(videos),
      page: page,
      totalPages: _integer(data['numPages']).clamp(1, 50),
    );
  }

  Future<void> _loadKeys({bool force = false}) async {
    if (!force &&
        _imgKey != null &&
        _subKey != null &&
        _keyExpiresAt != null &&
        _clock().isBefore(_keyExpiresAt!)) {
      return;
    }
    final Map<String, dynamic> response = await _get('/x/web-interface/nav');
    // Anonymous nav returns -101 while still supplying the public WBI keys.
    final Map<String, dynamic> keys = _map(_map(response['data'])['wbi_img']);
    String extract(dynamic value) {
      final Uri? uri = Uri.tryParse(_text(value));
      if (uri == null || uri.pathSegments.isEmpty) return '';
      return uri.pathSegments.last.split('.').first;
    }

    final String img = extract(keys['img_url']);
    final String sub = extract(keys['sub_url']);
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(img) ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(sub)) {
      throw const BilibiliVideoException('播放签名暂不可用，请稍后重试。');
    }
    _imgKey = img;
    _subKey = sub;
    _keyExpiresAt = _clock().add(const Duration(hours: 1));
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? parameters,
  }) async {
    try {
      final String cookie = await _cookieProvider();
      final String combinedCookie = <String>[
        cookie,
        _visitorCookie,
      ].where((part) => part.isNotEmpty).join('; ');
      final Response<dynamic> response = await _dio.get<dynamic>(
        'https://api.bilibili.com$path',
        queryParameters: parameters,
        options: Options(
          followRedirects: false,
          headers: <String, String>{
            ..._headers,
            if (combinedCookie.isNotEmpty) 'Cookie': combinedCookie,
          },
        ),
      );
      if (response.data is! Map) {
        throw const BilibiliVideoException('B站返回了无法识别的数据，请稍后重试。');
      }
      final Map<String, dynamic> body = _map(response.data);
      if (body['code'] == -101 &&
          !path.startsWith('/x/web-interface/nav') &&
          cookie.isNotEmpty) {
        await _auth?.signOut(expired: true);
        throw const BilibiliVideoException('B站登录已过期，请重新扫码登录。');
      }
      return body;
    } on DioException catch (error) {
      if (error.response?.statusCode == 412 ||
          error.response?.statusCode == 429) {
        throw const BilibiliVideoException('B站暂时限制了请求，请稍后重试。');
      }
      throw const BilibiliVideoException('无法连接 B站，请检查网络后重试。');
    }
  }

  static Map<String, dynamic> _data(Map<String, dynamic> response) {
    final Map<String, dynamic> data = _map(response['data']);
    final int? code = int.tryParse('${response['code']}');
    if (data.containsKey('v_voucher')) {
      throw const BilibiliVideoException('B站要求验证，请在 B站客户端打开视频后再试。');
    }
    if (code == -404 || code == 62002) {
      throw const BilibiliVideoException('视频不存在或已经下架。');
    }
    if (code == -352 || code == -412) {
      throw const BilibiliVideoException('B站暂时限制了搜索，请稍后重试或在 B站客户端完成验证。');
    }
    if (code != 0) {
      throw const BilibiliVideoException('这个视频当前不可播放，可能需要登录或额外权限。');
    }
    if (data.isEmpty) {
      throw const BilibiliVideoException('B站没有返回视频数据，请稍后重试。');
    }
    return data;
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _objects(dynamic value) => value is List
      ? value.whereType<Map>().map(_map).toList()
      : <Map<String, dynamic>>[];

  static String _text(dynamic value) => value is String ? value.trim() : '';

  static int _integer(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static bool _isAvc(Map<String, dynamic> track) {
    final int code = _integer(track['codecid']);
    return code == 7 ||
        (code == 0 && _text(track['codecs']).toLowerCase().startsWith('avc1.'));
  }

  static String _streamUrl(Map<String, dynamic> track) {
    final List<dynamic> candidates = <dynamic>[
      track['baseUrl'],
      track['base_url'],
      track['url'],
      if (track['backupUrl'] is List) ...track['backupUrl'] as List,
      if (track['backup_url'] is List) ...track['backup_url'] as List,
    ];
    for (final dynamic value in candidates) {
      final Uri? uri = Uri.tryParse(_text(value));
      if (uri != null &&
          uri.host.isNotEmpty &&
          (uri.scheme == 'https' || uri.scheme == 'http')) {
        return uri.replace(scheme: 'https').toString();
      }
    }
    return '';
  }
}
