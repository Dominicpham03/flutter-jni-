package com.example.hello_world_app

class Iperf3Bridge(private val progressHandler: Iperf3ProgressHandler?) {
    companion object {
        init {
            // Load the native library
            System.loadLibrary("iperf3_jni")
        }
    }

    // Store reference for native callbacks
    private var nativeHandle: Long = 0

    // Native method declarations - these will be implemented in C/C++ via JNI
    private external fun nativeRunClient(
        host: String,
        port: Int,
        duration: Int,
        parallel: Int,
        reverse: Boolean,
        useUdp: Boolean,
        bandwidth: Long
    ): Map<String, Any>

    private external fun nativeCancelClient()
    private external fun nativeStartServer(port: Int, useUdp: Boolean): Boolean
    private external fun nativeStopServer(): Boolean
    private external fun nativeGetVersion(): String

    // Kotlin wrapper methods
    fun runClient(
        host: String,
        port: Int,
        duration: Int,
        parallel: Int,
        reverse: Boolean,
        useUdp: Boolean = false,
        bandwidthBps: Long = 0  // Bandwidth in bits/sec (0 = use iperf3 default)
    ): Map<String, Any> {
        return nativeRunClient(host, port, duration, parallel, reverse, useUdp, bandwidthBps)
    }

    fun cancelClient() {
        nativeCancelClient()
    }

    fun startServer(port: Int, useUdp: Boolean = false): Boolean {
        return nativeStartServer(port, useUdp)
    }

    fun stopServer(): Boolean {
        return nativeStopServer()
    }

    fun getVersion(): String {
        return nativeGetVersion()
    }

    // Called from JNI to send progress updates
    // RTT is for TCP, jitter is for UDP
    @Suppress("unused")
    fun onProgress(interval: Int, bytesTransferred: Long, bitsPerSecond: Double, jitter: Double, lostPackets: Int, rtt: Double) {
        val progressData = mutableMapOf<String, Any>(
            "interval" to interval,
            "bytesTransferred" to bytesTransferred,
            "bitsPerSecond" to bitsPerSecond,
            "mbps" to (bitsPerSecond / 1000000.0)
        )

        // Add protocol-specific metrics
        if (rtt > 0) {
            // TCP mode: include RTT
            progressData["rtt"] = rtt
        }
        if (jitter > 0) {
            // UDP mode: include jitter
            progressData["jitter"] = jitter
            progressData["lostPackets"] = lostPackets
        }

        progressHandler?.sendProgress(progressData)
    }
}
