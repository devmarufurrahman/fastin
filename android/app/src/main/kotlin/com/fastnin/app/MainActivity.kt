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

                // ✅ File open — FileProvider দিয়ে PDF viewer খোলা
                "openFile" -> {
                    val filePath = call.argument<String>("filePath")
                    val mimeType = call.argument<String>("mimeType") ?: "application/pdf"
                    if (filePath == null) {
                        result.error("INVALID_ARG", "filePath is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                            return@setMethodCallHandler
                        }

                        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            // Android 7+ এ FileProvider required
                            FileProvider.getUriForFile(
                                this,
                                "${packageName}.provider",
                                file
                            )
                        } else {
                            Uri.fromFile(file)
                        }

                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mimeType)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        }

                        // কোনো PDF viewer আছে কিনা চেক করো
                        val packageManager = packageManager
                        if (intent.resolveActivity(packageManager) != null) {
                            startActivity(intent)
                            result.success(true)
                        } else {
                            // PDF viewer নেই — chooser দেখাও
                            val chooser = Intent.createChooser(intent, "Open PDF with")
                            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(chooser)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
