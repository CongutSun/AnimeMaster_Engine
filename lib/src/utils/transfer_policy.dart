/// Bounded discovery batches cover every tracker, including torrent-specific ones.
class TrackerRotation {
  int _cursor = 0;

  List<Uri> next(Iterable<Uri> trackers, int limit) {
    final List<Uri> candidates = trackers
        .where(
          (Uri uri) =>
              const <String>{'http', 'https', 'udp'}.contains(uri.scheme) &&
              uri.host.isNotEmpty,
        )
        .toSet()
        .toList();
    if (candidates.isEmpty || limit <= 0) return <Uri>[];
    final int count = limit.clamp(0, candidates.length);
    final List<Uri> batch = <Uri>[
      for (int i = 0; i < count; i++)
        candidates[(_cursor + i) % candidates.length],
    ];
    _cursor = (_cursor + count) % candidates.length;
    return batch;
  }
}

class TransferPolicy {
  static const int maxActiveDownloads = 3;
  static const int peerCap = 48;
  static const int playbackPeerCap = 50;
  static const Duration peerGracePeriod = Duration(seconds: 90);

  static bool canTrimPeer({
    required Duration age,
    required double downloadSpeed,
    required bool hasPendingRequests,
    required bool seeding,
  }) =>
      age >= peerGracePeriod &&
      !hasPendingRequests &&
      (seeding || downloadSpeed <= 0);
}
