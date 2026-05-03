import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/playable_media.dart';
import '../repositories/playback_progress_repository.dart';
import '../storage/app_database.dart';

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
  static final PlaybackProgressRepository _repository =
      PlaybackProgressRepository.instance;

  const PlaybackProgressStore._();

  static Future<PlaybackProgressSnapshot?> load(PlayableMedia media) async {
    final String key = keyFor(media);
    final PlaybackProgressRecord? record = await _repository.loadByKey(key);
    if (record != null) {
      return _snapshotFromRecord(record);
    }

    final PlaybackProgressSnapshot? legacySnapshot = await _loadLegacySnapshot(
      key,
    );
    if (legacySnapshot != null) {
      await _repository.save(
        mediaKey: key,
        media: media,
        position: legacySnapshot.position,
        duration: legacySnapshot.duration,
      );
      await _removeLegacySnapshot(key);
    }
    return legacySnapshot;
  }

  static PlaybackProgressSnapshot? _snapshotFromRecord(
    PlaybackProgressRecord record,
  ) {
    return _buildSnapshot(
      positionMs: record.positionMs,
      durationMs: record.durationMs,
      updatedAtMs: record.updatedAtMs,
    );
  }

  static Future<PlaybackProgressSnapshot?> _loadLegacySnapshot(
    String key,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _buildSnapshot(
      positionMs: prefs.getInt('$key.position') ?? 0,
      durationMs: prefs.getInt('$key.duration') ?? 0,
      updatedAtMs: prefs.getInt('$key.updatedAt') ?? 0,
    );
  }

  static PlaybackProgressSnapshot? _buildSnapshot({
    required int positionMs,
    required int durationMs,
    required int updatedAtMs,
  }) {
    final int savedPositionMs = positionMs;
    final int savedDurationMs = durationMs;
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
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
  }

  static Future<void> _removeLegacySnapshot(String key) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('$key.position');
    await prefs.remove('$key.duration');
    await prefs.remove('$key.updatedAt');
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

    final String key = keyFor(media);
    await _repository.save(
      mediaKey: key,
      media: media,
      position: position,
      duration: duration,
    );
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
