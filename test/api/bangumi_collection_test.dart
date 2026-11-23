import 'dart:convert';
import 'dart:typed_data';
import 'package:animemaster/src/api/bangumi_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  RequestOptions? request;
  int status = 200;
  Map<String, dynamic> Function(RequestOptions)? page;
  final offsets = <int>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    offsets.add(options.queryParameters['offset'] as int);
    return ResponseBody.fromString(
      jsonEncode(
        page?.call(options) ??
            {
              'data': [
                {'ep_status': 6},
              ],
            },
      ),
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
  for (final count in [0, 100, 101, 203]) {
    test(
      'loads all $count subjects with stable credentials and filters',
      () async {
        final adapter = _Adapter()
          ..page = (options) {
            expect(options.headers['Authorization'], 'Bearer test-token');
            expect(options.queryParameters['subject_type'], 1);
            expect(options.queryParameters['type'], 2);
            final offset = options.queryParameters['offset'] as int;
            return {
              'total': count,
              'offset': offset,
              'data': [
                for (int i = offset; i < count && i < offset + 100; i++)
                  {'subject_id': i + 1, 'ep_status': i},
              ],
            };
          };
        final api = BangumiApi.forTesting(
          dio: Dio()..httpClientAdapter = adapter,
        );
        final all = await api.getUserCollectionList(
          'test',
          token: 'test-token',
          subjectType: 1,
          type: 2,
        );
        expect(all.length, count);
        expect(adapter.offsets, [0, for (int i = 100; i < count; i += 100) i]);
        if (count > 0) expect(all.last['ep_status'], count - 1);
      },
    );
  }
  test(
    'handles missing totals and overlapping pages without duplicating subjects',
    () async {
      final adapter = _Adapter()
        ..page = (options) => {
          'data': options.queryParameters['offset'] == 0
              ? List.generate(100, (i) => {'subject_id': i + 1})
              : [
                  {'subject_id': 100},
                  {'subject_id': 101},
                ],
        };
      final api = BangumiApi.forTesting(
        dio: Dio()..httpClientAdapter = adapter,
      );
      expect((await api.getUserCollectionList('test')).length, 101);
      expect(adapter.offsets, [0, 100]);
    },
  );
  test(
    'a missing later page cannot be returned as a complete watch list',
    () async {
      final adapter = _Adapter()
        ..page = (options) => {
          'total': 101,
          'data': options.queryParameters['offset'] == 0
              ? List.generate(100, (i) => {'subject_id': i + 1})
              : [],
        };
      final api = BangumiApi.forTesting(
        dio: Dio()..httpClientAdapter = adapter,
      );
      await expectLater(api.getUserCollectionList('test'), throwsStateError);
    },
  );
}
