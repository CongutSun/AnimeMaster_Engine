import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/settings_provider.dart';
import 'screens/collection_page.dart';
import 'screens/download_center_page.dart';
import 'screens/home_page.dart';
import 'screens/onboarding_page.dart';
import 'screens/settings_page.dart';
import 'utils/app_strings.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  bool _showOnboarding = false;
  bool _onboardingChecked = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final bool completed = await OnboardingPage.hasCompleted();
    if (!mounted) return;
    setState(() {
      _showOnboarding = !completed;
      _onboardingChecked = true;
    });
  }

  void _onOnboardingComplete() {
    setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_onboardingChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_showOnboarding) {
      return OnboardingPage(onComplete: _onOnboardingComplete);
    }

    final SettingsProvider settings = context.watch<SettingsProvider>();
    final String bgPath = settings.customBgPath;
    final bool hasBg = bgPath.isNotEmpty && File(bgPath).existsSync();

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (hasBg)
            Positioned.fill(
              child: Image.file(
                File(bgPath),
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              ),
            ),
          if (hasBg)
            Positioned.fill(
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: ColoredBox(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black.withValues(alpha: 0.46)
                        : Theme.of(context).colorScheme.surface.withValues(alpha: 0.24),
                  ),
                ),
              ),
            ),
          IndexedStack(
            index: _currentIndex,
            children: const <Widget>[
              HomePage(),
              CollectionPage(),
              DownloadCenterPage(),
              SettingsPage(),
            ],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          HapticFeedback.lightImpact();
          setState(() => _currentIndex = index);
        },
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: AppStrings.navHome,
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library_rounded),
            label: AppStrings.navCollection,
          ),
          NavigationDestination(
            icon: Icon(Icons.download_for_offline_outlined),
            selectedIcon: Icon(Icons.download_for_offline_rounded),
            label: AppStrings.navDownloads,
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: AppStrings.navSettings,
          ),
        ],
      ),
    );
  }
}
