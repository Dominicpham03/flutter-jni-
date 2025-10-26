# Complete File List for Interval Updates

This document lists all files involved in providing interval updates for both Android and iOS, organized by layer and platform.

---

## File Organization

```
interval_updates_reference/
├── README.md                          ← Start here
├── FILE_LIST.md                       ← This file
├── FLOW_DIAGRAM.md                    ← Visual flow diagrams
│
├── shared/                            ← Platform-agnostic C code
│   ├── iperf3_bridge.c               ← Core interval extraction logic
│   ├── iperf3_bridge.h               ← Shared interface
│   └── SHARED_EXPLANATION.md         ← Detailed explanation
│
├── android/                           ← Android-specific files
│   ├── iperf3_jni.cpp                ← JNI bridge (C++ to Kotlin)
│   ├── Iperf3Bridge.kt               ← Kotlin bridge (native to Flutter)
│   ├── Iperf3ProgressHandler.kt      ← EventChannel handler
│   └── ANDROID_EXPLANATION.md        ← Detailed explanation
│
├── ios/                               ← iOS-specific files
│   ├── Iperf3Bridge.m                ← Objective-C bridge
│   ├── Iperf3Bridge.h                ← Objective-C header (if exists)
│   └── IOS_EXPLANATION.md            ← Detailed explanation
│
└── flutter/                           ← Dart/Flutter files
    ├── iperf3_service.dart           ← Service layer
    ├── main.dart                     ← UI layer
    └── FLUTTER_EXPLANATION.md        ← Detailed explanation
```

---

## Layer-by-Layer File Breakdown

### Layer 1: iperf3 Library (Not Included)

**Location:** `native/iperf3/src/`

**Key files (reference only):**
- `iperf_api.c` - Main API implementation
- `iperf_client_api.c` - Client-side functions
- `cjson.c` - JSON parsing
- Many more...

**What it does:**
- Sends/receives network packets
- Measures throughput every ~1 second
- Creates JSON intervals
- Calls reporter callback

**Not included in reference folder:** Too large, external dependency

---

### Layer 2: Shared C Bridge (Platform-Agnostic)

#### File: `shared/iperf3_bridge.c`

**Original location:** `hello_world_app/native/src/iperf3_bridge.c`

**Lines of code:** 500

**Key functions:**
- `bridge_reporter_callback()` (Lines 67-105)
  - Called by iperf3 every ~1 second
  - Extracts interval data from JSON
  - Fires platform callback

- `get_interval_sum()` (Lines 53-65)
  - Gets correct JSON object (sum/sum_sent/sum_received)
  - Handles different test types (UDP/TCP, upload/download)

- `get_json_number()` (Lines 45-51)
  - Safely extracts numbers from JSON
  - Returns fallback if missing

**Responsibilities:**
- ✅ Intercept iperf3 reporter callback
- ✅ Parse JSON intervals
- ✅ Extract: bits_per_second, jitter, lost_packets, bytes
- ✅ Track processed intervals (prevent duplicates)
- ✅ Fire platform-specific progress callback

**Used by:** Both Android and iOS (exact same file)

---

#### File: `shared/iperf3_bridge.h`

**Original location:** `hello_world_app/native/src/iperf3_bridge.h`

**Lines of code:** 63

**Key definitions:**

```c
// Result structure
typedef struct {
    bool success;
    double sentBitsPerSecond;
    double receivedBitsPerSecond;
    // ...
} Iperf3Result;

// Progress callback type
typedef void (*Iperf3ProgressCallback)(
    void* context,
    int interval,
    long bytesTransferred,
    double bitsPerSecond,
    double jitter,
    int lostPackets,
    double rtt
);

// Main API function
Iperf3Result* iperf3_run_client_test(
    const char* host,
    int port,
    // ...
    Iperf3ProgressCallback progressCallback,
    void* callbackContext
);
```

**Responsibilities:**
- ✅ Define cross-platform interface
- ✅ Declare function prototypes
- ✅ Define data structures

**Used by:** Both Android and iOS

---

### Layer 3: Platform Bridge

#### Android: `android/iperf3_jni.cpp`

**Original location:** `hello_world_app/android/app/src/main/cpp/iperf3_jni.cpp`

**Lines of code:** 210

**Language:** C++ (for JNI)

**Key function:**

