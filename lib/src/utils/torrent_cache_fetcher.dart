import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

class TorrentCacheFetcher {
  static String extractHash(String input) {
    final RegExp regex = RegExp(
      r'urn:btih:([a-zA-Z0-9]+)',
      caseSensitive: false,
    );
    final Match? match = regex.firstMatch(input);
    if (match != null) {
      return match.group(1)!.toUpperCase();
    }

    final RegExp rawHashRegex = RegExp(r'^[a-zA-Z0-9]{32,40}$');
    if (rawHashRegex.hasMatch(input)) {
      return input.toUpperCase();
    }

    return '';
  }

  static String base32ToHex(String base32) {
    const String base32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    String bits = '';
    for (int i = 0; i < base32.length; i++) {
      final int value = base32Chars.indexOf(base32[i].toUpperCase());
      if (value == -1) {
        continue;
      }
      bits += value.toRadixString(2).padLeft(5, '0');
    }

    String hex = '';
    for (int i = 0; i < bits.length - 3; i += 4) {
      final int chunk = int.parse(bits.substring(i, i + 4), radix: 2);
      hex += chunk.toRadixString(16);
    }
    return hex.toUpperCase();
  }

  static Future<Uint8List?> fetchFromHttpCache(String magnetUrl) async {
    String hash = extractHash(magnetUrl);
    if (hash.isEmpty) {
      return null;
    }

    if (hash.length == 32) {
      hash = base32ToHex(hash);
    } else if (hash.length != 40) {
      return null;
    }

    final String directUrl = 'https://itorrents.org/torrent/$hash.torrent';
    final List<String> requestUrls = <String>[
      directUrl,
      'https://api.codetabs.com/v1/proxy?quest=${Uri.encodeComponent(directUrl)}',
      'https://api.allorigins.win/raw?url=${Uri.encodeComponent(directUrl)}',
    ];

    final Completer<Uint8List?> completer = Completer<Uint8List?>();
    int pendingRequests = requestUrls.length;
    bool resolved = false;

    final Timer globalTimeout = Timer(const Duration(seconds: 7), () {
      if (!resolved) {
        resolved = true;
        debugPrint(
          '[TorrentCacheFetcher] Timed out while requesting torrent metadata.',
        );
        completer.complete(null);
      }
    });

    for (final String url in requestUrls) {
      _fetchSingleNode(url).then((Uint8List? bytes) {
        if (bytes != null && bytes.isNotEmpty && !resolved) {
          resolved = true;
          globalTimeout.cancel();
          completer.complete(bytes);
          return;
        }

        pendingRequests--;
        if (pendingRequests == 0 && !resolved) {
          resolved = true;
          globalTimeout.cancel();
          completer.complete(null);
        }
      });
    }

    return completer.future;
  }

  static Future<Uint8List?> _fetchSingleNode(String url) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..idleTimeout = const Duration(seconds: 4);

    try {
      final HttpClientRequest request = await client.getUrl(Uri.parse(url));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );

      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 4),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Uint8List bytes = await consolidateHttpClientResponseBytes(
          response,
        );
        if (bytes.isNotEmpty && bytes.first == 100) {
          return bytes;
        }
      }
    } catch (_) {
      // Ignore node-level failures and allow other cache nodes to race.
    } finally {
      client.close(force: true);
    }

    return null;
  }
}
