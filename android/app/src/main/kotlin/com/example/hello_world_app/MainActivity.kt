package com.example.hello_world_app

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.RouteInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.*
import java.net.InetAddress
import java.nio.ByteBuffer
import java.nio.ByteOrder

data class DestinationGatewayInfo(
    val success: Boolean,
    val gatewayAddress: String?,
    val networkType: String?,
    val interfaceName: String?,
    val destinationIp: String?,
    val allRoutes: List<RouteDetail>?,
    val error: String?
)

data class RouteDetail(
    val destination: String,
    val gateway: String,
    val isDefault: Boolean
)

class MainActivity : FlutterActivity() {
    private val TAG = "MainActivity"
    private val CHANNEL = "com.example.hello_world_app/iperf3"
    private val PROGRESS_CHANNEL = "com.example.hello_world_app/iperf3_progress"
    private var iperf3Bridge: Iperf3Bridge? = null
    private var progressHandler: Iperf3ProgressHandler? = null
    private var currentClientJob: Job? = null

    // Coroutine scope for background operations
    private val ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        progressHandler = Iperf3ProgressHandler()
        iperf3Bridge = Iperf3Bridge(progressHandler)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "runClient" -> {
                    val host = call.argument<String>("host") ?: ""
                    val port = call.argument<Int>("port") ?: 5201
                    val duration = call.argument<Int>("duration") ?: 10
                    val parallel = call.argument<Int>("parallel") ?: 1
                    val reverse = call.argument<Boolean>("reverse") ?: false
                    val useUdp = call.argument<Boolean>("useUdp") ?: false
                    // Handle both Int and Long for bandwidthBps (Dart may send either type)
                    val bandwidthBps = when (val bw = call.argument<Any>("bandwidthBps")) {
                        is Int -> bw.toLong()
                        is Long -> bw
                        else -> 0L
                    }

                    Log.i(TAG, "=== iperf3 runClient called from Flutter ===")
                    Log.i(TAG, "Parameters: host=$host, port=$port, duration=$duration, parallel=$parallel")
                    Log.i(TAG, "Protocol: ${if (useUdp) "UDP" else "TCP"}, reverse=$reverse, bandwidth=$bandwidthBps bps")

                    val hadExistingJob = currentClientJob?.isActive == true
                    if (hadExistingJob) {
                        Log.i(TAG, "Cancelling in-flight iperf3 client before starting a new one")
                        iperf3Bridge?.cancelClient()
                        currentClientJob?.cancel()
                    }

                    progressHandler?.sendStatus("starting")

                    // Run iperf3 test on background thread (IO dispatcher)
                    currentClientJob = ioScope.launch {
                        try {
                            progressHandler?.sendStatus("running")
                            Log.d(TAG, "Launching coroutine on IO dispatcher...")
                            val testResult = iperf3Bridge?.runClient(
                                host, port, duration, parallel, reverse, useUdp, bandwidthBps
                            )
                            Log.i(TAG, "iperf3 client test completed")
                            val success = (testResult?.get("success") as? Boolean) == true
                            val errorMessage = testResult?.get("error") as? String
                            val errorCode = (testResult?.get("errorCode") as? Number)?.toInt()

                            // Send result back on main thread
                            withContext(Dispatchers.Main) {
                                Log.d(TAG, "Sending result back to Flutter")
                                result.success(testResult)
                            }
                            if (success) {
                                progressHandler?.sendStatus("completed")
                            } else {
                                progressHandler?.sendStatus(
                                    "error",
                                    mapOf(
                                        "message" to (errorMessage ?: "iperf3 test failed"),
                                        "code" to errorCode
                                    )
                                )
                            }
                        } catch (e: CancellationException) {
                            Log.i(TAG, "iperf3 client cancelled")
                            iperf3Bridge?.cancelClient()
                            withContext(Dispatchers.Main + NonCancellable) {
                                result.error("IPERF3_CANCELLED", "Client test cancelled", null)
                            }
                            progressHandler?.sendStatus("cancelled")
                        } catch (e: Exception) {
                            Log.e(TAG, "Exception in iperf3 client test: ${e.message}", e)
                            withContext(Dispatchers.Main + NonCancellable) {
                                result.error("IPERF3_ERROR", "Failed to run client: ${e.message}", null)
                            }
                            progressHandler?.sendStatus(
                                "error",
                                mapOf(
                                    "message" to (e.message ?: "Unknown error"),
                                    "code" to null
                                )
                            )
                        } finally {
                            currentClientJob = null
                            progressHandler?.sendStatus("idle")
                        }
                    }
                }

                "cancelClient" -> {
                    Log.i(TAG, "Cancel request received from Flutter")
                    val hadActiveJob = currentClientJob?.isActive == true
                    iperf3Bridge?.cancelClient()
                    currentClientJob?.cancel()
                    result.success(hadActiveJob)
                }

                "getDefaultGateway" -> {
                    val gateway = getCurrentWifiGateway()
                    result.success(gateway ?: "")
                }

                "getGatewayForDestination" -> {
                    val hostname = call.argument<String>("hostname") ?: ""
                    val gatewayInfo = getGatewayForDestination(hostname)
                    result.success(mapOf(
                        "success" to gatewayInfo.success,
                        "gatewayAddress" to gatewayInfo.gatewayAddress,
                        "networkType" to gatewayInfo.networkType,
                        "interfaceName" to gatewayInfo.interfaceName,
                        "destinationIp" to gatewayInfo.destinationIp,
                        "allRoutes" to gatewayInfo.allRoutes?.map { route ->
                            mapOf(
                                "destination" to route.destination,
                                "gateway" to route.gateway,
                                "isDefault" to route.isDefault
                            )
                        },
                        "error" to gatewayInfo.error
                    ))
                }

