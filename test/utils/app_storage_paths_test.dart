import 'dart:io';

import 'package:animemaster/src/utils/app_storage_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_util;

void main() {
  group('download storage boundary', () {
    final String root = path_util.join(
      Directory.systemTemp.path,
      'animemaster-storage-test',
    );

    test('accepts a child task directory', () {
      expect(
        AppStoragePaths.debugIsPathWithinRoot(
          root,
          path_util.join(root, '0123456789abcdef0123456789abcdef01234567'),
        ),
        isTrue,
      );
    });

    test('rejects the root itself, siblings, and traversal', () {
      expect(AppStoragePaths.debugIsPathWithinRoot(root, root), isFalse);
      expect(
        AppStoragePaths.debugIsPathWithinRoot('${root}_other', root),
        isFalse,
      );
      expect(
        AppStoragePaths.debugIsPathWithinRoot(
          root,
          path_util.join(root, '..', 'outside'),
        ),
        isFalse,
      );
    });
  });

  test('rejects malformed BitTorrent info hashes before touching storage', () {
    expect(
      () => AppStoragePaths.torrentTaskDirectory('../outside'),
      throwsA(isA<FormatException>()),
    );
  });
}
