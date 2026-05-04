import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/embedded_credentials.dart';
import '../core/engine_bridge.dart';
import '../models/bangumi_auth_gateway_models.dart';
import '../models/bangumi_user_profile.dart';
import '../services/bangumi_auth_gateway_service.dart';
import '../services/bangumi_oauth_service.dart';

class SettingsProvider with ChangeNotifier {
  static const Set<String> _legacyBangumiGatewayHosts = <String>{
    'animemaster-bangumi-auth.animemaster-19277.workers.dev',
  };

  String _bgmAcc = '';
  String _bgmToken = '';
  DateTime? _bgmTokenExpiresAt;
  String _bgmNickname = '';
  String _bgmAvatarUrl = '';
  String _bgmBio = '';
  String _bgmAuthGatewayUrl = '';
  String _bgmGatewaySessionId = '';

  String _dandanplayAppId = '';
  String _dandanplayAppSecret = '';

  List<Map<String, String>> _rssSources = <Map<String, String>>[];
  bool _isLoaded = false;

  String _closeAction = 'minimize';
  String _themeMode = 'Light';
  String _customBgPath = '';
  String _appUpdateFeedUrl = '';
  bool _autoCheckUpdates = true;
  bool _enablePictureInPicture = false;
  String _resumePlaybackBehavior = 'ask';
  bool _autoPlayNextEpisode = false;
  bool _enableHapticFeedback = true;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String get bgmAcc => _bgmAcc;
  String get bgmToken => _bgmToken;
  DateTime? get bgmTokenExpiresAt => _bgmTokenExpiresAt;
  String get bgmNickname => _bgmNickname;
  String get bgmAvatarUrl => _bgmAvatarUrl;
  String get bgmBio => _bgmBio;
  String get bgmAuthGatewayUrl => _bgmAuthGatewayUrl.trim().isNotEmpty
      ? _bgmAuthGatewayUrl
      : EmbeddedCredentials.bangumiAuthGatewayUrl;
  String get bgmGatewaySessionId => _bgmGatewaySessionId;
  String get bangumiDisplayName =>
      _bgmNickname.trim().isNotEmpty ? _bgmNickname : _bgmAcc;
  bool get hasBangumiProfile =>
      _bgmNickname.trim().isNotEmpty || _bgmAvatarUrl.trim().isNotEmpty;
  bool get isBangumiAuthorized =>
      _bgmAcc.trim().isNotEmpty && _bgmToken.trim().isNotEmpty;
  bool get hasBangumiAuthGateway => bgmAuthGatewayUrl.trim().isNotEmpty;
  bool get hasBangumiGatewaySession =>
      _bgmGatewaySessionId.trim().isNotEmpty && hasBangumiAuthGateway;
  String get bangumiRedirectUri => BangumiOAuthService.redirectUri;

  String get dandanplayAppId {
    if (_dandanplayAppId.trim().isNotEmpty ||
        _dandanplayAppSecret.trim().isNotEmpty) {
      return _dandanplayAppId;
    }
    return EmbeddedCredentials.dandanplayAppId;
  }

  String get dandanplayAppSecret {
    if (_dandanplayAppId.trim().isNotEmpty ||
        _dandanplayAppSecret.trim().isNotEmpty) {
      return _dandanplayAppSecret;
    }
    return EmbeddedCredentials.dandanplayAppSecret;
  }

  bool get hasDandanplayCredentials =>
      dandanplayAppId.trim().isNotEmpty &&
      dandanplayAppSecret.trim().isNotEmpty;

  List<Map<String, String>> get rssSources => _rssSources;
  bool get isLoaded => _isLoaded;

  String get closeAction => _closeAction;
  String get themeMode => _themeMode;
  String get customBgPath => _customBgPath;
  String get coreEngineVersion => EngineBridge().engineVersion;
  String get appUpdateFeedUrl => _appUpdateFeedUrl;
  bool get autoCheckUpdates => _autoCheckUpdates;
  bool get enablePictureInPicture => _enablePictureInPicture;
  String get resumePlaybackBehavior => _resumePlaybackBehavior;
  bool get autoPlayNextEpisode => _autoPlayNextEpisode;
  bool get enableHapticFeedback => _enableHapticFeedback;

