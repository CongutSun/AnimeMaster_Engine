import 'dart:convert';
import 'dart:typed_data';

import 'package:animemaster/src/services/torrent_metadata_service.dart';
import 'package:animemaster/src/utils/torrent_cache_fetcher.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'BEP 9 info dictionary becomes a parseable torrent without changing its hash',
    () async {
      final info = ascii.encode(
        'd6:lengthi1e4:name8:test.mp412:piece lengthi16384e6:pieces20:abcdefghijklmnopqrste',
      );
      final hash = sha1.convert(info).toString();
      final bytes = TorrentMetadataService.wrapInfo(info, hash);
      final torrent = await Torrent.parseFromBytes(bytes);
      expect(torrent.infoHash.toLowerCase(), hash);
      expect(torrent.name, 'test.mp4');
      expect(torrent.files.single.length, 1);
    },
  );
  test('rejects mismatched or oversized metadata', () {
    expect(
      () => TorrentMetadataService.wrapInfo([100, 101], '0' * 40),
      throwsFormatException,
    );
    expect(
      () => TorrentMetadataService.wrapInfo(
        Uint8List(4 * 1024 * 1024 + 1),
        '0' * 40,
      ),
      throwsFormatException,
    );
  });
  test('rejects invalid hashes before peer discovery', () {
    expect(
      TorrentCacheFetcher.extractHash('magnet:?xt=urn:btih:${'Z' * 40}'),
      isEmpty,
    );
    expect(
      TorrentCacheFetcher.extractHash(
        'magnet:?xt=urn:btih:${'a' * 40}&dn=test',
      ),
      'A' * 40,
    );
    expect(TorrentCacheFetcher.extractHash('a' * 35), isEmpty);
  });
  test('cancelled requests do not start network discovery', () async {
    final token = CancelToken()..cancel();
    await expectLater(
      TorrentMetadataService().fetch('magnet:', 'a' * 40, cancelToken: token),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      TorrentCacheFetcher.fetchFromHttpCache('a' * 40, cancelToken: token),
      throwsA(isA<DioException>()),
    );
  });
}
