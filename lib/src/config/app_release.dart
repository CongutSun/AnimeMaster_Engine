abstract final class AppRelease {
  static const String version = '2.5.2';
  static const int build = 4056;
  static const List<String> notes = <String>[
    '修复离线缓存串集，已有缓存可自动重新识别，也可在下载中心手动校正集数，无需重新下载。',
    '网站合集按文件识别集数，搜索指定集时可找到包含该集的合集，播放时优先选中唯一匹配的文件。',
    '资源搜索支持设置网站资源或 B站视频优先，新增可选 Nyaa 来源和可独立更新的签名来源目录。',
    '同一种子的多个来源合并展示，下载时可切换备用入口。来源暂不可用时可查看最近搜索结果。',
    '连续加入缓存时合并提示并自动收起，修复弹幕匹配重复提醒、RSS 下载确认框重叠及缓冲结束时误关页面的问题。',
  ];
}
