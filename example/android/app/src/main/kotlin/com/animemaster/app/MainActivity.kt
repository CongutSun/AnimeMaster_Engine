package com.animemaster.app

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val pictureInPictureChannel = "com.animemaster.app/picture_in_picture"
    private val appUpdateChannel = "com.animemaster.app/app_update"
    private var autoEnterPictureInPicture = false
    private var pictureInPicturePlaybackActive = false

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        (application as DownloadApplication).getOrCreateEngine()

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onResume() {
        super.onResume()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
            !getPreferences(MODE_PRIVATE).getBoolean("notification_permission_requested", false)
        ) {
            getPreferences(MODE_PRIVATE).edit().putBoolean("notification_permission_requested", true).apply()
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 24019)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pictureInPictureChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> {
                        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    }
                    "setAutoEnter" -> {
                        autoEnterPictureInPicture = call.argument<Boolean>("enabled") == true
                        updatePictureInPictureParams()
                        result.success(null)
                    }
                    "setPlaybackActive" -> {
                        pictureInPicturePlaybackActive = call.argument<Boolean>("active") == true
                        updatePictureInPictureParams()
                        result.success(null)
                    }
                    "enter" -> {
                        result.success(enterPictureInPictureIfPossible())
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appUpdateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installUpdate" -> installVerifiedUpdate(
                        call.argument<String>("path"),
                        call.argument<Number>("expectedVersionCode")?.toLong(),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
    }

    override fun onUserLeaveHint() {
        if (shouldAutoEnterPictureInPicture()) {
            updatePictureInPictureParams()
            enterPictureInPictureIfPossible()
        }
        super.onUserLeaveHint()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pictureInPictureChannel).setMethodCallHandler(null)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appUpdateChannel).setMethodCallHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun enterPictureInPictureIfPossible(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || isInPictureInPictureMode) {
            return false
        }
        val params = buildPictureInPictureParams()
        updatePictureInPictureParams(params)
        return try {
            enterPictureInPictureMode(params)
        } catch (_: IllegalStateException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    private fun buildPictureInPictureParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(shouldAutoEnterPictureInPicture())
        }
        return builder.build()
    }

    private fun shouldAutoEnterPictureInPicture(): Boolean {
        return autoEnterPictureInPicture && pictureInPicturePlaybackActive
    }

    private fun updatePictureInPictureParams(params: PictureInPictureParams? = null) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        try {
            setPictureInPictureParams(params ?: buildPictureInPictureParams())
        } catch (_: IllegalStateException) {
        } catch (_: IllegalArgumentException) {
        }
    }

    private fun installVerifiedUpdate(
        rawPath: String?,
        expectedVersionCode: Long?,
        result: MethodChannel.Result,
    ) {
        try {
            val updateRoot = File(cacheDir, "updates").canonicalFile
            val apkFile = File(rawPath.orEmpty()).canonicalFile
            val isInsideUpdateRoot = apkFile.path.startsWith(updateRoot.path + File.separator)
            if (!isInsideUpdateRoot || !apkFile.isFile || apkFile.extension.lowercase() != "apk") {
                result.error("invalid_path", "安装包不在受信任的更新目录中。", null)
                return
            }

            val archiveInfo = packageInfoForArchive(apkFile.path)
            val currentInfo = currentPackageInfo()
            if (archiveInfo == null || archiveInfo.packageName != packageName) {
                result.error("invalid_package", "安装包的应用身份不匹配。", null)
                return
            }

            val archiveVersion = versionCodeOf(archiveInfo)
            val currentVersion = versionCodeOf(currentInfo)
            if (expectedVersionCode == null ||
                archiveVersion != expectedVersionCode ||
                archiveVersion <= currentVersion
            ) {
                result.error("invalid_version", "安装包版本号无效。", null)
                return
            }

            val archiveSigners = signerDigests(archiveInfo)
            val currentSigners = signerDigests(currentInfo)
            if (archiveSigners.isEmpty() || archiveSigners != currentSigners) {
                result.error("invalid_signer", "安装包签名与当前应用不一致。", null)
                return
            }

            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apkFile,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("install_failed", "无法启动系统安装器。", error.message)
        }
    }

    @Suppress("DEPRECATION")
    private fun packageInfoForArchive(path: String): PackageInfo? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(
                path,
                PackageManager.PackageInfoFlags.of(
                    PackageManager.GET_SIGNING_CERTIFICATES.toLong(),
                ),
            )
        } else {
            packageManager.getPackageArchiveInfo(path, PackageManager.GET_SIGNING_CERTIFICATES)
        }

    @Suppress("DEPRECATION")
    private fun currentPackageInfo(): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(
                    PackageManager.GET_SIGNING_CERTIFICATES.toLong(),
                ),
            )
        } else {
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        }

    @Suppress("DEPRECATION")
    private fun versionCodeOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }

    @Suppress("DEPRECATION")
    private fun signerDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners?.toList().orEmpty()
        } else {
            info.signatures?.toList().orEmpty()
        }
        return signatures.map { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
        }.toSet()
    }
}
