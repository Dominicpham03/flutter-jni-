# Android Interval Updates Explanation

## Overview

The Android layer bridges between the shared C code and Flutter using JNI (Java Native Interface) and Kotlin. It provides interval updates through an EventChannel stream.

## Files

1. **iperf3_jni.cpp** - JNI bridge (C++ to Kotlin)
2. **Iperf3Bridge.kt** - Kotlin bridge (native to Flutter)
3. **Iperf3ProgressHandler.kt** - EventChannel stream handler

---

## Architecture Flow

```
Shared C Bridge (iperf3_bridge.c)
        ↓ g_progress_callback()
JNI Layer (iperf3_jni.cpp)
        ↓ env->CallVoidMethod()
Kotlin Bridge (Iperf3Bridge.kt)
        ↓ progressHandler?.sendProgress()
Progress Handler (Iperf3ProgressHandler.kt)
        ↓ eventSink?.success()
Flutter EventChannel
        ↓ Stream<Map<String, dynamic>>
Dart Service (iperf3_service.dart)
```

---

## Layer 1: JNI Bridge (iperf3_jni.cpp)

### Purpose

Convert C callback to Kotlin method invocation using JNI.

### Key Components

#### Progress Context Structure

```cpp
struct ProgressContext {
    JNIEnv* env;      // JNI environment
    jobject bridge;   // Kotlin Iperf3Bridge object
};
```

**Created when test starts:**
```cpp
ProgressContext progressCtx = {env, thiz};
```

**Passed to C bridge:**
```cpp
Iperf3Result* result = iperf3_run_client_test(
    host, port, duration, parallel, reverse, useUdp, bandwidth,
    progressCallback,    // ← C callback function
    &progressCtx        // ← Context with JNI objects
);
```

---

### Progress Callback Implementation

**Function:** `progressCallback()` (Lines 58-79)

```cpp
void progressCallback(void* context, int interval, long bytesTransferred,
                     double bitsPerSecond, double jitter, int lostPackets, double rtt) {
    // 1. Extract JNI context
    ProgressContext* ctx = (ProgressContext*)context;
    if (!ctx || !ctx->env || !ctx->bridge) return;

    JNIEnv* env = ctx->env;
    jobject bridge = ctx->bridge;

    // 2. Get Kotlin class and method
    jclass bridgeClass = env->GetObjectClass(bridge);
    jmethodID onProgressMethod = env->GetMethodID(
        bridgeClass,
        "onProgress",      // Method name
        "(IJDDID)V"       // Method signature
    );

    // 3. Call Kotlin method
    if (onProgressMethod) {
        env->CallVoidMethod(bridge, onProgressMethod,
            (jint)interval,              // int → jint
            (jlong)bytesTransferred,     // long → jlong
            (jdouble)bitsPerSecond,      // double → jdouble
            (jdouble)jitter,             // double → jdouble
            (jint)lostPackets,           // int → jint
            (jdouble)rtt                 // double → jdouble
        );
    }
}
```

---

### JNI Method Signature

**`"(IJDDID)V"`** breakdown:

| Part | Meaning |
|------|---------|
| `(` | Start of parameters |
| `I` | int (interval) |
| `J` | long (bytesTransferred) |
| `D` | double (bitsPerSecond) |
| `D` | double (jitter) |
| `I` | int (lostPackets) |
| `D` | double (rtt) |
| `)` | End of parameters |
| `V` | void (return type) |

---

### Type Conversions

**C types → JNI types:**

```cpp
int interval          → (jint)interval
long bytesTransferred → (jlong)bytesTransferred
double bitsPerSecond  → (jdouble)bitsPerSecond
double jitter         → (jdouble)jitter
int lostPackets       → (jint)lostPackets
double rtt            → (jdouble)rtt
```

**JNI types → Kotlin types:**

```
jint    → Int
jlong   → Long
jdouble → Double
```

---

### Thread Context

**Execution thread:** iperf3's reporter thread (from C library)

**Thread safety:**
- JNI calls are thread-safe
- `env` is thread-local (passed in context)
- Kotlin layer handles main thread dispatch

---

## Layer 2: Kotlin Bridge (Iperf3Bridge.kt)

### Purpose

Format progress data and send to Flutter via EventChannel.

### Key Function: onProgress()

**Called from JNI (Lines 62-82):**

