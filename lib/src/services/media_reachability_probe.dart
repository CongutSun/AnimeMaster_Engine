import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

const int _videoSampleBytes = 2048;
const int _playlistSampleBytes = 64 * 1024;

Future<bool> probeMediaReachability(
  Dio dio,
  String url,
  Map<String, String> headers, {
  required Duration timeout,
}) async {
  final playlist = url.toLowerCase().contains('.m3u8');
  final limit = playlist ? _playlistSampleBytes : _videoSampleBytes;
  final token = CancelToken();
  final deadline = Timer(timeout, () => token.cancel('Media probe timed out'));
  try {
    final response = await dio.get<ResponseBody>(
      url,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        sendTimeout: timeout,
        receiveTimeout: timeout,
        validateStatus: (_) => true,
        headers: {
          ...headers,
          if (!playlist) 'Range': 'bytes=0-${limit - 1}',
          'Accept': playlist
              ? 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*'
              : '*/*',
        },
      ),
    );
    final body = response.data;
    if (body == null ||
        (response.statusCode != 200 && response.statusCode != 206)) {
      return false;
    }
    final sample = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      if (chunk.isEmpty) continue;
      // A binary probe needs only evidence that the response actually has bytes.
      if (!playlist) return true;
      final remaining = limit - sample.length;
      sample.add(
        chunk.length <= remaining
            ? chunk
            : Uint8List.sublistView(chunk, 0, remaining),
      );
      if (sample.length == limit) break;
    }
    if (!playlist) return false;
    final text = utf8.decode(sample.takeBytes(), allowMalformed: true);
    return text.contains('#EXTM3U') || text.contains('.ts');
  } on Exception {
    return false;
  } finally {
    deadline.cancel();
    token.cancel('Media probe complete');
  }
}
