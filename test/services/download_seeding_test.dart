import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animemaster/src/managers/download_manager.dart';
import 'package:animemaster/src/models/download_task_info.dart';
import 'package:animemaster/src/repositories/download_task_repository.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repository extends Fake implements DownloadTaskRepository {
  final rows = <String, DownloadTaskInfo>{};

  @override
  Future<List<DownloadTaskInfo>> loadAll() async =>
      rows.values.map((task) => task.copyWith()).toList();

  @override
  Future<void> upsert(DownloadTaskInfo task) async {
    rows[task.hash] = task.copyWith();
  }

  @override
  Future<void> saveIndex(DownloadTaskInfo task) => upsert(task);
  @override
  Future<List<Map<String, dynamic>>> catalog(int subjectId) async => [];
  @override
  Future<void> upsertAll(Iterable<DownloadTaskInfo> tasks) async {
    for (final task in tasks) {
      await upsert(task);
    }
  }
}

class _Task extends Fake implements TorrentTask {
  _Task(this.source);

  final TorrentTask source;
  @override
  late final events = source.events;

  @override
  Torrent get metaInfo => source.metaInfo;
  @override
  TaskState state = TaskState.stopped;
  @override
  double progress = 0;
  @override
  int get downloaded => 0;
  @override
  double get uploadSpeed => 0;
  @override
  double get currentDownloadSpeed => 0;
  @override
  void requestPeersFromDHT() {}
  @override
  void startAnnounceUrl(Uri url, Uint8List infoHash) {}
  @override
  void addDHTNode(Uri uri) {}

  @override
  Future<Map<String, dynamic>> start() async {
    state = TaskState.running;
    return {};
  }

  @override
  void pause() => state = TaskState.paused;
  @override
  void resume() => state = TaskState.running;
  @override
  Future<void> stop() async {
    state = TaskState.stopped;
    await events.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.animemaster.app/background_download');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final bytes = Uint8List.fromList(
    ascii.encode(
      'd4:infod6:lengthi1e4:name8:test.mp412:piece lengthi16384e6:pieces20:abcdefghijklmnopqrstee',
    ),
  );
  late Directory dir;
  late _Repository repository;
  late DownloadManager manager;
  final tasks = <String, _Task>{};
  final commands = <String>[];

  DownloadManager newManager() => DownloadManager.withDependencies(
    repository,
    (torrent, path, _) =>
        tasks[path] = _Task(TorrentTask.newTask(torrent, path)),
  );

