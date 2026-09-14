import 'package:flutter/material.dart';

import '../models/dandanplay_models.dart';
import '../services/dandanplay_service.dart';

class DandanplaySendSheet extends StatefulWidget {
  const DandanplaySendSheet({
    super.key,
    required this.service,
    required this.match,
    required this.position,
  });
  final DandanplayService service;
  final DandanplayMatchResult match;
  final Duration position;
  @override
  State<DandanplaySendSheet> createState() => _DandanplaySendSheetState();
}

class _DandanplaySendSheetState extends State<DandanplaySendSheet> {
  final _text = TextEditingController();
  late final _capabilities = widget.service.capabilities();
  String _requestId = DandanplayService.newRequestId();
  String _submittedText = '';
  String? _error;
  bool _sending = false;
  bool _uncertain = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _uncertain) return;
    final text = _text.text.trim();
    if (text.isEmpty || text.runes.length > 100) {
      setState(() => _error = '请输入 1–100 个字符。');
      return;
    }
    if (_submittedText.isNotEmpty && text != _submittedText) {
      _requestId = DandanplayService.newRequestId();
    }
    _submittedText = text;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.service.sendComment(
        widget.match,
        text: text,
        position: widget.position,
        requestId: _requestId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _uncertain =
            error is DandanplayException &&
            ['send_unknown', 'send_pending'].contains(error.code);
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('发送弹幕', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(widget.match.displayTitle),
              Text(
                '发送位置：${widget.position.inMinutes}:${(widget.position.inSeconds % 60).toString().padLeft(2, '0')}',
              ),
              const SizedBox(height: 12),
              FutureBuilder<Map<String, dynamic>>(
                future: _capabilities,
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  final quota = data?['quota'];
                  final available =
                      data?['send'] == true &&
                      (quota is! Map || quota['available'] == true);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (snapshot.connectionState != ConnectionState.done)
                        const LinearProgressIndicator()
                      else if (snapshot.hasError)
                        Text('暂时无法确认发送额度：${snapshot.error}')
                      else if (quota is Map)
                        Text(
                          '全应用共享额度：今日剩余 ${quota['dailyRemaining']} 条，本月剩余 ${quota['monthlyRemaining']} 条。',
                        ),
                      const SizedBox(height: 8),
                      const Text('弹幕会与本应用的其他用户共享，请确认剧集和发送位置。'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _text,
                        enabled: !_sending && !_uncertain,
                        maxLength: 100,
                        maxLines: 3,
                        minLines: 1,
                        decoration: const InputDecoration(
                          hintText: '说点什么…',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) {
                          if (available) _send();
                        },
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: available && !_sending && !_uncertain
                                ? _send
                                : null,
                            icon: _sending
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send),
                            label: Text(
                              _sending
                                  ? '正在发送…'
                                  : available
                                  ? '发送'
                                  : '暂不可发送',
                            ),
                          ),
                          TextButton(
                            onPressed: _sending
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
