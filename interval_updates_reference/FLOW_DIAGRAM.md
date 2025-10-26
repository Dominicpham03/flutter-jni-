# Interval Updates Visual Flow Diagram

## Complete Data Flow: Upload & Download

This document provides visual diagrams showing exactly how interval updates flow through the system for both UDP upload and UDP download tests.

---

## UDP Upload Flow (Client → Server)

### Overview

**Configuration:** `reverse: false`, `useUdp: true`

**Direction:** Client sends to server

**Key Point:** Server measures throughput and sends stats back to client

---

### Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│ LAYER 1: iperf3 Library (C)                                        │
│                                                                     │
│ Client sending UDP packets to server at target rate (e.g. 1.36 Gbps)│
│         ↓                                                           │
│ Server receives packets                                            │
│         ↓                                                           │
│ Server measures:                                                   │
│   • Actual receive rate: 340 Mbps (network bottleneck)           │
│   • Jitter: 0.042 ms                                              │
│   • Lost packets: 3                                               │
│         ↓                                                           │
│ Server sends stats back to client via TCP control connection      │
│         ↓                                                           │
│ Client receives server stats                                       │
│         ↓                                                           │
│ iperf3 creates JSON interval:                                     │
│ {                                                                  │
│   "intervals": [{                                                 │
│     "sum": {                                                      │
│       "bits_per_second": 340000000.0,  ← Server's receive rate   │
│       "jitter_ms": 0.042,              ← Server measured          │
│       "lost_packets": 3                ← Server detected          │
│     }                                                             │
│   }]                                                              │
│ }                                                                  │
│         ↓                                                           │
│ iperf3 calls: test->reporter_callback(test)                       │
└──────────────────────┬──────────────────────────────────────────────┘
                       │ Every ~1 second
                       ↓
┌─────────────────────────────────────────────────────────────────────┐
│ LAYER 2: iperf3_bridge.c (Shared C Bridge)                         │
│                                                                     │
│ bridge_reporter_callback() called                                  │
│         ↓                                                           │
│ Extract interval: test->json_intervals[idx]                        │
│         ↓                                                           │
│ Get sum object: intervals[idx].sum                                 │
│         ↓                                                           │
│ Parse values:                                                       │
│   double bits_per_second = sum["bits_per_second"]  // 340000000.0 │
│   double jitter = sum["jitter_ms"]                 // 0.042       │
│   double lost_packets = sum["lost_packets"]        // 3           │
│         ↓                                                           │
│ Fire callback:                                                      │
│   g_progress_callback(                                             │
│     context,           // Platform-specific (JNI/Obj-C)           │
│     1,                 // Interval number                          │
│     42500000,          // Bytes                                    │
│     340000000.0,       // bits_per_second ← THE UPLOAD SPEED!     │
│     0.042,             // jitter                                   │
│     3,                 // lost_packets                             │
│     0.0                // rtt (N/A for UDP)                        │
│   )                                                                 │
└──────────────────────┬──────────────────────────────────────────────┘
                       │ Function pointer call
                       ↓
        ┌──────────────┴──────────────┐
        │                             │
        ↓ ANDROID                     ↓ iOS
┌────────────────────────┐   ┌────────────────────────┐
│ LAYER 3A: JNI          │   │ LAYER 3B: Objective-C  │
│ iperf3_jni.cpp         │   │ Iperf3Bridge.m         │
│                        │   │                        │
│ progressCallback()     │   │ wrapper()              │
│   ↓                    │   │   ↓                    │
│ Convert C → JNI:       │   │ Cast context:          │
│   (jdouble)340000000.0 │   │   (__bridge)context    │
│   ↓                    │   │   ↓                    │
│ Call Kotlin:           │   │ dispatch_async(main) { │
│   CallVoidMethod(      │   │   ↓                    │
│     onProgress,        │   │   block.call(...)      │
│     340000000.0,       │   │ }                      │
│     0.042,             │   │                        │
│     3                  │   │                        │
│   )                    │   │                        │
└────────┬───────────────┘   └────────┬───────────────┘
         │                            │
         ↓ ANDROID                    ↓ iOS
