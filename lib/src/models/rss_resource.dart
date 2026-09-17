import 'dart:convert';
import 'package:crypto/crypto.dart';

String rssSourceId(Map<String, String> source) =>
    source['id'] ?? sha256.convert(utf8.encode(source['url'] ?? '')).toString();

bool isSubscriptionSource(Map<String, String> source) =>
    source['type'] == 'subscription' ||
    (source['type'] != 'search' &&
        !(source['url'] ?? '').contains('{keyword}'));

String? validateRssUrl(String value, {bool search = false}) {
  final uri = Uri.tryParse(value.replaceAll('{keyword}', 'test'));
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return '请输入完整的 HTTPS 订阅地址。';
  }
  if (search && !value.contains('{keyword}')) return '搜索源地址需要包含 {keyword}。';
  return null;
}

class RssResource {
  final String id, title, detailUrl, magnet, torrent;
  final DateTime? publishedAt;
  const RssResource({
    required this.id,
    required this.title,
    this.detailUrl = '',
    this.magnet = '',
    this.torrent = '',
    this.publishedAt,
  });
  String get downloadUrl => torrent.isNotEmpty ? torrent : magnet;
  String get dedupeKey {
    final hash = Uri.tryParse(magnet)?.queryParameters['xt'];
    return hash?.isNotEmpty == true
        ? hash!.toLowerCase()
        : (torrent.isNotEmpty ? torrent : id);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'detailUrl': detailUrl,
    'magnet': magnet,
    'torrent': torrent,
    'publishedAt': publishedAt?.toIso8601String(),
  };
  factory RssResource.fromJson(Map<String, dynamic> json) => RssResource(
    id: json['id'] as String,
    title: json['title'] as String,
    detailUrl: json['detailUrl'] as String? ?? '',
    magnet: json['magnet'] as String? ?? '',
    torrent: json['torrent'] as String? ?? '',
    publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
  );
}

class RssFeedSnapshot {
  final String title;
  final List<RssResource> items;
  final DateTime fetchedAt;
  const RssFeedSnapshot({
    required this.title,
    required this.items,
    required this.fetchedAt,
  });
}
