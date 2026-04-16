class AppUpdateInfo {
  final String version;
  final int buildNumber;
  final String apkUrl;
  final Map<String, String> apkUrls;
  final String changeLog;
  final String publishedAt;
  final bool forceUpdate;

  const AppUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    this.apkUrls = const <String, String>{},
    required this.changeLog,
    required this.publishedAt,
    this.forceUpdate = false,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final dynamic notesValue = json['notes'] ?? json['changeLog'] ?? '';
    final String changeLog = notesValue is List
        ? notesValue
              .map((dynamic item) => item.toString().trim())
              .where((String item) => item.isNotEmpty)
              .join('\n')
        : notesValue.toString().trim();

    final Map<String, String> apkUrls = _parseApkUrls(
      json['apkUrls'] ?? json['downloads'],
    );

    return AppUpdateInfo(
      version: (json['version'] ?? '').toString().trim(),
      buildNumber:
          int.tryParse(
            (json['build'] ?? json['buildNumber'] ?? '0').toString(),
          ) ??
          0,
      apkUrl: (json['apkUrl'] ?? json['url'] ?? '').toString().trim(),
      apkUrls: apkUrls,
      changeLog: changeLog,
      publishedAt: (json['publishedAt'] ?? '').toString().trim(),
      forceUpdate: json['forceUpdate'] == true,
    );
  }

  static Map<String, String> _parseApkUrls(dynamic value) {
    if (value is! Map) {
      return const <String, String>{};
    }

    final Map<String, String> result = value.map(
      (dynamic key, dynamic url) => MapEntry<String, String>(
        key.toString().trim(),
        url.toString().trim(),
      ),
    );
    result.removeWhere((String key, String url) => key.isEmpty || url.isEmpty);
    return result;
  }
}
