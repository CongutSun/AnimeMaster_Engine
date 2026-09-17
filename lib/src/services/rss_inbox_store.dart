import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/rss_resource.dart';
import 'rss_feed_service.dart';

class RssInboxEntry {
  final String sourceId, sourceName;
  final RssResource resource;
  final DateTime discoveredAt;
  String state;
  int? subjectId;
  RssInboxEntry({
    required this.sourceId,
    required this.sourceName,
    required this.resource,
    required this.discoveredAt,
    this.state = 'new',
    this.subjectId,
  });
  String get key => '$sourceId:${resource.id}';
  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'sourceName': sourceName,
    'resource': resource.toJson(),
    'discoveredAt': discoveredAt.toIso8601String(),
    'state': state,
    'subjectId': subjectId,
  };
  factory RssInboxEntry.fromJson(Map<String, dynamic> json) => RssInboxEntry(
    sourceId: json['sourceId'] as String,
    sourceName: json['sourceName'] as String,
    resource: RssResource.fromJson(
      Map<String, dynamic>.from(json['resource'] as Map),
    ),
    discoveredAt: DateTime.parse(json['discoveredAt'] as String),
    state: json['state'] as String? ?? 'new',
    subjectId: json['subjectId'] as int?,
  );
}

class RssInboxStore extends ChangeNotifier {
  static final instance = RssInboxStore();
  RssInboxStore({RssFeedService? service, FlutterSecureStorage? storage})
    : _service = service ?? RssFeedService.instance,
      _storage = storage ?? const FlutterSecureStorage();
  final RssFeedService _service;
  final FlutterSecureStorage _storage;
  final List<RssInboxEntry> entries = [];
  final Map<String, Map<String, String>> rules = {};
  final Map<String, String> errors = {};
  final Map<String, DateTime> refreshedAt = {};
  final Map<String, String> _processed = {};
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  Future<void>? _refreshing;
  bool refreshing = false;
  String? storageError;
  int get newCount => entries.where((e) => e.state == 'new').length;
  Future<void> initialize() => _initializing ??= _load();
  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: 'rss_inbox_v1');
      if (raw == null) return;
      final data = jsonDecode(raw) as Map;
      _processed.addAll(
        Map<String, String>.from(data['processed'] as Map? ?? {}),
      );
      for (final entry in data['entries'] as List? ?? []) {
        entries.add(
          RssInboxEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
        );
      }
      for (final rule in (data['rules'] as Map? ?? {}).entries) {
        rules[rule.key.toString()] = Map<String, String>.from(
          rule.value as Map,
        );
      }
      for (final entry in (data['refreshedAt'] as Map? ?? {}).entries) {
        final date = DateTime.tryParse(entry.value.toString());
        if (date != null) refreshedAt[entry.key.toString()] = date;
      }
    } catch (_) {
      storageError = '订阅记录读取失败，请重新打开应用后重试。';
    } finally {
      notifyListeners();
    }
  }

  Future<void> _persist() {
    final data = jsonEncode({
      'entries': entries.map((e) => e.toJson()).toList(),
      'rules': rules,
      'processed': _processed,
      'refreshedAt': refreshedAt.map(
        (key, value) => MapEntry(key, value.toIso8601String()),
      ),
    });
    _writes = _writes
        .catchError((Object _) {})
        .then((_) => _storage.write(key: 'rss_inbox_v1', value: data));
    return _writes;
  }

  Future<void> refresh(
    List<Map<String, String>> sources, {
    bool force = false,
  }) {
    return _refreshing ??= _refresh(
      sources,
      force: force,
    ).whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh(
    List<Map<String, String>> sources, {
    required bool force,
  }) async {
    await initialize();
    if (storageError != null) return;
    final subscriptions = sources
        .where((s) => isSubscriptionSource(s) && s['enabled'] != 'false')
        .toList();
    refreshing = true;
    notifyListeners();
    try {
      final allowed = sources.map(rssSourceId).toSet();
      entries.removeWhere((e) => !allowed.contains(e.sourceId));
      errors.removeWhere((key, _) => !allowed.contains(key));
      final byKey = {for (final e in entries) e.key: e};
      // Sequential requests keep private sites from receiving bursts on resume.
      for (final source in subscriptions) {
        final id = rssSourceId(source);
        if (!force &&
            refreshedAt[id] != null &&
            DateTime.now().difference(refreshedAt[id]!) <
                const Duration(minutes: 30)) {
          continue;
        }
        try {
          final feed = await _service.fetch(source['url']!, force: force);
          for (final item in feed.items) {
            final existing = byKey['$id:${item.id}'];
            final entry = RssInboxEntry(
              sourceId: id,
              sourceName: source['name'] ?? '订阅源',
              resource: item,
              discoveredAt: existing?.discoveredAt ?? DateTime.now(),
              state: _processed[item.dedupeKey] ?? 'new',
            );
            if (existing != null) {
              entry.state = _processed[item.dedupeKey] ?? existing.state;
              entry.subjectId = existing.subjectId;
            }
            byKey[entry.key] = entry;
          }
          refreshedAt[id] = feed.fetchedAt;
          errors.remove(id);
        } catch (error) {
          errors[id] = error is RssFeedException
              ? error.message
              : '刷新失败，请稍后重试。';
        }
      }
      final next = byKey.values.toList()
        ..sort((a, b) => b.discoveredAt.compareTo(a.discoveredAt));
      for (final entry in next) {
        entry.state = _processed[entry.resource.dedupeKey] ?? entry.state;
      }
      entries
        ..clear()
        ..addAll(next.take(1000));
      await _persist();
    } catch (_) {
      storageError = '订阅记录保存失败，请检查设备存储后重新打开应用。';
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> mark(RssInboxEntry entry, String state, {int? subjectId}) async {
    if (storageError != null) throw StateError(storageError!);
    final oldState = entry.state, oldId = entry.subjectId;
    final oldProcessed = Map<String, String>.from(_processed);
    _processed[entry.resource.dedupeKey] = state;
    final duplicates = {
      for (final e in entries.where(
        (e) => e.resource.dedupeKey == entry.resource.dedupeKey,
      ))
        e: e.state,
    };
    for (final duplicate in duplicates.keys) {
      duplicate.state = state;
    }
    while (_processed.length > 5000) {
      _processed.remove(_processed.keys.first);
    }
    entry.state = state;
    if (subjectId != null) entry.subjectId = subjectId;
    try {
      await _persist();
    } catch (_) {
      for (final duplicate in duplicates.entries) {
        duplicate.key.state = duplicate.value;
      }
      entry.state = oldState;
      entry.subjectId = oldId;
      _processed
        ..clear()
        ..addAll(oldProcessed);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> saveRule(
    String account,
    int subjectId,
    Map<String, String> rule,
  ) async {
    if (storageError != null) throw StateError(storageError!);
    final key = '$account:$subjectId';
    final previous = rules[key];
    rules[key] = rule;
    try {
      await _persist();
    } catch (_) {
      if (previous == null) {
        rules.remove(key);
      } else {
        rules[key] = previous;
      }
      rethrow;
    }
    notifyListeners();
  }

  static int? episode(String title) {
    if (RegExp(
      r'\d\s*[-~～]\s*\d|\b(OVA|OAD|SP|Special|Movie)\b|总集篇|劇場版|剧场版',
      caseSensitive: false,
    ).hasMatch(title)) {
      return null;
    }
    for (final pattern in [
      r'\bS\d{1,2}E0*(\d{1,3})(?:v\d+)?\b',
      r'\b(?:EP?|Episode)\s*[._-]?\s*0*(\d{1,3})(?:v\d+)?\b',
      r'第\s*0*(\d{1,3})\s*[话話集回]',
      r'[\[【]\s*0*(\d{1,3})(?:v\d+)?\s*[\]】]',
      r'\s[-–—]\s*0*(\d{1,3})(?:v\d+)?(?=\s*(?:[\[({]|\.(?:mkv|mp4)|$))',
    ]) {
      final match = RegExp(pattern, caseSensitive: false).firstMatch(title);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    return null;
  }
}