                "startServer" -> {
                    val port = call.argument<Int>("port") ?: 5201
                    val useUdp = call.argument<Boolean>("useUdp") ?: false

                    // Run server start on background thread
                    ioScope.launch {
                        try {
                            val success = iperf3Bridge?.startServer(port, useUdp) ?: false
                            withContext(Dispatchers.Main) {
                                result.success(success)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("IPERF3_ERROR", "Failed to start server: ${e.message}", null)
                            }
                        }
                    }
                }

                "stopServer" -> {
                    try {
                        val success = iperf3Bridge?.stopServer() ?: false
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("IPERF3_ERROR", "Failed to stop server: ${e.message}", null)
                    }
                }

                "getVersion" -> {
                    try {
                        val version = iperf3Bridge?.getVersion() ?: "Unknown"
                        result.success(version)
                    } catch (e: Exception) {
                        result.error("IPERF3_ERROR", "Failed to get version: ${e.message}", null)
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // Set up EventChannel for progress updates
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL).setStreamHandler(progressHandler)
    }

    override fun onDestroy() {
        super.onDestroy()
        // Cancel all coroutines when activity is destroyed
        ioScope.cancel()
    }

    private fun getCurrentWifiGateway(): String? {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return null
        val dhcpInfo = wifiManager.dhcpInfo ?: return null
        val gatewayInt = dhcpInfo.gateway
        if (gatewayInt == 0) {
            return null
        }

        return try {
            val gatewayBytes = ByteBuffer.allocate(4)
                .order(ByteOrder.LITTLE_ENDIAN)
                .putInt(gatewayInt)
                .array()
            InetAddress.getByAddress(gatewayBytes).hostAddress
        } catch (e: Exception) {
            Log.e(TAG, "Failed to resolve gateway address", e)
            null
        }
    }

    private fun getGatewayForDestination(hostname: String): DestinationGatewayInfo {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return DestinationGatewayInfo(
                success = false,
                gatewayAddress = null,
                networkType = null,
                interfaceName = null,
                destinationIp = null,
                allRoutes = null,
                error = "Requires Android 5.0 (API 21) or higher"
            )
        }

        val connectivityManager = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return DestinationGatewayInfo(
                success = false,
                gatewayAddress = null,
                networkType = null,
                interfaceName = null,
                destinationIp = null,
                allRoutes = null,
                error = "ConnectivityManager not available"
            )

        try {
            // Get the active network
            val activeNetwork = connectivityManager.activeNetwork
                ?: return DestinationGatewayInfo(
                    success = false,
                    gatewayAddress = null,
                    networkType = null,
                    interfaceName = null,
                    destinationIp = null,
                    allRoutes = null,
                    error = "No active network connection"
                )

            // Resolve hostname to IP address
            val destinationAddress = try {
                InetAddress.getByName(hostname)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to resolve hostname: $hostname", e)
                null
            } ?: return DestinationGatewayInfo(
                success = false,
                gatewayAddress = null,
                networkType = null,
                interfaceName = null,
                destinationIp = null,
                allRoutes = null,
                error = "Failed to resolve hostname: $hostname"
            )

            // Get link properties
            val linkProperties = connectivityManager.getLinkProperties(activeNetwork)
                ?: return DestinationGatewayInfo(
                    success = false,
                    gatewayAddress = null,
                    networkType = null,
                    interfaceName = null,
                    destinationIp = destinationAddress?.hostAddress ?: destinationAddress.toString(),
                    allRoutes = null,
                    error = "Failed to get network properties"
                )

            // Find the best matching route
            val routes = linkProperties.routes
            var bestMatch: RouteInfo? = null
            var bestPrefixLength = -1

            for (route in routes) {
                if (route.matches(destinationAddress)) {
                    val prefixLength = route.destination?.prefixLength ?: 0
                    if (prefixLength > bestPrefixLength) {
                        bestMatch = route
                        bestPrefixLength = prefixLength
                    }
                }
            }

            // Collect all routes for debugging
            val allRoutes = routes.map { route ->
                RouteDetail(
                    destination = route.destination?.toString() ?: "default",
                    gateway = route.gateway?.hostAddress ?: "direct",
                    isDefault = route.isDefaultRoute
                )
            }

            // Get network type
            val networkType = connectivityManager.getNetworkCapabilities(activeNetwork)?.let { capabilities ->
                when {
                    capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) -> "WiFi"
                    capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) -> "Cellular"
                    capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN) -> "VPN"
                    capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
                    else -> "Other"
                }
            } ?: "Unknown"

            return DestinationGatewayInfo(
                success = true,
                gatewayAddress = bestMatch?.gateway?.hostAddress,
                networkType = networkType,
                interfaceName = linkProperties.interfaceName,
                destinationIp = destinationAddress?.hostAddress ?: destinationAddress.toString(),
                allRoutes = allRoutes,
                error = null
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error determining gateway for destination", e)
            return DestinationGatewayInfo(
                success = false,
                gatewayAddress = null,
                networkType = null,
                interfaceName = null,
                destinationIp = null,
                allRoutes = null,
                error = e.message
            )
        }
    }
}