```cpp
void progressCallback(void* context, int interval, long bytesTransferred,
                     double bitsPerSecond, double jitter, int lostPackets, double rtt) {
    // 1. Extract JNI context
    ProgressContext* ctx = (ProgressContext*)context;

    // 2. Get Kotlin method
    jmethodID onProgressMethod = env->GetMethodID(...);

    // 3. Call Kotlin
    env->CallVoidMethod(bridge, onProgressMethod,
        (jint)interval,
        (jlong)bytesTransferred,
        (jdouble)bitsPerSecond,
        (jdouble)jitter,
        (jint)lostPackets,
        (jdouble)rtt
    );
}
```

**Responsibilities:**
- ✅ Receive C callback
- ✅ Convert C types to JNI types
- ✅ Invoke Kotlin method via JNI

**Used by:** Android only

---

#### iOS: `ios/Iperf3Bridge.m`

**Original location:** `hello_world_app/ios/Runner/Iperf3Bridge.m`

**Lines of code:** 146

**Language:** Objective-C

**Key function:**

```objc
static void iperf3_progress_callback_wrapper(void *context,
                                              int interval,
                                              long bytes_transferred,
                                              double bits_per_second,
                                              double jitter,
                                              int lost_packets,
                                              double rtt) {
    // 1. Cast context to Objective-C
    Iperf3Bridge *bridge = (__bridge Iperf3Bridge *)context;

    // 2. Dispatch to main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        // 3. Call Objective-C callback block
        bridge.progressCallback(interval, bytes_transferred,
                               bits_per_second, jitter, lost_packets, rtt);
    });
}
```

**Responsibilities:**
- ✅ Receive C callback
- ✅ Cast C pointer to Objective-C object
- ✅ Dispatch to main thread
- ✅ Call Objective-C block

**Used by:** iOS only

---

### Layer 4: Platform Handler

#### Android: `android/Iperf3Bridge.kt`

**Original location:** `hello_world_app/android/app/src/main/kotlin/com/example/hello_world_app/Iperf3Bridge.kt`

**Lines of code:** 84

**Language:** Kotlin

**Key function:**

```kotlin
fun onProgress(interval: Int, bytesTransferred: Long, bitsPerSecond: Double,
               jitter: Double, lostPackets: Int, rtt: Double) {
    // 1. Build progress data map
    val progressData = mutableMapOf<String, Any>(
        "interval" to interval,
        "bytesTransferred" to bytesTransferred,
        "bitsPerSecond" to bitsPerSecond,
        "mbps" to (bitsPerSecond / 1000000.0)
    )

    // 2. Add protocol-specific metrics
    if (jitter > 0) {
        progressData["jitter"] = jitter
        progressData["lostPackets"] = lostPackets
    }
    if (rtt > 0) {
        progressData["rtt"] = rtt
    }

    // 3. Send to Flutter
    progressHandler?.sendProgress(progressData)
}
```

**Responsibilities:**
- ✅ Receive JNI callback
- ✅ Format data as Map
- ✅ Add protocol-specific metrics
- ✅ Send to progress handler

**Used by:** Android only

---

#### Android: `android/Iperf3ProgressHandler.kt`

**Original location:** `hello_world_app/android/app/src/main/kotlin/com/example/hello_world_app/Iperf3ProgressHandler.kt`

**Lines of code:** 47

**Language:** Kotlin

**Key function:**

```kotlin
fun sendProgress(progressData: Map<String, Any>) {
    handler.post {
        eventSink?.success(progressData)
    }
}
```

**Responsibilities:**
- ✅ Manage EventChannel stream
- ✅ Post to Android main thread
- ✅ Emit to Flutter EventSink

**Used by:** Android only

---

#### iOS: Iperf3Plugin.m (Not Included)

**Location:** `hello_world_app/ios/Runner/Iperf3Plugin.m`

**Why not included:** Plugin setup code, not core interval logic

**What it does:**
- Sets up EventChannel
- Sets progressCallback block on bridge
- Sends to EventSink

---

### Layer 5: Dart Service

#### File: `flutter/iperf3_service.dart`

**Original location:** `hello_world_app/lib/iperf3_service.dart`

**Lines of code:** 252

**Language:** Dart

**Key function:**

```dart
Stream<Map<String, dynamic>> getProgressStream() {
    _progressStream ??= _progressChannel
        .receiveBroadcastStream()
        .map((event) {
            if (event is Map) {
                return Map<String, dynamic>.from(event);
            }
            return <String, dynamic>{};
        });

    return _progressStream!;
}
```

**Responsibilities:**
- ✅ Set up EventChannel
- ✅ Provide Stream interface
- ✅ Type-safe conversion

**Used by:** Both Android and iOS

---

