import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:animemaster/src/services/media_reachability_probe.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MediaAdapter implements HttpClientAdapter {
  _MediaAdapter(this.status, this.chunks, {this.length});
  final int status;
  final List<Uint8List> chunks;
  final int? length;
  late RequestOptions request;
  int delivered = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? data,
    Future<void>? cancel,
  ) async {
    request = options;
    Stream<Uint8List> stream() async* {
      for (final chunk in chunks) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        delivered += chunk.length;
        yield chunk;
      }
    }

    return ResponseBody(
      stream(),
      status,
      headers: {
        if (length != null) Headers.contentLengthHeader: ['$length'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<bool> _probe(_MediaAdapter adapter, {bool playlist = false}) =>
    probeMediaReachability(
      Dio()..httpClientAdapter = adapter,
      'https://media.example/video.${playlist ? 'm3u8' : 'mp4'}',
      {},
      timeout: const Duration(seconds: 3),
    );

void main() {
  for (final scenario in [(206, 2048), (200, 1024 * 1024), (200, null)]) {
    test(
      'bounds video reads for ${scenario.$1} with length ${scenario.$2}',
      () async {
        final chunks = List.filled(100, Uint8List(1024));
        final adapter = _MediaAdapter(scenario.$1, chunks, length: scenario.$2);
        expect(await _probe(adapter), isTrue);
        expect(adapter.request.headers['Range'], 'bytes=0-2047');
        expect(adapter.request.cancelToken!.isCancelled, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(adapter.delivered, lessThanOrEqualTo(2048));
      },
    );
  }

  test(
    'caps the playlist prefix even when one transport chunk exceeds the budget',
    () async {
      final chunk = Uint8List(128 * 1024)
        ..setAll(65536, ascii.encode('#EXTM3U'));
      final adapter = _MediaAdapter(200, [chunk, chunk]);
      expect(await _probe(adapter, playlist: true), isFalse);
      expect(adapter.request.cancelToken!.isCancelled, isTrue);
      expect(adapter.delivered, chunk.length);
    },
  );

  test('recognizes a playlist marker split across transport chunks', () async {
    final adapter = _MediaAdapter(200, [
      Uint8List.fromList(ascii.encode('#EXT')),
      Uint8List.fromList(ascii.encode('M3U\n')),
    ]);
    expect(await _probe(adapter, playlist: true), isTrue);
  });

  test('rejects empty success and error responses', () async {
    expect(await _probe(_MediaAdapter(206, [])), isFalse);
    expect(await _probe(_MediaAdapter(404, [Uint8List(64)])), isFalse);
  });
}