┌────────────────────────┐   ┌────────────────────────┐
│ LAYER 4A: Kotlin       │   │ LAYER 4B: Obj-C Block  │
│ Iperf3Bridge.kt        │   │ Iperf3Plugin.m         │
│                        │   │                        │
│ onProgress()           │   │ progressCallback block │
│   ↓                    │   │   ↓                    │
│ Build map:             │   │ Build dict:            │
│ {                      │   │ {                      │
│   "interval": 1,       │   │   "interval": 1,       │
│   "mbps": 340.0,       │   │   "mbps": 340.0,       │
│   "jitter": 0.042,     │   │   "jitter": 0.042,     │
│   "lostPackets": 3     │   │   "lostPackets": 3     │
│ }                      │   │ }                      │
│   ↓                    │   │   ↓                    │
│ progressHandler.       │   │ _eventSink(dict)       │
│   sendProgress()       │   │                        │
│   ↓                    │   │                        │
│ handler.post {         │   │                        │
│   eventSink.success()  │   │                        │
│ }                      │   │                        │
└────────┬───────────────┘   └────────┬───────────────┘
         │                            │
         └──────────┬─────────────────┘
                    │ EventChannel
                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│ LAYER 5: Dart Service (iperf3_service.dart)                        │
│                                                                     │
│ EventChannel receives platform message                             │
│         ↓                                                           │
│ Stream emits Map<String, dynamic>:                                 │
│ {                                                                  │
│   "interval": 1,                                                  │
│   "bytesTransferred": 42500000,                                   │
│   "bitsPerSecond": 340000000.0,                                   │
│   "mbps": 340.0,          ← Server's actual receive rate         │
│   "jitter": 0.042,        ← Server measured                       │
│   "lostPackets": 3        ← Server detected                       │
│ }                                                                  │
└──────────────────────┬──────────────────────────────────────────────┘
                       │ Stream subscription
                       ↓
┌─────────────────────────────────────────────────────────────────────┐
│ LAYER 6: Flutter UI (main.dart)                                    │
│                                                                     │
│ _listenToProgress() stream listener                                │
│         ↓                                                           │
│ Receives progress map                                              │
│         ↓                                                           │
│ setState(() {                                                       │
│   _currentProgress = progress;                                     │
│ })                                                                  │
│         ↓                                                           │
│ Widget rebuilds                                                     │
│         ↓                                                           │
│ UI displays:                                                        │
│   "340.00 Mbits/sec"     ← THE LIVE UPLOAD SPEED!                │
│   "Jitter: 0.04 ms"                                               │
│   "Lost Packets: 3"                                               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## UDP Download Flow (Server → Client)

### Overview

**Configuration:** `reverse: true`, `useUdp: true`

**Direction:** Server sends to client

**Key Point:** Client measures throughput locally (no network round-trip for stats)

---

### Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│ LAYER 1: iperf3 Library (C)                                        │
│                                                                     │
│ Server sending UDP packets to client at target rate                │
│         ↓                                                           │
│ Client receives packets                                            │
│         ↓                                                           │
│ Client measures LOCALLY:                                           │
│   • Actual receive rate: 340 Mbps                                 │
│   • Jitter: 0.128 ms                                              │
│   • Lost packets: 50                                              │
│         ↓                                                           │
│ Client creates JSON interval (no network communication needed):    │
│ {                                                                  │
│   "intervals": [{                                                 │
│     "sum": {                                                      │
│       "bits_per_second": 340000000.0,  ← Client's receive rate   │
│       "jitter_ms": 0.128,              ← Client measured          │
│       "lost_packets": 50               ← Client detected          │
│     }                                                             │
│   }]                                                              │
│ }                                                                  │
│         ↓                                                           │
│ iperf3 calls: test->reporter_callback(test)                       │
└──────────────────────┬──────────────────────────────────────────────┘
                       │ Every ~1 second
                       ↓
