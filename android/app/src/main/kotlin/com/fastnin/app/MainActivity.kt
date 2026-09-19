package com.fastnin.app

import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.fastnin.app/media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                // ✅ MediaStore scan — Files app এ file দেখানোর জন্য
                "scanFile" -> {
                    val filePath = call.argument<String>("filePath")
                    val mimeType = call.argument<String>("mimeType")
                    if (filePath != null) {
                        MediaScannerConnection.scanFile(
                            this,
                            arrayOf(filePath),
                            if (mimeType != null) arrayOf(mimeType) else null
                        ) { _, uri ->
                            result.success(uri?.toString() ?: "scanned")
                        }
                    } else {
                        result.error("INVALID_ARG", "filePath is required", null)
                    }
                }

// Removed openFile custom intent handler in favor of open_filex package

                else -> result.notImplemented()
            }
        }
    }
}
