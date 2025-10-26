# Shared C Bridge Explanation

## Overview

The shared C bridge is the **core interval update engine** used by both Android and iOS. It intercepts iperf3's reporter callback and extracts interval data.

## Files

### iperf3_bridge.c

**Purpose:** Platform-agnostic iperf3 wrapper with interval update support

**Key Components:**

1. **Reporter Callback Hook**
2. **Interval Data Extraction**
3. **Progress Callback System**

---

## How Interval Updates Work

### Step 1: Setup (Test Initialization)

```c
// In iperf3_run_client_test() - Line 157-160
g_original_reporter_callback = test->reporter_callback;
g_last_reported_interval = 0;
test->reporter_callback = bridge_reporter_callback;
```

**What happens:**
- Store iperf3's original callback
- Initialize interval counter to 0
- Replace callback with our custom `bridge_reporter_callback`

**Why:** This allows us to intercept iperf3's interval reports

---

### Step 2: iperf3 Calls Our Callback

**When:** After each ~1 second interval

**Function:** `bridge_reporter_callback()` (Lines 67-105)

```c
static void bridge_reporter_callback(struct iperf_test *test) {
    // 1. Call original iperf3 reporter first
    if (g_original_reporter_callback) {
        g_original_reporter_callback(test);
    }

    // 2. Safety checks
    if (!g_progress_callback || !test || !test->json_intervals) {
        return;
    }

    // 3. Count intervals
    int interval_count = cJSON_GetArraySize(test->json_intervals);
    if (interval_count <= g_last_reported_interval) {
        return;  // No new intervals
    }

    // 4. Process NEW intervals only
    for (int idx = g_last_reported_interval; idx < interval_count; ++idx) {
        // ... extract and report
    }

    // 5. Update counter
    g_last_reported_interval = interval_count;
}
```

---

### Step 3: Extract Interval Data

**Get the interval JSON object:**

```c
cJSON* interval = cJSON_GetArrayItem(test->json_intervals, idx);
```

**Interval structure:**
```json
{
  "sum": {
    "start": 0.0,
    "end": 1.0,
    "bytes": 1250000,
    "bits_per_second": 10000000.0,
    "jitter_ms": 0.042,
    "lost_packets": 3
  }
}
```

---

### Step 4: Get the Sum Object

**Function:** `get_interval_sum()` (Lines 53-65)

```c
static cJSON* get_interval_sum(cJSON* interval) {
    // Try "sum" first (UDP intervals)
    cJSON* sum = cJSON_GetObjectItemCaseSensitive(interval, "sum");

    // Fallback to "sum_sent" (TCP upload)
    if (!sum) {
        sum = cJSON_GetObjectItemCaseSensitive(interval, "sum_sent");
    }

    // Fallback to "sum_received" (TCP download)
    if (!sum) {
        sum = cJSON_GetObjectItemCaseSensitive(interval, "sum_received");
    }

    return sum;
}
```

**For different test types:**

| Test Type | JSON Field | Example |
|-----------|------------|---------|
| UDP Upload | `intervals[n].sum` | Server's receive stats |
| UDP Download | `intervals[n].sum` | Client's receive stats |
| TCP Upload | `intervals[n].sum_sent` or `sum` | Client's send stats |
| TCP Download | `intervals[n].sum_received` or `sum` | Client's receive stats |

---

### Step 5: Parse Metrics

**Function:** `get_json_number()` (Lines 45-51)

```c
static double get_json_number(cJSON* object, const char* name, double fallback) {
    if (!object || !name) {
        return fallback;
    }
    cJSON* item = cJSON_GetObjectItemCaseSensitive(object, name);
    return (item && cJSON_IsNumber(item)) ? item->valuedouble : fallback;
}
```

**Extract metrics (Lines 88-91):**

```c
double bytes = get_json_number(sum, "bytes", 0.0);
double bits_per_second = get_json_number(sum, "bits_per_second", 0.0);
double jitter = get_json_number(sum, "jitter_ms", 0.0);
double lost_packets = get_json_number(sum, "lost_packets", 0.0);
```

**Metrics explained:**

- **bytes:** Total bytes transferred this interval
- **bits_per_second:** Throughput in bits/sec (THE KEY METRIC!)
- **jitter_ms:** Packet delay variation (UDP only, receiver-measured)
- **lost_packets:** Lost packet count (UDP only, receiver-detected)

---

### Step 6: Fire Progress Callback

```c
g_progress_callback(
    g_progress_context,      // Platform context (JNI objects or Obj-C bridge)
    idx + 1,                 // Interval number (1-based: 1, 2, 3...)
    (long)bytes,             // Bytes transferred
    bits_per_second,         // Upload/download speed
    jitter,                  // Jitter (UDP)
    (int)lost_packets,       // Lost packets (UDP)
    0.0                      // RTT (would be used for TCP)
);
```

**What this does:**
- Calls platform-specific callback (JNI for Android, Obj-C for iOS)
- Platform layer converts and forwards to Flutter

---

## Global State Management

### Progress Callback Storage

```c
static Iperf3ProgressCallback g_progress_callback = NULL;
static void* g_progress_context = NULL;
```

**Set during test initialization:**
```c
g_progress_callback = progressCallback;
g_progress_context = callbackContext;
```

**Cleared after test:**
```c
g_progress_callback = NULL;
g_progress_context = NULL;
```

### Interval Counter

```c
static int g_last_reported_interval = 0;
```

**Purpose:** Track which intervals we've already reported

