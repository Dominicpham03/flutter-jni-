# Flutter/Dart Interval Updates Explanation

## Overview

The Flutter layer receives interval updates from native platforms (Android/iOS) via EventChannel and displays them in the UI.

## Files

1. **iperf3_service.dart** - Service layer providing Stream
2. **main.dart** - UI layer displaying updates

---

## Architecture Flow

```
Native Platform (Android/iOS)
        ↓ EventChannel
Dart Service (iperf3_service.dart)
        ↓ Stream<Map<String, dynamic>>
UI Widget (main.dart)
        ↓ setState()
Widget Tree Rebuild
        ↓
Display Updated Speed
```

---

## Layer 1: Dart Service (iperf3_service.dart)

### Purpose

Provide a clean Stream interface for interval updates from native platform.

### Key Components

#### EventChannel Declaration

**Lines 7-8:**

```dart
static const MethodChannel _channel =
    MethodChannel('com.example.hello_world_app/iperf3');

static const EventChannel _progressChannel =
    EventChannel('com.example.hello_world_app/iperf3_progress');
```

**MethodChannel:** For request/response (runClient, cancelClient, etc.)

**EventChannel:** For continuous stream (interval updates)

---

### Progress Stream Provider

**Function:** `getProgressStream()` (Lines 242-250)

```dart
Stream<Map<String, dynamic>>? _progressStream;

Stream<Map<String, dynamic>> getProgressStream() {
    // Create stream only once (singleton pattern)
    _progressStream ??= _progressChannel
        .receiveBroadcastStream()
        .map((event) {
            // Type-safe conversion from dynamic to Map<String, dynamic>
            if (event is Map) {
                return Map<String, dynamic>.from(event);
            }
            return <String, dynamic>{};
        });

    return _progressStream!;
}
```

---

### Stream Characteristics

**Type:** `Stream<Map<String, dynamic>>`

**Pattern:** Broadcast stream (multiple listeners supported)

**Data format:**
```dart
{
  "interval": 1,
  "bytesTransferred": 1250000,
  "bitsPerSecond": 10000000.0,
  "mbps": 10.0,
  "jitter": 0.042,        // UDP only
  "lostPackets": 3        // UDP only
  // or
  "rtt": 2.5              // TCP only
}
```

---

### Why Broadcast Stream?

**Normal stream:** Single listener only

**Broadcast stream:** Multiple listeners allowed

**Use case:**
```dart
// Multiple widgets can listen
_service.getProgressStream().listen(...);  // Widget 1
_service.getProgressStream().listen(...);  // Widget 2
```

**Created by:** `receiveBroadcastStream()`

---

### Type Safety

**Why map?**

```dart
.map((event) {
    if (event is Map) {
        return Map<String, dynamic>.from(event);
    }
    return <String, dynamic>{};
})
```

**Without map:**
- `event` type is `dynamic`
- No compile-time type checking
- Runtime errors possible

**With map:**
- Returns `Map<String, dynamic>`
- Type-safe access: `progress['mbps']`
- IDE autocomplete support

---

## Layer 2: UI Widget (main.dart)

### Purpose

Subscribe to progress stream and display live updates in UI.

### Key Components

#### State Variables

**Lines 49-52:**

```dart
// Results
Map<String, dynamic>? _testResults;        // Final results after test
String? _errorMessage;                     // Error if test fails
Map<String, dynamic>? _currentProgress;    // Live progress (updated every ~1 sec)
```

**Key difference:**
- `_testResults`: Set once when test completes
- `_currentProgress`: Updated continuously during test

---

### Stream Subscription Setup

**Function:** `_listenToProgress()` (Lines 68-114)

**Called from:** `initState()` (Line 64)

```dart
@override
void initState() {
    super.initState();
    _serverHostController.addListener(...);
    _listenToProgress();  // ← Subscribe to progress stream
    _initializeDefaultGateway();
}
```

**Why initState?**
- Called once when widget is created
- Perfect for setting up stream subscriptions
- Ensures listener is active before test starts

---

### Stream Listener Implementation

