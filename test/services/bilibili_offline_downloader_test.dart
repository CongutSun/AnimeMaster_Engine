import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:animemaster/src/managers/download_manager.dart';
import 'package:animemaster/src/models/bilibili_video.dart';
import 'package:animemaster/src/models/download_task_info.dart';
import 'package:animemaster/src/models/playable_media.dart';
import 'package:animemaster/src/repositories/download_task_repository.dart';
import 'package:animemaster/src/services/bilibili_offline_downloader.dart';
import 'package:animemaster/src/services/bilibili_video_service.dart';
import 'package:animemaster/src/storage/app_database.dart';
import 'package:animemaster/src/utils/cached_media_playback.dart';
import 'package:animemaster/src/utils/playback_progress_store.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const p1 = BilibiliPart(
  cid: 10,
  page: 1,
  title: '开场',
  duration: Duration(minutes: 1),
);
const p2 = BilibiliPart(
  cid: 20,
  page: 2,
  title: '正文',
  duration: Duration(minutes: 2),
);
const bvid = 'BV1xx411c7mD';
const key = 'bili_${bvid}_20';

class _Videos extends BilibiliVideoService {
  bool allowed = true;
  bool split = true;
  bool streamingOnly = false;
  final resolved = <int>[];
  Completer<void>? gate;
  BilibiliVideo get video => BilibiliVideo(
    bvid: bvid,
    title: '样片',
    parts: const [p1, p2],
    allowsDownload: allowed,
  );
  @override
  Future<BilibiliVideo> loadVideo(String input) async {
    expect(input, bvid);
    await gate?.future;
    return video;
  }

  @override
  Future<PlayableMedia> resolvePart(
    BilibiliVideo video,
    BilibiliPart part, {
    int? preferredQuality,
  }) async {
    resolved.add(part.cid);
    return PlayableMedia(
      title: part.label,
      bilibili: BilibiliPlayback(
        video: video,
        part: part,
        qualityLabel: '480P',
        restrictedToStreaming: streamingOnly,
      ),
      url: 'https://test.bilivideo.com/video?token=temporary',
      audioUrl: split
          ? 'https://test.bilivideo.com/audio?token=temporary'
          : null,
      headers: const {
        'Referer': 'https://www.bilibili.com/',
        'Cookie': 'secret',
      },
    );
  }
}

