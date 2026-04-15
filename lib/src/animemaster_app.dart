import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'managers/download_manager.dart';
import 'providers/settings_provider.dart';
import 'screens/home_page.dart';

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
        builder: (BuildContext context, SettingsProvider settings, Widget? child) {
          final String currentTheme = settings.themeMode.toLowerCase();
          final bool isDark =
              currentTheme.contains('dark') ||
              settings.themeMode.contains('深色') ||
              settings.themeMode.contains('暗');

          return MaterialApp(
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
          );
        },
      ),
    );
  }
}
