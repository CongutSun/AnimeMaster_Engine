abstract final class AppRelease {
  static const String version = '2.4.8';
  static const int build = 4053;
  static const List<String> notes = <String>[
    '新增 B站视频搜索、BV 号与链接播放、扫码登录和账号可用画质选择。',
    '番剧详情页统一“搜索资源”入口，支持 B站视频与网站资源切换及别名搜索。',
    '返回搜索列表保留关键词、分页结果和浏览位置，切换资源标签保留结果与筛选条件。',
    '支持选择分 P、剧集匹配建议与本机关联，播放进度按视频和分 P 分别保存。',
    '修复部分 Android 设备播放 B站视频时绿屏、画面更新缓慢的问题，完善音视频同步加载。',
    '切换画质保留播放位置与暂停状态，登录过期和播放失败提供明确提示及重试入口。',
  ];
}