```dart
void _listenToProgress() {
    _iperf3Service.getProgressStream().listen((progress) {
        // 1. Check if widget still mounted
        if (!mounted) return;

        // 2. Update state
        setState(() {
            final status = progress['status'];

            // Check if this is a status message or progress data
            if (status is String) {
                // Handle status messages (starting, completed, error, etc.)
                switch (status) {
                    case 'starting':
                        _currentProgress = null;
                        _canCancel = false;
                        break;

                    case 'running':
                        _errorMessage = null;
                        break;

                    case 'completed':
                        _canCancel = false;
                        break;

                    case 'cancelled':
                        _canCancel = false;
                        _errorMessage = 'Test cancelled by user.';
                        _testResults = null;
                        break;

                    case 'error':
                        final message = (details is Map && details['message'] != null)
                            ? details['message'].toString()
                            : 'iperf3 test failed';
                        _errorMessage = message;
                        _testResults = null;
                        _canCancel = false;
                        break;
                }
            } else {
                // This is interval progress data!
                _currentProgress = progress;  // ← Replace old with new

                // Enable cancel button once first interval arrives
                if (_isRunning && !_canCancel) {
                    _canCancel = true;
                }
            }
        });
    });
}
```

---

### Progress vs Status Messages

**Status message:**
```dart
{
  "status": "starting",
  "details": {...}
}
```

**Progress message:**
```dart
{
  "interval": 1,
  "mbps": 10.0,
  "jitter": 0.042,
  ...
}
```

**Differentiation:**
```dart
if (progress['status'] is String) {
    // It's a status message
} else {
    // It's progress data
}
```

---

### Single Active Display

**Pattern:**

```dart
_currentProgress = progress;  // Replaces previous, not appends
```

**Result:**
- Only latest interval shown
- No history accumulation
- Lower memory usage
- Simpler UI

**Example timeline:**
```
Time 1s: _currentProgress = {"interval": 1, "mbps": 10.0}
Time 2s: _currentProgress = {"interval": 2, "mbps": 9.5}  // Replaced!
Time 3s: _currentProgress = {"interval": 3, "mbps": 10.2} // Replaced!
```

---

### UI Display

**Function:** `build()` (Lines 462-538)

```dart
// Live Progress Card
if (_currentProgress != null) ...[
    Card(
        elevation: 4,
        child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    // Header
                    Row(
                        children: [
                            Icon(Icons.trending_up, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                                'Live Test Progress',
                                style: Theme.of(context).textTheme.titleLarge,
                            ),
                        ],
                    ),
                    const SizedBox(height: 16),

                    // Interval number
                    Row(
                        children: [
                            Text('Interval:', style: Theme.of(context).textTheme.bodyLarge),
                            const SizedBox(width: 8),
                            CircleAvatar(
                                backgroundColor: Colors.blue,
                                child: Text(
                                    '${_currentProgress!['interval']}',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                            ),
                        ],
                    ),

                    const SizedBox(height: 12),

                    // Speed - THE LIVE UPLOAD/DOWNLOAD SPEED!
                    Text(
                        '${_currentProgress!['mbps']?.toStringAsFixed(2)} Mbits/sec',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                        ),
                    ),

                    const SizedBox(height: 8),

                    // Protocol-specific metrics
                    // TCP: RTT
                    if (_currentProgress!.containsKey('rtt') && _currentProgress!['rtt'] > 0)
                        Text(
                            'RTT: ${_currentProgress!['rtt']?.toStringAsFixed(2)} ms',
                            style: Theme.of(context).textTheme.bodyMedium,
                        ),

                    // UDP: Jitter and Packet Loss
                    if (_currentProgress!.containsKey('jitter'))
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text(
                                    'Jitter: ${_currentProgress!['jitter']?.toStringAsFixed(2)} ms',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                if (_currentProgress!.containsKey('lostPackets'))
                                    Text(
                                        'Lost Packets: ${_currentProgress!['lostPackets']}',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                            ],
                        ),

                    // Bytes transferred (optional)
                    if (_currentProgress!.containsKey('bytesTransferred'))
                        Text(
                            'Bytes: ${(_currentProgress!['bytesTransferred'] / 1024 / 1024).toStringAsFixed(2)} MB',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                        ),
                ],
            ),
        ),
    ),
    const SizedBox(height: 16),
]
```

