class AppUpdateInfo {
  final String version;
  final int buildNumber;
  final String apkUrl;
  final String changeLog;
  final String publishedAt;
  final bool forceUpdate;

  const AppUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
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

    return AppUpdateInfo(
      version: (json['version'] ?? '').toString().trim(),
      buildNumber:
          int.tryParse(
            (json['build'] ?? json['buildNumber'] ?? '0').toString(),
          ) ??
          0,
      apkUrl: (json['apkUrl'] ?? json['url'] ?? '').toString().trim(),
      changeLog: changeLog,
      publishedAt: (json['publishedAt'] ?? '').toString().trim(),
      forceUpdate: json['forceUpdate'] == true,
    );
  }
}
