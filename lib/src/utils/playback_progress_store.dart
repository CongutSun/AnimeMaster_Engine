import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/playable_media.dart';

class PlaybackProgressSnapshot {
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  const PlaybackProgressSnapshot({
    required this.position,
    required this.duration,
    required this.updatedAt,
  });
}

class PlaybackProgressStore {
  static const Duration _minimumRestorePosition = Duration(seconds: 10);
  static const Duration _minimumSavePosition = Duration(seconds: 5);
  static const Duration _endIgnoreWindow = Duration(seconds: 20);

  const PlaybackProgressStore._();

  static Future<PlaybackProgressSnapshot?> load(PlayableMedia media) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = keyFor(media);
    final int savedPositionMs = prefs.getInt('$key.position') ?? 0;
    final int savedDurationMs = prefs.getInt('$key.duration') ?? 0;
    if (savedPositionMs < _minimumRestorePosition.inMilliseconds) {
      return null;
    }
    if (savedDurationMs > 0 &&
        savedPositionMs > savedDurationMs - _endIgnoreWindow.inMilliseconds) {
      return null;
    }

    return PlaybackProgressSnapshot(
      position: Duration(milliseconds: savedPositionMs),
      duration: Duration(milliseconds: savedDurationMs),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        prefs.getInt('$key.updatedAt') ?? 0,
      ),
    );
  }

  static Future<void> save(
    PlayableMedia media, {
    required Duration position,
    required Duration duration,
    bool force = false,
  }) async {
    if (!force && position < _minimumSavePosition) {
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = keyFor(media);
    await prefs.setInt('$key.position', position.inMilliseconds);
    await prefs.setInt('$key.duration', duration.inMilliseconds);
    await prefs.setInt('$key.updatedAt', DateTime.now().millisecondsSinceEpoch);
  }

  static String keyFor(PlayableMedia media) {
    final String identity = media.bangumiEpisodeId > 0
        ? 'bgm_ep:${media.bangumiEpisodeId}'
        : <String>[
            media.localFilePath,
            media.url,
            media.subjectTitle,
            media.episodeLabel,
            media.title,
          ].where((String value) => value.trim().isNotEmpty).join('|');
    final String encoded = base64Url.encode(utf8.encode(identity));
    return 'playback_progress.$encoded';
  }
}
