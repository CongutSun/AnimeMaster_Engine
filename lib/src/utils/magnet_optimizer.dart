import 'dart:core';

import 'tracker_pool.dart';

class MagnetOptimizer {
  static String optimize(String original) {
    String magnet = original.trim();

    if (!magnet.toLowerCase().startsWith('magnet:?')) {
      if (RegExp(r'^[a-zA-Z0-9]{32,40}$').hasMatch(magnet)) {
        magnet = 'magnet:?xt=urn:btih:$magnet';
      } else {
        return original;
      }
    }

    for (final String tracker in TrackerPool.robustTrackers) {
      final String encodedTracker = Uri.encodeComponent(tracker);
      if (!magnet.contains(encodedTracker) && !magnet.contains(tracker)) {
        magnet += '&tr=$encodedTracker';
      }
    }

    return magnet;
  }
}
