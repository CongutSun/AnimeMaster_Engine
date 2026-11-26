import 'dart:io';

import 'package:dio/dio.dart';

import '../models/download_task_info.dart';
import '../utils/app_storage_paths.dart';
import 'bilibili_video_service.dart';

class BilibiliOfflineDownloader {
  BilibiliOfflineDownloader({
    Dio? client,
    BilibiliVideoService? videos,
    this.directoryFor = AppStoragePaths.bilibiliTaskDirectory,
  }) : _client =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 25),
             ),
           ),
       _videos = videos ?? BilibiliVideoService();

  final Dio _client;
  final BilibiliVideoService _videos;
  final Future<Directory> Function(String) directoryFor;

  Future<DownloadTaskInfo> download(
    DownloadTaskInfo task,
    CancelToken cancel,
    void Function(String track, double fraction) progress,
  ) async {
    final match = DownloadTaskInfo.bilibiliKey.firstMatch(task.hash)!;
    final video = await _videos.loadVideo(match[1]!);
    if (!video.allowsDownload) {
      throw const BilibiliVideoException('这个视频未开放离线缓存。');
    }
    final part = video.parts
        .where((p) => p.cid == int.parse(match[2]!))
        .firstOrNull;
    if (part == null) throw const BilibiliVideoException('这个分 P 已不可用。');
    if (cancel.isCancelled) throw cancel.cancelError!;
    final media = await _videos.resolvePart(video, part);
    if (media.bilibili?.restrictedToStreaming == true) {
      throw const BilibiliVideoException('当前分 P 仅提供在线播放。');
    }
    if (cancel.isCancelled) throw cancel.cancelError!;
    final dir = await directoryFor(task.hash);
    final picture = File('${dir.path}/video.mp4');
    final sound = File('${dir.path}/audio.m4a');
    try {
      final pictureSize = await _track(
        media.url,
        picture,
        media.headers,
        cancel,
        (fraction) => progress('视频', fraction),
      );
      final audioUrl = media.audioUrl;
      final audioSize = audioUrl == null
          ? 0
          : await _track(
              audioUrl,
              sound,
              media.headers,
              cancel,
              (fraction) => progress('音频', fraction),
            );
      if (audioSize == 0 && await sound.exists()) await sound.delete();
      if (cancel.isCancelled) throw cancel.cancelError!;
      return task.copyWith(
        savePath: dir.path,
        targetPath: picture.path,
        targetSize: pictureSize,
        audioSize: audioSize,
        isCompleted: true,
        isPaused: false,
      );
    } catch (_) {
      for (final file in [picture, sound]) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
  }

  Future<int> _track(
    String url,
    File destination,
    Map<String, String>? headers,
    CancelToken cancel,
    void Function(double) progress,
  ) async {
    var uri = Uri.parse(url);
    for (var hop = 0; hop <= 4; hop++) {
      final host = uri.host.toLowerCase();
      const domains = [
        'bilivideo.com',
        'bilivideo.cn',
        'bilibili.com',
        'hdslb.com',
      ];
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          !(domains.any((d) => host == d || host.endsWith('.$d')) ||
              (host.startsWith('upos-') && host.endsWith('.akamaized.net')))) {
        throw const BilibiliVideoException('缓存地址不可用，请重新读取视频。');
      }
      final response = await _client.getUri<ResponseBody>(
        uri,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 400,
          headers: {
            for (final e in (headers ?? <String, String>{}).entries)
              if (['referer', 'user-agent'].contains(e.key.toLowerCase()))
                e.key: e.value,
            'Accept-Encoding': 'identity',
          },
        ),
      );
      final body = response.data!;
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        await body.stream.listen(null).cancel();
        final location = response.headers.value('location');
        if (location == null) break;
        uri = uri.resolve(location);
        continue;
      }
      final length =
          int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
      final type = (response.headers.value('content-type') ?? '').toLowerCase();
      if (response.statusCode != 200 ||
          response.headers.value('content-range') != null ||
          length <= 0 ||
          type.startsWith('text/') ||
          type.contains('json') ||
          type.contains('xml')) {
        await body.stream.listen(null).cancel();
        throw const BilibiliVideoException('未取得完整的媒体文件，请重试。');
      }
      var received = 0;
      var lastPercent = -1;
      final output = destination.openWrite();
      try {
        progress(0);
        await output.addStream(
          body.stream.map((chunk) {
            if (cancel.isCancelled) throw cancel.cancelError!;
            received += chunk.length;
            if (received > length) {
              throw const BilibiliVideoException('媒体文件长度不符，请重试。');
            }
            final percent = received * 100 ~/ length;
            if (percent != lastPercent) {
              lastPercent = percent;
              progress(received / length);
            }
            return chunk;
          }),
        );
      } finally {
        await output.close();
      }
      if (received != length || await destination.length() != length) {
        throw const BilibiliVideoException('媒体文件下载不完整，请重试。');
      }
      return length;
    }
    throw const BilibiliVideoException('缓存地址跳转失败，请重试。');
  }
}
