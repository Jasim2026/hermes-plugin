package com.hermes.plugin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.FileObserver
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.io.File
import java.util.concurrent.Executors

class HermesService : Service() {

    companion object {
        const val CHANNEL_ID = "hermes_service"
        const val NOTIFICATION_ID = 1
        const val CONTROL_DIR = "/storage/emulated/0/hermes_plugin"
        const val CONTROL_FILE = "control.txt"
        const val RESPONSE_FILE = "response.txt"

        var instance: HermesService? = null
            private set
        var isRunning = false
            private set
    }

    private var fileObserver: FileObserver? = null
    private val commandExecutor = Executors.newSingleThreadExecutor()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        isRunning = true
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Monitoring control file"))
        ensureControlDir()
        startFileObserver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        instance = null
        stopFileObserver()
        commandExecutor.shutdownNow()
        super.onDestroy()
    }

    // ========================
    // NOTIFICATION
    // ========================

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Hermes Service",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Keeps Hermes plugin alive"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Hermes Plugin")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    // ========================
    // CONTROL DIRECTORY
    // ========================

    private fun ensureControlDir() {
        val dir = File(CONTROL_DIR)
        if (!dir.exists()) dir.mkdirs()
        writeResponse("IDLE")
    }

    private fun writeResponse(response: String) {
        try {
            File(CONTROL_DIR, RESPONSE_FILE).writeText(response)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ========================
    // FILE OBSERVER (inotify)
    // ========================

    private fun startFileObserver() {
        val mask = FileObserver.CLOSE_WRITE

        fileObserver = object : FileObserver(CONTROL_DIR, mask) {
            override fun onEvent(event: Int, path: String?) {
                if (path != CONTROL_FILE) return
                commandExecutor.submit { processCommandFile() }
            }
        }

        fileObserver?.startWatching()
    }

    private fun processCommandFile() {
        try {
            Thread.sleep(100)

            val cmdFile = File(CONTROL_DIR, CONTROL_FILE)
            if (!cmdFile.exists()) return

            val command = cmdFile.readText().trim()
            if (command.isEmpty()) return

            cmdFile.writeText("")

            handleCommand(command)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopFileObserver() {
        try { fileObserver?.stopWatching() } catch (_: Exception) {}
        fileObserver = null
    }

    // ========================
    // COMMAND HANDLER
    // ========================

    private fun handleCommand(command: String) {
        when (command.uppercase()) {
            "STATUS" -> writeResponse(if (isRunning) "RUNNING" else "STOPPED")
            "PING" -> writeResponse("PONG")
            else -> writeResponse("UNKNOWN:$command")
        }
    }
}
