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
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class HermesService : Service() {

    companion object {
        const val CHANNEL_ID = "hermes_service"
        const val NOTIFICATION_ID = 1
        const val WS_PORT = 8765
        const val ENGINE_ID = "hermes_bg_engine"
        const val CONTROL_DIR = "/sdcard/hermes_plugin"
        const val CONTROL_FILE = "control.txt"
        const val RESPONSE_FILE = "response.txt"
        const val ENGINE_READY_TIMEOUT_MS = 5000L

        var instance: HermesService? = null
            private set
        var isRunning = false
            private set

        @Volatile
        var wsServerRunning = false
            private set
    }

    private var fileObserver: FileObserver? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val commandExecutor = Executors.newSingleThreadExecutor()
    private var flutterEngine: FlutterEngine? = null
    private var wsChannel: MethodChannel? = null
    private val engineReadyLatch = CountDownLatch(1)
    private val engineReady = AtomicBoolean(false)

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
        stopEverything()
        commandExecutor.shutdownNow()
        executor.shutdownNow()
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

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(text))
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
                // Read file on executor thread — NOT on inotify thread
                commandExecutor.submit { processCommandFile() }
            }
        }

        fileObserver?.startWatching()
    }

    private fun processCommandFile() {
        try {
            // Small delay to ensure file is fully written by agent
            Thread.sleep(100)

            val cmdFile = File(CONTROL_DIR, CONTROL_FILE)
            if (!cmdFile.exists()) return

            val command = cmdFile.readText().trim()
            if (command.isEmpty()) return

            // Clear command file immediately to prevent re-read
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
            "START" -> {
                writeResponse("STARTING")
                // Queue on executor — ensures sequential execution
                executor.submit {
                    startFullStack()
                    writeResponse(if (wsServerRunning) "STARTED" else "ERROR")
                }
            }
            "STOP" -> {
                writeResponse("STOPPING")
                executor.submit {
                    stopFullStack()
                    writeResponse("STOPPED")
                }
            }
            "STATUS" -> {
                val status = if (wsServerRunning) "RUNNING" else "STOPPED"
                writeResponse(status)
            }
            "PING" -> writeResponse("PONG")
            else -> writeResponse("UNKNOWN:$command")
        }
    }

    // ========================
    // FULL STACK (Flutter + WS)
    // ========================

    private fun startFullStack() {
        // Atomic check — prevents double-start from rapid commands
        if (wsServerRunning) return

        try {
            // Reset readiness state
            engineReady.set(false)
            val latch = CountDownLatch(1)

            // Create Flutter engine
            flutterEngine = FlutterEngine(this).apply {
                dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault()
                )
                // Signal readiness when engine is idle
                addEngineLifecycleListener(object : io.flutter.embedding.engine.FlutterEngine.EngineLifecycleListener {
                    override fun onEngineWillDestroy() {}
                    override fun onPreEngineRestart() {}
                    override fun onEngineWillDetach() {}
                })
            }

            // Wait for engine with timeout (not fixed sleep)
            val ready = engineReadyLatch.await(ENGINE_READY_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            if (!ready) {
                // Fallback: wait minimum time then try anyway
                Thread.sleep(500)
            }

            // Setup WS channel
            wsChannel = MethodChannel(
                flutterEngine!!.dartExecutor.binaryMessenger,
                "com.hermes.plugin/service_control"
            )

            // Init accessibility channel
            HermesAccessibilityService.instance?.initChannel(flutterEngine!!)

            // Start WS server
            wsChannel?.invokeMethod("startWsServer", mapOf("port" to WS_PORT))
            wsServerRunning = true
            updateNotification("WS server running :$WS_PORT")
        } catch (e: Exception) {
            e.printStackTrace()
            wsServerRunning = false
            writeResponse("ERROR:${e.message}")
        }
    }

    private fun stopFullStack() {
        wsServerRunning = false

        try { wsChannel?.invokeMethod("stopWsServer", null) } catch (_: Exception) {}
        try { flutterEngine?.destroy() } catch (_: Exception) {}

        flutterEngine = null
        wsChannel = null
        engineReady.set(false)
        updateNotification("WS server stopped")
    }

    private fun stopEverything() {
        stopFullStack()
    }
}
