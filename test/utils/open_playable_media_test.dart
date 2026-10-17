import 'dart:async';

import 'package:animemaster/src/models/playable_media.dart';
import 'package:animemaster/src/utils/open_playable_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

class _Player implements Player {
  final List<String> calls = <String>[];
  Media? opened;
  String? audio;
  bool failAudio = false;
  bool reportAudioFailure = false;
  bool holdAudio = false;
  bool hasVideoDuration = true;
  final _Stream events = _Stream();

  @override
  PlayerStream get stream => events;

  @override
  PlayerState get state => PlayerState(
    duration: hasVideoDuration ? const Duration(seconds: 600) : Duration.zero,
  );

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    calls.add('open:$play');
    opened = playable as Media;
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    calls.add('audio');
    audio = track.id;
    if (failAudio) throw StateError('audio unavailable');
    if (reportAudioFailure) {
      events.errors.add('audio unavailable');
    } else if (!holdAudio) {
      events.audio.add(const AudioParams(sampleRate: 48000));
    }
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek:${position.inSeconds}');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Stream implements PlayerStream {
  final StreamController<String> errors = StreamController<String>.broadcast();
  final StreamController<AudioParams> audio =
      StreamController<AudioParams>.broadcast();
  final StreamController<Duration> durations =
      StreamController<Duration>.broadcast();
  @override
  Stream<String> get error => errors.stream;
  @override
  Stream<AudioParams> get audioParams => audio.stream;
  @override
  Stream<PlayerLog> get log => const Stream<PlayerLog>.empty();
  @override
  Stream<Duration> get duration => durations.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'quality reload restores position after audio readiness and preserves pause',
    () async {
      final player = _Player();
      await openPlayableMedia(
        player,
        PlayableMedia(
          title: 'DASH',
          url: 'https://cdn.example/v',
          audioUrl: 'https://cdn.example/a',
        ),
        startPosition: const Duration(seconds: 90),
        play: false,
      );
      expect(player.calls, <String>['open:false', 'audio', 'seek:90']);
    },
  );
  test('audio is attached only after video metadata is available', () async {
    final player = _Player()..hasVideoDuration = false;
    final opening = openPlayableMedia(
      player,
      PlayableMedia(
        title: 'DASH',
        url: 'https://cdn.example/v',
        audioUrl: 'https://cdn.example/a',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(player.calls, <String>['open:false']);
    player.events.durations.add(const Duration(seconds: 600));
    await opening;
    expect(player.calls, <String>['open:false', 'audio', 'play']);
  });

  test('playback waits for external audio decoder readiness', () async {
    final player = _Player()..holdAudio = true;
    final opening = openPlayableMedia(
      player,
      PlayableMedia(
        title: 'DASH',
        url: 'https://cdn.example/v',
        audioUrl: 'https://cdn.example/a',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(player.calls, <String>['open:false', 'audio']);
    player.events.audio.add(const AudioParams(sampleRate: 48000));
    await opening;
    expect(player.calls.last, 'play');
  });

  test(
    'split DASH is opened paused, audio attached, and playback started in order',
    () async {
      final player = _Player();
      await openPlayableMedia(
        player,
        PlayableMedia(
          title: 'DASH',
          url: 'https://cdn.example/video',
          audioUrl: 'https://cdn.example/audio',
          headers: <String, String>{'Referer': 'https://www.bilibili.com/'},
        ),
      );
      expect(player.calls, <String>['open:false', 'audio', 'play']);
      expect(player.audio, 'https://cdn.example/audio');
      expect(
        player.opened!.httpHeaders!['Referer'],
        'https://www.bilibili.com/',
      );
    },
  );

  test(
    'ordinary media keeps automatic playback and does not load external audio',
    () async {
      final player = _Player();
      await openPlayableMedia(
        player,
        PlayableMedia(title: 'MP4', url: '/video.mp4'),
      );
      expect(player.calls, <String>['open:true']);
    },
  );

  test('audio attachment failure does not start silent playback', () async {
    final player = _Player()..failAudio = true;
    await expectLater(
      openPlayableMedia(
        player,
        PlayableMedia(
          title: 'DASH',
          url: 'https://cdn.example/v',
          audioUrl: 'https://cdn.example/a',
        ),
      ),
      throwsStateError,
    );
    expect(player.calls, <String>['open:false', 'audio']);
  });

  test(
    'native asynchronous audio error is surfaced before playback starts',
    () async {
      final player = _Player()..reportAudioFailure = true;
      await expectLater(
        openPlayableMedia(
          player,
          PlayableMedia(
            title: 'DASH',
            url: 'https://cdn.example/v',
            audioUrl: 'https://cdn.example/a',
          ),
        ),
        throwsStateError,
      );
      expect(player.calls, <String>['open:false', 'audio']);
    },
  );
}
