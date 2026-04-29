package com.animemaster.app

import android.app.PictureInPictureParams
import android.content.Intent
import android.os.Build
import android.util.Rational
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val backgroundChannel = "com.animemaster.app/background_download"
    private val pictureInPictureChannel = "com.animemaster.app/picture_in_picture"
    private var autoEnterPictureInPicture = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backgroundChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startBackgroundDownloadService()
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, BackgroundDownloadService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pictureInPictureChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> {
                        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    }
                    "setAutoEnter" -> {
                        autoEnterPictureInPicture = call.argument<Boolean>("enabled") == true
                        result.success(null)
                    }
                    "enter" -> {
                        result.success(enterPictureInPictureIfPossible())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoEnterPictureInPicture) {
            enterPictureInPictureIfPossible()
        }
    }

    private fun startBackgroundDownloadService() {
        val intent = Intent(this, BackgroundDownloadService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun enterPictureInPictureIfPossible(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || isInPictureInPictureMode) {
            return false
        }
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnterPictureInPicture)
        }
        return try {
            enterPictureInPictureMode(builder.build())
        } catch (_: IllegalStateException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }
}