  SettingsProvider() {
    EngineBridge().wakeUpEngine();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    _bgmAcc = prefs.getString('bgm_acc') ?? '';
    _closeAction = prefs.getString('close_action') ?? 'minimize';
    _themeMode = _normalizeThemeMode(prefs.getString('theme_mode'));
    _customBgPath = prefs.getString('custom_bg_path') ?? '';
    final String? storedUpdateFeedUrl = prefs.getString('app_update_feed_url');
    _appUpdateFeedUrl = _normalizeAppUpdateFeedUrl(storedUpdateFeedUrl);
    if (storedUpdateFeedUrl != _appUpdateFeedUrl) {
      await prefs.setString('app_update_feed_url', _appUpdateFeedUrl);
    }
    _autoCheckUpdates = prefs.getBool('app_auto_check_updates') ?? true;
    _enablePictureInPicture =
        prefs.getBool('playback_enable_picture_in_picture') ?? false;
    _resumePlaybackBehavior = _normalizeResumePlaybackBehavior(
      prefs.getString('playback_resume_behavior'),
    );
    _autoPlayNextEpisode =
        prefs.getBool('playback_auto_play_next_episode') ?? false;
    _enableHapticFeedback =
        prefs.getBool('ui_enable_haptic_feedback') ?? true;
    _bgmNickname = prefs.getString('bgm_nickname') ?? '';
    _bgmAvatarUrl = prefs.getString('bgm_avatar_url') ?? '';
    _bgmBio = prefs.getString('bgm_bio') ?? '';
    final String? storedGatewayUrl = prefs.getString('bgm_auth_gateway_url');
    _bgmAuthGatewayUrl = _normalizeBangumiAuthGatewayUrl(storedGatewayUrl);
    if (storedGatewayUrl != _bgmAuthGatewayUrl) {
      await prefs.setString('bgm_auth_gateway_url', _bgmAuthGatewayUrl);
    }
    _dandanplayAppId = prefs.getString('dandanplay_app_id') ?? '';

    final String? expiresAtRaw = prefs.getString('bgm_token_expires_at');
    if (expiresAtRaw != null && expiresAtRaw.isNotEmpty) {
      _bgmTokenExpiresAt = DateTime.tryParse(expiresAtRaw);
    }

    _bgmToken = await _secureStorage.read(key: 'bgm_token') ?? '';
    _bgmGatewaySessionId =
        await _secureStorage.read(key: 'bgm_gateway_session_id') ?? '';
    _dandanplayAppSecret =
        await _secureStorage.read(key: 'dandanplay_app_secret') ?? '';

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

    if (_shouldRefreshBangumiToken()) {
      await ensureBangumiAccessToken(forceRefresh: true);
    }
    if (_bgmToken.trim().isNotEmpty &&
        (_bgmNickname.trim().isEmpty || _bgmAvatarUrl.trim().isEmpty)) {
      await refreshBangumiProfile(silent: true);
    }

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> updateAccount(String acc, String token) async {
    _bgmAcc = acc.trim();
    _bgmToken = token.trim();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('bgm_acc', _bgmAcc);
    // Token stored ONLY in encrypted secure storage.
    await _secureStorage.write(key: 'bgm_token', value: _bgmToken);
    // Purge any legacy plain‑text token.
    await prefs.remove('bgm_token');

    notifyListeners();
  }

  Future<void> updateBangumiAuthGateway(String gatewayUrl) async {
    _bgmAuthGatewayUrl = _normalizeBangumiAuthGatewayUrl(gatewayUrl);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('bgm_auth_gateway_url', _bgmAuthGatewayUrl);
    notifyListeners();
  }

  Future<void> bindBangumiGatewaySession(
    BangumiGatewaySession session, {
    String? gatewayUrl,
  }) async {
    _bgmGatewaySessionId = session.sessionId.trim();
    _bgmToken = session.accessToken.trim();
    _bgmTokenExpiresAt = session.expiresAt;
    if (gatewayUrl != null && gatewayUrl.trim().isNotEmpty) {
      _bgmAuthGatewayUrl = _normalizeBangumiAuthGatewayUrl(gatewayUrl);
    }

    await _applyBangumiProfile(
      session.profile,
      accessToken: session.accessToken,
      expiresAt: session.expiresAt,
      sessionId: session.sessionId,
    );
  }

  Future<BangumiUserProfile?> refreshBangumiProfile({
    bool silent = false,
  }) async {
    final String token = _bgmToken.trim();
    if (token.isEmpty) {
      return null;
    }

    try {
      final BangumiUserProfile profile = await BangumiOAuthService()
          .fetchCurrentUserProfile(token);
      await _applyBangumiProfile(profile, notify: !silent);
      return profile;
    } catch (_) {
      if (!silent) {
        notifyListeners();
      }
      return null;
    }
  }

  Future<bool> ensureBangumiAccessToken({bool forceRefresh = false}) async {
    if (_bgmToken.trim().isEmpty) {
      return false;
    }
    if (!forceRefresh && !_shouldRefreshBangumiToken()) {
      return true;
    }
    if (!hasBangumiGatewaySession) {
      return false;
    }

    try {
      final BangumiGatewaySession session = await BangumiAuthGatewayService(
        baseUrl: bgmAuthGatewayUrl,
      ).refreshSession(_bgmGatewaySessionId);
      await bindBangumiGatewaySession(session);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearBangumiAuthorization({
    bool keepGatewayConfig = true,
  }) async {
    final String gatewayUrl = bgmAuthGatewayUrl;
    final String sessionId = _bgmGatewaySessionId;

    _bgmAcc = '';
    _bgmToken = '';
    _bgmTokenExpiresAt = null;
    _bgmNickname = '';
    _bgmAvatarUrl = '';
    _bgmBio = '';
    _bgmGatewaySessionId = '';
    if (!keepGatewayConfig) {
      _bgmAuthGatewayUrl = EmbeddedCredentials.bangumiAuthGatewayUrl;
    }

    if (gatewayUrl.trim().isNotEmpty && sessionId.trim().isNotEmpty) {
      try {
        await BangumiAuthGatewayService(baseUrl: gatewayUrl).logout(sessionId);
      } catch (_) {}
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('bgm_acc');
    await prefs.remove('bgm_token_expires_at');
    await prefs.remove('bgm_nickname');
    await prefs.remove('bgm_avatar_url');
    await prefs.remove('bgm_bio');
    if (!keepGatewayConfig) {
      await prefs.setString('bgm_auth_gateway_url', _bgmAuthGatewayUrl);
    }
    await _secureStorage.delete(key: 'bgm_token');
    await _secureStorage.delete(key: 'bgm_gateway_session_id');
    await _secureStorage.delete(key: 'bgm_refresh_token');
    await _secureStorage.delete(key: 'bgm_oauth_client_secret');

    notifyListeners();
  }

  Future<void> updateDandanplayCredentials(
    String appId,
    String appSecret,
  ) async {
    _dandanplayAppId = appId.trim();
    _dandanplayAppSecret = appSecret.trim();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('dandanplay_app_id', _dandanplayAppId);
    await _secureStorage.write(
      key: 'dandanplay_app_secret',
      value: _dandanplayAppSecret,
    );

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


  Future<void> updateHapticFeedback(bool enabled) async {
    _enableHapticFeedback = enabled;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ui_enable_haptic_feedback', enabled);
    notifyListeners();
  }
  Future<void> updateDistribution(bool autoCheckUpdates) async {
    _appUpdateFeedUrl = _normalizeAppUpdateFeedUrl();
    _autoCheckUpdates = autoCheckUpdates;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_update_feed_url', _appUpdateFeedUrl);
    await prefs.setBool('app_auto_check_updates', _autoCheckUpdates);

    notifyListeners();
  }

  Future<void> updatePlaybackOptions({
    required bool enablePictureInPicture,
    String? resumePlaybackBehavior,
    bool? autoPlayNextEpisode,
  }) async {
    _enablePictureInPicture = enablePictureInPicture;
    if (resumePlaybackBehavior != null) {
      _resumePlaybackBehavior = _normalizeResumePlaybackBehavior(
        resumePlaybackBehavior,
      );
    }
    if (autoPlayNextEpisode != null) {
      _autoPlayNextEpisode = autoPlayNextEpisode;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'playback_enable_picture_in_picture',
      _enablePictureInPicture,
    );
    await prefs.setString('playback_resume_behavior', _resumePlaybackBehavior);
    await prefs.setBool(
      'playback_auto_play_next_episode',
      _autoPlayNextEpisode,
    );

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

  String _normalizeBangumiAuthGatewayUrl(String? value) {
    final String fallback = EmbeddedCredentials.bangumiAuthGatewayUrl.trim();
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return fallback;
    }

    final Uri? uri = Uri.tryParse(trimmed);
    if (uri != null && _legacyBangumiGatewayHosts.contains(uri.host)) {
      return fallback;
    }
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  String _normalizeAppUpdateFeedUrl([String? value]) {
    final String trimmed = (value ?? '').trim();
    return trimmed.isEmpty
        ? EmbeddedCredentials.appUpdateFeedUrl.trim()
        : trimmed;
  }

  Future<void> _applyBangumiProfile(
    BangumiUserProfile profile, {
    String? accessToken,
    DateTime? expiresAt,
    String? sessionId,
    bool notify = true,
  }) async {
    _bgmAcc = profile.username.isNotEmpty ? profile.username : _bgmAcc;
    _bgmNickname = profile.nickname;
    _bgmAvatarUrl = profile.avatarUrl;
    _bgmBio = profile.sign;
    if (accessToken != null) {
      _bgmToken = accessToken.trim();
    }
    if (expiresAt != null) {
      _bgmTokenExpiresAt = expiresAt;
    }
    if (sessionId != null && sessionId.trim().isNotEmpty) {
      _bgmGatewaySessionId = sessionId.trim();
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('bgm_acc', _bgmAcc);
    await prefs.setString('bgm_nickname', _bgmNickname);
    await prefs.setString('bgm_avatar_url', _bgmAvatarUrl);
    await prefs.setString('bgm_bio', _bgmBio);
    await prefs.setString(
      'bgm_token_expires_at',
      _bgmTokenExpiresAt?.toIso8601String() ?? '',
    );
    await prefs.setString('bgm_auth_gateway_url', _bgmAuthGatewayUrl);
    await _secureStorage.write(key: 'bgm_token', value: _bgmToken);
    await _secureStorage.write(
      key: 'bgm_gateway_session_id',
      value: _bgmGatewaySessionId,
    );

    if (notify) {
      notifyListeners();
    }
  }

  bool _shouldRefreshBangumiToken() {
    if (_bgmToken.trim().isEmpty) {
      return false;
    }
    if (_bgmTokenExpiresAt == null) {
      return false;
    }
    return DateTime.now().isAfter(
      _bgmTokenExpiresAt!.subtract(const Duration(minutes: 5)),
    );
  }

  String _normalizeThemeMode(String? rawValue) {
    final String value = (rawValue ?? '').toLowerCase();
    if (value.contains('dark')) {
      return 'Dark';
    }
    return 'Light';
  }

  String _normalizeResumePlaybackBehavior(String? rawValue) {
    switch ((rawValue ?? '').trim()) {
      case 'auto':
      case 'never':
      case 'ask':
        return rawValue!.trim();
      default:
        return 'ask';
    }
  }
}
