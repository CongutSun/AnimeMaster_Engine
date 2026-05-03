/// Shared formatting utilities for duration, date/time, and display.
library;

/// Formats a [Duration] to "M:SS" or "H:MM:SS".
String formatDuration(Duration value) {
  final int totalSeconds = value.inSeconds;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final int hours = totalSeconds ~/ 3600;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Formats a [DateTime] to "YYYY-MM-DD HH:MM" in local time.
String formatLocalDateTime(DateTime value) {
  final DateTime local = value.toLocal();
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
