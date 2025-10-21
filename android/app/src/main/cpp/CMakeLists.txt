cmake_minimum_required(VERSION 3.10)

project(iperf3_jni)

# Set C/C++ standard
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Shared native code directory
set(NATIVE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native)

# iperf3 source directory (now in shared location)
set(IPERF3_SRC_DIR ${NATIVE_DIR}/iperf3/src)

# Build iperf3 as a static library from source
add_library(libiperf STATIC
    # Core iperf3 source files - we'll add the actual iperf3 source here
    ${IPERF3_SRC_DIR}/cjson.c
    ${IPERF3_SRC_DIR}/iperf_api.c
    ${IPERF3_SRC_DIR}/iperf_error.c
    ${IPERF3_SRC_DIR}/iperf_auth.c
    ${IPERF3_SRC_DIR}/iperf_client_api.c
    ${IPERF3_SRC_DIR}/iperf_server_api.c
    ${IPERF3_SRC_DIR}/iperf_tcp.c
    ${IPERF3_SRC_DIR}/iperf_udp.c
    ${IPERF3_SRC_DIR}/iperf_sctp.c
    ${IPERF3_SRC_DIR}/iperf_util.c
    ${IPERF3_SRC_DIR}/iperf_locale.c
    ${IPERF3_SRC_DIR}/iperf_time.c
    ${IPERF3_SRC_DIR}/dscp.c
    ${IPERF3_SRC_DIR}/net.c
    ${IPERF3_SRC_DIR}/tcp_info.c
    ${IPERF3_SRC_DIR}/timer.c
    ${IPERF3_SRC_DIR}/units.c
)

# Include directories for iperf3
target_include_directories(libiperf PUBLIC
    ${IPERF3_SRC_DIR}
    ${NATIVE_DIR}/iperf3/include
)

# Compile definitions for iperf3
target_compile_definitions(libiperf PRIVATE
    HAVE_CONFIG_H
    ANDROID
)

# Build shared bridge (platform-agnostic C code)
add_library(iperf3_bridge STATIC
    ${NATIVE_DIR}/src/iperf3_bridge.c
)

target_include_directories(iperf3_bridge PUBLIC
    ${NATIVE_DIR}/src
    ${IPERF3_SRC_DIR}
)

target_link_libraries(iperf3_bridge
    libiperf
)

# Build our JNI wrapper (Android-specific)
add_library(iperf3_jni SHARED
    iperf3_jni.cpp
)

# Include directories for JNI (Android NDK provides these automatically)
target_include_directories(iperf3_jni PRIVATE
    ${NATIVE_DIR}/src
    ${IPERF3_SRC_DIR}
)

# Link everything together
target_link_libraries(iperf3_jni
    iperf3_bridge
    libiperf
    log
    android
)
