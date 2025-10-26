# iOS Interval Updates Explanation

## Overview

The iOS layer bridges between the shared C code and Flutter using Objective-C. It provides interval updates through EventChannel, similar to Android but with iOS-specific patterns.

## Files

1. **Iperf3Bridge.m** - Objective-C bridge (C to Flutter)
2. **Iperf3Bridge.h** - Objective-C header (if exists)

---

## Architecture Flow

```
Shared C Bridge (iperf3_bridge.c)
        ↓ g_progress_callback()
Objective-C Wrapper (Iperf3Bridge.m)
        ↓ dispatch_async(main_queue)
Progress Callback Block
        ↓ bridge.progressCallback()
Flutter Plugin (Iperf3Plugin.m)
        ↓ eventSink
Flutter EventChannel
        ↓ Stream<Map<String, dynamic>>
Dart Service (iperf3_service.dart)
```

---

## Layer 1: Objective-C Bridge (Iperf3Bridge.m)

### Purpose

Convert C callback to Objective-C block and dispatch to main thread.

### Key Components

#### Progress Context

```objc
@implementation Iperf3Bridge {
    void *_progressContext;  // Stores bridge instance for C callback
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _progressContext = (__bridge void *)self;  // Bridge self to C pointer
    }
    return self;
}
```

**What is `__bridge`?**
- Casts Objective-C object to C pointer (or vice versa)
- No memory management change
- Allows passing Obj-C object through C code

---

### C Callback Wrapper

**Function:** `iperf3_progress_callback_wrapper()` (Lines 37-58)

```objc
// Static C function that bridges to Objective-C
static void iperf3_progress_callback_wrapper(void *context,
                                              int interval,
                                              long bytes_transferred,
                                              double bits_per_second,
                                              double jitter,
                                              int lost_packets,
                                              double rtt) {
    // 1. Check context exists
    if (!context) return;

    // 2. Convert C pointer back to Objective-C object
    Iperf3Bridge *bridge = (__bridge Iperf3Bridge *)context;

    // 3. Check if callback block exists
    if (bridge.progressCallback) {
        // 4. Dispatch to main queue for UI safety
        dispatch_async(dispatch_get_main_queue(), ^{
            // 5. Call Objective-C callback block
            bridge.progressCallback(interval,
                                   bytes_transferred,
                                   bits_per_second,
                                   jitter,
                                   lost_packets,
                                   rtt);
        });
    }
}
```

---

### Why Static C Function?

**Problem:** C callbacks can't call Objective-C methods directly

**Solution:** Static C function acts as wrapper

**Flow:**
```
C code
  ↓ calls C function pointer
iperf3_progress_callback_wrapper (static C function)
  ↓ casts context to Obj-C
Iperf3Bridge instance (Objective-C object)
  ↓ calls block
progressCallback block
```

---

### Callback Registration

**When test starts (Lines 74-85):**

```objc
- (Iperf3ResultObjC *)runClientWithHost:(NSString *)host
                                    port:(NSInteger)port
                                duration:(NSInteger)duration
                                parallel:(NSInteger)parallel
                                 reverse:(BOOL)reverse
                                  useUdp:(BOOL)useUdp
                               bandwidth:(long long)bandwidth {

    // Call shared C bridge
    Iperf3Result *c_result = iperf3_run_client_test(
        [host UTF8String],
        (int)port,
        (int)duration,
        (int)parallel,
        reverse ? 1 : 0,
        useUdp ? 1 : 0,
        bandwidth,
        iperf3_progress_callback_wrapper,  // ← C callback function
        _progressContext                    // ← Self as C pointer
    );

    // ... process result
}
```

---

### Progress Callback Property

**Defined in header:**

```objc
@property (nonatomic, copy) void (^progressCallback)(int interval,
                                                      long bytes,
                                                      double bitsPerSecond,
                                                      double jitter,
                                                      int lostPackets,
                                                      double rtt);
```

**Set by plugin:**

