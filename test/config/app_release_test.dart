import 'dart:convert';
import 'dart:io';

import 'package:animemaster/src/config/app_release.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application, engine and update feed use the same release identity', () {
    const String version = AppRelease.version;
    expect(
      File('pubspec.yaml').readAsStringSync().replaceAll('\r\n', '\n'),
      contains('version: $version\n'),
    );
    expect(
      File('example/pubspec.yaml').readAsStringSync(),
      contains('version: $version+${AppRelease.build}'),
    );
    expect(
      File('src/CMakeLists.txt').readAsStringSync(),
      contains('VERSION $version LANGUAGES'),
    );
    expect(
      File('src/animemaster.cpp').readAsStringSync(),
      contains('AnimeMaster Engine v$version (Native parser/scanner)'),
    );
    expect(
      File('android/build.gradle').readAsStringSync(),
      contains('version = "$version"'),
    );
    expect(
      File('ios/animemaster.podspec').readAsStringSync(),
      contains("s.version          = '$version'"),
    );
    final manifest =
        jsonDecode(File('release/app_update.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(manifest['version'], version);
    expect(manifest['build'], AppRelease.build);
    expect(manifest['notes'], AppRelease.notes);
    final urls = manifest['apkUrls'] as Map<String, dynamic>;
    expect(
      urls.keys,
      containsAll(<String>[
        'android-arm64',
        'android-arm',
        'android-x64',
        'universal',
      ]),
    );
    for (final url in urls.values) {
      expect(
        url,
        startsWith(
          'https://github.com/CongutSun/AnimeMaster_Engine/releases/download/v$version/',
        ),
      );
      expect(url, endsWith('-release.apk'));
    }
    expect(File('CHANGELOG.md').readAsStringSync(), startsWith('## $version'));
  });
}
