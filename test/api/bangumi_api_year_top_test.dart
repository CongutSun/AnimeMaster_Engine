import 'dart:convert';
import 'dart:typed_data';

import 'package:animemaster/src/api/bangumi_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubResponse {
  const _StubResponse(this.statusCode, this.body)
    : contentType = 'text/html; charset=utf-8';

  const _StubResponse.json(this.statusCode, this.body)
    : contentType = 'application/json';

  final int statusCode;
  final String body;
  final String contentType;
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.responses);

  final List<_StubResponse> responses;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (responses.isEmpty) {
      throw StateError('Unexpected request: ${options.uri}');
    }
    final _StubResponse response = responses.removeAt(0);
    return ResponseBody.fromString(
      response.body,
      response.statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[response.contentType],
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

String _apiResponse(List<Map<String, dynamic>> subjects) {
  return jsonEncode(<String, dynamic>{
    'data': subjects,
    'total': subjects.length,
  });
}

Map<String, dynamic> _apiSubject({
  required int id,
  required int year,
  required int rank,
  double score = 8,
  int type = 2,
}) {
  return <String, dynamic>{
    'id': id,
    'type': type,
    'date': '$year-01-01',
    'name': '动画$id',
    'rating': <String, dynamic>{'rank': rank, 'score': score, 'total': 100},
    'images': <String, dynamic>{'large': 'https://example.com/$id.jpg'},
  };
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
    test(
      'uses the official API and keeps only ranked anime this year',
      () async {
        final int year = DateTime.now().year;
        late _QueueAdapter adapter;
        final BangumiApi api = _makeApi(
          <_StubResponse>[
            _StubResponse.json(
              200,
              _apiResponse(<Map<String, dynamic>>[
                _apiSubject(id: 1, year: year, rank: 200),
                _apiSubject(id: 2, year: year - 1, rank: 1),
                _apiSubject(id: 3, year: year, rank: 0),
                _apiSubject(id: 4, year: year, rank: 50, score: 8.5),
                _apiSubject(id: 5, year: year, rank: 2, type: 1),
              ]),
            ),
          ],
          (List<_StubResponse> responses) => adapter = _QueueAdapter(responses),
        );

        final List<Map<String, dynamic>> result = await api.getYearTop();

        expect(result.map((Map<String, dynamic> item) => item['id']), <int>[
          4,
          1,
        ]);
        expect(adapter.requests, hasLength(1));
        expect(adapter.requests.single.method, 'POST');
        expect(
          adapter.requests.single.uri.path,
          endsWith('/bangumi/api/v0/search/subjects'),
        );
        final Map<dynamic, dynamic> requestBody =
            adapter.requests.single.data as Map<dynamic, dynamic>;
        final Map<dynamic, dynamic> filter =
            requestBody['filter'] as Map<dynamic, dynamic>;
        expect(filter['air_date'], <String>[
          '>=$year-01-01',
          '<${year + 1}-01-01',
        ]);
        expect(filter['rank'], <String>['>=1']);
      },
    );

    test('falls back to the same-year page when the API fails', () async {
      late _QueueAdapter adapter;
      final BangumiApi api = _makeApi(<_StubResponse>[
        const _StubResponse.json(503, '{"error":"unavailable"}'),
        _StubResponse(200, _browserHtml(id: 456)),
      ], (List<_StubResponse> responses) => adapter = _QueueAdapter(responses));

      final List<Map<String, dynamic>> result = await api.getYearTop();

      expect(result.single['id'], 456);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.last.uri.path,
        endsWith('/anime/browser/airtime/${DateTime.now().year}'),
      );
      expect(
        adapter.requests.any(
          (RequestOptions request) =>
              request.uri.path.endsWith('/anime/browser'),
        ),
        isFalse,
      );
    });

    test('caches the first successful API result', () async {
      final int year = DateTime.now().year;
      late _QueueAdapter adapter;
      final BangumiApi api = _makeApi(<_StubResponse>[
        _StubResponse.json(
          200,
          _apiResponse(<Map<String, dynamic>>[
            _apiSubject(id: 1, year: year, rank: 50),
          ]),
        ),
      ], (List<_StubResponse> responses) => adapter = _QueueAdapter(responses));

      await api.getYearTop();
      await api.getYearTop();

      expect(adapter.requests, hasLength(1));
    });

    test('returns an empty list only after all candidates fail', () async {
      late _QueueAdapter adapter;
      final BangumiApi api = _makeApi(<_StubResponse>[
        const _StubResponse.json(503, '{"error":"unavailable"}'),
        const _StubResponse(503, 'unavailable'),
      ], (List<_StubResponse> responses) => adapter = _QueueAdapter(responses));

      final List<Map<String, dynamic>> result = await api.getYearTop();

      expect(result, isEmpty);
      expect(adapter.requests, hasLength(2));
    });
  });
}