```objc
bridge.progressCallback = ^(int interval, long bytes, double bitsPerSecond,
                           double jitter, int lostPackets, double rtt) {
    // Send to Flutter EventSink
    NSDictionary *progressData = @{
        @"interval": @(interval),
        @"bytesTransferred": @(bytes),
        @"bitsPerSecond": @(bitsPerSecond),
        @"mbps": @(bitsPerSecond / 1000000.0)
    };

    // Add protocol-specific metrics
    if (jitter > 0) {
        progressData[@"jitter"] = @(jitter);
        progressData[@"lostPackets"] = @(lostPackets);
    }
    if (rtt > 0) {
        progressData[@"rtt"] = @(rtt);
    }

    eventSink(progressData);
};
```

---

### Thread Safety: dispatch_async

**Why needed?**
- C callback executes on iperf3's reporter thread
- Flutter EventSink requires main thread
- UI updates must be on main thread

**dispatch_async(dispatch_get_main_queue(), ^{ ... })**

**What it does:**
- Schedules block execution on main thread
- Non-blocking (returns immediately)
- Block executes asynchronously

**Thread flow:**
```
iperf3 Reporter Thread
    ↓ C callback
iperf3_progress_callback_wrapper() [iperf3 thread]
    ↓ dispatch_async
Main Queue (scheduled)
    ↓ block executes
Main Thread
    ↓ progressCallback block
Flutter EventSink
```

---

### Type Conversions

**C types → Objective-C types:**

```objc
int interval           → @(interval)          // NSNumber
long bytes_transferred → @(bytes_transferred) // NSNumber
double bits_per_second → @(bits_per_second)  // NSNumber
double jitter          → @(jitter)           // NSNumber
int lost_packets       → @(lost_packets)     // NSNumber
double rtt             → @(rtt)              // NSNumber
```

**Objective-C → Flutter:**

```objc
NSDictionary → Map<String, dynamic> (automatic via platform channel)
```

---

## Layer 2: Flutter Plugin Integration

### EventChannel Setup

**In Iperf3Plugin.m:**

```objc
FlutterEventChannel* progressChannel = [FlutterEventChannel
    eventChannelWithName:@"com.example.hello_world_app/iperf3_progress"
    binaryMessenger:[registrar messenger]];

[progressChannel setStreamHandler:self];
```

---

### Stream Handler Implementation

```objc
- (FlutterError*)onListenWithArguments:(id)arguments
                             eventSink:(FlutterEventSink)events {
    _eventSink = events;  // Store event sink

    // Set up progress callback on bridge
    _bridge.progressCallback = ^(int interval, long bytes, double bitsPerSecond,
                                 double jitter, int lostPackets, double rtt) {
        // Format data
        NSMutableDictionary *progressData = [NSMutableDictionary dictionary];
        progressData[@"interval"] = @(interval);
        progressData[@"bytesTransferred"] = @(bytes);
        progressData[@"bitsPerSecond"] = @(bitsPerSecond);
        progressData[@"mbps"] = @(bitsPerSecond / 1000000.0);

        // Protocol-specific
        if (jitter > 0) {
            progressData[@"jitter"] = @(jitter);
            progressData[@"lostPackets"] = @(lostPackets);
        }
        if (rtt > 0) {
            progressData[@"rtt"] = @(rtt);
        }

        // Send to Flutter
        if (_eventSink) {
            _eventSink([progressData copy]);
        }
    };

    return nil;
}

- (FlutterError*)onCancelWithArguments:(id)arguments {
    _eventSink = nil;
    _bridge.progressCallback = nil;
    return nil;
}
```

---

## Complete Data Flow Example

### Timeline for UDP Upload at 10 Mbps

**Time: 0.0s - Test Starts**

```
1. Flutter calls runClient via MethodChannel
2. Iperf3Plugin receives call
3. Creates Iperf3Bridge instance
4. Sets progressCallback block
5. Calls bridge.runClientWithHost(...)
6. Bridge calls iperf3_run_client_test()
7. Passes iperf3_progress_callback_wrapper as callback
8. Passes _progressContext (self) as context
```

