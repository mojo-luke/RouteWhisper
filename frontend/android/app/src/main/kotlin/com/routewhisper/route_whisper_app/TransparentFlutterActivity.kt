package com.routewhisper.route_whisper_app

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Transparent Flutter activity that overlays on top of native navigation.
 *
 * This activity provides a generic way to show Flutter UI on top of MapActivity
 * without closing the native navigation session. It's designed to be flexible:
 *
 * - Shares Flutter engine with MainActivity (same Dart isolate, state preserved)
 * - All UI logic lives in Flutter (easy to modify)
 * - Can show any Flutter screen via route parameter
 * - Transparent background lets MapActivity show through
 * - Data passing via Intent extras and result codes
 *
 * Usage:
 *   val intent = Intent(this, TransparentFlutterActivity::class.java)
 *   intent.putExtra("route", "/poi-discovery")  // Flutter route to show
 *   intent.putExtra("data", jsonData)           // Optional data to pass
 *   startActivity(intent)
 */
class TransparentFlutterActivity : FlutterActivity() {

    companion object {
        private const val TAG = "TransparentFlutterActivity"
        const val EXTRA_ROUTE = "route"
        const val EXTRA_DATA = "data"
    }

    // Use the cached Flutter engine from MainActivity
    override fun getCachedEngineId(): String {
        return MainActivity.SHARED_ENGINE_ID
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val route = intent.getStringExtra(EXTRA_ROUTE) ?: "/poi-discovery"
        val data = intent.getStringExtra(EXTRA_DATA)

        Log.d(TAG, "Created transparent overlay for route: $route")
        if (data != null) {
            Log.d(TAG, "Received data: $data")
        }

        // Give Flutter a moment to be ready, then send the overlay request
        Handler(Looper.getMainLooper()).postDelayed({
            sendOverlayRequest(route, data)
        }, 100)
    }

    private fun sendOverlayRequest(route: String, data: String?) {
        Log.d(TAG, "Notifying Flutter to show overlay: $route")

        // Use the static method channel from MainActivity (shared engine)
        MainActivity.methodChannelInstance?.invokeMethod(
            "showOverlay",
            mapOf(
                "route" to route,
                "data" to data
            ),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    Log.d(TAG, "✅ Overlay request sent successfully")
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e(TAG, "❌ Error sending overlay request: $errorMessage")
                }

                override fun notImplemented() {
                    Log.w(TAG, "⚠️ showOverlay not implemented in Flutter")
                }
            }
        )
    }

    override fun onBackPressed() {
        // Let Flutter handle back button (close overlay gracefully)
        Log.d(TAG, "Back pressed - closing overlay")
        super.onBackPressed()
    }
}
