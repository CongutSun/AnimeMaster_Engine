import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Small on-disk cache; failures never prevent playback.
class DandanplayCache {
  DandanplayCache({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationCacheDirectory;
  final Future<Directory> Function() _directory;
  static Future<void> _writes = Future<void>.value();

  Future<File> _file(String key) async {
    final root = await _directory();
    return File(
      '${root.path}/dandanplay/${sha256.convert(utf8.encode(key))}.json',
    );
  }

  Future<Map<String, dynamic>?> read(
    String key, {
    bool allowExpired = false,
  }) async {
    try {
      final file = await _file(key);
      if (!await file.exists() || await file.length() > 1024 * 1024) {
        return null;
      }
      final entry =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (!allowExpired &&
          (entry['expires'] as int) <= DateTime.now().millisecondsSinceEpoch) {
        return null;
      }
      return Map<String, dynamic>.from(entry['data'] as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> data, Duration ttl) {
    final operation = _writes.then((_) async {
      try {
        final text = jsonEncode({
          'expires': DateTime.now().add(ttl).millisecondsSinceEpoch,
          'data': data,
        });
        if (utf8.encode(text).length > 1024 * 1024) return;
        final file = await _file(key);
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(text, flush: true);
        if (await file.exists()) await file.delete();
        await temporary.rename(file.path);
        final files = await file.parent
            .list()
            .where((entry) => entry is File && entry.path.endsWith('.json'))
            .cast<File>()
            .toList();
        if (files.length > 64) {
          final dated = <(File, DateTime)>[];
          for (final item in files) {
            dated.add((item, await item.lastModified()));
          }
          dated.sort((a, b) => a.$2.compareTo(b.$2));
          for (final entry in dated.take(files.length - 64)) {
            await entry.$1.delete();
          }
        }
      } catch (_) {
        /* Cache storage is optional. */
      }
    });
    _writes = operation;
    return operation;
  }

  Future<void> remove(String key) async {
    await _writes;
    try {
      final file = await _file(key);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
