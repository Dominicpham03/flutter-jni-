#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NATIVE_DIR="$SCRIPT_DIR/Runner/Native"
BUILD_DIR="$SCRIPT_DIR/build/native"
IPERF3_LIB="$SCRIPT_DIR/iperf3_lib"

# Create build directory
mkdir -p "$BUILD_DIR"

echo "Compiling native C bridge..."

# Get the SDK path
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
MIN_IOS_VERSION="12.0"

# Compiler flags for iOS
CFLAGS="-arch arm64 -isysroot $SDK_PATH -mios-version-min=$MIN_IOS_VERSION -fembed-bitcode -I$IPERF3_LIB -I$NATIVE_DIR/iperf3"

# Compile iperf3_bridge.c
xcrun clang -c "$NATIVE_DIR/iperf3_bridge.c" -o "$BUILD_DIR/iperf3_bridge.o" $CFLAGS

# Compile Iperf3Bridge.m
xcrun clang -c "$SCRIPT_DIR/Runner/Iperf3Bridge.m" -o "$BUILD_DIR/Iperf3Bridge.o" $CFLAGS \
    -fobjc-arc -framework Foundation -framework SystemConfiguration

# Compile Iperf3Plugin.m  
xcrun clang -c "$SCRIPT_DIR/Runner/Iperf3Plugin.m" -o "$BUILD_DIR/Iperf3Plugin.o" $CFLAGS \
    -fobjc-arc -framework Foundation -framework Flutter

echo "Native compilation complete!"
