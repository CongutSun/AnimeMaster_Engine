import 'dart:io';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:path/path.dart' as p;

import '../models/cache_episode_file.dart';
import '../models/download_task_info.dart';

class CacheEpisodeIndex {
  static List<CacheEpisodeFile> torrent(
    Torrent torrent,
    String base,
    String subject,
    List<Map<String, dynamic>> catalog, {
    String releaseTitle = '',
  }) {
    final files = <CacheEpisodeFile>[];
    for (final item in torrent.files) {
      final relative = item.path.replaceAll('\\', '/');
      if (!CacheEpisodeFile.isVideo(relative)) continue;
      final path = p.normalize(p.join(base, relative));
      if (!p.isWithin(base, path)) throw const FormatException('种子中的文件路径无效');
      files.add(
        CacheEpisodeFile.identify(
          path,
          item.length,
          p.posix.basename(relative),
          parent: p.posix.dirname(relative),
          subject: subject,
          catalog: catalog,
        ),
      );
    }
    if (files.length == 1 && files.single.label.startsWith('待确认 · ')) {
      final old = files.single;
      for (final title in [torrent.name, releaseTitle]) {
        final named = CacheEpisodeFile.identify(
          old.path,
          old.size,
          title,
          subject: subject,
          catalog: catalog,
        );
        if (named.number > 0) {
          files[0] = named;
          break;
        }
      }
    }
    files.sort(
      (a, b) => a.number == b.number
          ? a.path.compareTo(b.path)
          : (a.number == 0
                ? 1
                : b.number == 0
                ? -1
                : a.number.compareTo(b.number)),
    );
    return files;
  }

  static DownloadTaskInfo attach(
    DownloadTaskInfo task,
    List<CacheEpisodeFile> files,
  ) {
    final selected =
        files.where((f) => p.equals(f.path, task.targetPath)).firstOrNull ??
        files.firstOrNull;
    final indexed = task.copyWith(files: files);
    return selected == null ? indexed : indexed.forFile(selected);
  }

  static Future<List<CacheEpisodeFile>> localFiles(
    DownloadTaskInfo task,
    List<Map<String, dynamic>> catalog,
  ) async {
    final selected = legacyFile(task, catalog);
    final files = [if (selected.path.isNotEmpty) selected];
    final dir = Directory(task.savePath);
    if (task.isBilibili ||
        !task.isCompleted ||
        !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(task.hash) ||
        p.basename(dir.path).toUpperCase() != task.hash.toUpperCase() ||
        !await dir.exists()) {
      return files;
    }
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File &&
            CacheEpisodeFile.isVideo(entity.path) &&
            !p.equals(entity.path, selected.path)) {
          final stat = await entity.stat();
          if (stat.size > 0) {
            files.add(
              CacheEpisodeFile.identify(
                entity.path,
                stat.size,
                p.basename(entity.path),
                subject: task.subjectTitle,
                parent: p.dirname(p.relative(entity.path, from: dir.path)),
                catalog: catalog,
              ),
            );
          }
        }
      }
    } on FileSystemException {
      return files;
    }
    return files;
  }

  static CacheEpisodeFile legacyFile(
    DownloadTaskInfo task,
    List<Map<String, dynamic>> catalog,
  ) {
    final marker = RegExp(r' · P\d+ · ').firstMatch(task.title);
    final name = task.isBilibili
        ? (marker == null ? task.title : task.title.substring(marker.end))
        : p.basename(task.targetPath.replaceAll('\\', '/'));
    return CacheEpisodeFile.identify(
      task.targetPath,
      task.targetSize,
      name,
      subject: task.subjectTitle,
      parent: marker == null ? '' : task.title.substring(0, marker.start),
      catalog: catalog,
    );
  }
}
