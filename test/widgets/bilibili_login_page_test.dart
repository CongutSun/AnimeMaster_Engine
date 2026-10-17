import 'dart:async';

import 'package:animemaster/src/screens/bilibili_login_page.dart';
import 'package:animemaster/src/services/bilibili_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _Auth extends BilibiliAuthService {
  int calls = 0;
  bool cancelled = false;
  Completer<BilibiliLoginStatus>? gate;
  @override
  Future<void> initialize() async {}
  @override
  Future<BilibiliLoginAttempt> beginLogin() async => BilibiliLoginAttempt(
    url: 'https://passport.bilibili.com/scan?qrcode_key=test',
    key: 'test',
    expiresAt: DateTime(2050),
    generation: 1,
  );
  @override
  Future<BilibiliLoginStatus> poll(BilibiliLoginAttempt attempt) async {
    calls++;
    return gate == null ? BilibiliLoginStatus.waiting : await gate!.future;
  }

  @override
  void cancelLogin() {
    cancelled = true;
  }
}

void main() {
  testWidgets('QR fits a narrow screen and closing login cancels polling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _Auth();
    await tester.pumpWidget(MaterialApp(home: BilibiliLoginPage(auth: auth)));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(auth.calls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(auth.cancelled, isTrue);
    await tester.pump(const Duration(seconds: 10));
    expect(auth.calls, 1);
  });

  testWidgets('slow login polling cannot overlap requests', (tester) async {
    final auth = _Auth()..gate = Completer<BilibiliLoginStatus>();
    await tester.pumpWidget(MaterialApp(home: BilibiliLoginPage(auth: auth)));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(auth.calls, 1);
    auth.gate!.complete(BilibiliLoginStatus.waiting);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(auth.calls, 1);
    expect(tester.takeException(), isNull);
  });
}
