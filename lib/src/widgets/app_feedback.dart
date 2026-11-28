import 'package:flutter/material.dart';

/// Transient feedback belongs to the route on which the action took place.
class AppFeedback extends NavigatorObserver {
  static final observer = AppFeedback();
  static ScaffoldMessengerState? _messenger;
  static Route<dynamic>? _owner;
  static Object? _ticket;
  static int _downloads = 0;
  static DateTime? _lastDownload;

  static void show(
    BuildContext context,
    SnackBar bar, {
    bool download = false,
  }) {
    final route = ModalRoute.of(context);
    if (!context.mounted || route?.isCurrent == false) return;
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final consecutive =
        download &&
        _owner == route &&
        _lastDownload != null &&
        now.difference(_lastDownload!) < const Duration(seconds: 3);
    _downloads = download ? (consecutive ? _downloads + 1 : 1) : 0;
    _lastDownload = download ? now : null;
    messenger.removeCurrentSnackBar();
    _messenger = messenger;
    _owner = route;
    final token = _ticket = Object();
    final notice = SnackBar(
      content: _downloads > 1 ? Text('已加入 $_downloads 个缓存任务') : bar.content,
      action: bar.action,
      persist: false,
      backgroundColor: bar.backgroundColor,
      duration: download ? const Duration(seconds: 3) : bar.duration,
    );
    messenger.showSnackBar(notice).closed.then((_) {
      if (_ticket == token) {
        _ticket = null;
        _owner = null;
        _messenger = null;
      }
    });
  }

  static void dismiss(Route<dynamic>? route) {
    if (route == null || route != _owner) return;
    final token = _ticket;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ticket == token && _messenger?.mounted == true) {
        _messenger!.removeCurrentSnackBar();
      }
    });
  }

  @override
  void didChangeTop(
    Route<dynamic> topRoute,
    Route<dynamic>? previousTopRoute,
  ) => dismiss(previousTopRoute);
}

class DanmakuMatchPrompt {
  String? _lastMedia;
  void show(BuildContext context, String mediaKey, VoidCallback select) {
    if (_lastMedia == mediaKey || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _lastMedia = mediaKey;
    AppFeedback.show(
      context,
      SnackBar(
        content: const Text('自动匹配失败，可以手动搜索并指定弹幕剧集。'),
        action: SnackBarAction(label: '手动匹配', onPressed: select),
      ),
    );
  }
}
