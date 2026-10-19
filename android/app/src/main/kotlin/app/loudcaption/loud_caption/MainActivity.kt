package app.loudcaption.loud_caption

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Exposes two device checks Dart has no portable API for, kept as our own
/// tiny channel rather than a third-party plugin for either — network-type
/// detection and disk-space checking are both a few lines of stable, stock
/// Android API, and this project already hit real bugs in a third-party
/// plugin once this release cycle (see pubspec.yaml's llama_flutter_android
/// fork note).
class MainActivity : FlutterActivity() {
    private val deviceStatusChannel = "loud_caption/device_status"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deviceStatusChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isWifiConnected" -> result.success(isWifiConnected())
                "availableDiskSpaceBytes" -> result.success(availableDiskSpaceBytes())
                else -> result.notImplemented()
            }
        }
    }

    private fun isWifiConnected(): Boolean {
        val connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities =
            connectivityManager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    // Same partition lib/downloads/model_downloader.dart actually writes
    // downloads to (app-private internal storage).
    private fun availableDiskSpaceBytes(): Long = StatFs(filesDir.path).availableBytes
}