  Future<DownloadTaskInfo> add(String hash, {bool completed = false}) async {
    final info = DownloadTaskInfo(
      hash: hash,
      title: hash,
      url: '',
      savePath: '${dir.path}/$hash',
      targetPath: '${dir.path}/$hash/test.mp4',
      targetSize: 1,
      isCompleted: completed,
    );
    await manager.addTask(info, bytes);
    return info;
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('animemaster-seeding-');
    tasks.clear();
    commands.clear();
    repository = _Repository();
    messenger.setMockMethodCallHandler(channel, (call) async {
      final command = call.method == 'stop'
          ? 'stop'
          : call.arguments['title'] as String;
      commands.add(command);
      return null;
    });
    manager = newManager();
    await manager.initPersistedTasks();
  });

  tearDown(() async {
    manager.dispose();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    for (final task in repository.rows.values) {
      await File('${task.savePath}/meta.torrent').delete();
      await Directory(task.savePath).delete();
    }
    await dir.delete();
  });

  for (final share in [true, false]) {
    test(
      'completion reconciles torrent, notification and persisted policy with seeding=$share',
      () async {
        expect(manager.seedingEnabled, isTrue);
        await manager.setSeedingEnabled(share);
        final info = await add('episode');
        final task = tasks[info.savePath]!;
        expect(commands.last, 'AnimeMaster 正在下载');
        expect(task.state, TaskState.running);

        final expectedCommand = share ? 'AnimeMaster 正在分享' : 'stop';
        final completed = Completer<void>();
        void onChange() {
          if (!completed.isCompleted &&
              info.isCompleted &&
              commands.last == expectedCommand &&
              (share
                  ? manager.isSeeding(info.hash)
                  : task.state == TaskState.stopped)) {
            completed.complete();
          }
        }

        manager.addListener(onChange);
        if (share) {
          // A restored torrent may already be complete when the first sample arrives.
          task.progress = 1;
        } else {
          task.events.emit(AllComplete());
        }
        await completed.future.timeout(const Duration(seconds: 8));
        manager.removeListener(onChange);
        expect(repository.rows[info.hash]!.isCompleted, isTrue);
        expect(manager.isSeeding(info.hash), share);
        expect(task.state, share ? TaskState.running : TaskState.stopped);
        expect(commands, ['stop', 'AnimeMaster 正在下载', expectedCommand]);

        manager.dispose();
        manager = newManager();
        commands.clear();
        await manager.initPersistedTasks();
        expect(manager.seedingEnabled, share);
        expect(manager.isSeeding(info.hash), share);
        expect(
          tasks[info.savePath]!.state,
          share ? TaskState.running : TaskState.stopped,
        );
        if (!share) {
          await manager.prepareForPlayback(info.hash);
          await manager.toggleTask(info.hash);
          expect(commands, isNot(contains('AnimeMaster 正在分享')));
          expect(tasks[info.savePath]!.state, TaskState.stopped);
        }
      },
    );
  }

  test(
    'disabling sharing while a seed starts leaves the engine and service stopped',
    () async {
      await manager.setSeedingEnabled(false);
      final info = await add('completed', completed: true);
      final startEntered = Completer<void>();
      final releaseStart = Completer<void>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'start') {
          startEntered.complete();
          await releaseStart.future;
        }
        return null;
      });
      final enabling = manager.setSeedingEnabled(true);
      await startEntered.future;
      final disabling = manager.setSeedingEnabled(false);
      await Future<void>.delayed(Duration.zero);
      expect(manager.seedingEnabled, isFalse);
      releaseStart.complete();
      await Future.wait([enabling, disabling]);
      expect(tasks[info.savePath]!.state, TaskState.stopped);
      expect(manager.isSeeding(info.hash), isFalse);
      expect(calls, ['start', 'stop']);
    },
  );

  test(
    'queued seeds yield to downloads and manual pause survives policy changes and playback',
    () async {
      final first = await add('first', completed: true);
      final second = await add('second', completed: true);
      expect(manager.isSeeding(first.hash), isTrue);
      expect(manager.isQueued(second.hash), isTrue);
      final download = await add('downloading');
      expect(commands.last, 'AnimeMaster 正在下载');
      expect(manager.isSeeding(first.hash), isFalse);
      expect(manager.isQueued(first.hash), isTrue);

      await manager.toggleTask(first.hash);
      expect(manager.isPaused(first.hash), isTrue);
      await manager.setSeedingEnabled(false);
      expect(manager.isQueued(second.hash), isFalse);
      expect(tasks[download.savePath]!.state, TaskState.running);
      await manager.toggleTask(download.hash);
      expect(commands.last, 'stop');
      await manager.setSeedingEnabled(true);
      expect(manager.isSeeding(second.hash), isTrue);
      expect(commands.last, 'AnimeMaster 正在分享');

      await manager.prepareForPlayback(first.hash);
      await manager.addTask(first, bytes, streamOptimized: true);
      expect(manager.isPaused(first.hash), isTrue);
      expect(manager.isSeeding(first.hash), isFalse);
      await manager.pauseAll();
      expect(commands.last, 'stop');
      expect(repository.rows[second.hash]!.isPaused, isTrue);
      await manager.toggleTask(first.hash);
      expect(manager.isSeeding(first.hash), isTrue);
      expect(commands.last, 'AnimeMaster 正在分享');
      await manager.setSeedingEnabled(false);
      expect(commands.last, 'stop');
      expect(tasks[first.savePath]!.state, TaskState.stopped);
    },
  );
}
