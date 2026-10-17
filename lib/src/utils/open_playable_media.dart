import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../models/playable_media.dart';

Future<void> openPlayableMedia(
  Player player,
  PlayableMedia media, {
  Duration? startPosition,
  bool play = true,
}) async {
  final String? audioUrl = media.audioUrl;
  final bool hasExternalAudio = audioUrl != null && audioUrl.isNotEmpty;
  final Media video = Media(media.url, httpHeaders: media.headers);
  if (!hasExternalAudio) {
    await player.open(video, play: play && startPosition == null);
    if (startPosition != null) {
      await player.seek(startPosition);
      if (play) await player.play();
    }
    return;
  }

  final Completer<void> videoReady = Completer<void>();
  final Completer<void> audioReady = Completer<void>();
  String? failure;
  final List<StreamSubscription<dynamic>> subscriptions =
      <StreamSubscription<dynamic>>[];
  void fail(String message) {
    failure = message;
    if (!videoReady.isCompleted) videoReady.complete();
    if (!audioReady.isCompleted) audioReady.complete();
  }

  bool loadingAudio = false;
  subscriptions.add(player.stream.error.listen(fail));
  subscriptions.add(
    player.stream.log.listen((PlayerLog log) {
      if (log.level == 'error' && log.text.contains('_command(audio-add')) {
        fail('加载音轨失败');
      }
    }),
  );
  subscriptions.add(
    player.stream.duration.listen((Duration duration) {
      if (duration > Duration.zero && !videoReady.isCompleted) {
        videoReady.complete();
      }
    }),
  );
  subscriptions.add(
    player.stream.audioParams.listen((AudioParams params) {
      if (loadingAudio &&
          (params.sampleRate ?? 0) > 0 &&
          !audioReady.isCompleted) {
        audioReady.complete();
      }
    }),
  );
  try {
    await player.open(video, play: false);
    if (player.state.duration > Duration.zero && !videoReady.isCompleted) {
      videoReady.complete();
    }
    await videoReady.future.timeout(const Duration(seconds: 20));
    if (failure != null) throw StateError('加载视频失败');
    loadingAudio = true;
    await player.setAudioTrack(AudioTrack.uri(audioUrl));
    await audioReady.future.timeout(const Duration(seconds: 20));
    if (failure != null) throw StateError('加载音轨失败');
    if (startPosition != null) await player.seek(startPosition);
    if (play) await player.play();
  } finally {
    for (final StreamSubscription<dynamic> subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}
