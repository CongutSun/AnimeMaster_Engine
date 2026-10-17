import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:animemaster/src/services/bilibili_auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handle;
  _Adapter(this.handle);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handle(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _reply(Map<String, dynamic> body, {List<String>? cookies}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
        'set-cookie': ?cookies,
      },
    );

Map<String, dynamic> _account() => <String, dynamic>{
  'code': 0,
  'data': <String, dynamic>{
    'isLogin': true,
    'mid': 123,
    'uname': '测试用户',
    'vipStatus': 1,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BilibiliAuthService auth;
  late List<RequestOptions> requests;
  late Future<ResponseBody> Function(RequestOptions) handler;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    requests = <RequestOptions>[];
    handler = (options) async {
      if (options.uri.path.endsWith('/generate')) {
        return _reply(<String, dynamic>{
          'code': 0,
          'data': <String, String>{
            'url':
                'https://passport.bilibili.com/h5-app/passport/login/scan?qrcode_key=key',
            'qrcode_key': 'key',
          },
        });
      }
      if (options.uri.path.endsWith('/poll')) {
        return _reply(
          <String, dynamic>{
            'code': 0,
            'data': <String, int>{'code': 0},
          },
          cookies: <String>[
            'SESSDATA=test-session; Path=/; Domain=bilibili.com; HttpOnly; Secure',
            'bili_jct=test-csrf; Path=/; Domain=bilibili.com',
          ],
        );
      }
      return _reply(_account());
    };
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) {
        requests.add(options);
        return handler(options);
      });
    auth = BilibiliAuthService(dio: dio);
  });

  test(
    'clearing stored authorization before initialization cannot restore the old session',
    () async {
      await auth.poll(await auth.beginLogin());
      final fresh = BilibiliAuthService();
      final cleared = fresh.signOut();
      final header = fresh.cookieHeader();
      await cleared;
      expect(await header, isEmpty);
      expect(fresh.isLoggedIn, isFalse);
    },
  );

  test(
    'current account-domain QR URL is accepted while unrelated origins are rejected',
    () async {
      handler = (_) async => _reply(<String, dynamic>{
        'code': 0,
        'data': <String, String>{
          'url':
              'https://account.bilibili.com/h5/account-h5/auth/scan-web?qrcode_key=key',
          'qrcode_key': 'key',
        },
      });
      expect(
        Uri.parse((await auth.beginLogin()).url).host,
        'account.bilibili.com',
      );
      handler = (_) async => _reply(<String, dynamic>{
        'code': 0,
        'data': <String, String>{
          'url': 'https://account.bilibili.com.evil.example/scan?key=key',
          'qrcode_key': 'key',
        },
      });
      await expectLater(
        auth.beginLogin(),
        throwsA(isA<BilibiliAuthException>()),
      );
    },
  );

  test(
    'QR login verifies session before saving and restores the account from secure storage',
    () async {
      final attempt = await auth.beginLogin();
      expect(attempt.appUri.scheme, 'bilibili');
      expect(await auth.poll(attempt), BilibiliLoginStatus.success);
      expect(auth.account!.uid, 123);
      expect(auth.account!.isVip, isTrue);
      expect(
        requests.last.headers['Cookie'],
        contains('SESSDATA=test-session'),
      );
      final restored = BilibiliAuthService();
      await restored.initialize();
      expect(restored.account!.name, '测试用户');
      await auth.signOut();
      expect(await auth.cookieHeader(), isEmpty);
      expect(
        await const FlutterSecureStorage().read(
          key: BilibiliAuthService.storageKey,
        ),
        isNull,
      );
    },
  );

  test('successful poll without cookies is not a successful login', () async {
    final attempt = await auth.beginLogin();
    handler = (_) async => _reply(<String, dynamic>{
      'code': 0,
      'data': <String, int>{'code': 0},
    });
    await expectLater(
      auth.poll(attempt),
      throwsA(isA<BilibiliAuthException>()),
    );
    expect(auth.isLoggedIn, isFalse);
    expect(
      await const FlutterSecureStorage().read(
        key: BilibiliAuthService.storageKey,
      ),
      isNull,
    );
  });

  test(
    'cancel during account verification prevents a late response from saving credentials',
    () async {
      final attempt = await auth.beginLogin();
      final entered = Completer<void>();
      final gate = Completer<ResponseBody>();
      final previous = handler;
      handler = (options) {
        if (options.uri.path.endsWith('/nav')) {
          entered.complete();
          return gate.future;
        }
        return previous(options);
      };
      final pending = auth.poll(attempt);
      await entered.future;
      auth.cancelLogin();
      gate.complete(_reply(_account()));
      expect(await pending, BilibiliLoginStatus.cancelled);
      expect(auth.isLoggedIn, isFalse);
      expect(
        await const FlutterSecureStorage().read(
          key: BilibiliAuthService.storageKey,
        ),
        isNull,
      );
    },
  );

  test('waiting and scanned states do not persist a session', () async {
    final attempt = await auth.beginLogin();
    handler = (_) async => _reply(<String, dynamic>{
      'code': 0,
      'data': <String, int>{'code': 86101},
    });
    expect(await auth.poll(attempt), BilibiliLoginStatus.waiting);
    handler = (_) async => _reply(<String, dynamic>{
      'code': 0,
      'data': <String, int>{'code': 86090},
    });
    expect(await auth.poll(attempt), BilibiliLoginStatus.scanned);
    expect(auth.isLoggedIn, isFalse);
  });

  test(
    'network failure preserves credentials while server expiration clears them',
    () async {
      await auth.poll(await auth.beginLogin());
      handler = (options) async => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
      await expectLater(auth.refresh(), throwsA(isA<BilibiliAuthException>()));
      expect(auth.isLoggedIn, isTrue);
      handler = (_) async => _reply(<String, dynamic>{
        'code': -101,
        'data': <String, bool>{'isLogin': false},
      });
      await expectLater(auth.refresh(), throwsA(isA<BilibiliAuthException>()));
      expect(auth.isLoggedIn, isFalse);
      expect(auth.isExpired, isTrue);
    },
  );
}
