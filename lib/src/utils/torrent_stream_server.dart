import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../managers/download_manager.dart';

class TorrentStreamServer {
  static const int _chunkSize = 64 * 1024;
  static const int _startupProbeBytes = 512 * 1024;
  static const int _maxHoleRetries = 960;
  static const Duration _probeDelay = Duration(milliseconds: 250);

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
    await DownloadManager().prepareForPlayback(infoHash);
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

    DownloadManager().prioritizePlaybackRange(
      infoHash,
      videoFilePath,
      start,
      min(_startupProbeBytes, end - start + 1),
    );

    if (request.method != 'HEAD' &&
        !await _waitForReadableRange(
          file,
          start,
          min(_startupProbeBytes, end - start + 1),
        )) {
      _sendErrorResponse(request, HttpStatus.serviceUnavailable);
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

        final int bytesToRead = min(_chunkSize, end - currentPos + 1);
        DownloadManager().prioritizePlaybackRange(
          infoHash,
          videoFilePath,
          currentPos,
          bytesToRead,
        );
        final List<int> buffer = await _readReadyChunk(
          raf,
          currentPos,
          bytesToRead,
        );

        if (buffer.length != bytesToRead) {
          break;
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

  Future<bool> _waitForReadableRange(
    File file,
    int start,
    int requiredBytes,
  ) async {
    if (requiredBytes <= 0) {
      return true;
    }

    for (int i = 0; i < _maxHoleRetries; i++) {
      if (!DownloadManager().hasTask(infoHash)) {
        return false;
      }

      if (!await file.exists()) {
        await Future.delayed(_probeDelay);
        continue;
      }

      RandomAccessFile? raf;
      try {
        final int fileLength = await file.length();
        final int probeLength = min(requiredBytes, _chunkSize);
        if (fileLength < start + probeLength) {
          await Future.delayed(_probeDelay);
          continue;
        }

        raf = await file.open(mode: FileMode.read);
        await raf.setPosition(start);
        final List<int> probe = await raf.read(probeLength);
        if (probe.isNotEmpty && !_isZeroFilled(probe)) {
          return true;
        }
      } catch (_) {
        // The downloader may be replacing file handles while writing.
      } finally {
        await raf?.close();
      }

      await Future.delayed(_probeDelay);
    }

    return false;
  }

  Future<List<int>> _readReadyChunk(
    RandomAccessFile raf,
    int position,
    int length,
  ) async {
    for (int i = 0; i < _maxHoleRetries; i++) {
      if (!DownloadManager().hasTask(infoHash)) {
        return const <int>[];
      }

      await raf.setPosition(position);
      final int availableLength = await raf.length();
      if (availableLength < position + length) {
        await Future.delayed(_probeDelay);
        continue;
      }

      final List<int> buffer = await raf.read(length);
      if (buffer.length == length && !_isZeroFilled(buffer)) {
        return buffer;
      }

      await Future.delayed(_probeDelay);
    }

    return const <int>[];
  }

  bool _isZeroFilled(List<int> buffer) {
    if (buffer.isEmpty || buffer.first != 0 || buffer.last != 0) {
      return false;
    }
    return !buffer.any((byte) => byte != 0);
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