### Layer 6: Flutter UI

#### File: `flutter/main.dart`

**Original location:** `hello_world_app/lib/main.dart`

**Lines of code:** 634

**Language:** Dart

**Key functions:**

```dart
// Subscribe to stream
void _listenToProgress() {
    _iperf3Service.getProgressStream().listen((progress) {
        if (!mounted) return;

        setState(() {
            _currentProgress = progress;
        });
    });
}

// Display in UI
if (_currentProgress != null) {
    Text('${_currentProgress!['mbps']?.toStringAsFixed(2)} Mbits/sec')
    Text('Jitter: ${_currentProgress!['jitter']?.toStringAsFixed(2)} ms')
    Text('Lost Packets: ${_currentProgress!['lostPackets']}')
}
```

**Responsibilities:**
- ✅ Subscribe to progress stream
- ✅ Call setState() on updates
- ✅ Display live metrics in UI

**Used by:** Both Android and iOS

---

## File Dependencies

### Shared Bridge Dependencies

**iperf3_bridge.c depends on:**
- `iperf3_bridge.h` - Own header
- `iperf.h` - iperf3 main header
- `iperf_api.h` - iperf3 API
- `cjson.h` - JSON parsing

**iperf3_bridge.h depends on:**
- Nothing (standalone header)

---

### Android Dependencies

**iperf3_jni.cpp depends on:**
- `iperf3_bridge.h` - Shared interface
- `<jni.h>` - JNI interface

**Iperf3Bridge.kt depends on:**
- `Iperf3ProgressHandler` - Progress handler

**Iperf3ProgressHandler.kt depends on:**
- Flutter EventChannel (Android SDK)

---

### iOS Dependencies

**Iperf3Bridge.m depends on:**
- `iperf3_bridge.h` - Shared interface
- Foundation framework (Objective-C)

---

### Dart Dependencies

**iperf3_service.dart depends on:**
- Flutter services (MethodChannel, EventChannel)

**main.dart depends on:**
- `iperf3_service.dart` - Service layer
- Flutter material (UI components)

---

## Build Integration

### Android CMakeLists.txt

**Location:** `hello_world_app/android/app/src/main/cpp/CMakeLists.txt`

**Includes:**
```cmake
add_library(iperf3_jni SHARED
    iperf3_jni.cpp
    ../../../../../../native/src/iperf3_bridge.c
    # ... iperf3 source files
)
```

---

### iOS Xcode Project

**Location:** `hello_world_app/ios/Runner.xcodeproj`

**Includes:**
- `Iperf3Bridge.m`
- `Native/iperf3_bridge.c`
- iperf3 source files

---

## Total Lines of Code

| File | Lines | Language |
|------|-------|----------|
| **Shared** | | |
| iperf3_bridge.c | 500 | C |
| iperf3_bridge.h | 63 | C |
| **Android** | | |
| iperf3_jni.cpp | 210 | C++ |
| Iperf3Bridge.kt | 84 | Kotlin |
| Iperf3ProgressHandler.kt | 47 | Kotlin |
| **iOS** | | |
| Iperf3Bridge.m | 146 | Objective-C |
| **Flutter** | | |
| iperf3_service.dart | 252 | Dart |
| main.dart (interval portion) | ~150 | Dart |
| **Total** | **~1,452** | Mixed |

---

## Quick Reference

### I want to modify interval extraction logic
→ Edit `shared/iperf3_bridge.c`

### I want to change Android data format
→ Edit `android/Iperf3Bridge.kt`

### I want to change iOS data format
→ Edit `ios/Iperf3Bridge.m` (progressCallback block)

### I want to modify the stream in Dart
→ Edit `flutter/iperf3_service.dart`

### I want to change how UI displays intervals
→ Edit `flutter/main.dart`

### I want to add a new metric
1. Extract in `iperf3_bridge.c`
2. Add parameter to callback signature
3. Update JNI/Obj-C bridges
4. Update Kotlin/Obj-C handlers
5. Add to Dart Map
6. Display in UI

---

## Summary

**Total files involved in interval updates:** 8 core files

**Shared across platforms:** 2 files (iperf3_bridge.c, iperf3_bridge.h)

**Android-specific:** 3 files (iperf3_jni.cpp, Iperf3Bridge.kt, Iperf3ProgressHandler.kt)

**iOS-specific:** 1 file (Iperf3Bridge.m)

**Flutter (both platforms):** 2 files (iperf3_service.dart, main.dart)

**Architecture:** 6-layer stack with clear separation of concerns
