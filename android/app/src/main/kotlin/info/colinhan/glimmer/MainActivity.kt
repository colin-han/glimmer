package info.colinhan.glimmer

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "info.colinhan.glimmer/audio_device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCurrentInputDevice" -> result.success(detectInputDevice())
                    else -> result.notImplemented()
                }
            }
    }

    /// 判断当前录音输入设备：蓝牙耳机 > 有线耳机 > 内置麦克风。
    /// 用 AudioManager.getDevices（API 23+），不需蓝牙权限；
    /// 设备名通过 AudioDeviceInfo.productName（系统提供，无权限）。
    private fun detectInputDevice(): Map<String, String> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val inputs = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)

        // 1. 蓝牙耳机（SCO 输入）
        val bluetooth = inputs.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        }
        if (bluetooth != null) {
            // AudioDeviceInfo 在 SDK stub 中暴露 getProductName()（返回 CharSequence），
            // 运行时其值即设备名（API 23+，系统提供，无需蓝牙权限）。
            val name = bluetooth.productName?.takeIf { it.isNotBlank() }?.toString()
            val label = if (name != null) "蓝牙耳机（$name）" else "蓝牙耳机"
            return mapOf("type" to "bluetooth", "label" to label)
        }

        // 2. 有线耳机
        val wired = inputs.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
        }
        if (wired != null) {
            return mapOf("type" to "wired", "label" to "有线耳机")
        }

        // 3. 内置麦克风
        return mapOf("type" to "builtin", "label" to "内置麦克风")
    }
}
