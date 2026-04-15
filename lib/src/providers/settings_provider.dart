import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/engine_bridge.dart';

class SettingsProvider with ChangeNotifier {
  String _bgmAcc = '';
  String _bgmToken = '';
  List<Map<String, String>> _rssSources = <Map<String, String>>[];
  bool _isLoaded = false;

  String _closeAction = '直接退出';
  String _themeMode = '浅色 (Light)';
  String _customBgPath = '';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String get bgmAcc => _bgmAcc;
  String get bgmToken => _bgmToken;
  List<Map<String, String>> get rssSources => _rssSources;
  bool get isLoaded => _isLoaded;

  String get closeAction => _closeAction;
  String get themeMode => _themeMode;
  String get customBgPath => _customBgPath;
  String get coreEngineVersion => EngineBridge().engineVersion;

  SettingsProvider() {
    EngineBridge().wakeUpEngine();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    _bgmAcc = prefs.getString('bgm_acc') ?? '';
    _closeAction = prefs.getString('close_action') ?? '直接退出';
    _themeMode = _normalizeThemeMode(prefs.getString('theme_mode'));
    _customBgPath = prefs.getString('custom_bg_path') ?? '';
    _bgmToken = await _secureStorage.read(key: 'bgm_token') ?? '';

    final String? rssString = prefs.getString('rss_sources');
    if (rssString != null) {
      final List<dynamic> decoded = jsonDecode(rssString);
      _rssSources = decoded
          .map((dynamic item) => Map<String, String>.from(item as Map))
          .toList();
    } else {
      _rssSources = <Map<String, String>>[
        <String, String>{
          'name': '动漫花园 (DMHY)',
          'url': 'https://share.dmhy.org/topics/rss/rss.xml?keyword={keyword}',
        },
        <String, String>{
          'name': '蜜柑计划 (Mikan)',
          'url': 'https://mikanani.me/RSS/Search?searchstr={keyword}',
        },
      ];
    }

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> updateAccount(String acc, String token) async {
    _bgmAcc = acc.trim();
    _bgmToken = token.trim();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('bgm_acc', _bgmAcc);
    await _secureStorage.write(key: 'bgm_token', value: _bgmToken);

    notifyListeners();
  }

  Future<void> updateAppearance(
    String action,
    String mode,
    String bgPath,
  ) async {
    _closeAction = action;
    _themeMode = _normalizeThemeMode(mode);
    _customBgPath = bgPath.trim();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('close_action', _closeAction);
    await prefs.setString('theme_mode', _themeMode);
    await prefs.setString('custom_bg_path', _customBgPath);

    notifyListeners();
  }

  Future<void> addRssSource(String name, String url) async {
    _rssSources.add(<String, String>{'name': name.trim(), 'url': url.trim()});
    await _saveRssToPrefs();
    notifyListeners();
  }

  Future<void> removeRssSource(int index) async {
    if (index >= 0 && index < _rssSources.length) {
      _rssSources.removeAt(index);
      await _saveRssToPrefs();
      notifyListeners();
    }
  }

  Future<void> _saveRssToPrefs() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('rss_sources', jsonEncode(_rssSources));
  }

  String _normalizeThemeMode(String? rawValue) {
    final String value = (rawValue ?? '').toLowerCase();
    if (value.contains('dark') || rawValue?.contains('深色') == true) {
      return '深色 (Dark)';
    }
    return '浅色 (Light)';
  }
}
