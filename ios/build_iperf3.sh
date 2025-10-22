#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
IPERF3_SRC="$SCRIPT_DIR/Runner/Native/iperf3"
BUILD_DIR="$SCRIPT_DIR/build/iperf3"
INSTALL_DIR="$SCRIPT_DIR/iperf3_lib"

# Clean previous builds
rm -rf "$BUILD_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$INSTALL_DIR"

echo "Building iperf3 for iOS..."

# Get the SDK path
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
MIN_IOS_VERSION="12.0"

# Compiler flags for iOS
export CFLAGS="-arch arm64 -isysroot $SDK_PATH -mios-version-min=$MIN_IOS_VERSION -fembed-bitcode"
export LDFLAGS="-arch arm64 -isysroot $SDK_PATH"

cd "$IPERF3_SRC"

# Compile iperf3 source files into object files
SOURCES=(
    "cjson.c"
    "dscp.c"
    "iperf_api.c"
    "iperf_auth.c"
    "iperf_client_api.c"
    "iperf_error.c"
    "iperf_locale.c"
    "iperf_pthread.c"
    "iperf_sctp.c"
    "iperf_server_api.c"
    "iperf_tcp.c"
    "iperf_time.c"
    "iperf_udp.c"
    "iperf_util.c"
    "net.c"
    "tcp_info.c"
    "timer.c"
    "units.c"
)

OBJS=()
for src in "${SOURCES[@]}"; do
    obj="$BUILD_DIR/$(basename $src .c).o"
    echo "Compiling $src..."
    xcrun clang -c "$src" -o "$obj" $CFLAGS -I. -DHAVE_CONFIG_H
    OBJS+=("$obj")
done

# Create static library
echo "Creating static library..."
xcrun ar rcs "$INSTALL_DIR/libiperf.a" "${OBJS[@]}"

# Copy headers
echo "Copying headers..."
cp *.h "$INSTALL_DIR/" 2>/dev/null || true

echo "iperf3 build complete!"
echo "Library: $INSTALL_DIR/libiperf.a"
