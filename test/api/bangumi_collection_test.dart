import 'dart:typed_data';
import 'package:animemaster/src/api/bangumi_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  RequestOptions? request;
  int status = 200;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      '{"data":[{"ep_status":6}]}',
      status,
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
    'collection reads include current authentication and preserve progress',
    () async {
      final adapter = _Adapter();
      final api = BangumiApi.forTesting(
        dio: Dio()..httpClientAdapter = adapter,
      );
      final data = await api.getUserCollectionList('test', token: 'test-token');
      expect(adapter.request!.headers['Authorization'], 'Bearer test-token');
      expect(data.single['ep_status'], 6);
    },
  );
  test(
    'collection failures remain errors instead of becoming an empty library',
    () async {
      final adapter = _Adapter()..status = 503;
      final api = BangumiApi.forTesting(
        dio: Dio()..httpClientAdapter = adapter,
      );
      await expectLater(
        api.getUserCollectionList('test'),
        throwsA(isA<DioException>()),
      );
    },
  );
}