```kotlin
@Suppress("unused")  // Called from JNI, not directly from Kotlin
fun onProgress(interval: Int, bytesTransferred: Long, bitsPerSecond: Double,
               jitter: Double, lostPackets: Int, rtt: Double) {

    // 1. Build progress data map
    val progressData = mutableMapOf<String, Any>(
        "interval" to interval,                    // Which second (1, 2, 3...)
        "bytesTransferred" to bytesTransferred,   // Bytes this interval
        "bitsPerSecond" to bitsPerSecond,         // Raw bits/sec
        "mbps" to (bitsPerSecond / 1000000.0)    // Convert to Mbps
    )

    // 2. Add protocol-specific metrics
    if (rtt > 0) {
        // TCP mode: include RTT
        progressData["rtt"] = rtt
    }
    if (jitter > 0) {
        // UDP mode: include jitter and packet loss
        progressData["jitter"] = jitter
        progressData["lostPackets"] = lostPackets
    }

    // 3. Send to Flutter
    progressHandler?.sendProgress(progressData)
}
```

---

### Data Formatting

**For UDP Upload/Download:**

```kotlin
{
    "interval": 1,
    "bytesTransferred": 1250000,
    "bitsPerSecond": 10000000.0,
    "mbps": 10.0,
    "jitter": 0.042,
    "lostPackets": 3
}
```

**For TCP:**

```kotlin
{
    "interval": 1,
    "bytesTransferred": 125000000,
    "bitsPerSecond": 1000000000.0,
    "mbps": 1000.0,
    "rtt": 2.5
}
```

---

### Protocol Detection

**UDP detection:**
```kotlin
if (jitter > 0) {
    // jitter only exists for UDP
    progressData["jitter"] = jitter
    progressData["lostPackets"] = lostPackets
}
```

**TCP detection:**
```kotlin
if (rtt > 0) {
    // rtt only exists for TCP
    progressData["rtt"] = rtt
}
```

---

### Progress Handler Integration

**Handler passed from MainActivity:**

```kotlin
class Iperf3Bridge(private val progressHandler: Iperf3ProgressHandler?) {
    // ...
}
```

**Send to handler:**
```kotlin
progressHandler?.sendProgress(progressData)
```

---

## Layer 3: Progress Handler (Iperf3ProgressHandler.kt)

### Purpose

Manage EventChannel stream and ensure main thread execution.

### Key Components

#### EventSink Storage

```kotlin
private var eventSink: EventChannel.EventSink? = null
private val handler = Handler(Looper.getMainLooper())
```

**Why Handler?** JNI callback executes on iperf3 thread, but Flutter requires main thread.

---

### Stream Setup

**Interface:** `EventChannel.StreamHandler`

```kotlin
override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events  // Store sink for later use
}

override fun onCancel(arguments: Any?) {
    eventSink = null    // Clear sink when stream cancelled
}
```

---

### Send Progress

**Function:** `sendProgress()` (Lines 20-24)

```kotlin
fun sendProgress(progressData: Map<String, Any>) {
    handler.post {
        eventSink?.success(progressData)
    }
}
```

**What happens:**

1. **Called from:** `Iperf3Bridge.onProgress()`
2. **Execution thread:** iperf3 reporter thread
3. **`handler.post {}`:** Schedules execution on main thread
4. **`eventSink?.success()`:** Emits data to Flutter EventChannel
5. **Dart receives:** `Stream<Map<String, dynamic>>`

---

### Thread Flow

```
iperf3 Reporter Thread
    ↓ JNI callback
Kotlin onProgress() [iperf3 thread]
    ↓ progressHandler?.sendProgress()
handler.post {} [schedules on main thread]
    ↓
Android Main Thread
    ↓ eventSink?.success()
Flutter Platform Thread
    ↓ EventChannel stream
Dart Isolate
```

---

## MainActivity Integration

### Setup EventChannel

**In MainActivity.kt:**

```kotlin
class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Create progress handler
        val progressHandler = Iperf3ProgressHandler()

        // 2. Register EventChannel
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.hello_world_app/iperf3_progress"
        ).setStreamHandler(progressHandler)

        // 3. Create bridge with handler
        val iperf3Bridge = Iperf3Bridge(progressHandler)

        // 4. Register MethodChannel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.hello_world_app/iperf3"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "runClient" -> {
                    // Bridge will use progressHandler
                    val testResult = iperf3Bridge.runClient(...)
                    result.success(testResult)
                }
            }
        }
    }
}
```

---

## Complete Data Flow Example

### Timeline for UDP Upload at 10 Mbps

**Time: 0.0s - Test Starts**

```
1. MainActivity creates Iperf3ProgressHandler
2. EventChannel registered
3. Dart subscribes to stream
4. eventSink stored in handler
5. iperf3_run_client_test() called with progressCallback
```

**Time: 1.0s - Interval 1 Complete**

