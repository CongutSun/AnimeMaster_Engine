import 'dart:async';
import 'dart:convert';
import 'dart:io';

class MediaDurationProbe {
  static const Duration _timeout = Duration(seconds: 6);

  const MediaDurationProbe._();

  static Future<Duration?> probeHttpDuration(
    String url, {
    Map<String, String>? headers,
  }) async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }

    if (!uri.toString().toLowerCase().contains('.m3u8')) {
      return null;
    }

    try {
      return await _probePlaylist(
        uri,
        headers ?? const <String, String>{},
        0,
      ).timeout(_timeout);
    } catch (_) {
      return null;
    }
  }

  static Future<Duration?> _probePlaylist(
    Uri uri,
    Map<String, String> headers,
    int depth,
  ) async {
    if (depth > 1) {
      return null;
    }

    final String text = await _loadText(uri, headers);
    final Duration? directDuration = _parseMediaPlaylistDuration(text);
    if (directDuration != null) {
      return directDuration;
    }

    final Uri? variant = _selectBestVariant(uri, text);
    if (variant == null) {
      return null;
    }
    return _probePlaylist(variant, headers, depth + 1);
  }

  static Future<String> _loadText(Uri uri, Map<String, String> headers) async {
    final HttpClient client = HttpClient()..connectionTimeout = _timeout;
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      request.followRedirects = true;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.apple.mpegurl,application/x-mpegURL,*/*',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        headers['User-Agent'] ?? headers['user-agent'] ?? 'AnimeMaster/1.0',
      );
      for (final MapEntry<String, String> header in headers.entries) {
        if (header.key.trim().isEmpty || header.value.trim().isEmpty) {
          continue;
        }
        request.headers.set(header.key, header.value);
      }

      final HttpClientResponse response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return '';
      }
      return response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  static Duration? _parseMediaPlaylistDuration(String playlist) {
    if (!playlist.contains('#EXTINF')) {
      return null;
    }
    final bool isVod =
        playlist.contains('#EXT-X-ENDLIST') ||
        playlist.contains('#EXT-X-PLAYLIST-TYPE:VOD');
    if (!isVod || playlist.contains('#EXT-X-PLAYLIST-TYPE:EVENT')) {
      return null;
    }

    double seconds = 0;
    for (final RegExpMatch match in RegExp(
      r'#EXTINF:([0-9]+(?:\.[0-9]+)?)',
    ).allMatches(playlist)) {
      seconds += double.tryParse(match.group(1) ?? '') ?? 0;
    }
    if (seconds <= 0) {
      return null;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  static Uri? _selectBestVariant(Uri baseUri, String playlist) {
    final List<String> lines = playlist
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();

    Uri? best;
    int bestBandwidth = -1;
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      if (!line.startsWith('#EXT-X-STREAM-INF')) {
        continue;
      }

      int bandwidth = 0;
      final RegExpMatch? match = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      if (match != null) {
        bandwidth = int.tryParse(match.group(1) ?? '') ?? 0;
      }

      String? variantPath;
      for (int j = i + 1; j < lines.length; j++) {
        if (lines[j].startsWith('#')) {
          continue;
        }
        variantPath = lines[j];
        break;
      }
      if (variantPath == null || variantPath.isEmpty) {
        continue;
      }

      if (best == null || bandwidth > bestBandwidth) {
        best = baseUri.resolve(variantPath);
        bestBandwidth = bandwidth;
      }
    }
    return best;
  }
}