---

### Conditional Rendering

**Only show if progress exists:**

```dart
if (_currentProgress != null) ...[
    // Progress card
]
```

**Why?**
- Before test starts: `_currentProgress = null` → No card shown
- During test: `_currentProgress` updated → Card appears and updates
- After test ends: Card remains with last interval

---

### Protocol-Specific Display

**UDP detection:**

```dart
if (_currentProgress!.containsKey('jitter'))
    // Show jitter and lost packets
```

**TCP detection:**

```dart
if (_currentProgress!.containsKey('rtt') && _currentProgress!['rtt'] > 0)
    // Show RTT
```

**Why this works:**
- Native layer only includes `jitter` for UDP
- Native layer only includes `rtt` for TCP
- Dart can detect protocol from available keys

---

## State Management

### setState() Explained

**What it does:**

```dart
setState(() {
    _currentProgress = progress;
});
```

1. Updates state variable
2. Marks widget as dirty
3. Schedules rebuild
4. Flutter rebuilds widget tree
5. UI updates with new data

**Result:** UI shows new speed value

---

### Mounted Check

**Why needed:**

```dart
if (!mounted) return;
```

**Problem without check:**
```dart
// Widget disposed
stream.listen((progress) {
    setState(() { ... });  // ERROR! Widget no longer in tree
});
```

**Solution:**
```dart
stream.listen((progress) {
    if (!mounted) return;  // Don't call setState if disposed
    setState(() { ... });
});
```

---

## Complete User Flow Example

### UDP Upload Test at 10 Mbps

**User Action:** Taps "Run Test" button

**Step 1: Test Starts**

```dart
Future<void> _runTest() async {
    setState(() {
        _isRunning = true;
        _testResults = null;
        _errorMessage = null;
        _currentProgress = null;  // Clear previous progress
        _canCancel = false;
    });

    final result = await _iperf3Service.runClient(...);
    // ... handle result
}
```

**UI State:** Loading indicator, no progress card

---

**Step 2: First Interval (1 second)**

**Native sends:**
```dart
{
  "interval": 1,
  "bytesTransferred": 1250000,
  "bitsPerSecond": 10000000.0,
  "mbps": 10.0,
  "jitter": 0.042,
  "lostPackets": 3
}
```

**Stream listener receives:**
```dart
_listenToProgress() {
    stream.listen((progress) {
        setState(() {
            _currentProgress = progress;
            _canCancel = true;  // Enable cancel button
        });
    });
}
```

**UI updates:**
- Progress card appears
- Shows: "Interval: 1"
- Shows: "10.00 Mbits/sec"
- Shows: "Jitter: 0.04 ms"
- Shows: "Lost Packets: 3"
- Cancel button enabled

---

**Step 3: Second Interval (2 seconds)**

**Native sends:**
```dart
{
  "interval": 2,
  "mbps": 9.5,
  "jitter": 0.05,
  "lostPackets": 5
}
```

**UI updates:**
- Shows: "Interval: 2"
- Shows: "9.50 Mbits/sec" ← Updated!
- Shows: "Jitter: 0.05 ms"
- Shows: "Lost Packets: 5"

---

**Step 4: Test Completes (10 seconds)**

**Native sends final result:**

```dart
{
  "success": true,
  "sendMbps": 9.87,
  "receiveMbps": 0.0,
  "jitter": 0.045,
  "lostPackets": 42,
  ...
}
```

**UI updates:**
```dart
setState(() {
    _testResults = result;
    _isRunning = false;
    _canCancel = false;
});
```

- Progress card remains (last interval)
- Results card appears
- Shows final summary

---

## Error Handling

### Widget Lifecycle Safety

**Scenario:** User navigates away during test

