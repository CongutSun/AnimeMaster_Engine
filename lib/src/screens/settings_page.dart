import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import 'about_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController bgController = TextEditingController();
  final TextEditingController bgmAccController = TextEditingController();
  final TextEditingController bgmTokenController = TextEditingController();
  final TextEditingController rssNameController = TextEditingController();
  final TextEditingController rssUrlController = TextEditingController();

  String themeMode = '浅色 (Light)';
  int selectedRssIndex = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final SettingsProvider provider = context.read<SettingsProvider>();
      bgmAccController.text = provider.bgmAcc;
      bgmTokenController.text = provider.bgmToken;
      setState(() {
        themeMode = provider.themeMode;
        bgController.text = provider.customBgPath;
      });
    });
  }

  @override
  void dispose() {
    bgController.dispose();
    bgmAccController.dispose();
    bgmTokenController.dispose();
    rssNameController.dispose();
    rssUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickAndCropImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile == null) {
      return;
    }

    final CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 9, ratioY: 16),
      uiSettings: <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle: '裁剪背景图片',
          toolbarColor: Colors.blueGrey.shade700,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: '裁剪背景图片',
          aspectRatioLockEnabled: true,
        ),
      ],
    );

    if (croppedFile == null) {
      return;
    }

    setState(() {
      bgController.text = croppedFile.path;
    });
  }

  void _saveSettings() {
    final SettingsProvider provider = context.read<SettingsProvider>();
    provider.updateAccount(bgmAccController.text, bgmTokenController.text);
    provider.updateAppearance(provider.closeAction, themeMode, bgController.text);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设置已保存。')),
    );
  }

  void _addRss(SettingsProvider provider) {
    final String name = rssNameController.text.trim();
    final String url = rssUrlController.text.trim();

    if (name.isEmpty || !url.contains('{keyword}')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RSS 名称不能为空，且 URL 必须包含 {keyword}。')),
      );
      return;
    }

    final Uri? uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写合法的 HTTP 或 HTTPS 地址。')),
      );
      return;
    }

    provider.addRssSource(name, url);
    rssNameController.clear();
    rssUrlController.clear();
  }

  void _deleteRss(SettingsProvider provider) {
    if (selectedRssIndex >= 0) {
      provider.removeRssSource(selectedRssIndex);
      setState(() {
        selectedRssIndex = -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettingsProvider provider = context.watch<SettingsProvider>();
    if (!provider.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('系统设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _buildAppearanceCard(),
          const SizedBox(height: 12),
          _buildAccountCard(),
          const SizedBox(height: 12),
          _buildRssCard(provider),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于 AnimeMaster'),
                  subtitle: Text(provider.coreEngineVersion),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const AboutPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _saveSettings,
          icon: const Icon(Icons.save_outlined),
          label: const Text('保存设置'),
        ),
      ),
    );
  }

  Widget _buildAppearanceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '界面外观',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: themeMode,
              decoration: const InputDecoration(labelText: '主题模式'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(
                  value: '浅色 (Light)',
                  child: Text('浅色 (Light)'),
                ),
                DropdownMenuItem(
                  value: '深色 (Dark)',
                  child: Text('深色 (Dark)'),
                ),
              ],
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  themeMode = value;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bgController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: '自定义背景',
                hintText: '选择一张图片作为首页背景',
                suffixIcon: IconButton(
                  onPressed: _pickAndCropImage,
                  icon: const Icon(Icons.image_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.blueGrey.shade700,
                image:
                    bgController.text.isNotEmpty &&
                        File(bgController.text).existsSync()
                    ? DecorationImage(
                        image: FileImage(File(bgController.text)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              alignment: Alignment.center,
              child: bgController.text.isEmpty
                  ? const Text(
                      '暂无背景预览',
                      style: TextStyle(color: Colors.white70),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Bangumi 账号',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '账号字段填写 Bangumi 用户名或数字 UID，Token 用于同步收藏、评分与进度。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bgmAccController,
              decoration: const InputDecoration(labelText: '账号 / UID'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bgmTokenController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Access Token'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRssCard(SettingsProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'RSS 检索源',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: provider.rssSources.length,
                itemBuilder: (BuildContext context, int index) {
                  final Map<String, String> item = provider.rssSources[index];
                  final bool isSelected = selectedRssIndex == index;
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: Colors.blueAccent.withValues(alpha: 0.08),
                    title: Text(item['name'] ?? '未知源'),
                    subtitle: Text(item['url'] ?? ''),
                    onTap: () {
                      setState(() {
                        selectedRssIndex = index;
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rssNameController,
              decoration: const InputDecoration(labelText: '站点名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rssUrlController,
              decoration: const InputDecoration(
                labelText: 'RSS 地址',
                hintText: '必须包含 {keyword}',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => _deleteRss(provider),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _addRss(provider),
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
