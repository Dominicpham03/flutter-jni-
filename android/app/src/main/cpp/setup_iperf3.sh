#!/bin/bash

# Script to download and set up iperf3 source code for Android build

IPERF3_VERSION="3.19"
IPERF3_URL="https://github.com/esnet/iperf/archive/refs/tags/${IPERF3_VERSION}.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Downloading iperf3 version ${IPERF3_VERSION}..."
cd "$SCRIPT_DIR"

# Download iperf3 source
curl -L "$IPERF3_URL" -o iperf3.tar.gz

# Extract
echo "Extracting iperf3..."
tar -xzf iperf3.tar.gz

# Rename directory
mv "iperf-${IPERF3_VERSION}" iperf3

# Create config.h for Android
echo "Creating config.h for Android..."
cat > iperf3/src/iperf_config.h << 'EOF'
#ifndef IPERF_CONFIG_H
#define IPERF_CONFIG_H

#define PACKAGE_NAME "iperf"
#define PACKAGE_VERSION "3.19"
#define IPERF_VERSION "3.19"

// Android specific configurations
#define HAVE_CONFIG_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_ARPA_INET_H 1
#define HAVE_NETDB_H 1
#define HAVE_UNISTD_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_PTHREAD_H 1
#define HAVE_SELECT 1
#define HAVE_GETTIMEOFDAY 1

// Disable SCTP for Android
#undef HAVE_SCTP_H

#endif
EOF

# Clean up
rm iperf3.tar.gz

echo "iperf3 setup complete!"
echo "iperf3 source is now in: $SCRIPT_DIR/iperf3"
