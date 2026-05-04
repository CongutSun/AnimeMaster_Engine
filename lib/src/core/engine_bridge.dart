import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _InitializeEngineCoreC = Bool Function();
typedef _InitializeEngineCoreDart = bool Function();
typedef _GetEngineVersionC = Pointer<Utf8> Function();
typedef _GetEngineVersionDart = Pointer<Utf8> Function();
typedef _ParseMagnetLinkC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ParseMagnetLinkDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ScanLocalDirectoryC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ScanLocalDirectoryDart = Pointer<Utf8> Function(Pointer<Utf8>);

class EngineBridge {
  static final EngineBridge _instance = EngineBridge._internal();
  factory EngineBridge() => _instance;

  DynamicLibrary? _dylib;
  bool _didAttemptLoad = false;
  bool _isCoreReady = false;
  String _engineVersion = 'AnimeMaster Engine (Dart fallback)';
  String? _lastLoadError;

  String get engineVersion => _engineVersion;
  bool get isCoreReady => _isCoreReady;

  EngineBridge._internal();

  DynamicLibrary? _loadLibrary() {
    if (_didAttemptLoad) {
      return _dylib;
    }

    _didAttemptLoad = true;
    const String libName = 'animemaster';

    try {
      if (Platform.isAndroid || Platform.isLinux) {
        _dylib = DynamicLibrary.open('lib$libName.so');
      } else if (Platform.isWindows) {
        _dylib = DynamicLibrary.open('$libName.dll');
      } else {
        _dylib = DynamicLibrary.executable();
      }
    } catch (e) {
      _lastLoadError = e.toString();
      debugPrint('[EngineBridge] Dynamic library load failed: $e');
    }

    return _dylib;
  }

  void wakeUpEngine() {
    final DynamicLibrary? dylib = _loadLibrary();
    if (dylib == null) {
      _isCoreReady = false;
      _engineVersion = 'AnimeMaster Engine (Dart fallback)';
      return;
    }

    try {
      final initFunc = dylib
          .lookupFunction<_InitializeEngineCoreC, _InitializeEngineCoreDart>(
            'InitializeEngineCore',
          );
      final versionFunc = dylib
          .lookupFunction<_GetEngineVersionC, _GetEngineVersionDart>(
            'GetEngineVersion',
          );

      _isCoreReady = initFunc();
      _engineVersion = versionFunc().toDartString();
      debugPrint('[EngineBridge] $_engineVersion | Core Status: $_isCoreReady');
    } catch (e) {
      _isCoreReady = false;
      _engineVersion = 'AnimeMaster Engine (Dart fallback)';
      debugPrint('[EngineBridge] Wakeup error, fallback to Dart: $e');
    }
  }

  Map<String, dynamic> parseMagnet(String uri) {
    final DynamicLibrary? dylib = _loadLibrary();
    if (_isCoreReady && dylib != null) {
      try {
        final parseFunc = dylib
            .lookupFunction<_ParseMagnetLinkC, _ParseMagnetLinkDart>(
              'ParseMagnetLink',
            );
        return using((Arena arena) {
          final Pointer<Utf8> uriPtr = uri.toNativeUtf8(allocator: arena);
          final Pointer<Utf8> resultPtr = parseFunc(uriPtr);
          final String jsonStr = resultPtr.toDartString();
          final dynamic decoded = jsonDecode(jsonStr);
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
          return _parseMagnetFallback(uri);
        });
      } catch (e) {
        debugPrint('[EngineBridge] Native magnet parse failed: $e');
      }
    }

    return _parseMagnetFallback(uri);
  }

  Map<String, dynamic> scanLocalDirectory(String path) {
    final DynamicLibrary? dylib = _loadLibrary();
    if (_isCoreReady && dylib != null) {
      try {
        final scanFunc = dylib
            .lookupFunction<_ScanLocalDirectoryC, _ScanLocalDirectoryDart>(
              'ScanLocalDirectory',
            );
        return using((Arena arena) {
          final Pointer<Utf8> pathPtr = path.toNativeUtf8(allocator: arena);
          final Pointer<Utf8> resultPtr = scanFunc(pathPtr);
          final String jsonStr = resultPtr.toDartString();
          final dynamic decoded = jsonDecode(jsonStr);
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
          return _scanDirectoryFallback(path);
        });
      } catch (e) {
        debugPrint('[EngineBridge] Native directory scan failed: $e');
      }
    }

    return _scanDirectoryFallback(path);
  }

  Map<String, dynamic> _parseMagnetFallback(String uri) {
    final String normalized = uri.trim();
    final RegExp magnetRegex = RegExp(
      r'urn:btih:([a-zA-Z0-9]{32,40})',
      caseSensitive: false,
    );
    final RegExp rawHashRegex = RegExp(r'^[a-zA-Z0-9]{32,40}$');

    final Match? magnetMatch = magnetRegex.firstMatch(normalized);
    if (magnetMatch != null) {
      return {'success': true, 'infoHash': magnetMatch.group(1)!.toUpperCase()};
    }

    if (rawHashRegex.hasMatch(normalized)) {
      return {'success': true, 'infoHash': normalized.toUpperCase()};
    }

    return {
      'success': false,
      'infoHash': '',
      'error': _lastLoadError ?? 'Unable to parse magnet source.',
    };
  }

  Map<String, dynamic> _scanDirectoryFallback(String path) {
    final String normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return {
        'success': false,
        'path': '',
        'error': 'Empty scan path.',
        'entries': const [],
      };
    }

    final Directory directory = Directory(normalizedPath);
    if (!directory.existsSync()) {
      return {
        'success': false,
        'path': normalizedPath,
        'error': 'Directory does not exist.',
        'entries': const [],
      };
    }

    final List<Map<String, dynamic>> entries = <Map<String, dynamic>>[];
    const Set<String> videoExtensions = <String>{
      '.mp4',
      '.mkv',
      '.avi',
      '.flv',
      '.rmvb',
      '.ts',
      '.m2ts',
      '.wmv',
      '.webm',
      '.m4v',
    };

    for (final FileSystemEntity entity
        in directory.listSync(recursive: true, followLinks: false).take(500)) {
      final FileStat stat = entity.statSync();
      final bool isDirectory = stat.type == FileSystemEntityType.directory;
      final String name = entity.uri.pathSegments.isEmpty
          ? entity.path
          : entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
      final String lowerPath = entity.path.toLowerCase();

      entries.add({
        'name': name,
        'path': entity.path,
        'relativePath': entity.path.replaceFirst(
          '${directory.path}${Platform.pathSeparator}',
          '',
        ),
        'isDirectory': isDirectory,
        'isVideo':
            !isDirectory &&
            videoExtensions.any((extension) => lowerPath.endsWith(extension)),
        'size': isDirectory ? 0 : stat.size,
        'modifiedAtEpochMs': stat.modified.millisecondsSinceEpoch,
      });
    }

    return {
      'success': true,
      'path': normalizedPath,
      'entries': entries,
      'truncated': entries.length >= 500,
    };
  }
}
