package com.example.hello_world_app

import io.flutter.plugin.common.EventChannel
import android.os.Handler
import android.os.Looper

class Iperf3ProgressHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // Called from native code or bridge to send progress updates
    fun sendProgress(progressData: Map<String, Any>) {
        handler.post {
            eventSink?.success(progressData)
        }
    }

    // Send error
    fun sendError(errorCode: String, errorMessage: String, errorDetails: Any?) {
        handler.post {
            eventSink?.error(errorCode, errorMessage, errorDetails)
        }
    }

    // Send status updates (used for cancel button enable/disable)
    fun sendStatus(status: String, details: Any? = null) {
        handler.post {
            eventSink?.success(mapOf("status" to status, "details" to details))
        }
    }

    // Send completion
    fun sendEndOfStream() {
        handler.post {
            eventSink?.endOfStream()
        }
    }
}
