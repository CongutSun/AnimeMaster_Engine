import 'package:flutter/material.dart';
import '../screens/bilibili_video_page.dart';
import '../screens/search_page.dart';
import '../screens/settings_page.dart';

class TopToolBar extends StatefulWidget {
  const TopToolBar({super.key});
  @override
  State<TopToolBar> createState() => _TopToolBarState();
}

class _TopToolBarState extends State<TopToolBar> {
  final input = TextEditingController();
  bool bilibili = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void search() {
    final query = input.text.trim();
    if (query.isEmpty && !bilibili) return;
    FocusScope.of(context).unfocus();
    final page =
        bilibili ||
            RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(query) ||
            query.startsWith('https://www.bilibili.com/video/')
        ? BilibiliVideoPage(initialKeyword: query)
        : SearchPage(keyword: query);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: input,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => search(),
                decoration: InputDecoration(
                  hintText: bilibili ? '输入关键词或 BV 号' : '搜索番剧或书籍',
                  suffixIcon: IconButton(
                    tooltip: '搜索',
                    onPressed: search,
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final scope in [false, true])
              ChoiceChip(
                label: Text(scope ? 'B站视频' : '番剧资料'),
                selected: bilibili == scope,
                onSelected: (_) => setState(() => bilibili = scope),
              ),
          ],
        ),
      ],
    ),
  );
}
