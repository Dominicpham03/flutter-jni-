# Interval Updates Reference

This folder contains a complete reference of all files involved in providing real-time interval updates for iperf3 upload and download tests.

## Directory Structure

```
interval_updates_reference/
├── README.md (this file)
├── FLOW_DIAGRAM.md (visual flow explanation)
├── shared/ (Platform-agnostic C code)
│   ├── iperf3_bridge.c
│   ├── iperf3_bridge.h
│   └── SHARED_EXPLANATION.md
├── android/ (Android-specific code)
│   ├── iperf3_jni.cpp
│   ├── Iperf3Bridge.kt
│   ├── Iperf3ProgressHandler.kt
│   └── ANDROID_EXPLANATION.md
├── ios/ (iOS-specific code)
│   ├── Iperf3Bridge.m
│   ├── Iperf3Bridge.h (if exists)
│   └── IOS_EXPLANATION.md
└── flutter/ (Dart/Flutter code)
    ├── iperf3_service.dart
    ├── main.dart
    └── FLUTTER_EXPLANATION.md
```

## Quick Overview

### What Are Interval Updates?

Interval updates provide **real-time throughput measurements every ~1 second** during an iperf3 network test. This allows users to see:
- Live upload/download speed fluctuations
- Packet loss (UDP)
- Jitter (UDP)
- RTT/latency (TCP)

### Architecture Layers

```
Layer 1: iperf3 Library → Measures network, creates JSON intervals
                ↓
Layer 2: Shared C Bridge → Extracts interval data from JSON
                ↓
Layer 3: Platform Bridge → JNI (Android) or Obj-C (iOS)
                ↓
Layer 4: Platform Handler → Kotlin (Android) or Obj-C (iOS)
                ↓
Layer 5: Dart Service → Stream provider
                ↓
Layer 6: Flutter UI → Displays live updates
```

## File Responsibilities

### Shared Layer (Used by Both Platforms)

**`shared/iperf3_bridge.c`**
- Intercepts iperf3's reporter callback
- Extracts interval JSON data
- Parses: `bits_per_second`, `jitter_ms`, `lost_packets`, `bytes`
- Fires platform-specific progress callback
- **Key Functions:**
  - `bridge_reporter_callback()` - Called by iperf3 every ~1 second
  - `get_interval_sum()` - Extracts correct JSON object (sum/sum_sent/sum_received)
  - `get_json_number()` - Safely parses JSON numbers

**`shared/iperf3_bridge.h`**
- Header defining shared interface
- `Iperf3Result` struct
- `Iperf3ProgressCallback` function pointer type
- Cross-platform C API

### Android Layer

**`android/iperf3_jni.cpp`**
- JNI bridge between C and Kotlin
- Converts C types to Java types
- Calls Kotlin `onProgress()` method
- **Key Function:** `progressCallback()` - Receives C callback, invokes Kotlin

**`android/Iperf3Bridge.kt`**
- Kotlin bridge to Flutter
- Formats progress data as Map
- Adds protocol-specific metrics (jitter for UDP, rtt for TCP)
- Sends to EventChannel
- **Key Function:** `onProgress()` - Called from JNI, sends to Flutter

**`android/Iperf3ProgressHandler.kt`**
- Manages EventChannel stream
- Posts to Android main thread
- **Key Function:** `sendProgress()` - Emits to Flutter EventChannel

### iOS Layer

**`ios/Iperf3Bridge.m`**
- Objective-C bridge between C and Flutter
- Converts C types to Objective-C types
- Dispatches to main queue for UI safety
- **Key Function:** `iperf3_progress_callback_wrapper()` - C callback wrapper

### Flutter Layer

**`flutter/iperf3_service.dart`**
- Dart service layer
- Provides Stream<Map<String, dynamic>>
- Receives from EventChannel
- **Key Function:** `getProgressStream()` - Returns broadcast stream

**`flutter/main.dart`**
- UI layer
- Subscribes to progress stream
- Displays live updates
- **Key Function:** `_listenToProgress()` - Stream listener

## How It Works for Different Test Types

### UDP Upload (reverse: false)

**Data Source:** Server measures throughput, sends back to client

**Interval JSON Path:** `intervals[n].sum.bits_per_second`

**Flow:**
1. Client sends UDP packets to server
2. Server measures actual receive rate (e.g., 340 Mbps)
3. Server calculates jitter and packet loss
4. Server sends stats to client via control connection
5. Client includes server stats in `intervals[n].sum`
6. Our bridge extracts and displays

**Proof it's server data:**
- Contains `jitter_ms` (only receiver can measure)
- Contains `lost_packets` (only receiver knows)

### UDP Download (reverse: true)

**Data Source:** Client measures throughput locally

**Interval JSON Path:** `intervals[n].sum.bits_per_second`

**Flow:**
1. Server sends UDP packets to client
2. Client measures actual receive rate
3. Client calculates jitter and packet loss locally
4. Client includes own stats in `intervals[n].sum`
5. Our bridge extracts and displays

**Advantage:** Lower latency (no network round-trip)

### TCP Upload (reverse: false)

**Data Source:** Client measures send throughput

**Interval JSON Path:** `intervals[n].sum_sent.bits_per_second` or `intervals[n].sum.bits_per_second`

### TCP Download (reverse: true)

**Data Source:** Client measures receive throughput

