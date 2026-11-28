import 'dart:convert';
import 'dart:io';
import 'package:animemaster/src/services/resource_catalog.dart';
import 'package:animemaster/src/services/public_search_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('发布目录的签名、内置种子与发布源一致，篡改后拒绝', () async {
    final signed = await File(
      'tools/resource_catalog/signed.json',
    ).readAsString();
    final doc = ResourceCatalog.verify(signed);
    expect(doc.revision, ResourceCatalog.bundled.revision);
    expect(doc.sources, ResourceCatalog.bundled.sources);
    final value = jsonDecode(signed) as Map<String, dynamic>;
    expect(
      jsonDecode(utf8.decode(base64Decode(value['payload']))),
      jsonDecode(
        await File('tools/resource_catalog/catalog.json').readAsString(),
      ),
    );
    value['payload'] = base64Encode(utf8.encode('{"revision":99}'));
    expect(
      () => ResourceCatalog.verify(jsonEncode(value)),
      throwsFormatException,
    );
  });
  test('公共搜索缓存只持久化无凭据入口，独立查询互不污染', () async {
    SharedPreferences.setMockInitialValues({});
    await PublicSearchCache.save('查询1', DateTime.now(), [
      {
        'title': '番剧',
        'source': '公共源',
        'torrent': 'https://x.example/token.torrent?key=secret',
        'magnet': 'magnet:?xt=urn:btih:${'a' * 40}&tr=secret',
      },
    ]);
    final result = (await PublicSearchCache.load('查询1'))!.$2.single;
    expect(result.containsKey('torrent'), false);
    expect(result['magnet'], isNot(contains('secret')));
    expect(await PublicSearchCache.load('查询2'), null);
  });
}