┌─────────────────────────────────────────────────────────────────────┐
│ LAYER 2: iperf3_bridge.c (Shared C Bridge)                         │
│                                                                     │
│ bridge_reporter_callback() called                                  │
│         ↓                                                           │
│ Extract interval: test->json_intervals[idx]                        │
│         ↓                                                           │
│ Get sum object: intervals[idx].sum                                 │
│         ↓                                                           │
│ Parse values:                                                       │
│   double bits_per_second = sum["bits_per_second"]  // 340000000.0 │
│   double jitter = sum["jitter_ms"]                 // 0.128       │
│   double lost_packets = sum["lost_packets"]        // 50          │
│         ↓                                                           │
│ Fire callback:                                                      │
│   g_progress_callback(                                             │
│     context,                                                        │
│     1,                 // Interval number                          │
│     42500000,          // Bytes                                    │
│     340000000.0,       // bits_per_second ← THE DOWNLOAD SPEED!   │
│     0.128,             // jitter                                   │
│     50,                // lost_packets                             │
│     0.0                // rtt (N/A for UDP)                        │
│   )                                                                 │
└──────────────────────┬──────────────────────────────────────────────┘
                       │ Same flow as upload from here
                       ↓
              Platform Bridge → Dart → UI
                       ↓
         UI displays: "340.00 Mbits/sec" ← THE LIVE DOWNLOAD SPEED!
```

---

## Key Differences: Upload vs Download

| Aspect | UDP Upload | UDP Download |
|--------|------------|--------------|
| **Sender** | Client | Server |
| **Receiver** | Server | Client |
| **Who measures?** | Server | Client (local) |
| **Stats source** | Server sends back to client | Client already has it |
| **Network delay** | Yes (control connection) | No (local measurement) |
| **Latency** | ~100-500ms | ~10-50ms |
| **JSON field** | `intervals[n].sum` | `intervals[n].sum` |
| **Proof of source** | Contains `jitter_ms` (only receiver knows) | Contains `jitter_ms` (only receiver knows) |

---

## Timeline Comparison

### UDP Upload Timeline

```
Time 0.0s:  Test starts
            Client begins sending UDP packets to server

Time 1.0s:  Interval 1 completes
            Server: "I received 340 Mbps with 0.042ms jitter, 3 lost"
            Server sends stats to client (network delay: 50-200ms)
            Client receives server stats
            iperf3 creates interval JSON with server data
            bridge_reporter_callback() fires
            Platform layers forward
            UI updates: "340.00 Mbits/sec"
            Total latency: ~150-250ms

Time 2.0s:  Interval 2 completes
            (Same flow)
            UI updates: "338.50 Mbits/sec"
```

### UDP Download Timeline

```
Time 0.0s:  Test starts
            Server begins sending UDP packets to client

Time 1.0s:  Interval 1 completes
            Client: "I received 340 Mbps with 0.128ms jitter, 50 lost"
            Client creates interval JSON immediately (no network wait)
            bridge_reporter_callback() fires
            Platform layers forward
            UI updates: "340.00 Mbits/sec"
            Total latency: ~20-70ms (FASTER!)

Time 2.0s:  Interval 2 completes
            (Same flow)
            UI updates: "342.10 Mbits/sec"
```

---

## Thread Flow Diagram

### Android Thread Flow

```
┌──────────────────────┐
│ iperf3 Reporter      │  [Background thread created by iperf3]
│ Thread               │
└──────────┬───────────┘
           │ C callback
           ↓
┌──────────────────────┐
│ JNI progressCallback │  [Same iperf3 thread]
└──────────┬───────────┘
           │ env->CallVoidMethod
           ↓
┌──────────────────────┐
│ Kotlin onProgress    │  [Same iperf3 thread]
└──────────┬───────────┘
           │ progressHandler.sendProgress()
           ↓
┌──────────────────────┐
│ Handler.post { }     │  [Schedules on main thread]
└──────────┬───────────┘
           │
           ↓
