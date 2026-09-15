package com.animemaster.app

import android.app.Application
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** One engine owns both the download database and the UI across Activity lifetimes. */
class DownloadApplication : Application() {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null

    @Synchronized
    fun getOrCreateEngine(): FlutterEngine {
        engine?.let { return it }
        val created = FlutterEngine(this)
        engine = created
        channel = MethodChannel(created.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            val intent = Intent(this@DownloadApplication, BackgroundDownloadService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(null)
                        }
                        "stop" -> {
                            stopService(Intent(this@DownloadApplication, BackgroundDownloadService::class.java))
                            result.success(null)
                        }
                        "openSettings" -> {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            })
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("background_service_failed", error.message, null)
                }
            }
        }
        created.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return created
    }

    fun pauseDownloads() {
        channel?.invokeMethod("pauseAll", null)
    }

    companion object {
        const val CHANNEL = "com.animemaster.app/background_download"
    }
}
