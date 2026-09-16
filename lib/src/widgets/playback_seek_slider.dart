import 'package:flutter/material.dart';

class PlaybackSeekSlider extends StatefulWidget {
  const PlaybackSeekSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<PlaybackSeekSlider> createState() => _PlaybackSeekSliderState();
}

class _PlaybackSeekSliderState extends State<PlaybackSeekSlider> {
  double? _preview;
  @override
  Widget build(BuildContext context) {
    final max = widget.duration.inMilliseconds.clamp(1, 1 << 53).toDouble();
    return Slider(
      value: (_preview ?? widget.position.inMilliseconds.toDouble()).clamp(
        0,
        max,
      ),
      max: max,
      activeColor: Colors.white,
      inactiveColor: Colors.white30,
      onChanged: widget.duration <= Duration.zero
          ? null
          : (value) => setState(() => _preview = value),
      onChangeEnd: (value) {
        setState(() => _preview = null);
        widget.onSeek(Duration(milliseconds: value.round()));
      },
    );
  }
}
