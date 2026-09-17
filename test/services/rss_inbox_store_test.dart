import 'package:animemaster/src/models/rss_resource.dart';
import 'package:animemaster/src/services/rss_feed_service.dart';
import 'package:animemaster/src/services/rss_inbox_store.dart';
import 'package:animemaster/src/providers/settings_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class FakeFeed extends RssFeedService {
  int calls = 0;
  @override
  Future<RssFeedSnapshot> fetch(String url, {bool force = false}) async {
    calls++;
    return RssFeedSnapshot(
      title: 'Test',
      items: const [
        RssResource(
          id: 'one',
          title: 'Test EP01',
          torrent: 'https://test.example/one.torrent',
        ),
      ],
      fetchedAt: DateTime.now(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final data = <String, String>{};
  bool failWrite = false;
  const source = {
    'id': 'test',
    'name': 'Test',
    'url': 'https://test.example/rss',
  };
  setUp(() {
    data.clear();
    failWrite = false;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final key = call.arguments['key'] as String;
            if (call.method == 'read') return data[key];
            if (call.method == 'write') {
              if (failWrite) throw PlatformException(code: 'write_failed');
              data[key] = call.arguments['value'] as String;
            }
            return null;
          },
        );
  });
  test(
    'refresh throttles, keeps processed history across restart and disable/re-enable',
    () async {
      final feed = FakeFeed();
      final store = RssInboxStore(service: feed);
      await store.refresh([source]);
      final firstSeen = store.entries.single.discoveredAt;
      await store.mark(store.entries.single, 'ignored');
      await store.refresh([source]);
      expect(feed.calls, 1);
      await store.refresh([
        {...source, 'enabled': 'false'},
      ]);
      expect(store.entries.single.state, 'ignored');
      final reopened = RssInboxStore(service: feed);
      await reopened.refresh([source], force: true);
      expect(reopened.entries.length, 1);
      expect(reopened.entries.single.state, 'ignored');
      expect(reopened.entries.single.discoveredAt, firstSeen);
      await reopened.refresh([]);
      expect(reopened.entries, isEmpty);
    },
  );
  test(
    'failed state save rolls back and corrupt data is not overwritten',
    () async {
      final store = RssInboxStore(service: FakeFeed());
      await store.refresh([source]);
      failWrite = true;
      await expectLater(
        store.mark(store.entries.single, 'downloaded'),
        throwsA(isA<PlatformException>()),
      );
      expect(store.entries.single.state, 'new');
      data['rss_inbox_v1'] = 'invalid';
      failWrite = false;
      final corrupted = RssInboxStore(service: FakeFeed());
      await corrupted.refresh([source]);
      expect(corrupted.storageError, isNotNull);
      expect(data['rss_inbox_v1'], 'invalid');
    },
  );
  test(
    'episode parsing distinguishes normal episodes from batches and specials',
    () {
      for (final title in [
        'Test EP06',
        'Test S01E06',
        '测试 第06话',
        '[组] 测试 [06]',
        'Test - 06 [1080p]',
      ]) {
        expect(RssInboxStore.episode(title), 6, reason: title);
      }
      for (final title in [
        'Test [01-12]',
        'Test OVA 01',
        'Test Special EP01',
        'Test 1080p x265',
        'Test - 12.5',
      ]) {
        expect(RssInboxStore.episode(title), isNull, reason: title);
      }
    },
  );
  test('source migration removes plaintext only after secure save', () async {
    final legacy = jsonEncode([source]);
    SharedPreferences.setMockInitialValues({'rss_sources': legacy});
    final settings = SettingsProvider();
    await settings.initialize();
    expect(data['rss_sources_v2'], legacy);
    expect(
      (await SharedPreferences.getInstance()).containsKey('rss_sources'),
      isFalse,
    );
    final again = SettingsProvider();
    await again.initialize();
    expect(again.rssSources.single['id'], 'test');
  });
  test('failed source save preserves existing settings', () async {
    final settings = SettingsProvider();
    await settings.initialize();
    final count = settings.rssSources.length;
    failWrite = true;
    await expectLater(
      settings.addRssSource('Test', source['url']!),
      throwsA(isA<PlatformException>()),
    );
    expect(settings.rssSources.length, count);
  });
  test(
    'processing a resource updates equivalent entries from other sources',
    () async {
      final store = RssInboxStore(service: FakeFeed());
      await store.refresh([
        source,
        {...source, 'id': 'other'},
      ]);
      expect(store.entries.length, 2);
      await store.mark(store.entries.first, 'downloaded');
      expect(store.entries.every((e) => e.state == 'downloaded'), isTrue);
      await store.refresh([
        source,
        {...source, 'id': 'other'},
      ], force: true);
      expect(store.entries.every((e) => e.state == 'downloaded'), isTrue);
      await store.mark(store.entries.first, 'new');
      expect(store.entries.every((e) => e.state == 'new'), isTrue);
    },
  );
}
