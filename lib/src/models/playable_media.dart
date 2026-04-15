/// 统一的可播放媒体对象
/// 无论是本地文件、网盘直链还是其他协议，最终都会被转换为这个对象喂给播放器
class PlayableMedia {
  final String title;
  final String url;
  final Map<String, String>? headers;
  final bool isLocal; // 标识是否为本地已经缓存的文件

  PlayableMedia({
    required this.title,
    required this.url,
    this.headers,
    this.isLocal = false,
  });
}

/// 解析器基类（策略模式接口）
/// 未来的 WebDAV解析器、本地文件解析器、网页提取解析器都会继承它
abstract class MediaResolver {
  /// 判断当前解析器是否支持处理传入的原始数据
  bool canResolve(dynamic sourceData);

  /// 将原始数据解析为统一的可播放对象
  Future<PlayableMedia> resolve(dynamic sourceData);
}