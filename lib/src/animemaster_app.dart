import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/dio_client.dart';
import 'app_shell.dart';
import 'core/service_locator.dart';
import 'managers/download_manager.dart';
import 'providers/settings_provider.dart';
import 'services/app_update_service.dart';
import 'theme/app_theme.dart';

class AnimeMasterApp extends StatelessWidget {
  const AnimeMasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <ChangeNotifierProvider<dynamic>>[
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
        ChangeNotifierProvider<DownloadManager>.value(value: ServiceLocator.downloadManager),
      ],
      child: Consumer<SettingsProvider>(
        builder:
            (BuildContext context, SettingsProvider settings, Widget? child) {
              // Register 401 auto-refresh callback once settings are loaded.
              if (settings.isLoaded) {
                DioClient.setAuthTokenRefresher(
                  () => settings.ensureBangumiAccessToken(forceRefresh: true)
                      .then((bool ok) => ok ? settings.bgmToken : null),
                );
              }

              final String currentTheme = settings.themeMode.toLowerCase();
              final bool isDark =
                  currentTheme.contains('dark') ||
                  settings.themeMode.contains('深色') ||
                  settings.themeMode.contains('暗');

              return MaterialApp(
                title: 'AnimeMaster',
                debugShowCheckedModeBanner: false,
                themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                home: _StartupUpdateProbe(
                  settings: settings,
                  child: const AppShell(),
                ),
              );
            },
      ),
    );
  }
}

class _StartupUpdateProbe extends StatefulWidget {
  final SettingsProvider settings;
  final Widget child;

  const _StartupUpdateProbe({required this.settings, required this.child});

  @override
  State<_StartupUpdateProbe> createState() => _StartupUpdateProbeState();
}

class _StartupUpdateProbeState extends State<_StartupUpdateProbe> {
  String _checkedFeedUrl = '';
  bool _isChecking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleUpdateCheckIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _StartupUpdateProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleUpdateCheckIfNeeded();
  }

  void _scheduleUpdateCheckIfNeeded() {
    final SettingsProvider settings = widget.settings;
    final String feedUrl = settings.appUpdateFeedUrl.trim();

    if (!settings.isLoaded || !settings.autoCheckUpdates || feedUrl.isEmpty) {
      return;
    }
    if (_checkedFeedUrl == feedUrl) {
      return;
    }

    _checkedFeedUrl = feedUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(
        const Duration(milliseconds: 900),
        () => _runStartupUpdateCheck(feedUrl),
      );
    });
  }

  Future<void> _runStartupUpdateCheck(String feedUrl) async {
    if (!mounted || _isChecking) {
      return;
    }
    _isChecking = true;
    try {
      final AppUpdateService updateService = ServiceLocator.appUpdateService;
      final AppUpdateCheckResult result = await updateService
          .checkForUpdates(feedUrl);
      if (!mounted || !result.updateAvailable) {
        return;
      }

      await updateService.showUpdateDialog(
        context,
        result,
        quietIfUpToDate: true,
      );
    } finally {
      _isChecking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
