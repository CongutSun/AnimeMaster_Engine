import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BilibiliAuthException implements Exception {
  final String message;
  final bool invalidSession;
  const BilibiliAuthException(this.message, {this.invalidSession = false});
  @override
  String toString() => message;
}

class BilibiliAccount {
  final int uid;
  final String name;
  final bool isVip;
  const BilibiliAccount({
    required this.uid,
    required this.name,
    required this.isVip,
  });
}

class BilibiliLoginAttempt {
  final String url;
  final String key;
  final DateTime expiresAt;
  final int generation;
  const BilibiliLoginAttempt({
    required this.url,
    required this.key,
    required this.expiresAt,
    required this.generation,
  });

  Uri get appUri => Uri(
    scheme: 'bilibili',
    host: 'browser',
    queryParameters: <String, String>{'url': url},
  );
}

enum BilibiliLoginStatus { waiting, scanned, expired, success, cancelled }

class BilibiliAuthService extends ChangeNotifier {
  BilibiliAuthService({
    Dio? dio,
    FlutterSecureStorage? storage,
    DateTime Function()? clock,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 15),
             ),
           ),
       _storage = storage ?? const FlutterSecureStorage(),
       _clock = clock ?? DateTime.now;

  static final BilibiliAuthService instance = BilibiliAuthService();
  static const String storageKey = 'bilibili.session.v1';
  static const Set<String> _cookieNames = <String>{
    'SESSDATA',
    'bili_jct',
    'DedeUserID',
    'DedeUserID__ckMd5',
  };
  final Dio _dio;
  final FlutterSecureStorage _storage;
  final DateTime Function() _clock;
  Future<void>? _initialization;
  Future<void> _storageQueue = Future<void>.value();
  Map<String, String> _cookies = <String, String>{};
  BilibiliAccount? _account;
  DateTime? _expiresAt;
  int _generation = 0;
  CancelToken? _loginCancel;
  int? _pollingGeneration;
  bool _expired = false;

  BilibiliAccount? get account => _account;
  bool get isLoggedIn =>
      _account != null && _cookies['SESSDATA']?.isNotEmpty == true;
  bool get isExpired => _expired;

  Future<void> initialize() => _initialization ??= _loadStored(_generation)
      .onError((Object error, StackTrace stack) {
        _initialization = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _store(Future<void> Function() action) {
    final Future<void> operation = _storageQueue.then((_) => action());
    _storageQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _loadStored(int generation) async {
    await _storageQueue;
    final String? raw = await _storage.read(key: storageKey);
    if (generation != _generation || raw == null) return;
    try {
      final dynamic data = jsonDecode(raw);
      final Map<String, String> cookies = Map<String, String>.from(
        data['cookies'] as Map,
      );
      if (!_validCookies(cookies)) throw const FormatException();
      final int uid = data['uid'] as int;
      if (uid <= 0) throw const FormatException();
      _cookies = cookies;
      _account = BilibiliAccount(
        uid: uid,
        name: data['name'] as String,
        isVip: data['vip'] == true,
      );
      _expiresAt = DateTime.tryParse(data['expiresAt'] as String? ?? '');
      if (_expiresAt != null && !_clock().isBefore(_expiresAt!)) {
        await signOut(expired: true);
      } else {
        notifyListeners();
      }
    } on FormatException {
      await signOut(expired: true);
    } on TypeError {
      await signOut(expired: true);
    }
  }

  Future<String> cookieHeader() async {
    await initialize();
    if (_expiresAt != null && !_clock().isBefore(_expiresAt!)) {
      await signOut(expired: true);
    }
    return _header(_cookies);
  }

  Future<void> refresh() async {
    await initialize();
    if (!isLoggedIn) return;
    final int generation = _generation;
    try {
      final BilibiliAccount account = await _validate(_cookies);
      if (generation != _generation) return;
      _account = account;
      notifyListeners();
    } on BilibiliAuthException catch (error) {
      if (error.invalidSession && generation == _generation) {
        await signOut(expired: true);
      }
      rethrow;
    }
  }

  Future<BilibiliLoginAttempt> beginLogin() async {
    await initialize();
    cancelLogin();
    final int generation = _generation;
    final CancelToken cancel = _loginCancel = CancelToken();
    final Response<dynamic> response = await _request(
      'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
      cancel: cancel,
    );
    if (generation != _generation) throw const BilibiliAuthException('登录已取消。');
    final dynamic data = response.data['data'];
    if (response.data['code'] != 0 || data is! Map) {
      throw const BilibiliAuthException('暂时无法生成登录二维码，请重试。');
    }
    final String url = data['url'] is String ? data['url'] as String : '';
    final String key = data['qrcode_key'] is String
        ? data['qrcode_key'] as String
        : '';
    final Uri? uri = Uri.tryParse(url);
    if (key.isEmpty ||
        uri == null ||
        uri.scheme != 'https' ||
        !<String>{
          'passport.bilibili.com',
          'account.bilibili.com',
        }.contains(uri.host)) {
      throw const BilibiliAuthException('登录二维码无效，请重试。');
    }
    return BilibiliLoginAttempt(
      url: url,
      key: key,
      expiresAt: _clock().add(const Duration(seconds: 180)),
      generation: generation,
    );
  }

  Future<BilibiliLoginStatus> poll(BilibiliLoginAttempt attempt) async {
    if (attempt.generation != _generation) return BilibiliLoginStatus.cancelled;
    if (!_clock().isBefore(attempt.expiresAt)) {
      return BilibiliLoginStatus.expired;
    }
    if (_pollingGeneration == attempt.generation) {
      throw const BilibiliAuthException('正在检查登录状态。');
    }
    _pollingGeneration = attempt.generation;
    try {
      final Response<dynamic> response = await _request(
        'https://passport.bilibili.com/x/passport-login/web/qrcode/poll',
        parameters: <String, String>{'qrcode_key': attempt.key},
        cancel: _loginCancel,
      );
      if (attempt.generation != _generation) {
        return BilibiliLoginStatus.cancelled;
      }
      final dynamic data = response.data['data'];
      if (response.data['code'] != 0 || data is! Map) {
        throw const BilibiliAuthException('无法检查登录状态，请重试。');
      }
      switch (data['code']) {
        case 86101:
          return BilibiliLoginStatus.waiting;
        case 86090:
          return BilibiliLoginStatus.scanned;
        case 86038:
          return BilibiliLoginStatus.expired;
        case 0:
          final Map<String, String> cookies = <String, String>{};
          DateTime? expiresAt;
          for (final String raw
              in response.headers['set-cookie'] ?? <String>[]) {
            try {
              final Cookie cookie = Cookie.fromSetCookieValue(raw);
              if (!_cookieNames.contains(cookie.name)) continue;
              cookies[cookie.name] = cookie.value;
              if (cookie.name == 'SESSDATA') expiresAt = cookie.expires;
            } on FormatException {
              continue;
            }
          }
          if (!_validCookies(cookies)) {
            throw const BilibiliAuthException('登录未返回有效凭据，请刷新二维码重试。');
          }
          final BilibiliAccount account = await _validate(cookies);
          if (attempt.generation != _generation) {
            return BilibiliLoginStatus.cancelled;
          }
          await _store(() async {
            if (attempt.generation != _generation) return;
            await _storage.write(
              key: storageKey,
              value: jsonEncode(<String, dynamic>{
                'cookies': cookies,
                'uid': account.uid,
                'name': account.name,
                'vip': account.isVip,
                'expiresAt': expiresAt?.toIso8601String(),
              }),
            );
            if (attempt.generation != _generation) return;
            _cookies = cookies;
            _account = account;
            _expiresAt = expiresAt;
            _expired = false;
            notifyListeners();
          });
          return attempt.generation == _generation
              ? BilibiliLoginStatus.success
              : BilibiliLoginStatus.cancelled;
        default:
          throw const BilibiliAuthException('B站返回了未知登录状态，请刷新二维码。');
      }
    } finally {
      if (_pollingGeneration == attempt.generation) _pollingGeneration = null;
    }
  }

  void cancelLogin() {
    _generation++;
    _loginCancel?.cancel();
    _loginCancel = null;
  }

  Future<void> signOut({bool expired = false}) async {
    cancelLogin();
    _cookies = <String, String>{};
    _account = null;
    _expiresAt = null;
    _expired = expired;
    notifyListeners();
    await _store(() => _storage.delete(key: storageKey));
  }

  Future<BilibiliAccount> _validate(Map<String, String> cookies) async {
    final Response<dynamic> response = await _request(
      'https://api.bilibili.com/x/web-interface/nav',
      cookie: _header(cookies),
    );
    final dynamic data = response.data['data'];
    if (response.data['code'] != 0 ||
        data is! Map ||
        data['isLogin'] != true ||
        data['mid'] is! int ||
        (data['mid'] as int) <= 0) {
      throw BilibiliAuthException(
        '登录状态无法确认，请稍后重试。',
        invalidSession:
            response.data['code'] == -101 ||
            (data is Map && data['isLogin'] == false),
      );
    }
    return BilibiliAccount(
      uid: data['mid'] as int,
      name: data['uname'] is String ? data['uname'] as String : 'B站用户',
      isVip: data['vipStatus'] == 1,
    );
  }

  Future<Response<dynamic>> _request(
    String url, {
    String? cookie,
    Map<String, String>? parameters,
    CancelToken? cancel,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        url,
        queryParameters: parameters,
        cancelToken: cancel,
        options: Options(
          followRedirects: false,
          headers: <String, String>{
            'Referer': 'https://www.bilibili.com/',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
          },
        ),
      );
      if (response.data is! Map) {
        throw const BilibiliAuthException('B站返回了无法识别的登录数据。');
      }
      return response;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const BilibiliAuthException('登录已取消。');
      }
      throw const BilibiliAuthException('无法连接 B站，请检查网络后重试。');
    }
  }

  static bool _validCookies(Map<String, String> cookies) =>
      cookies['SESSDATA']?.isNotEmpty == true &&
      cookies.entries.every(
        (entry) =>
            _cookieNames.contains(entry.key) &&
            !RegExp(r'[;\r\n]').hasMatch(entry.value),
      );

  static String _header(Map<String, String> cookies) =>
      cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
}
