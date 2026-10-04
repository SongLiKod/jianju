package com.jianju.jianju

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pipChannel: MethodChannel? = null

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
