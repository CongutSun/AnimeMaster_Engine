import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/dandanplay_models.dart';

class ActiveDanmakuItem {
  final int id;
  final DandanplayComment comment;
  final int lane;

  const ActiveDanmakuItem({
    required this.id,
    required this.comment,
    required this.lane,
  });
}

class DanmakuOverlay extends StatelessWidget {
  final List<ActiveDanmakuItem> items;
  final double fontSize;
  final double opacity;
  final double speed;
  final bool showBackground;
  final bool showStroke;
  final bool paused;
  final ValueChanged<int> onCompleted;

  const DanmakuOverlay({
    super.key,
    required this.items,
    required this.fontSize,
    required this.opacity,
    required this.speed,
    required this.showBackground,
    required this.showStroke,
    required this.paused,
    required this.onCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: items
              .map(
                (ActiveDanmakuItem item) => _DanmakuBullet(
                  key: ValueKey<int>(item.id),
                  item: item,
                  viewportSize: constraints.biggest,
                  fontSize: fontSize,
                  opacity: opacity,
                  speed: speed,
                  showBackground: showBackground,
                  showStroke: showStroke,
                  paused: paused,
                  onCompleted: () => onCompleted(item.id),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _DanmakuBullet extends StatefulWidget {
  final ActiveDanmakuItem item;
  final Size viewportSize;
  final double fontSize;
  final double opacity;
  final double speed;
  final bool showBackground;
  final bool showStroke;
  final bool paused;
  final VoidCallback onCompleted;

  const _DanmakuBullet({
    super.key,
    required this.item,
    required this.viewportSize,
    required this.fontSize,
    required this.opacity,
    required this.speed,
    required this.showBackground,
    required this.showStroke,
    required this.paused,
    required this.onCompleted,
  });

  @override
  State<_DanmakuBullet> createState() => _DanmakuBulletState();
}

class _DanmakuBulletState extends State<_DanmakuBullet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    final int baseDurationMs = widget.item.comment.mode == 1
        ? (7000 + widget.item.comment.text.length * 80).clamp(6500, 12000)
        : 4000;
    final int durationMs = (baseDurationMs / widget.speed).round().clamp(
      2600,
      18000,
    );
    _controller =
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: durationMs),
        )..addStatusListener((AnimationStatus status) {
          if (status == AnimationStatus.completed && mounted) {
            widget.onCompleted();
          }
        });
    if (!widget.paused) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _DanmakuBullet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused != oldWidget.paused) {
      if (widget.paused) {
        _controller.stop();
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double laneHeight = widget.fontSize + 14;
    final double textWidth = math.max(
      120.0,
      widget.item.comment.text.runes.length * widget.fontSize,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final int mode = widget.item.comment.mode;
        final double progress = _controller.value;
        final double top = switch (mode) {
          4 =>
            widget.viewportSize.height -
                90 -
                (widget.item.lane + 1) * laneHeight,
          5 => 12 + widget.item.lane * laneHeight,
          _ => 12 + widget.item.lane * laneHeight,
        };

        final double left = mode == 1
            ? widget.viewportSize.width -
                  (widget.viewportSize.width + textWidth + 32) * progress
            : (widget.viewportSize.width - textWidth) / 2;
        final double opacity = mode == 1
            ? 1
            : (progress < 0.15
                  ? progress / 0.15
                  : (progress > 0.85 ? (1 - progress) / 0.15 : 1));

        // Positioned must apply its parent data directly to the Stack child.
        return Positioned(
          left: left,
          top: top,
          child: mode == 1 && widget.opacity >= 0.99
              ? child!
              : Opacity(
                  opacity: (opacity * widget.opacity).clamp(0, 1),
                  child: child!,
                ),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.showBackground
              ? Colors.black.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            widget.item.comment.text,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              color: Color(0xFF000000 | widget.item.comment.color),
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w600,
              shadows: widget.showStroke
                  ? const <Shadow>[
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 3,
                        offset: Offset(0.8, 0.8),
                      ),
                    ]
                  : const <Shadow>[],
            ),
          ),
        ),
      ),
    );
  }
}
