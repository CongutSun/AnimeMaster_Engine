import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';
import '../models/rss_resource.dart';

class RssFeedException implements Exception {
  final String message;
  const RssFeedException(this.message);
  @override
  String toString() => message;
}

class RssFeedService {
  static final instance = RssFeedService();
  RssFeedService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              followRedirects: false,
            ),
          );
  final Dio _dio;
  final _cache = <String, RssFeedSnapshot>{};
  final _validators = <String, Map<String, String>>{};
  final _pending = <String, Future<RssFeedSnapshot>>{};
  static const maxBytes = 2 * 1024 * 1024;

  Future<RssFeedSnapshot> fetch(String url, {bool force = false}) {
    if (validateRssUrl(url) != null) {
      return Future.error(const RssFeedException('请输入有效的 HTTPS 订阅地址。'));
    }
    final cached = _cache[url];
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            const Duration(minutes: 5)) {
      return Future.value(cached);
    }
    return _pending.putIfAbsent(
      url,
      () => _fetch(url).whenComplete(() {
        _pending.remove(url);
      }),
    );
  }

  Future<RssFeedSnapshot> _fetch(String url) async {
    final cancel = CancelToken();
    final deadline = Timer(const Duration(seconds: 25), () => cancel.cancel());
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (code) => code == 200 || code == 304,
          headers: {
            'Accept':
                'application/rss+xml,application/atom+xml,application/xml,text/xml',
            ...?_validators[url],
          },
        ),
      );
      if (response.statusCode == 304 && _cache[url] != null) {
        await response.data?.stream.drain<void>();
        final old = _cache[url]!;
        return _cache[url] = RssFeedSnapshot(
          title: old.title,
          items: old.items,
          fetchedAt: DateTime.now(),
        );
      }
      final body = response.data;
      if (body == null) throw const RssFeedException('订阅源没有返回内容。');
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        if (bytes.length + chunk.length > maxBytes) {
          cancel.cancel();
          throw const RssFeedException('订阅源内容过大，请使用范围更小的订阅。');
        }
        bytes.add(chunk);
      }
      final feed = parse(utf8.decode(bytes.takeBytes()), Uri.parse(url));
      _validators[url] = {
        if (response.headers.value('etag') case final String etag)
          'If-None-Match': etag,
        if (response.headers.value('last-modified') case final String modified)
          'If-Modified-Since': modified,
      };
      if (_cache.length >= 30 && !_cache.containsKey(url)) {
        final key = _cache.keys.first;
        _cache.remove(key);
        _validators.remove(key);
      }
      _cache[url] = feed;
      return feed;
    } on RssFeedException {
      rethrow;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const RssFeedException('订阅地址已失效或需要授权，请检查个人 RSS 地址。');
      }
      if (status != null && status >= 300 && status < 400) {
        throw const RssFeedException('订阅地址发生跳转，请填写网站提供的最终 HTTPS 地址。');
      }
      throw const RssFeedException('连接失败，请检查网络或稍后重试。');
    } catch (_) {
      throw const RssFeedException('返回内容不是可识别的 RSS 或 Atom 订阅。');
    } finally {
      deadline.cancel();
    }
  }

  static RssFeedSnapshot parse(String text, Uri base) {
    if (text.length > maxBytes ||
        RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(text)) {
      throw const RssFeedException('订阅内容格式不受支持。');
    }
    final document = XmlDocument.parse(text);
    final root = document.rootElement;
    if (!['rss', 'feed', 'RDF'].contains(root.name.local)) {
      throw const RssFeedException('该地址返回的是网页，请填写 RSS 或 Atom 地址。');
    }
    String childText(XmlElement element, List<String> names) {
      for (final child in element.childElements) {
        if (names.contains(child.name.local)) return child.innerText.trim();
      }
      return '';
    }

    final channel =
        root.childElements
            .where((e) => e.name.local == 'channel')
            .firstOrNull ??
        root;
    final items = <String, RssResource>{};
    for (final entry
        in root.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'item' || e.name.local == 'entry')
            .take(1000)) {
      final title = childText(entry, ['title']);
      if (title.isEmpty) continue;
      String magnet = '', torrent = '', detail = '';
      void candidate(String raw, {bool enclosure = false}) {
        final value = raw.trim();
        if (value.isEmpty) return;
        if (value.toLowerCase().startsWith('magnet:')) {
          final uri = Uri.tryParse(value);
          final xt = uri?.queryParameters['xt'] ?? '';
          if (RegExp(
            r'^urn:btih:([a-f0-9]{40}|[a-z2-7]{32})$',
            caseSensitive: false,
          ).hasMatch(xt)) {
            magnet = value;
          }
          return;
        }
        final Uri uri;
        try {
          uri = base.resolve(value);
        } on FormatException {
          return;
        }
        if (!['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          return;
        }
        if (enclosure ||
            RegExp(
              r'\.torrent(?:$|[?#])|/(download|dl)/',
              caseSensitive: false,
            ).hasMatch(uri.toString())) {
          torrent = uri.toString();
        } else if (detail.isEmpty) {
          detail = uri.toString();
        }
      }

      for (final node in entry.childElements) {
        final name = node.name.local.toLowerCase();
        if (['enclosure', 'link'].contains(name)) {
          final type = node.getAttribute('type') ?? '';
          candidate(
            node.getAttribute('url') ??
                node.getAttribute('href') ??
                node.innerText,
            enclosure: type.contains('bittorrent'),
          );
        } else if (['guid', 'id', 'magneturi', 'magnet'].contains(name)) {
          final value = node.innerText.trim();
          if (value.startsWith('magnet:') || value.startsWith('http')) {
            candidate(value);
          }
        } else if ([
          'description',
          'content',
          'encoded',
          'summary',
        ].contains(name)) {
          final fragment = html.parseFragment(
            node.getAttribute('type') == 'xhtml'
                ? node.children.map((child) => child.toXmlString()).join()
                : node.innerText,
          );
          for (final link in fragment.querySelectorAll('a[href]')) {
            candidate(link.attributes['href']!);
          }
          for (final match in RegExp(
            r'''magnet:\?[^\s<>"']+''',
          ).allMatches(fragment.text ?? '')) {
            candidate(match.group(0)!);
          }
        }
      }
      final guid = childText(entry, ['guid', 'id']);
      final id = sha256
          .convert(
            utf8.encode(
              guid.isNotEmpty ? guid : '$title|$magnet|$torrent|$detail',
            ),
          )
          .toString();
      final rawDate = childText(entry, [
        'pubDate',
        'published',
        'updated',
        'date',
      ]);
      DateTime? date = DateTime.tryParse(rawDate);
      if (date == null && rawDate.isNotEmpty) {
        try {
          date = HttpDate.parse(rawDate);
        } catch (_) {}
        date ??= _rfcDate(rawDate);
      }
      final item = RssResource(
        id: id,
        title: title,
        detailUrl: detail,
        magnet: magnet,
        torrent: torrent,
        publishedAt: date,
      );
      items.putIfAbsent(item.dedupeKey, () => item);
    }
    return RssFeedSnapshot(
      title: childText(channel, ['title']),
      items: items.values.toList(),
      fetchedAt: DateTime.now(),
    );
  }

  static bool matchesTitle(String title, Iterable<String> names) {
    String normalize(String s) => s.toLowerCase().replaceAll(
      RegExp(r'[\s\p{P}\p{S}]+', unicode: true),
      '',
    );
    final text = normalize(title);
    return names.any((name) {
      final n = normalize(name);
      return n.length >= 2 && text.contains(n);
    });
  }

  static DateTime? _rfcDate(String value) {
    final match = RegExp(
      r'^(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s+([+-])(\d{2})(\d{2})$',
    ).firstMatch(value);
    if (match == null) return null;
    final month =
        [
          'jan',
          'feb',
          'mar',
          'apr',
          'may',
          'jun',
          'jul',
          'aug',
          'sep',
          'oct',
          'nov',
          'dec',
        ].indexOf(match[2]!.toLowerCase()) +
        1;
    if (month == 0) return null;
    final offset =
        (int.parse(match[8]!) * 60 + int.parse(match[9]!)) *
        (match[7] == '-' ? -1 : 1);
    return DateTime.utc(
      int.parse(match[3]!),
      month,
      int.parse(match[1]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6] ?? '0'),
    ).subtract(Duration(minutes: offset));
  }
}
