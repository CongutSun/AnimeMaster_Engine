import 'package:flutter/services.dart';

class PictureInPictureService {
  static const MethodChannel _channel = MethodChannel(
    'com.animemaster.app/picture_in_picture',
  );

  const PictureInPictureService._();

  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> enter() async {
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> setAutoEnter(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setAutoEnter', <String, bool>{
        'enabled': enabled,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