class _Cdn implements HttpClientAdapter {
  bool truncateAudio = false;
  bool redirect = false;
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.headers['Cookie'], isNull);
    expect(options.headers['Referer'], 'https://www.bilibili.com/');
    final path = options.uri.path;
    paths.add(path);
    if (redirect) {
      return ResponseBody.fromBytes(
        [],
        302,
        headers: {
          'location': ['http://other.invalid/redirect'],
        },
      );
    }
    final data = path == '/video' ? [1, 2, 3] : [4, 5];
    return ResponseBody.fromBytes(
      data,
      200,
      headers: {
        'content-length': [
          '${path == '/audio' && truncateAudio ? 4 : data.length}',
        ],
        'content-type': ['application/octet-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDatabase database;
  late DownloadTaskRepository repository;
  late _Videos videos;
  late _Cdn cdn;
  late BilibiliOfflineDownloader downloader;
  late DownloadManager manager;
  DownloadManager newManager() => DownloadManager.withDependencies(
    repository,
    (_, _, _) => throw StateError('B 站缓存不应启动 BT'),
    bilibili: downloader,
  );
  Future<DownloadTaskInfo> waitFor(
    bool Function(DownloadTaskInfo) predicate,
  ) async {
    final done = Completer<DownloadTaskInfo>();
    void check() {
      final task = manager.taskFor(key);
      if (!done.isCompleted && task != null && predicate(task)) {
        done.complete(task);
      }
    }

    manager.addListener(check);
    try {
      check();
      return await done.future.timeout(const Duration(seconds: 5));
    } finally {
      manager.removeListener(check);
    }
  }

  Future<void> enqueue() => manager.cacheBilibiliPart(
    videos.video,
    p2,
    bangumiSubjectId: 11,
    bangumiEpisodeId: 12,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('bili-offline-');
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DownloadTaskRepository(database);
    videos = _Videos();
    cdn = _Cdn();
    downloader = BilibiliOfflineDownloader(
      client: Dio()..httpClientAdapter = cdn,
      videos: videos,
      directoryFor: (k) => Directory('${root.path}/$k').create(),
    );
    manager = newManager();
    await manager.initPersistedTasks();
  });
  tearDown(() async {
    await manager.pauseAll();
    manager.dispose();
    await database.close();
    await root.delete(recursive: true);
  });
  test('同一分 P 只缓存一次，重启后两轨纯本地播放，进度沿用在线标识', () async {
    videos.gate = Completer();
    await Future.wait([enqueue(), enqueue()]);
    videos.gate!.complete();
    await waitFor((t) => t.isCompleted);
    expect(videos.resolved, [20]);
    expect(cdn.paths, ['/video', '/audio']);
    final saved = (await repository.loadAll()).single;
    expect(saved.url, 'https://www.bilibili.com/video/$bvid?p=2');
    expect(saved.targetSize, 3);
    expect(saved.audioSize, 2);
    manager.dispose();
    manager = newManager();
    await manager.initPersistedTasks();
    final restored = manager.taskFor(key)!;
    final media = (await CachedMediaPlayback.prepare(restored)).media;
    expect(media.isLocal, isTrue);
    expect(await File(media.url).readAsBytes(), [1, 2, 3]);
    expect(await File.fromUri(Uri.parse(media.audioUrl!)).readAsBytes(), [
      4,
      5,
    ]);
    expect(
      PlaybackProgressStore.bilibiliPartForKey(
        PlaybackProgressStore.keyFor(media),
      ),
      (bvid: bvid, cid: 20),
    );
    expect(await repository.watchOfflineEpisode(11, 12, '').first, isTrue);
    expect(manager.isSeeding(key), isFalse);
    expect(await manager.deleteTask(key), isTrue);
    expect(await repository.loadAll(), isEmpty);
    expect(await Directory(saved.savePath).exists(), isFalse);
  });
  test('短音轨使整个缓存失败，重试重取媒体；已完成后损坏的音轨也不能播放', () async {
    cdn.truncateAudio = true;
    await enqueue();
    final broken = await waitFor((t) => manager.isPaused(key));
    expect(broken.isCompleted, isFalse);
    expect(await Directory(broken.savePath).list().isEmpty, isTrue);
    expect(await CachedMediaPlayback.preferredTask([broken]), isNull);
    await expectLater(CachedMediaPlayback.prepare(broken), throwsStateError);
    cdn.truncateAudio = false;
    await manager.toggleTask(key);
    final good = await waitFor((t) => t.isCompleted);
    expect(videos.resolved, [20, 20]);
    await File.fromUri(Uri.parse(good.localAudioUrl!)).writeAsBytes([1]);
    expect(await repository.watchOfflineEpisode(11, 12, '').first, isFalse);
    await expectLater(CachedMediaPlayback.prepare(good), throwsStateError);
    manager.dispose();
    manager = newManager();
    await manager.initPersistedTasks();
    expect(manager.taskFor(key)!.isCompleted, isFalse);
    expect(manager.isPaused(key), isTrue);
  });
  test('中止和重启后可重新缓存单文件视频，不依赖外部音轨', () async {
    videos.gate = Completer();
    await enqueue();
    final cancelled = manager.toggleTask(key);
    videos.gate!.complete();
    await cancelled;
    expect((await repository.loadAll()).single.isCompleted, isFalse);
    expect(cdn.paths, isEmpty);
    manager.dispose();
    manager = newManager();
    await manager.initPersistedTasks();
    videos.split = false;
    await manager.toggleTask(key);
    final task = await waitFor((t) => t.isCompleted);
    final media = (await CachedMediaPlayback.prepare(task)).media;
    expect(media.audioUrl, isNull);
    expect(await File(media.url).readAsBytes(), [1, 2, 3]);
    expect(cdn.paths, ['/video']);
  });
  test('缓存前重新核对稿件权限，拒绝外部跳转', () async {
    final video = videos.video;
    videos.allowed = false;
    await manager.cacheBilibiliPart(video, p2);
    await waitFor((t) => manager.isPaused(key));
    expect(videos.resolved, isEmpty);
    expect(cdn.paths, isEmpty);
    videos.allowed = true;
    videos.streamingOnly = true;
    await manager.toggleTask(key);
    await waitFor((t) => manager.isPaused(key));
    expect(cdn.paths, isEmpty);
    videos.streamingOnly = false;
    cdn.redirect = true;
    await manager.toggleTask(key);
    final task = await waitFor((t) => manager.isPaused(key));
    expect(task.isCompleted, isFalse);
    expect(cdn.paths, ['/video']);
  });
  test('等待中的分 P 可独立取消，不会中断正在缓存的分 P', () async {
    videos.gate = Completer();
    await enqueue();
    await manager.cacheBilibiliPart(videos.video, p1);
    final other = manager.taskFor('bili_${bvid}_10')!;
    expect(manager.bilibiliStatus(other), '等待缓存');
    expect(await manager.deleteTask(other.hash), isTrue);
    videos.gate!.complete();
    await waitFor((t) => t.isCompleted);
    expect(videos.resolved, [20]);
    expect((await repository.loadAll()).single.hash, key);
  });
}