**Time: 1.0s - Interval 1 Complete**

```
C Layer (iperf3_bridge.c):
    - Interval complete
    - Extracts: bits_per_second = 10000000.0
    - Calls: g_progress_callback(_progressContext, 1, 1250000, 10000000.0, 0.042, 3, 0.0)

Objective-C Wrapper (Iperf3Bridge.m):
    iperf3_progress_callback_wrapper() receives C callback
        - context = void pointer to Iperf3Bridge instance
        - Casts: (__bridge Iperf3Bridge *)context
        - Checks: bridge.progressCallback exists
        - Dispatches: dispatch_async(dispatch_get_main_queue(), ^{ ... })

Main Thread (async block executes):
    - Calls: bridge.progressCallback(1, 1250000, 10000000.0, 0.042, 3, 0.0)

Plugin Layer (Iperf3Plugin.m):
    progressCallback block executes:
        - Creates NSDictionary:
          {
              "interval": 1,
              "bytesTransferred": 1250000,
              "bitsPerSecond": 10000000.0,
              "mbps": 10.0,
              "jitter": 0.042,
              "lostPackets": 3
          }
        - Calls: _eventSink(progressData)

Flutter Layer:
    - EventChannel receives dictionary
    - Converts to Map<String, dynamic>
    - Stream emits data
    - Dart listener receives
    - UI calls setState()
    - Displays: "10.00 Mbits/sec"
```

**Time: 2.0s - Interval 2 Complete**

Same flow, new values → UI updates to "9.50 Mbits/sec"

---

## Memory Management

### ARC (Automatic Reference Counting)

**Block copying:**
```objc
@property (nonatomic, copy) void (^progressCallback)(...);
```

**Why `copy`?**
- Blocks are stack-allocated by default
- `copy` moves block to heap
- Prevents deallocation when stack frame exits

**EventSink storage:**
```objc
@property (nonatomic, copy) FlutterEventSink _eventSink;
```

### Bridge Pattern

**`__bridge` cast:**
```objc
_progressContext = (__bridge void *)self;
```

**No retain/release:**
- Just a cast, no ownership change
- Safe because bridge instance outlives C callback
- Bridge instance destroyed only after test completes

---

## iOS-Specific Patterns

### Grand Central Dispatch (GCD)

**Main queue dispatch:**
```objc
dispatch_async(dispatch_get_main_queue(), ^{
    // Execute on main thread
});
```

**Why not synchronous?**
```objc
dispatch_sync(dispatch_get_main_queue(), ^{
    // This would block!
});
```

**Async is better:**
- Non-blocking
- Prevents deadlocks
- Better performance

---

### Blocks vs Functions

**Block (closure):**
```objc
^(int interval, long bytes, ...) {
    // Captures variables from surrounding scope
}
```

**Function (method):**
```objc
- (void)onProgress:(int)interval bytes:(long)bytes ... {
    // No capture, must pass all data as parameters
}
```

**Why blocks here?**
- Can capture `_eventSink`
- Cleaner syntax
- Flutter plugin API uses blocks

---

## Error Handling

### Null Checks

**In C wrapper:**
```objc
if (!context) return;
if (bridge.progressCallback) {
    // Only call if exists
}
```

**In block:**
```objc
if (_eventSink) {
    _eventSink(progressData);
}
```

### Thread Safety

**dispatch_async guarantees:**
- Main thread execution
- No race conditions with UI
- Proper EventSink access

---

## Debugging

### Enable Logs

**Add to Iperf3Bridge.m:**

```objc
NSLog(@"Iperf3Bridge: Progress callback - Interval %d, Mbps: %.2f",
      interval, bits_per_second / 1000000.0);
```

**In wrapper:**