```
C Layer (iperf3_bridge.c):
    - Extracts: bits_per_second = 10000000.0
    - Calls: g_progress_callback(ctx, 1, 1250000, 10000000.0, 0.042, 3, 0.0)

JNI Layer (iperf3_jni.cpp):
    - progressCallback() receives C data
    - Converts to JNI types
    - Calls: env->CallVoidMethod(bridge, onProgressMethod, ...)

Kotlin Layer (Iperf3Bridge.kt):
    - onProgress() receives JNI data
    - Creates map: {"interval": 1, "mbps": 10.0, "jitter": 0.042, ...}
    - Calls: progressHandler?.sendProgress(progressData)

Handler Layer (Iperf3ProgressHandler.kt):
    - sendProgress() receives map
    - Posts to main thread: handler.post { ... }
    - On main thread: eventSink?.success(progressData)

Flutter Layer:
    - EventChannel receives map
    - Stream emits: Map<String, dynamic>
    - Dart listener receives data
    - UI calls setState()
    - Displays: "10.00 Mbits/sec"
```

**Time: 2.0s - Interval 2 Complete**

Same flow, new values → UI updates to "9.50 Mbits/sec"

---

## Error Handling

### JNI Layer

```cpp
if (!ctx || !ctx->env || !ctx->bridge) return;  // Null checks

if (onProgressMethod) {  // Check method exists
    env->CallVoidMethod(...);
}
```

### Kotlin Layer

```kotlin
progressHandler?.sendProgress(progressData)  // Null-safe call
```

### Handler Layer

```kotlin
eventSink?.success(progressData)  // Null-safe (stream might be cancelled)
```

---

## Debugging

### Enable JNI Logs

```cpp
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

LOGD("JNI: nativeRunClient called");
LOGD("JNI: Calling iperf3_run_client_test...");
LOGD("JNI: iperf3_run_client_test returned");
```

### Enable Kotlin Logs

```kotlin
fun onProgress(...) {
    Log.d("Iperf3Bridge", "Progress: interval=$interval, mbps=${bitsPerSecond/1000000.0}")
    // ...
}
```

### View Logs

```bash
adb logcat | grep -E "iperf3|Iperf3"
```

---

## Performance Notes

### Memory

**Per interval:**
- Kotlin Map: ~200 bytes
- EventChannel buffer: ~500 bytes
- Total: ~700 bytes per interval

**10-second test:**
- 10 intervals × 700 bytes = ~7KB
- Negligible memory impact

### Latency

**Thread transitions:**
- iperf3 thread → JNI → Kotlin [~1-5ms]
- Kotlin → Main thread (handler.post) [~5-10ms]
- Main thread → Flutter [~5-10ms]
- **Total:** ~10-25ms from C callback to Dart

**Overall latency:**
- UDP download: ~20-70ms (C measurement to UI)
- UDP upload: ~120-550ms (server measurement + network + UI)

---

## Common Issues

### Issue: No Progress Updates

**Check:**

1. **ProgressHandler created?**
   ```kotlin
   val progressHandler = Iperf3ProgressHandler()  // Must not be null
   ```

2. **EventChannel registered?**
   ```kotlin
   EventChannel(...).setStreamHandler(progressHandler)
   ```

3. **Bridge has handler reference?**
   ```kotlin
   val bridge = Iperf3Bridge(progressHandler)  // Pass handler
   ```

4. **Stream subscribed in Dart?**
   ```dart
   _iperf3Service.getProgressStream().listen(...)
   ```

### Issue: Crashes in JNI

**Symptom:** App crashes during test

**Common causes:**

1. **Invalid context:**
   ```cpp
   if (!ctx || !ctx->env || !ctx->bridge) return;  // Add this check
   ```

2. **Wrong method signature:**
   ```cpp
   "(IJDDID)V"  // Must match Kotlin method exactly
   ```

3. **Thread issues:**
   - Don't store `env` globally (thread-local)
   - Use context passed to callback

---

## Summary

**Android interval updates use 3 files:**

1. **iperf3_jni.cpp**
   - Bridges C to Kotlin via JNI
   - Converts C types to Java types
   - Invokes Kotlin method

2. **Iperf3Bridge.kt**
   - Receives JNI callback
   - Formats data as Map
   - Sends to progress handler

3. **Iperf3ProgressHandler.kt**
   - Manages EventChannel stream
   - Ensures main thread execution
   - Emits to Flutter

**Data flow:** C → JNI → Kotlin → Handler → EventChannel → Dart

**Thread flow:** iperf3 thread → Main thread (via Handler) → Dart isolate

**Latency:** ~10-25ms from C callback to Flutter UI