┌──────────────────────┐
│ Android Main Thread  │  [UI thread]
│ eventSink.success()  │
└──────────┬───────────┘
           │ Platform channel
           ↓
┌──────────────────────┐
│ Flutter Platform     │  [Platform thread]
│ Thread               │
└──────────┬───────────┘
           │ EventChannel
           ↓
┌──────────────────────┐
│ Dart Isolate         │  [Dart main isolate]
│ Stream listener      │
└──────────┬───────────┘
           │ setState()
           ↓
┌──────────────────────┐
│ Flutter UI Thread    │  [Same as Dart isolate]
│ Widget rebuild       │
└──────────────────────┘
```

### iOS Thread Flow

```
┌──────────────────────┐
│ iperf3 Reporter      │  [Background thread created by iperf3]
│ Thread               │
└──────────┬───────────┘
           │ C callback
           ↓
┌──────────────────────┐
│ C wrapper function   │  [Same iperf3 thread]
└──────────┬───────────┘
           │ dispatch_async(main_queue)
           ↓
┌──────────────────────┐
│ iOS Main Queue       │  [Main thread]
│ Block executes       │
└──────────┬───────────┘
           │ progressCallback block
           ↓
┌──────────────────────┐
│ eventSink()          │  [Same main thread]
└──────────┬───────────┘
           │ Platform channel
           ↓
┌──────────────────────┐
│ Flutter Platform     │  [Platform thread]
│ Thread               │
└──────────┬───────────┘
           │ EventChannel
           ↓
┌──────────────────────┐
│ Dart Isolate         │  [Dart main isolate]
│ Stream listener      │
└──────────┬───────────┘
           │ setState()
           ↓
┌──────────────────────┐
│ Flutter UI Thread    │  [Same as Dart isolate]
│ Widget rebuild       │
└──────────────────────┘
```

---

## Data Transformation Diagram

### Type Conversions Through Layers

```
iperf3 Library (C)
    double bits_per_second = 340000000.0
    double jitter_ms = 0.042
    int lost_packets = 3
            ↓
Shared C Bridge
    Same types (C doubles, ints)
            ↓
    ┌───────────────┴────────────────┐
    ↓ ANDROID                        ↓ iOS
JNI Bridge                    Objective-C Bridge
    (jdouble)340000000.0          @(340000000.0)  // NSNumber
    (jdouble)0.042                @(0.042)
    (jint)3                       @(3)
            ↓                             ↓
Kotlin/Obj-C Handler
    Double = 340000000.0          NSNumber
    Double = 0.042                NSNumber
    Int = 3                       NSNumber
            ↓                             ↓
EventChannel
    Map<String, Any>              NSDictionary
    {                             {
      "mbps": 340.0,                @"mbps": @340.0,
      "jitter": 0.042,              @"jitter": @0.042,
      "lostPackets": 3              @"lostPackets": @3
    }                             }
            ↓                             ↓
            └─────────┬───────────────────┘
                      ↓
            Dart (Flutter)
            Map<String, dynamic>
            {
              "mbps": 340.0,        // double
              "jitter": 0.042,      // double
              "lostPackets": 3      // int
            }
                      ↓
            UI Display
            String = "340.00 Mbits/sec"
            String = "Jitter: 0.04 ms"
            String = "Lost Packets: 3"
```

---

## Summary

### Upload (Client → Server)

1. Server measures throughput
2. Server sends stats to client (network delay)
3. Client receives and displays
4. Latency: ~150-250ms

### Download (Server → Client)

1. Client measures throughput locally
2. No network wait for stats
3. Client displays immediately
4. Latency: ~20-70ms (faster!)

### Common Flow

Both go through same 6-layer architecture:
1. iperf3 → 2. C Bridge → 3. Platform Bridge → 4. Platform Handler → 5. Dart Service → 6. Flutter UI

### Thread Safety

- Android: Handler posts to main thread
- iOS: dispatch_async to main queue
- Flutter: EventChannel handles threading automatically
