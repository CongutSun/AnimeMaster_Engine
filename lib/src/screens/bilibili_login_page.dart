import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/bilibili_auth_service.dart';

class BilibiliLoginPage extends StatefulWidget {
  final BilibiliAuthService? auth;
  const BilibiliLoginPage({super.key, this.auth});
  @override
  State<BilibiliLoginPage> createState() => _BilibiliLoginPageState();
}

class _BilibiliLoginPageState extends State<BilibiliLoginPage> {
  late final BilibiliAuthService _auth;
  BilibiliLoginAttempt? _attempt;
  bool _loading = false;
  String _status = '';
  int _epoch = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? BilibiliAuthService.instance;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _auth.initialize();
      if (!mounted) return;
      if (_auth.isLoggedIn) {
        await _auth.refresh();
        if (mounted) setState(() {});
      } else {
        await _generate();
      }
    } catch (_) {
      if (mounted) setState(() => _status = '登录状态暂不可用，请重试。');
    }
  }

  Future<void> _generate() async {
    if (_loading) return;
    final int epoch = ++_epoch;
    _pollTimer?.cancel();
    setState(() {
      _loading = true;
      _attempt = null;
      _status = '';
    });
    try {
      final BilibiliLoginAttempt attempt = await _auth.beginLogin();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _attempt = attempt;
        _status = '使用 B站 App 扫码并确认登录';
      });
      unawaited(_poll(attempt, epoch));
    } catch (error) {
      if (!mounted || epoch != _epoch) return;
      setState(
        () => _status = error is BilibiliAuthException
            ? error.message
            : '无法生成登录二维码，请重试。',
      );
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _poll(BilibiliLoginAttempt attempt, int epoch) async {
    if (!mounted || epoch != _epoch) return;
    try {
      final BilibiliLoginStatus status = await _auth.poll(attempt);
      if (!mounted || epoch != _epoch) return;
      if (status == BilibiliLoginStatus.success) {
        Navigator.of(context).pop(true);
        return;
      }
      if (status == BilibiliLoginStatus.expired ||
          status == BilibiliLoginStatus.cancelled) {
        setState(() {
          _attempt = null;
          _status = '二维码已失效，请刷新后重试。';
        });
        return;
      }
      setState(
        () => _status = status == BilibiliLoginStatus.scanned
            ? '已扫码，请在 B站 App 中确认登录'
            : '等待 B站 App 扫码确认',
      );
    } catch (error) {
      if (!mounted || epoch != _epoch) return;
      setState(
        () => _status = error is BilibiliAuthException
            ? error.message
            : '检查登录失败，请刷新后重试。',
      );
      return;
    }
    _pollTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_poll(attempt, epoch));
    });
  }

  Future<void> _openApp() async {
    final BilibiliLoginAttempt? attempt = _attempt;
    if (attempt == null) return;
    bool opened = false;
    try {
      opened = await launchUrl(
        attempt.appUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (mounted && !opened) {
      setState(() => _status = '无法打开 B站 App。可截屏后在 B站“扫一扫”中从相册识别二维码。');
    }
  }

  Future<void> _signOut() async {
    _epoch++;
    _pollTimer?.cancel();
    try {
      await _auth.signOut();
      if (!mounted) return;
      setState(() => _status = '已清除本机授权。');
      await _generate();
    } catch (_) {
      if (mounted) setState(() => _status = '清除授权失败，请重试。');
    }
  }

  @override
  void dispose() {
    _epoch++;
    _pollTimer?.cancel();
    _auth.cancelLogin();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('B站登录')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AnimatedBuilder(
                animation: _auth,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (_auth.isLoggedIn) ...<Widget>[
                      const Icon(Icons.account_circle, size: 64),
                      const SizedBox(height: 12),
                      Text(
                        _auth.account!.name,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        _auth.account!.isVip ? '大会员账号' : '已登录',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton(
                        onPressed: _signOut,
                        child: const Text('清除本机授权'),
                      ),
                    ] else ...<Widget>[
                      if (_loading)
                        const Center(child: CircularProgressIndicator()),
                      if (_attempt != null)
                        Center(
                          child: QrImageView(
                            data: _attempt!.url,
                            size: 240,
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Colors.white,
                            semanticsLabel: 'B站登录二维码',
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(_status, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      if (_attempt != null)
                        FilledButton.icon(
                          onPressed: _openApp,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('打开 B站 App 确认'),
                        ),
                      TextButton.icon(
                        onPressed: _loading ? null : _generate,
                        icon: const Icon(Icons.refresh),
                        label: const Text('刷新二维码'),
                      ),
                      const Text(
                        '同一台手机也可先截屏，再到 B站“扫一扫”中从相册识别二维码。',
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_auth.isLoggedIn && _status.isNotEmpty) Text(_status),
                    const SizedBox(height: 24),
                    const Text(
                      '登录凭据仅保存在本机系统安全存储中。播放画质与内容权限由 B站账号的实际授权决定。',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
