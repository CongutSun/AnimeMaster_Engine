import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

/// Call before any interactive action. Checks the haptic setting.
void maybeHaptic(BuildContext context) {
  if (context.read<SettingsProvider>().enableHapticFeedback) {
    HapticFeedback.lightImpact();
  }
}

/// Global navigator observer that fires haptics on every route push/pop.
class HapticNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _fireIfEnabled();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _fireIfEnabled();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _fireIfEnabled();
  }

  void _fireIfEnabled() {
    // NavigatorObserver doesn't have BuildContext, so we use a static flag.
    if (_hapticsGloballyEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  static bool _hapticsGloballyEnabled = false;

  /// Called once during app startup to sync the global haptics flag.
  static void syncFromSettings(bool enabled) {
    _hapticsGloballyEnabled = enabled;
  }
}

/// Quick haptic for switches/toggles — checks global flag.
void quickHaptic() {
  if (HapticNavigatorObserver._hapticsGloballyEnabled) {
    HapticFeedback.lightImpact();
  }
}
