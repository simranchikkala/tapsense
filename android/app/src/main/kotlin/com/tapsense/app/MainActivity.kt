package com.tapsense.app

// TapSense — android/app/src/main/kotlin/<your/package/path>/MainActivity.kt
//
// KEEP your existing first line (`package com.something.tapsense`) and replace
// everything below it with this file's content (from `import` down).
//
// Adds a small channel "tapsense/apps" used by the "Pay with…" chooser:
//   listLaunchableApps → [{package, label, icon (PNG bytes)}]
//   launchApp(package) → true/false
// Needs the <queries> LAUNCHER entry in AndroidManifest.xml (no
// QUERY_ALL_PACKAGES permission, which Google Play restricts).

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "tapsense/apps"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listLaunchableApps" -> {
                        // Loading icons takes a moment — do it off the UI thread.
                        Thread {
                            try {
                                val apps = listApps()
                                runOnUiThread { result.success(apps) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("LIST_FAILED", e.message, null) }
                            }
                        }.start()
                    }
                    "launchApp" -> {
                        val pkg = call.argument<String>("package")
                        val intent = pkg?.let { packageManager.getLaunchIntentForPackage(it) }
                        if (intent == null) {
                            result.success(false)
                        } else {
                            try {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun listApps(): List<Map<String, Any>> {
        val pm = packageManager
        val main = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val infos = if (Build.VERSION.SDK_INT >= 33) {
            pm.queryIntentActivities(main, PackageManager.ResolveInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(main, 0)
        }
        return infos
            .filter { it.activityInfo.packageName != packageName } // not TapSense itself
            .distinctBy { it.activityInfo.packageName }
            .map { ri ->
                mapOf(
                    "package" to ri.activityInfo.packageName,
                    "label" to ri.loadLabel(pm).toString(),
                    "icon" to drawableToPng(ri.loadIcon(pm))
                )
            }
            .sortedBy { (it["label"] as String).lowercase() }
    }

    private fun drawableToPng(d: Drawable, size: Int = 96): ByteArray {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(canvas)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }
}