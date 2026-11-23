import 'dart:convert';
import 'dart:typed_data';

import 'package:animemaster/src/services/bangumi_auth_gateway_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway implements HttpClientAdapter {
  bool supportsProof = true;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(
        options.path.endsWith('/start')
            ? {
                if (supportsProof) 'code_challenge_method': 'S256',
                'request_id': 'r',
                'authorization_url': 'https://bgm.tv/oauth/authorize',
              }
            : {'session_id': 'durable', 'access_token': 'access'},
      ),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'each login sends only its challenge before callback and exchanges proof in the POST body',
    () async {
      final adapter = _Gateway();
      final gateway = BangumiAuthGatewayService(
        baseUrl: 'https://gateway.example',
        dio: Dio()..httpClientAdapter = adapter,
      );
      final proof = BangumiLoginProof();
      expect(proof.verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(BangumiLoginProof().verifier, isNot(proof.verifier));
      await gateway.startAuthorization(
        callbackScheme: 'animemasteroauth',
        proof: proof,
      );
      final start = adapter.requests.single;
      expect(start.queryParameters['code_challenge_method'], 'S256');
      expect(
        start.queryParameters['code_challenge'],
        base64Url
            .encode(sha256.convert(ascii.encode(proof.verifier)).bytes)
            .replaceAll('=', ''),
      );
      expect(start.uri.toString(), isNot(contains(proof.verifier)));
      final session = await gateway.fetchSession('grant', proof: proof);
      final exchange = adapter.requests.last;
      expect(exchange.method, 'POST');
      expect(exchange.uri.hasQuery, isFalse);
      expect(exchange.data, {
        'session_id': 'grant',
        'code_verifier': proof.verifier,
      });
      expect(exchange.followRedirects, isFalse);
      expect(session.sessionId, 'durable');
    },
  );
  test('an old gateway cannot start an unbound login', () async {
    final adapter = _Gateway()..supportsProof = false;
    final gateway = BangumiAuthGatewayService(
      baseUrl: 'https://gateway.example',
      dio: Dio()..httpClientAdapter = adapter,
    );
    await expectLater(
      gateway.startAuthorization(
        callbackScheme: 'animemasteroauth',
        proof: BangumiLoginProof(),
      ),
      throwsException,
    );
    expect(adapter.requests.length, 1);
  });
  test('remote HTTP cannot carry a login proof', () async {
    final adapter = _Gateway();
    final gateway = BangumiAuthGatewayService(
      baseUrl: 'http://gateway.example',
      dio: Dio()..httpClientAdapter = adapter,
    );
    await expectLater(
      gateway.fetchSession('grant', proof: BangumiLoginProof()),
      throwsFormatException,
    );
    expect(adapter.requests, isEmpty);
  });
}