**Example:**
- After interval 0 processed: `g_last_reported_interval = 1`
- After interval 1 processed: `g_last_reported_interval = 2`
- Next callback processes from index 2 onwards

**Why needed:** Prevents duplicate reports if callback fires multiple times

---

## UDP Upload: Server Stats Flow

### The Question: How do we get server throughput?

**Answer:** Server sends stats back via control connection

**Step-by-step:**

1. **Client sends UDP packets** at target rate (e.g., 1.36 Gbps)

2. **Server receives packets** and measures:
   - Actual receive rate (e.g., 340 Mbps if network bottleneck)
   - Jitter (packet delay variation)
   - Packet loss

3. **Server sends stats to client** via TCP control connection

4. **iperf3 client includes server stats** in `intervals[n].sum`

5. **Our bridge extracts** `bits_per_second` from server data

**Proof it's server data:**
- `jitter_ms` can ONLY be measured by receiver (server)
- `lost_packets` can ONLY be detected by receiver (server)
- If these fields exist, `bits_per_second` is also from server

### JSON Evidence

```json
{
  "intervals": [
    {
      "sum": {
        "bits_per_second": 340000000.0,  // ← Server's actual receive rate
        "jitter_ms": 0.042,              // ← Server measured
        "lost_packets": 3                // ← Server detected
      }
    }
  ]
}
```

**This is NOT the client's send rate!** It's the server's actual measured throughput.

---

## UDP Download: Client Stats Flow

### Simpler Case: Local Measurement

**Step-by-step:**

1. **Server sends UDP packets** at target rate

2. **Client receives packets** and measures locally:
   - Actual receive rate
   - Jitter
   - Packet loss

3. **Client includes own stats** in `intervals[n].sum`

4. **Our bridge extracts** data immediately

**Advantage:** No network round-trip, lower latency

---

## Thread Safety

### Callback Execution

**Thread:** iperf3's reporter thread (internal to iperf3 library)

**Safety:**
- No shared state modified (only reads `test->json_intervals`)
- Callback registration happens before test starts
- Cleanup happens after test ends

### Platform Callback

**Android (JNI):**
- Executes on iperf3 thread
- JNI calls are thread-safe
- Kotlin layer posts to main thread

**iOS (Objective-C):**
- Executes on iperf3 thread
- Dispatches to main queue for UI safety

---

## Error Handling

### Safety Checks

```c
// Check callback registered
if (!g_progress_callback || !test || !test->json_intervals) {
    return;
}

// Check for new intervals
if (interval_count <= g_last_reported_interval) {
    return;
}

// Check sum object exists
cJSON* sum = get_interval_sum(interval);
if (!sum) {
    continue;  // Skip this interval
}
```

### Fallback Values

```c
double get_json_number(cJSON* object, const char* name, double fallback) {
    // Returns fallback (0.0) if:
    // - object is NULL
    // - name is NULL
    // - item not found
    // - item is not a number
}
```

---

## Integration Points

### Android Integration

**Callback:**
```c
void progressCallback(void* context, int interval, long bytesTransferred,
                     double bitsPerSecond, double jitter, int lostPackets, double rtt)
```

**Context:**
```cpp
struct ProgressContext {
    JNIEnv* env;
    jobject bridge;  // Kotlin Iperf3Bridge object
};
```

### iOS Integration

**Callback:**
```c
static void iperf3_progress_callback_wrapper(void *context, int interval,
                                             long bytes_transferred,
                                             double bits_per_second,
                                             double jitter, int lost_packets, double rtt)
```

**Context:**
```objc
void *_progressContext = (__bridge void *)self;  // Objective-C Iperf3Bridge
```

---

## Performance Characteristics

### Frequency

**Intervals:** ~1 second (iperf3's default)

**Adjustable?** Yes, via iperf3's `-i` flag (but requires iperf3 API modification)

### Latency

**UDP Download:**
- Client local measurement
- ~10-50ms from measurement to callback

**UDP Upload:**
- Server measures, sends to client
- ~100-500ms from measurement to callback (network dependent)

**TCP:**
- Similar to UDP

### Memory

**JSON Storage:**
- iperf3 stores all intervals in memory
- 10-second test = ~10 interval objects
- Each interval ~500 bytes
- Total: ~5KB for typical test

---

## Debug Logging

### Enabled for Android

```c
#ifdef __ANDROID__
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#endif
```

### Key Log Points

**Interval check:**
```c
LOGI("Found %d intervals - logging data:", interval_count);
```

**Interval data:**
```c
LOGI("Interval %d (%.3f - %.3f sec):", i + 1, start, end);
LOGI("  bytes: %lld", bytes);
LOGI("  bits_per_second: %.2f (%.2f Mbps)", bps, bps / 1000000.0);
LOGI("  packets: %lld", packets);
```

---

## Summary

**The shared C bridge:**

1. ✅ Hooks into iperf3's reporter callback system
2. ✅ Extracts interval JSON data automatically
3. ✅ Parses throughput, jitter, packet loss
4. ✅ Fires platform-specific progress callbacks
5. ✅ Tracks processed intervals to prevent duplicates
6. ✅ Thread-safe and error-resistant
7. ✅ Same code for Android and iOS

**For UDP upload:**
- `bits_per_second` = Server's actual receive rate (NOT client's send cap)
- Proof: jitter and packet loss are server-measured

**For UDP download:**
- `bits_per_second` = Client's actual receive rate
- Lower latency (local measurement)

**Data flows:** C bridge → Platform bridge → Platform handler → Dart → UI
