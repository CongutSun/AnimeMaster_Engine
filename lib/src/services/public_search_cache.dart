import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'resource_catalog.dart';

/// Keep only public, credential-free download routes in the disk cache.
class PublicSearchCache {
  static const _storageKey = 'recent_public_resource_searches';
  static bool accepts(String url) =>
      ResourceCatalog.bundled.sources.any((s) => s['url'] == url);
  static String _key(String query) =>
      sha256.convert(utf8.encode(query)).toString();
  static Future<void> _writes = Future.value();
  static Future<void> save(
    String query,
    DateTime time,
    List<Map<String, String>> rows,
  ) {
    return _writes = _writes
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          final index = Map<String, dynamic>.from(
            jsonDecode(prefs.getString(_storageKey) ?? '{}'),
          );
          final key = _key(query);
          index.remove(key);
          final clean = <Map<String, String>>[];
          for (final item in rows.take(100)) {
            final routes = <String, String>{};
            for (final type in ['torrent', 'url']) {
              final uri = Uri.tryParse(item[type] ?? '');
              if (uri?.scheme == 'https' &&
                  uri!.userInfo.isEmpty &&
                  !uri.hasQuery &&
                  !uri.hasFragment) {
                routes[type] = uri.toString();
              }
            }
            final xt =
                Uri.tryParse(item['magnet'] ?? '')?.queryParameters['xt'] ?? '';
            if (RegExp(
              r'^urn:btih:([0-9a-f]{40}|[a-z2-7]{32})$',
              caseSensitive: false,
            ).hasMatch(xt)) {
              routes['magnet'] = 'magnet:?xt=$xt';
            }
            if (routes.containsKey('torrent') || routes.containsKey('magnet')) {
              clean.add({
                for (final field in ['title', 'source', 'date'])
                  field: item[field] ?? '',
                ...routes,
              });
            }
          }
          index[key] = {'at': time.millisecondsSinceEpoch, 'rows': clean};
          while (index.length > 20) {
            index.remove(index.keys.first);
          }
          await prefs.setString(_storageKey, jsonEncode(index));
        })
        .catchError((Object _) {});
  }

  static Future<(DateTime, List<Map<String, String>>)?> load(
    String query,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = jsonDecode(
        prefs.getString(_storageKey) ?? '{}',
      )[_key(query)];
      if (value == null) return null;
      return (
        DateTime.fromMillisecondsSinceEpoch(value['at'] as int),
        [for (final e in value['rows']) Map<String, String>.from(e)],
      );
    } catch (_) {
      return null;
    }
  }
}
