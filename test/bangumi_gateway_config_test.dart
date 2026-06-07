import 'package:animemaster/src/config/bangumi_gateway_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    BangumiGatewayConfig.configure('https://gateway.example/base/');
  });

  test('builds Bangumi API and HTML gateway URLs', () {
    expect(
      BangumiGatewayConfig.apiUrl('/v0/subjects/1'),
      'https://gateway.example/base/bangumi/api/v0/subjects/1',
    );
    expect(
      BangumiGatewayConfig.webUrl('/subject/1/comments'),
      'https://gateway.example/base/bangumi/web/subject/1/comments',
    );
    expect(
      BangumiGatewayConfig.chiiUrl('/ep/1'),
      'https://gateway.example/base/bangumi/chii/ep/1',
    );
  });

  test('builds proxied Bangumi image URLs only for allowed hosts', () {
    expect(
      BangumiGatewayConfig.imageProxyUrl('//lain.bgm.tv/pic/cover/l/a.jpg'),
      'https://gateway.example/base/bangumi/image?url=https%3A%2F%2Flain.bgm.tv%2Fpic%2Fcover%2Fl%2Fa.jpg',
    );
    expect(
      BangumiGatewayConfig.imageProxyUrl('https://example.com/a.jpg'),
      'https://example.com/a.jpg',
    );
  });

  test('detects configured Bangumi gateway requests', () {
    expect(
      BangumiGatewayConfig.isGatewayUri(
        Uri.parse('https://gateway.example/base/bangumi/api/calendar'),
      ),
      true,
    );
    expect(
      BangumiGatewayConfig.isGatewayUri(
        Uri.parse('https://gateway.example/base/proxy/rss'),
      ),
      false,
    );
  });
}