```objc
static void iperf3_progress_callback_wrapper(...) {
    NSLog(@"C callback wrapper called: interval=%d, bps=%.2f",
          interval, bits_per_second);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Main thread block executing");
        bridge.progressCallback(...);
    });
}
```

### View Logs

**Xcode:**
- Console window shows NSLog output
- Filter by "Iperf3" or "Progress"

**Command line:**
```bash
xcrun simctl spawn booted log stream --level debug | grep -i iperf
```

---

## Performance Notes

### Latency

**Thread transitions:**
- iperf3 thread → C wrapper [~1-5ms]
- C wrapper → Main thread (dispatch_async) [~5-15ms]
- Main thread → Flutter [~5-10ms]
- **Total:** ~10-30ms from C callback to Dart

**Overall latency:**
- UDP download: ~20-80ms (C measurement to UI)
- UDP upload: ~120-580ms (server measurement + network + UI)

### Memory

**Per interval:**
- NSDictionary: ~300 bytes
- Block capture: ~100 bytes
- Total: ~400 bytes per interval

**10-second test:**
- 10 intervals × 400 bytes = ~4KB
- Negligible

---

## Differences from Android

| Aspect | Android (JNI + Kotlin) | iOS (Objective-C) |
|--------|----------------------|-------------------|
| **Bridge language** | C++ (JNI) | Objective-C |
| **Callback mechanism** | JNI method invocation | Objective-C block |
| **Thread dispatch** | `Handler.post()` | `dispatch_async()` |
| **Data structure** | `Map<String, Any>` | `NSDictionary` |
| **Type conversion** | Manual (jint, jlong, etc.) | Automatic (NSNumber) |
| **Memory management** | GC (Kotlin) | ARC (Objective-C) |
| **Latency** | ~10-25ms | ~10-30ms |

---

## Common Issues

### Issue: No Progress Updates

**Check:**

1. **EventChannel registered?**
   ```objc
   [progressChannel setStreamHandler:self];
   ```

2. **progressCallback set?**
   ```objc
   _bridge.progressCallback = ^(...) { ... };
   ```

3. **eventSink not nil?**
   ```objc
   if (_eventSink) {
       _eventSink(progressData);
   }
   ```

4. **Stream subscribed in Dart?**
   ```dart
   _iperf3Service.getProgressStream().listen(...)
   ```

### Issue: Callback Not Firing

**Symptoms:** C wrapper called but block doesn't execute

**Possible causes:**

1. **progressCallback nil:**
   ```objc
   NSLog(@"progressCallback: %@", _bridge.progressCallback);
   ```

2. **dispatch_async issue:**
   ```objc
   NSLog(@"Before dispatch_async");
   dispatch_async(dispatch_get_main_queue(), ^{
       NSLog(@"Inside dispatch block");
   });
   ```

3. **Context invalid:**
   ```objc
   NSLog(@"Context: %p, Bridge: %@", context, bridge);
   ```

### Issue: Crashes

**Common causes:**

1. **eventSink called after cancelled:**
   ```objc
   if (_eventSink) {  // Always check!
       _eventSink(progressData);
   }
   ```

2. **Block accessing deallocated variables:**
   - Use `copy` property attribute
   - Blocks must be heap-allocated

3. **Wrong thread for EventSink:**
   - Always use dispatch_async to main queue

---

## Summary

**iOS interval updates use Objective-C bridge:**

1. **Iperf3Bridge.m**
   - C callback wrapper (static function)
   - Objective-C block property
   - Main thread dispatch via GCD
   - Type conversions (C → Obj-C)

**Data flow:** C → Obj-C wrapper → Main thread → Block → EventSink → Dart

**Thread flow:** iperf3 thread → Main queue (via dispatch_async) → Dart isolate

**Latency:** ~10-30ms from C callback to Flutter UI

**Key differences from Android:**
- Uses blocks instead of JNI
- Uses GCD instead of Handler
- Automatic type conversions (NSNumber)
- ARC instead of GC