**Interval JSON Path:** `intervals[n].sum_received.bits_per_second` or `intervals[n].sum.bits_per_second`

## Key Implementation Details

### 1. Callback Registration

**When test starts:**
```c
// Replace iperf3's reporter callback with ours
g_original_reporter_callback = test->reporter_callback;
test->reporter_callback = bridge_reporter_callback;
```

### 2. Interval Tracking

**Prevent duplicate reports:**
```c
static int g_last_reported_interval = 0;

// Only process NEW intervals
for (int idx = g_last_reported_interval; idx < interval_count; ++idx) {
    // Process interval
}

g_last_reported_interval = interval_count;
```

### 3. Thread Safety

- **C layer:** Uses iperf3's reporter thread
- **Android:** Posts to main thread via Handler
- **iOS:** Dispatches to main queue
- **Flutter:** EventChannel handles threading automatically

### 4. Data Type Conversions

**C → JNI:**
```cpp
(jint)interval, (jlong)bytes, (jdouble)bitsPerSecond
```

**JNI → Kotlin:**
```kotlin
Int, Long, Double
```

**Kotlin → EventChannel:**
```kotlin
Map<String, Any>
```

**EventChannel → Dart:**
```dart
Map<String, dynamic>
```

## Usage Example

### Subscribe to Stream (Flutter)

```dart
@override
void initState() {
    super.initState();
    _listenToProgress();
}

void _listenToProgress() {
    _iperf3Service.getProgressStream().listen((progress) {
        if (!mounted) return;

        setState(() {
            _currentProgress = progress;
        });
    });
}
```

### Display Updates (Flutter)

```dart
if (_currentProgress != null) {
    Text('${_currentProgress!['mbps']?.toStringAsFixed(2)} Mbits/sec');

    // UDP-specific
    if (_currentProgress!.containsKey('jitter'))
        Text('Jitter: ${_currentProgress!['jitter']?.toStringAsFixed(2)} ms');

    if (_currentProgress!.containsKey('lostPackets'))
        Text('Lost Packets: ${_currentProgress!['lostPackets']}');

    // TCP-specific
    if (_currentProgress!.containsKey('rtt'))
        Text('RTT: ${_currentProgress!['rtt']?.toStringAsFixed(2)} ms');
}
```

## Timeline Example

```
Time 0.0s:  Test starts
            - Callback registered
            - g_last_reported_interval = 0

Time 1.0s:  Interval 1 completes
            - iperf3 calls bridge_reporter_callback()
            - Extract: bits_per_second = 10000000.0
            - Fire: g_progress_callback(..., 10000000.0, ...)
            - JNI → Kotlin → EventChannel → Dart
            - UI shows: "10.00 Mbits/sec"
            - g_last_reported_interval = 1

Time 2.0s:  Interval 2 completes
            - Extract: bits_per_second = 9500000.0
            - UI updates: "9.50 Mbits/sec"
            - g_last_reported_interval = 2

Time 3.0s:  Interval 3 completes
            - Extract: bits_per_second = 10200000.0
            - UI updates: "10.20 Mbits/sec"
            - g_last_reported_interval = 3
```

## Common Issues & Solutions

### Issue: No Interval Updates

**Symptoms:** UI shows "Running..." but no live speed

**Check:**
1. Progress callback registered?
2. EventChannel set up?
3. Stream subscribed in initState()?

### Issue: Wrong Speed Displayed

**Symptoms:** Shows bandwidth cap instead of actual throughput

**Diagnosis:**
```dart
print('Jitter: ${progress['jitter']}');  // Should be non-zero for UDP
print('Lost Packets: ${progress['lostPackets']}');  // Should be present
```

**If jitter is 0 or null:** Server stats not received
**If jitter has values:** Data is correct

### Issue: Delayed Updates

**Expected:**
- UDP download: <100ms delay
- UDP upload: 100-500ms delay
- TCP: Similar to UDP

**If excessive:** Network congestion or server load

## Testing Interval Updates

### Android

```bash
# Enable debug logs
adb logcat | grep -E "iperf3|Iperf3"

# Look for:
# - "JNI: Calling iperf3_run_client_test..."
# - "Interval 1 (0.0 - 1.0 sec):"
# - "bits_per_second: X"
```

### iOS

```bash
# View iOS logs
# Look for:
# - "Iperf3Bridge: Running client test"
# - Progress callback invocations
```

### Flutter

```dart
void _listenToProgress() {
    _iperf3Service.getProgressStream().listen((progress) {
        print('=== Interval ${progress['interval']} ===');
        print('Mbps: ${progress['mbps']}');
        print('Jitter: ${progress['jitter']}');
        print('Lost Packets: ${progress['lostPackets']}');
    });
}
```

## References

- **Main Documentation:** `/INTERVAL_UPDATES_DOCUMENTATION.md`
- **iperf3 Source:** `native/iperf3/src/`
- **Active Files:** See directory structure above

## Summary

**One shared C bridge** provides interval updates for both Android and iOS:
- ✅ Same logic on all platforms
- ✅ Real-time updates (~1 second intervals)
- ✅ Server throughput for UDP upload
- ✅ Client throughput for UDP download
- ✅ Thread-safe implementation
- ✅ Type-safe conversions at each layer

**6-layer architecture** from iperf3 to UI with clear separation of concerns.
