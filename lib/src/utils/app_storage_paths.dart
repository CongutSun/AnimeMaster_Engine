import 'dart:io';

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
    final root = await _engineRoot;
    final taskDir = Directory('${root.path}${Platform.pathSeparator}$infoHash');

    if (!await taskDir.exists()) {
      await taskDir.create(recursive: true);
    }

    return taskDir;
  }
}
