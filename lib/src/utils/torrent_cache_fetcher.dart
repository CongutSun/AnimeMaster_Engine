import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';

class TorrentCacheFetcher {
  static String extractHash(String input) {
    final RegExp regex = RegExp(
      r'urn:btih:([a-zA-Z0-9]+)(?:&|$)',
      caseSensitive: false,
    );
    final Match? match = regex.firstMatch(input);
    if (match != null) {
      final value = match.group(1)!.toUpperCase();
      return RegExp(r'^(?:[A-F0-9]{40}|[A-Z2-7]{32})$').hasMatch(value)
          ? value
          : '';
    }

    final RegExp rawHashRegex = RegExp(
      r'^(?:[a-fA-F0-9]{40}|[a-zA-Z2-7]{32})$',
    );
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

  static Future<Uint8List?> fetchFromHttpCache(
    String magnetUrl, {
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
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
    final clients = <HttpClient>[];

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
      unawaited(
        _fetchSingleNode(url, hash, clients).then((Uint8List? bytes) {
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
        }),
      );
    }

    try {
      return await Future.any<Uint8List?>([
        completer.future,
        if (cancelToken != null)
          cancelToken.whenCancel.then<Uint8List?>((error) => throw error),
      ]);
    } finally {
      resolved = true;
      globalTimeout.cancel();
      for (final client in clients) {
        client.close(force: true);
      }
    }
  }

  static Future<Uint8List?> _fetchSingleNode(
    String url,
    String hash,
    List<HttpClient> clients,
  ) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..idleTimeout = const Duration(seconds: 4);
    clients.add(client);

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
        final collected = <int>[];
        await for (final chunk in response) {
          collected.addAll(chunk);
          if (collected.length > 4 * 1024 * 1024) return null;
        }
        final bytes = Uint8List.fromList(collected);
        if (bytes.isNotEmpty && bytes.first == 100) {
          final torrent = await Torrent.parseFromBytes(bytes);
          if (torrent.infoHash.toUpperCase() == hash) return bytes;
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
