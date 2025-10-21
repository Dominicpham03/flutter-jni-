#ifndef IPERF3_BRIDGE_H
#define IPERF3_BRIDGE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Platform-agnostic iperf3 bridge interface
// This header can be used by both Android (JNI) and iOS (Objective-C++)

typedef struct {
    bool success;
    double sentBitsPerSecond;
    double receivedBitsPerSecond;
    double sendMbps;
    double receiveMbps;
    double rtt;         // Mean RTT in milliseconds (TCP only)
    double jitter;      // Jitter in milliseconds (UDP only)
    char* jsonOutput;
    char* errorMessage;
    int errorCode;
} Iperf3Result;

// Progress callback function type
typedef void (*Iperf3ProgressCallback)(
    void* context,
    int interval,
    long bytesTransferred,
    double bitsPerSecond,
    double jitter,
    int lostPackets,
    double rtt
);

// Core iperf3 wrapper functions
Iperf3Result* iperf3_run_client_test(
    const char* host,
    int port,
    int duration,
    int parallel,
    bool reverse,
    bool use_udp,
    long bandwidth,  // Target bandwidth in bits/sec (for UDP, 0 = unlimited)
    Iperf3ProgressCallback progressCallback,
    void* callbackContext
);

void iperf3_request_client_cancel(void);
bool iperf3_start_server_test(int port, bool use_udp);
bool iperf3_stop_server_test(void);
const char* iperf3_get_version_string(void);

// Cleanup function
void iperf3_free_result(Iperf3Result* result);

#ifdef __cplusplus
}
#endif

#endif // IPERF3_BRIDGE_H