**Without check:**
```dart
// Widget disposed, but stream still active
stream.listen((progress) {
    setState(() { ... });  // CRASH!
});
```

**With check:**
```dart
stream.listen((progress) {
    if (!mounted) return;  // Safe exit
    setState(() { ... });
});
```

---

### Null Safety

**Safe access:**

```dart
'${_currentProgress!['mbps']?.toStringAsFixed(2)} Mbits/sec'
```

**Why `!` and `?`:**
- `_currentProgress!` - We know it's not null (inside `if` check)
- `['mbps']?` - Value might be null or missing (safe navigation)

---

### Type Safety

**Safe type check:**

```dart
if (_currentProgress!.containsKey('jitter'))
```

**Safer than:**

```dart
if (_currentProgress!['jitter'] != null)  // Works but less clear
```

---

## Performance Optimization

### Stream Singleton

**Pattern:**

```dart
_progressStream ??= _progressChannel.receiveBroadcastStream()...
```

**Why?**
- Create stream only once
- Reuse for multiple listeners
- Lower memory overhead

---

### setState Efficiency

**Only update what changed:**

```dart
setState(() {
    _currentProgress = progress;  // Minimal state change
});
```

**Flutter optimizes:**
- Only rebuilds affected widgets
- Progress card rebuilds
- Other widgets unchanged

---

## Debugging

### Add Debug Logs

**In listener:**

```dart
void _listenToProgress() {
    _iperf3Service.getProgressStream().listen((progress) {
        print('=== Interval Update ===');
        print('Data: $progress');
        print('Interval: ${progress['interval']}');
        print('Mbps: ${progress['mbps']}');
        print('Jitter: ${progress['jitter']}');
        print('Lost Packets: ${progress['lostPackets']}');
        print('======================');

        if (!mounted) return;
        setState(() {
            _currentProgress = progress;
        });
    });
}
```

---

### Check Stream Events

**Count updates:**

```dart
int _updateCount = 0;

void _listenToProgress() {
    _iperf3Service.getProgressStream().listen((progress) {
        _updateCount++;
        print('Update #$_updateCount: ${progress['mbps']} Mbps');
        // ...
    });
}
```

**Expected:** ~10 updates for 10-second test

---

## Common Issues

### Issue: No Progress Updates

**Symptoms:** UI shows "Running..." but no live speed

**Check:**

1. **Stream subscribed?**
   ```dart
   @override
   void initState() {
       _listenToProgress();  // Must be here
   }
   ```

2. **Mounted check not blocking?**
   ```dart
   if (!mounted) {
       print('Widget not mounted!');  // Debug
       return;
   }
   ```

3. **Progress card conditional?**
   ```dart
   if (_currentProgress != null) {  // Check this condition
       print('Showing progress: $_currentProgress');
   }
   ```

---

### Issue: Updates Stop After First Interval

**Symptoms:** Shows interval 1, then freezes

**Possible causes:**

1. **setState not called:**
   ```dart
   setState(() {
       print('setState called');  // Add debug
       _currentProgress = progress;
   });
   ```

2. **Widget disposed:**
   ```dart
   if (!mounted) {
       print('Widget disposed!');
       return;
   }
   ```

---

### Issue: Wrong Data Displayed

**Symptoms:** Shows 0.00 Mbps or strange values

**Debug:**

```dart
void _listenToProgress() {
    stream.listen((progress) {
        print('Raw progress: $progress');
        print('mbps type: ${progress['mbps'].runtimeType}');
        print('mbps value: ${progress['mbps']}');
    });
}
```

---

## Summary

**Flutter interval updates use 2 files:**

1. **iperf3_service.dart**
   - EventChannel setup
   - Stream provider
   - Type-safe conversion

2. **main.dart**
   - Stream subscription
   - setState() updates
   - UI display

**Data flow:** EventChannel → Stream → Listener → setState → UI rebuild

**Update pattern:** Replace previous (not accumulate)

**Display:** Single live card showing latest interval

**Frequency:** ~1 update per second during test

**Thread safety:** Automatic (Flutter handles threading)
