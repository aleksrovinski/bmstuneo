package ru.bmstu.neo

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest

/** Installs an APK downloaded by AppUpdater (lib/services/app_update.dart). */
class AppUpdateFileProvider : FileProvider()

object AppUpdateInstaller {
    fun downloadPath(activity: Activity): String {
        val dir = File(activity.cacheDir, "updates").apply { mkdirs() }
        return File(dir, "update.apk").absolutePath
    }

    /** "started", "needsPermission", "corrupted" or "failed". */
    fun install(activity: Activity, path: String, sha256: String): String {
        val file = File(path)
        // Only files we downloaded ourselves, and only if the website's checksum matches
        if (file.parentFile?.canonicalPath != File(activity.cacheDir, "updates").canonicalPath) return "failed"
        if (!file.exists() || !sha256(file).equals(sha256, ignoreCase = true)) {
            file.delete()
            return "corrupted"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
            )
            return "needsPermission"
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return try {
            activity.startActivity(intent)
            "started"
        } catch (e: Exception) {
            "failed"
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
