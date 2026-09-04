import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';

class AppStoragePaths {
  static Future<Directory> get _engineRoot async {
    final baseDir = await getApplicationSupportDirectory();
    final engineDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}AnimeMaster',
    );

    if (!await engineDir.exists()) {
      await engineDir.create(recursive: true);
    }

    return engineDir;
  }

  static Future<Directory> torrentTaskDirectory(String infoHash) async {
    if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(infoHash)) {
      throw const FormatException('Invalid BitTorrent info hash.');
    }
    final root = await _engineRoot;
    final taskDir = Directory('${root.path}${Platform.pathSeparator}$infoHash');

    if (!await taskDir.exists()) {
      await taskDir.create(recursive: true);
    }

    return taskDir;
  }

  static Future<bool> isManagedTaskDirectory(String path) async {
    final String trimmed = path.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    try {
      final Directory root = await _engineRoot;
      final Directory candidate = Directory(trimmed);
      final String rootPath = path_util.canonicalize(root.absolute.path);
      final String candidatePath = path_util.canonicalize(
        candidate.absolute.path,
      );
      if (!debugIsPathWithinRoot(rootPath, candidatePath)) {
        return false;
      }

      if (!await candidate.exists()) {
        return true;
      }

      final String resolvedRoot = path_util.canonicalize(
        await root.resolveSymbolicLinks(),
      );
      final String resolvedCandidate = path_util.canonicalize(
        await candidate.resolveSymbolicLinks(),
      );
      return debugIsPathWithinRoot(resolvedRoot, resolvedCandidate);
    } on FileSystemException {
      return false;
    }
  }

  @visibleForTesting
  static bool debugIsPathWithinRoot(String root, String candidate) {
    final String normalizedRoot = path_util.canonicalize(
      Directory(root).absolute.path,
    );
    final String normalizedCandidate = path_util.canonicalize(
      Directory(candidate).absolute.path,
    );
    return path_util.isWithin(normalizedRoot, normalizedCandidate);
  }
}
