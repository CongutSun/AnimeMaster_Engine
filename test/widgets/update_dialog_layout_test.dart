import 'package:animemaster/src/models/app_update_info.dart';
import 'package:animemaster/src/services/app_update_service.dart';
import 'package:animemaster/src/utils/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  for (final size in const [
    Size(320, 640),
    Size(360, 640),
    Size(412, 800),
    Size(640, 260),
  ]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('长更新日志可滚动，下载和关闭可达 ${size.width}×${size.height} @ $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final result = AppUpdateCheckResult(
          packageInfo: PackageInfo(
            appName: 'AnimeMaster',
            packageName: 'com.animemaster.app',
            version: '2.4.9',
            buildNumber: '4054',
          ),
          latest: AppUpdateInfo(
            version: '2.5.1',
            buildNumber: 4055,
            apkUrl: 'https://example.com/update.apk',
            sha256Map: {'universal': 'a' * 64},
            changeLog: List.generate(
              50,
              (i) => '第 $i 条 · 长更新日志与新功能说明',
            ).join('\n'),
            publishedAt: '2026-11-26',
          ),
          updateAvailable: true,
          message: '',
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => const AppUpdateService().showUpdateDialog(
                    context,
                    result,
                  ),
                  child: const Text('检查'),
                ),
              ),
            ),
          ),
        );
        final check = tester
            .widget<TextButton>(find.widgetWithText(TextButton, '检查'))
            .onPressed!;
        check();
        check();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scroll = find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(SingleChildScrollView),
            )
            .first;
        await tester.drag(scroll, const Offset(0, -350));
        await tester.pumpAndSettle();
        final later = find.text(AppStrings.updateDialogLater);
        await tester.ensureVisible(find.text(AppStrings.updateDialogDownload));
        await tester.pumpAndSettle();
        expect(
          find.text(AppStrings.updateDialogDownload).hitTestable(),
          findsOneWidget,
        );
        await tester.ensureVisible(later);
        await tester.pumpAndSettle();
        await tester.tap(later);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
