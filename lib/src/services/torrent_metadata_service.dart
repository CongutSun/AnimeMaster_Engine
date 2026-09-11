import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:dtorrent_tracker/dtorrent_tracker.dart';

import '../utils/tracker_pool.dart';

/// Runs peer discovery in an isolate so cancellation also closes its sockets.
class TorrentMetadataService {
  static Uint8List wrapInfo(List<int> info, String expectedHash) {
    if (info.isEmpty ||
        info.length > 4 * 1024 * 1024 ||
        sha1.convert(info).toString() != expectedHash.toLowerCase()) {
      throw const FormatException('种子元数据校验失败。');
    }
    return Uint8List.fromList([...ascii.encode('d4:info'), ...info, 101]);
  }

  Future<Uint8List> fetch(
    String source,
    String hash, {
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final messages = ReceivePort();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(_discover, [
        messages.sendPort,
        source,
        hash,
      ]);
      final result =
          await Future.any<Object?>([
            messages.first,
            if (cancelToken != null)
              cancelToken.whenCancel.then<Object?>((error) => throw error),
          ]).timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw TimeoutException(
              '暂未找到能提供文件信息的节点。可以重试、换用种子直链，或复制链接到其他下载器。',
            ),
          );
      if (result is Uint8List) return result;
      throw StateError(result?.toString() ?? '获取种子元数据失败。');
    } finally {
      isolate?.kill(priority: Isolate.immediate);
      messages.close();
    }
  }

  static Future<void> _discover(List<Object> args) async {
    final port = args[0] as SendPort;
    final source = args[1] as String;
    final hash = args[2] as String;
    try {
      final downloader = MetadataDownloader(hash);
      downloader.createListener()
        ..on<MetaDataDownloadComplete>((event) {
          try {
            port.send(wrapInfo(event.data, hash));
          } catch (_) {
            port.send('种子元数据校验失败，请更换资源。');
          }
        })
        ..on<MetaDataDownloadFailed>((event) => port.send('种子元数据校验失败，请更换资源。'));
      final tracker = TorrentAnnounceTracker(downloader);
      tracker.createListener().on<AnnouncePeerEventEvent>((event) {
        final peers = event.event?.peers;
        if (peers == null) return;
        for (final peer in peers) {
          downloader.addNewPeerAddress(peer, PeerSource.tracker);
        }
      });
      final starting = downloader.startDownload();
      final hashBytes = Uint8List.fromList([
        for (int i = 0; i < hash.length; i += 2)
          int.parse(hash.substring(i, i + 2), radix: 16),
      ]);
      final urls = {
        ...?Uri.tryParse(source)?.queryParametersAll['tr'],
        ...TrackerPool.robustTrackers,
      };
      for (final url in urls.take(30)) {
        final uri = Uri.tryParse(url);
        if (uri != null &&
            ['udp', 'http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty) {
          tracker.runTracker(uri, hashBytes);
        }
      }
      await starting;
    } catch (_) {
      port.send('无法建立种子节点连接，请检查网络后重试。');
    }
  }
}
