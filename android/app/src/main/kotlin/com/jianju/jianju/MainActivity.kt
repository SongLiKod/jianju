package com.jianju.jianju

import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.res.Configuration
import android.net.Uri
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private var pipChannel: MethodChannel? = null
    private var updaterChannel: MethodChannel? = null

    /** Flutter 侧告知“正在播放”（决定 Home 键是否自动进小窗） */
    private var pipEligible = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "jianju/pip"
        )
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    val ok = enterPipInternal()
                    result.success(ok)
                }
                "setActive" -> {
                    pipEligible = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        configureUpdater(flutterEngine)
        handleInstallStatus(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleInstallStatus(intent)
    }

    /**
     * 系统安装回执（PackageInstaller 异步回调，状态经 PendingIntent 回到本 Activity）：
     * - STATUS_PENDING_USER_ACTION：浮起系统确认框（不启动它则安装卡住无任何提示）
     * - 其余状态：转给 Dart 弹窗展示，失败不再停在「正在安装」或只报含糊错误码
     */
    private fun handleInstallStatus(intent: Intent?) {
        if (intent?.action != "$packageName.INSTALL_STATUS") return
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            if (confirm == null) {
                sendInstallStatus(PackageInstaller.STATUS_FAILURE, "缺少系统确认页")
            } else {
                try {
                    startActivity(confirm)
                } catch (e: Exception) {
                    sendInstallStatus(PackageInstaller.STATUS_FAILURE, e.message)
                }
            }
            return
        }
        sendInstallStatus(status, intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE))
    }

    private fun sendInstallStatus(status: Int, message: String?) {
        runOnUiThread {
            updaterChannel?.invokeMethod(
                "installStatus",
                mapOf("status" to status, "message" to (message ?: ""))
            )
        }
    }

    /** 应用内检查更新：授权查询 / 打开安装授权页 / 提交安装会话 */
    private fun configureUpdater(flutterEngine: FlutterEngine) {
        updaterChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "jianju/updater"
        )
        updaterChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(packageManager.canRequestPackageInstalls())
                "openInstallSettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName")
                        )
                    )
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.arguments as? String
                    if (path.isNullOrBlank()) {
                        result.error("args", "缺少 APK 路径", null)
                        return@setMethodCallHandler
                    }
                    try {
                        installApkInternal(path)
                        result.success(null)
                    } catch (e: SecurityException) {
                        result.error("blocked", e.message, null)
                    } catch (e: Exception) {
                        result.error("install", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 交系统 PackageInstaller 安装：APK 写入安装会话后 commit，确认框浮在
     * 本应用之上（不离开软件）；会话按 sessionId 区分，重复提交互不冲突。
     */
    private fun installApkInternal(path: String) {
        val apk = File(path)
        if (!apk.isFile || apk.length() < 1024) {
            throw IllegalArgumentException("APK 文件无效")
        }
        val installer = getSystemService(PackageInstaller::class.java)
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        ).apply { setAppPackageName(packageName) }

        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            session.openWrite("base.apk", 0, apk.length()).use { out ->
                FileInputStream(apk).use { input -> input.copyTo(out) }
                session.fsync(out)
            }
            val intent = Intent(this, MainActivity::class.java).apply {
                action = "$packageName.INSTALL_STATUS"
                putExtra(PackageInstaller.EXTRA_SESSION_ID, sessionId)
            }
            val pending = PendingIntent.getActivity(
                this,
                sessionId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            session.commit(pending.intentSender)
        }
    }

    private fun enterPipInternal(): Boolean {
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .build()
        return try {
            enterPictureInPictureMode(params)
        } catch (e: Exception) {
            false
        }
    }

    /** 播放中按 Home/切后台：直接进画中画小窗，视频不中断 */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipEligible) {
            enterPipInternal()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPipMode: Boolean,
        newConfiguration: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPipMode, newConfiguration)
        pipChannel?.invokeMethod("onPipChanged", isInPipMode)
    }
}
