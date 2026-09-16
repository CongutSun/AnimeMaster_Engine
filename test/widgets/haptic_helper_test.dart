import 'package:animemaster/src/utils/haptic_helper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'disabled feedback is silent; enabled feedback is dispatched and throttled',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        HapticNavigatorObserver.syncFromSettings(false);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });
      HapticNavigatorObserver.syncFromSettings(false);
      quickHaptic();
      expect(calls, isEmpty);
      HapticNavigatorObserver.syncFromSettings(true);
      quickHaptic();
      quickHaptic();
      await Future<void>.delayed(Duration.zero);
      expect(calls.single.method, 'HapticFeedback.vibrate');
      expect(calls.single.arguments, 'HapticFeedbackType.mediumImpact');
      HapticNavigatorObserver.syncFromSettings(false);
      quickHaptic();
      expect(calls.length, 1);
    },
  );
}
