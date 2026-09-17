import 'package:flutter/material.dart';
import '../screens/rss_inbox_page.dart';

class RssInboxEntryPoint extends StatelessWidget {
  const RssInboxEntryPoint({super.key});
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.rss_feed_rounded),
      title: const Text('订阅更新'),
      subtitle: const Text('查看新资源 · 匹配在看番剧 · 确认下载'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const RssInboxPage()),
      ),
    ),
  );
}
