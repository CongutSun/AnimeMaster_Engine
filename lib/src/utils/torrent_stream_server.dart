import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../managers/download_manager.dart';

class TorrentStreamServer {
  HttpServer? _server;
  final String videoFilePath;
  final int videoSize;
  final String infoHash;

  TorrentStreamServer({
    required this.videoFilePath,
    required this.videoSize,
    required this.infoHash,
  });

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handlePlayerRequest);
    return 'http://127.0.0.1:${_server!.port}/stream';
  }

  void stop() {
    _server?.close(force: true);
    _server = null;
  }

  Future<void> _handlePlayerRequest(HttpRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      _sendErrorResponse(request, HttpStatus.methodNotAllowed);
      return;
    }

    if (!DownloadManager().hasTask(infoHash)) {
      _sendErrorResponse(request, HttpStatus.notFound);
      return;
    }

    final File file = File(videoFilePath);
    if (!await _waitUntilFileExists(file)) {
      _sendErrorResponse(request, HttpStatus.notFound);
      return;
    }

    final String? rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final bool hasRange =
        rangeHeader != null && rangeHeader.startsWith('bytes=');
    int start = 0;
    int end = videoSize - 1;

    if (hasRange) {
      final List<String> range = rangeHeader.substring(6).split('-');
      start = int.tryParse(range.first) ?? 0;
      if (range.length > 1 && range[1].isNotEmpty) {
        end = int.tryParse(range[1]) ?? end;
      }
    }

    end = min(end, videoSize - 1);
    if (start < 0 || start > end) {
      _sendErrorResponse(request, HttpStatus.requestedRangeNotSatisfiable);
      return;
    }

    request.response.statusCode = hasRange
        ? HttpStatus.partialContent
        : HttpStatus.ok;
    request.response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.add(
      HttpHeaders.contentTypeHeader,
      _contentTypeForPath(videoFilePath),
    );
    request.response.headers.contentLength = end - start + 1;

    if (hasRange) {
      request.response.headers.add(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$videoSize',
      );
    }

    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }

    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      await raf.setPosition(start);
      int currentPos = start;

      while (currentPos <= end) {
        if (!DownloadManager().hasTask(infoHash)) {
          break;
        }

        final int bytesToRead = min(65536, end - currentPos + 1);
        final List<int> buffer = await raf.read(bytesToRead);

        if (buffer.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 500));
          await raf.setPosition(currentPos);
          continue;
        }

        bool isHole = false;
        if (buffer.first == 0 && buffer.last == 0) {
          isHole = !buffer.any((byte) => byte != 0);
        }

        if (isHole) {
          await Future.delayed(const Duration(milliseconds: 1000));
          await raf.setPosition(currentPos);
          continue;
        }

        request.response.add(buffer);
        currentPos += buffer.length;
      }
    } catch (_) {
      // Ignore disconnected clients.
    } finally {
      await raf?.close();
      await request.response.close();
    }
  }

  Future<bool> _waitUntilFileExists(File file) async {
    if (await file.exists()) {
      return true;
    }

    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await file.exists()) {
        return true;
      }
    }

    return false;
  }

  String _contentTypeForPath(String path) {
    final String lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.mp4') || lowerPath.endsWith('.m4v')) {
      return 'video/mp4';
    }
    if (lowerPath.endsWith('.mkv')) {
      return 'video/x-matroska';
    }
    if (lowerPath.endsWith('.webm')) {
      return 'video/webm';
    }
    if (lowerPath.endsWith('.avi')) {
      return 'video/x-msvideo';
    }
    if (lowerPath.endsWith('.wmv')) {
      return 'video/x-ms-wmv';
    }
    if (lowerPath.endsWith('.flv')) {
      return 'video/x-flv';
    }
    if (lowerPath.endsWith('.ts')) {
      return 'video/mp2t';
    }
    if (lowerPath.endsWith('.m2ts')) {
      return 'video/mp2t';
    }
    return 'application/octet-stream';
  }

  void _sendErrorResponse(HttpRequest request, int statusCode) {
    request.response.statusCode = statusCode;
    request.response.close();
  }
}
