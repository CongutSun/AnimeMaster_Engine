import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

void maybeHaptic(BuildContext context) {
  if (context.read<SettingsProvider>().enableHapticFeedback) {
    HapticFeedback.lightImpact();
  }
}
