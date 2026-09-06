package com.anxcye.anx_reader

import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private var fileOpenChannel: MethodChannel? = null
    private var isFlutterReady = false
    private val pendingFiles = mutableListOf<String>()
    private var lastProcessedIntentUri: String? = null

    override fun getInitialRoute(): String? {
        if (intent?.action == Intent.ACTION_VIEW || intent?.action == Intent.ACTION_SEND) {
            return "/"
        }
        return super.getInitialRoute()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Ensure the latest intent is stored so plugins relying on Activity#getIntent can read it.
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val openChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_OPEN_CHANNEL)
        fileOpenChannel = openChannel
        openChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    isFlutterReady = true
                    if (pendingFiles.isNotEmpty()) {
                        for (path in pendingFiles) {
                            openChannel.invokeMethod("onOpenFile", path)
                        }
                        pendingFiles.clear()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        handleIncomingIntent(intent)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INSTALL_INFO_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstallInfo" -> {
                    try {
                        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(
                                packageName,
                                PackageManager.PackageInfoFlags.of(0),
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, 0)
                        }
                        result.success(
                            hashMapOf(
                                "firstInstallTime" to packageInfo.firstInstallTime,
                                "lastUpdateTime" to packageInfo.lastUpdateTime,
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("PACKAGE_INFO_ERROR", e.message, null)
                    }
                }

                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("INVALID_PATH", "File path cannot be null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "APK file does not exist", null)
                            return@setMethodCallHandler
                        }
                        val uri: Uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            file
                        )
                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                        }
                        startActivity(installIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_VIEW && action != Intent.ACTION_SEND) return

        val uri: Uri? = if (action == Intent.ACTION_VIEW) {
            intent.data
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
        }

        if (uri == null) return
        val uriString = uri.toString()
        if (uriString == lastProcessedIntentUri) return
        lastProcessedIntentUri = uriString

        Thread {
            try {
                var fileName = "unknown"
                if (uri.scheme == "content") {
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (nameIndex != -1) {
                                fileName = cursor.getString(nameIndex) ?: "unknown"
                            }
                        }
                    }
                } else if (uri.scheme == "file") {
                    fileName = uri.lastPathSegment ?: "unknown"
                }

                if (!fileName.contains(".")) {
                    fileName = "$fileName.epub"
                }

                val incomingDir = File(cacheDir, "external_incoming/${System.currentTimeMillis()}").apply { mkdirs() }
                val targetFile = File(incomingDir, fileName)
                contentResolver.openInputStream(uri)?.use { input ->
                    targetFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }

                if (targetFile.exists() && targetFile.length() > 0) {
                    runOnUiThread {
                        deliverIncomingFile(targetFile.absolutePath)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("AnxReader", "Failed to resolve incoming file from URI: $uri", e)
            }
        }.start()
    }

    private fun deliverIncomingFile(filePath: String) {
        if (isFlutterReady && fileOpenChannel != null) {
            fileOpenChannel?.invokeMethod("onOpenFile", filePath)
        } else {
            pendingFiles.add(filePath)
        }
    }

    companion object {
        private const val FILE_OPEN_CHANNEL = "anx_reader/desktop_file_open"
        private const val INSTALL_INFO_CHANNEL =
            "io.github.gxwane.anx_reader_gx_preview/install_info"
    }
}
