import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import '../models/rss_resource.dart';

class ResourceCatalog {
  final int revision;
  final List<Map<String, String>> sources;
  const ResourceCatalog(this.revision, this.sources);
  static const bundled = ResourceCatalog(1, [
    {
      'id': 'dmhy',
      'name': '动漫花园 (DMHY)',
      'url': 'https://share.dmhy.org/topics/rss/rss.xml?keyword={keyword}',
    },
    {
      'id': 'mikan',
      'name': '蜜柑计划 (Mikan)',
      'url': 'https://mikanani.me/RSS/Search?searchstr={keyword}',
    },
    {
      'id': 'nyaa',
      'name': 'Nyaa 动画',
      'url': 'https://nyaa.si/?page=rss&c=1_0&q={keyword}',
    },
  ]);
  static const url =
      'https://raw.githubusercontent.com/CongutSun/AnimeMaster_Engine/main/tools/resource_catalog/signed.json';
  static const _modulus =
      'c1f5053063658b0dff101cebe089bf02cadd611a1a3ef4eafb814dd9c354de527723bd6de559e75ca56affef7831ddfe91fa39484377118976056c28408145b0a7310f30432e9d178af99ed96ec6ea0a0caee8fbea23894a6f7ea61e01f5360b8d55277d3fd3dfac575c40cb3124d756057377b2891eaff5083cbbb6d95cffaa11a0ee015ed445e38b2fda58bd3b21160f9490eb7d550e4a6d6b338ebbcb3fcc71281a994926a7d49a126e6502a747bdc63b44056ee7dc98095f5fe96f7a0a645ac57137096d6ccb05869a22151a20e7e361f9d2ceec55cdbb9d1822881fbf1f3cd7c30fafc220da483947d013e88d5ccdce5e996987bab12127ca8e2c349e95';

  static ResourceCatalog verify(String envelope) {
    if (envelope.length > 64000) throw const FormatException('目录过大');
    final doc = jsonDecode(envelope) as Map;
    final bytes = base64Decode(doc['payload'] as String);
    final signature = base64Decode(doc['signature'] as String);
    String hex(List<int> values) =>
        values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (signature.length != 256) throw const FormatException('目录签名无效');
    final value = BigInt.parse(hex(signature), radix: 16);
    final modulus = BigInt.parse(_modulus, radix: 16);
    const sha256Prefix = '3031300d060960864801650304020105000420';
    final digest = sha256Prefix + sha256.convert(bytes).toString();
    final expected = '0001${'ff' * ((512 - 6 - digest.length) ~/ 2)}00$digest';
    if (value >= modulus ||
        value
                .modPow(BigInt.from(65537), modulus)
                .toRadixString(16)
                .padLeft(512, '0') !=
            expected) {
      throw const FormatException('目录签名无效');
    }
    final data = jsonDecode(utf8.decode(bytes)) as Map;
    final entries = <Map<String, String>>[];
    final ids = <String>{};
    for (final s in data['sources'] as List) {
      final id = s['id'] as String,
          name = s['name'] as String,
          url = s['url'] as String;
      if (!ids.add(id) ||
          id.isEmpty ||
          name.isEmpty ||
          validateRssUrl(url, search: true) != null) {
        throw const FormatException('目录来源无效');
      }
      entries.add({'id': id, 'name': name, 'url': url});
    }
    return ResourceCatalog(data['revision'] as int, entries);
  }

  static Future<String> fetch() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    try {
      final response = await dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
        ),
      );
      final bytes = <int>[];
      await for (final chunk in response.data!.stream) {
        if (bytes.length + chunk.length > 64000) {
          throw const FormatException('目录过大');
        }
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    } finally {
      dio.close(force: true);
    }
  }
}
