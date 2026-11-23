import 'package:animemaster/src/core/service_locator.dart';
import 'package:animemaster/src/screens/download_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('做种策略可在首个下载前设置并显示当前选项', (tester) async {
    SharedPreferences.setMockInitialValues({});
    ServiceLocator.setup();
    await tester.pumpWidget(const MaterialApp(home: DownloadCenterPage()));
    final settings = find.byTooltip('做种设置');
    for (final enabled in [false, true]) {
      await tester.tap(settings);
      await tester.pumpAndSettle();
      final selected = tester.widget<CheckedPopupMenuItem<bool>>(
        find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem<bool> && widget.checked,
        ),
      );
      expect(selected.value, !enabled);
      await tester.tap(find.text(enabled ? '空闲时做种' : '完成后停止做种'));
      await tester.pumpAndSettle();
      expect(ServiceLocator.downloadManager.seedingEnabled, enabled);
      expect(find.text('当前没有下载任务。'), findsOneWidget);
    }
  });
}
