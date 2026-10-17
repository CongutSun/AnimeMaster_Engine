import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/playable_media.dart';

VideoControllerConfiguration videoPlaybackConfiguration(
  PlayableMedia media, {
  required TargetPlatform platform,
}) {
  if (media.bilibili != null && platform == TargetPlatform.android) {
    // Decode H.264 on the CPU while retaining the normal GPU video output.
    // Some Android MediaCodec paths render green or stalled DASH frames.
    return const VideoControllerConfiguration(hwdec: 'no');
  }
  return const VideoControllerConfiguration();
}
