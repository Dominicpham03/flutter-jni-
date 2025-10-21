# iperf3 Native Library Integration Guide

## Architecture Overview

This Flutter app integrates iperf3 using the following architecture:

```
Flutter (Dart)
    ↓
MethodChannel
    ↓
Kotlin (Android)
    ↓
JNI Bridge (C++)
    ↓
iperf3 Native Library (C)
```

## Components

### 1. **Dart Layer** ([lib/iperf3_service.dart](lib/iperf3_service.dart))
- Provides Flutter-friendly API for iperf3 operations
- Uses MethodChannel to communicate with native code
- Methods: `runClient()`, `startServer()`, `stopServer()`, `getVersion()`

### 2. **Kotlin Layer** ([android/app/src/main/kotlin/.../MainActivity.kt](android/app/src/main/kotlin/com/example/hello_world_app/MainActivity.kt))
- Handles MethodChannel calls from Dart
- Delegates to Iperf3Bridge for actual work
- Manages Flutter engine configuration

### 3. **Kotlin JNI Bridge** ([android/app/src/main/kotlin/.../Iperf3Bridge.kt](android/app/src/main/kotlin/com/example/hello_world_app/Iperf3Bridge.kt))
- Loads native library (`libiperf3_jni.so`)
- Declares native method signatures
- Provides Kotlin-friendly wrappers

### 4. **C++ JNI Implementation** ([android/app/src/main/cpp/iperf3_jni.cpp](android/app/src/main/cpp/iperf3_jni.cpp))
- Implements JNI native methods
- Calls iperf3 C API functions
- Handles data conversion between Java and C types

### 5. **Build System** ([android/app/src/main/cpp/CMakeLists.txt](android/app/src/main/cpp/CMakeLists.txt))
- Builds iperf3 from source as static library
- Compiles JNI wrapper
- Links everything together

## Setup Instructions

### Step 1: Download and Set Up iperf3 Source

```bash
cd android/app/src/main/cpp
./setup_iperf3.sh
```

This will:
- Download iperf3 version 3.19 from GitHub
- Extract and prepare the source code
- Create necessary configuration files for Android

### Step 2: Verify Directory Structure

After running the setup script, your directory structure should look like:

```
android/app/src/main/cpp/
├── CMakeLists.txt
├── iperf3/
│   └── src/
│       ├── iperf_api.c
│       ├── iperf_api.h
│       ├── iperf_config.h
│       └── ... (other iperf3 source files)
├── iperf3_jni.cpp
└── setup_iperf3.sh
```

### Step 3: Build the Project

```bash
cd /Users/dominicpham/flut/hello_world_app
flutter build apk
```

Or for development:

```bash
flutter run
```

The Android build system will:
1. Compile iperf3 C source files into a static library
2. Compile the JNI wrapper (iperf3_jni.cpp)
3. Link them together into `libiperf3_jni.so`
4. Package the .so file into the APK

### Step 4: Usage Example

```dart
import 'package:hello_world_app/iperf3_service.dart';

final iperf3 = Iperf3Service();

// Run client test
try {
  final result = await iperf3.runClient(
    serverHost: '192.168.1.100',
    port: 5201,
    durationSeconds: 10,
    parallelStreams: 1,
    reverse: false,
  );

  print('Send speed: ${result['sendMbps']} Mbps');
  print('Receive speed: ${result['receiveMbps']} Mbps');
} catch (e) {
  print('Error: $e');
}

// Get version
String version = await iperf3.getVersion();
print('iperf3 version: $version');
```

## Troubleshooting

### Issue: CMake can't find iperf3 source files

**Solution**: Make sure you ran `setup_iperf3.sh` and the `iperf3/src` directory exists.

### Issue: Build fails with "undefined reference" errors

**Solution**: Check that all iperf3 source files are listed in `CMakeLists.txt`. You may need to add/remove files based on the actual iperf3 source structure.

### Issue: JNI method not found

**Solution**: Verify the JNI method naming convention. The format is:
```
Java_com_example_hello_1world_1app_Iperf3Bridge_nativeMethodName
```
Note: underscores in package names become `_1` in JNI.

## Next Steps

1. **Update main.dart** to use the Iperf3Service
2. **Test on physical device** (network operations need real hardware)
3. **Add proper error handling** for network failures
4. **Implement UI** to display test results
5. **Add permissions** in AndroidManifest.xml:
   ```xml
   <uses-permission android:name="android.permission.INTERNET" />
   <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
   ```

## How the Architecture Works

1. **Dart calls Kotlin**: Flutter uses MethodChannel to invoke native methods
2. **Kotlin calls C++**: Kotlin declares `external` functions that are implemented in C++
3. **C++ calls iperf3**: JNI wrapper calls iperf3 C API functions
4. **Results flow back**: C++ converts results to Java objects → Kotlin → Dart

## Key Files Reference

| Layer | File | Purpose |
|-------|------|---------|
| Dart | [lib/iperf3_service.dart](lib/iperf3_service.dart) | Flutter API |
| Kotlin | [MainActivity.kt](android/app/src/main/kotlin/com/example/hello_world_app/MainActivity.kt) | MethodChannel handler |
| Kotlin | [Iperf3Bridge.kt](android/app/src/main/kotlin/com/example/hello_world_app/Iperf3Bridge.kt) | JNI bridge |
| C++ | [iperf3_jni.cpp](android/app/src/main/cpp/iperf3_jni.cpp) | JNI implementation |
| Build | [CMakeLists.txt](android/app/src/main/cpp/CMakeLists.txt) | Native build config |
| Build | [build.gradle.kts](android/app/build.gradle.kts) | Android build config |

## Performance Considerations

- iperf3 tests run on background threads (via pthread)
- Server mode runs in a separate thread to avoid blocking
- Results are marshalled efficiently through JNI
- Static linking reduces runtime dependencies

## Supported Architectures

The build is configured for:
- arm64-v8a (64-bit ARM)
- armeabi-v7a (32-bit ARM)
- x86 (32-bit Intel)
- x86_64 (64-bit Intel)
