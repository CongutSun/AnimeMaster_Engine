import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'managers/download_manager.dart';
import 'providers/settings_provider.dart';
import 'screens/home_page.dart';
import 'services/app_update_service.dart';

class AnimeMasterApp extends StatelessWidget {
  const AnimeMasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <ChangeNotifierProvider<dynamic>>[
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
        ChangeNotifierProvider<DownloadManager>.value(value: DownloadManager()),
      ],
      child: Consumer<SettingsProvider>(
        builder:
            (BuildContext context, SettingsProvider settings, Widget? child) {
              final String currentTheme = settings.themeMode.toLowerCase();
              final bool isDark =
                  currentTheme.contains('dark') ||
                  settings.themeMode.contains('深色') ||
                  settings.themeMode.contains('暗');

              return _StartupUpdateProbe(
                settings: settings,
                child: MaterialApp(
                  title: 'AnimeMaster',
                  debugShowCheckedModeBanner: false,
                  themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
                  theme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.deepPurple,
                      brightness: Brightness.light,
                    ),
                    useMaterial3: true,
                  ),
                  darkTheme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.deepPurple,
                      brightness: Brightness.dark,
                    ),
                    useMaterial3: true,
                  ),
                  home: const HomePage(),
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }

      final AppUpdateCheckResult result = await const AppUpdateService()
          .checkForUpdates(feedUrl);
      if (!mounted || !result.updateAvailable) {
        return;
      }

      await const AppUpdateService().showUpdateDialog(
        context,
        result,
        quietIfUpToDate: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
