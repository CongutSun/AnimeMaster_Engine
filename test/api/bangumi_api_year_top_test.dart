import 'dart:typed_data';

import 'package:animemaster/src/api/bangumi_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubResponse {
  const _StubResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.responses);

  final List<_StubResponse> responses;
  final List<Uri> requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    if (responses.isEmpty) {
      throw StateError('Unexpected request: ${options.uri}');
    }
    final _StubResponse response = responses.removeAt(0);
    return ResponseBody.fromString(
      response.body,
      response.statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _browserHtml({int id = 123}) {
  return '''
    <html><body>
      <ul id="browserItemList">
        <li class="item">
          <a class="l" href="/subject/$id">测试动画</a>
          <small class="fade">8.7</small>
          <img src="//lain.bgm.tv/pic/cover/s/test.jpg">
        </li>
      </ul>
    </body></html>
  ''';
}

BangumiApi _makeApi(
  List<_StubResponse> responses,
  _QueueAdapter Function(List<_StubResponse>) capture,
) {
  final _QueueAdapter adapter = capture(responses);
  final Dio dio = Dio()..httpClientAdapter = adapter;
  return BangumiApi.forTesting(dio: dio);
}

void main() {
  group('BangumiApi.getYearTop', () {
    test('falls back when the year page returns HTTP 403', () async {
      late _QueueAdapter adapter;
      final BangumiApi api = _makeApi(<_StubResponse>[
        const _StubResponse(403, '<title>Just a moment...</title>'),
        _StubResponse(200, _browserHtml()),
      ], (List<_StubResponse> responses) => adapter = _QueueAdapter(responses));

      final List<Map<String, dynamic>> result = await api.getYearTop();

      expect(result, hasLength(1));
      expect(result.single['id'], 123);
      expect(result.single['name'], '测试动画');
      expect((result.single['rating'] as Map<String, dynamic>)['score'], '8.7');
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.first.path,
        endsWith('/anime/browser/airtime/${DateTime.now().year}'),
      );
      expect(adapter.requests.last.path, endsWith('/anime/browser'));
    });

    test(
      'falls back when a successful response has no parseable items',
      () async {
        late _QueueAdapter adapter;
        final BangumiApi api = _makeApi(
          <_StubResponse>[
            const _StubResponse(
              200,
              '<html><body>changed markup</body></html>',
            ),
            _StubResponse(200, _browserHtml(id: 456)),
          ],
          (List<_StubResponse> responses) => adapter = _QueueAdapter(responses),
        );

        final List<Map<String, dynamic>> result = await api.getYearTop();

        expect(result.single['id'], 456);
        expect(adapter.requests, hasLength(2));
      },
    );

    test('caches the first successful fallback result', () async {
      late _QueueAdapter adapter;
      final BangumiApi api = _makeApi(<_StubResponse>[
        const _StubResponse(403, 'challenge'),
        _StubResponse(200, _browserHtml()),
      ], (List<_StubResponse> responses) => adapter = _QueueAdapter(responses));

      await api.getYearTop();
      await api.getYearTop();

      expect(adapter.requests, hasLength(2));
    });

    test('returns an empty list only after all candidates fail', () async {
      late _QueueAdapter adapter;
      final BangumiApi api = _makeApi(<_StubResponse>[
        const _StubResponse(403, 'challenge'),
        const _StubResponse(503, 'unavailable'),
      ], (List<_StubResponse> responses) => adapter = _QueueAdapter(responses));

      final List<Map<String, dynamic>> result = await api.getYearTop();

      expect(result, isEmpty);
      expect(adapter.requests, hasLength(2));
    });
  });
}
