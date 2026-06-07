import 'embedded_credentials.dart';

class BangumiGatewayConfig {
  BangumiGatewayConfig._();

  static String _baseUrl = EmbeddedCredentials.bangumiAuthGatewayUrl;

  static String get baseUrl => _normalizeBaseUrl(_baseUrl);

  static void configure(String? value) {
    final String normalized = _normalizeBaseUrl(value);
    _baseUrl = normalized.isEmpty
        ? EmbeddedCredentials.bangumiAuthGatewayUrl
        : normalized;
  }

  static String apiUrl(String path) => _join('/bangumi/api', path);

  static String webUrl(String path) => _join('/bangumi/web', path);

  static String chiiUrl(String path) => _join('/bangumi/chii', path);

  static List<String> get htmlBases => <String>[chiiUrl(''), webUrl('')];

  static bool isGatewayUri(Uri uri) {
    final Uri? gatewayUri = Uri.tryParse(baseUrl);
    final String basePath =
        gatewayUri?.path.replaceAll(RegExp(r'/+$'), '') ?? '';
    final String bangumiPrefix = basePath.isEmpty
        ? '/bangumi/'
        : '$basePath/bangumi/';
    return gatewayUri != null &&
        gatewayUri.host.toLowerCase() == uri.host.toLowerCase() &&
        uri.path.startsWith(bangumiPrefix);
  }

  static String imageProxyUrl(String imageUrl) {
    final String normalized = normalizeBangumiUrl(imageUrl);
    if (normalized.isEmpty || !isBangumiImageUrl(normalized)) {
      return normalized;
    }
    final String imageEndpoint = _join(
      '/bangumi/image',
      '',
    ).replaceFirst(RegExp(r'/$'), '');
    return '$imageEndpoint?url=${Uri.encodeComponent(normalized)}';
  }

  static String normalizeBangumiUrl(String url) {
    if (url.isEmpty) return '';
    final String cleanUrl = url.trim();
    if (cleanUrl.startsWith('http://')) {
      return cleanUrl.replaceFirst('http://', 'https://');
    }
    if (cleanUrl.startsWith('//')) {
      return 'https:$cleanUrl';
    }
    if (cleanUrl.startsWith('/')) {
      return 'https://bgm.tv$cleanUrl';
    }
    return cleanUrl;
  }

  static bool isBangumiImageUrl(String url) {
    final Uri? uri = Uri.tryParse(normalizeBangumiUrl(url));
    if (uri == null || uri.scheme != 'https') {
      return false;
    }
    final String host = uri.host.toLowerCase();
    return host == 'bgm.tv' ||
        host == 'chii.in' ||
        host.endsWith('.bgm.tv') ||
        host.endsWith('.chii.in');
  }

  static String _join(String prefix, String path) {
    final String cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final String cleanPrefix = prefix.startsWith('/') ? prefix : '/$prefix';
    final String cleanPath = path.trim();
    if (cleanPath.isEmpty) {
      return '$cleanBase$cleanPrefix';
    }
    return cleanPath.startsWith('/')
        ? '$cleanBase$cleanPrefix$cleanPath'
        : '$cleanBase$cleanPrefix/$cleanPath';
  }

  static String _normalizeBaseUrl(String? value) {
    final String trimmed = (value ?? '').trim();
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }
}
