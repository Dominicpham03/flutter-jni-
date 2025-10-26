#include "iperf3_bridge.h"
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <stdio.h>
#include <signal.h>

// Include iperf3 headers
#include "iperf.h"
#include "iperf_api.h"
#include "iperf_config.h"
#include "cjson.h"

// Include Android compatibility shims and logging
#ifdef __ANDROID__
#include "android_pthread_compat.h"
#include <android/log.h>
#define LOG_TAG "iperf3_bridge"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define LOGD(...) fprintf(stderr, "DEBUG: " __VA_ARGS__); fprintf(stderr, "\n")
#define LOGI(...) fprintf(stderr, "INFO: " __VA_ARGS__); fprintf(stderr, "\n")
#define LOGW(...) fprintf(stderr, "WARN: " __VA_ARGS__); fprintf(stderr, "\n")
#define LOGE(...) fprintf(stderr, "ERROR: " __VA_ARGS__); fprintf(stderr, "\n")
#endif

// Platform-agnostic implementation of iperf3 bridge
// This code is shared between Android and iOS

// Global progress callback storage
static Iperf3ProgressCallback g_progress_callback = NULL;
static void* g_progress_context = NULL;

typedef void (*IperfReporterCallbackFn)(struct iperf_test *);
static IperfReporterCallbackFn g_original_reporter_callback = NULL;
static int g_last_reported_interval = 0;

static pthread_mutex_t g_client_mutex = PTHREAD_MUTEX_INITIALIZER;
static struct iperf_test* g_active_client_test = NULL;
static volatile sig_atomic_t g_cancel_client_requested = 0;

static double get_json_number(cJSON* object, const char* name, double fallback) {
    if (!object || !name) {
        return fallback;
    }
    cJSON* item = cJSON_GetObjectItemCaseSensitive(object, name);
    return (item && cJSON_IsNumber(item)) ? item->valuedouble : fallback;
}

static cJSON* get_interval_sum(cJSON* interval) {
    if (!interval) {
        return NULL;
    }
    cJSON* sum = cJSON_GetObjectItemCaseSensitive(interval, "sum");
    if (!sum) {
        sum = cJSON_GetObjectItemCaseSensitive(interval, "sum_sent");
    }
    if (!sum) {
        sum = cJSON_GetObjectItemCaseSensitive(interval, "sum_received");
    }
    return sum;
}

static void bridge_reporter_callback(struct iperf_test *test) {
    if (g_original_reporter_callback) {
        g_original_reporter_callback(test);
    }

    if (!g_progress_callback || !test || !test->json_intervals) {
        return;
    }

    int interval_count = cJSON_GetArraySize(test->json_intervals);
    if (interval_count <= g_last_reported_interval) {
        return;
    }

    for (int idx = g_last_reported_interval; idx < interval_count; ++idx) {
        cJSON* interval = cJSON_GetArrayItem(test->json_intervals, idx);
        cJSON* sum = get_interval_sum(interval);
        if (!sum) {
            continue;
        }

        double bytes = get_json_number(sum, "bytes", 0.0);
        double bits_per_second = get_json_number(sum, "bits_per_second", 0.0);
        double jitter = get_json_number(sum, "jitter_ms", 0.0);
        double lost_packets = get_json_number(sum, "lost_packets", 0.0);

        g_progress_callback(
            g_progress_context,
            idx + 1,
            (long)bytes,
            bits_per_second,
            jitter,
            (int)lost_packets,
            0.0
        );
    }

    g_last_reported_interval = interval_count;
}

Iperf3Result* iperf3_run_client_test(
    const char* host,
    int port,
    int duration,
    int parallel,
    bool reverse,
    bool use_udp,
    long bandwidth,
    Iperf3ProgressCallback progressCallback,
    void* callbackContext) {

    LOGI("=== iperf3 Client Test Starting ===");
    LOGI("Host: %s, Port: %d, Duration: %d sec", host, port, duration);
    LOGI("Protocol: %s, Parallel: %d, Reverse: %s", use_udp ? "UDP" : "TCP", parallel, reverse ? "yes" : "no");
    if (bandwidth > 0) {
        LOGI("Bandwidth limit: %ld bits/sec (%.2f Mbits/sec)", bandwidth, bandwidth / 1000000.0);
    }

    Iperf3Result* result = (Iperf3Result*)malloc(sizeof(Iperf3Result));
    memset(result, 0, sizeof(Iperf3Result));

    // Store callback for use during test
    g_progress_callback = progressCallback;
    g_progress_context = callbackContext;

    // Create and configure iperf3 test
    LOGD("Creating iperf3 test instance...");
    struct iperf_test* test = iperf_new_test();
    if (!test) {
        LOGE("Failed to create iperf3 test instance");
        result->success = false;
        result->errorMessage = strdup("Failed to create iperf3 test");
        return result;
    }
    LOGD("iperf3 test instance created successfully");

    iperf_defaults(test);
    LOGD("Setting client mode...");
    iperf_set_test_role(test, 'c'); // Client mode
    LOGD("Configuring test parameters...");
    iperf_set_test_server_hostname(test, host);
    iperf_set_test_server_port(test, port);
    iperf_set_test_duration(test, duration);
    iperf_set_test_num_streams(test, parallel);
    iperf_set_test_reverse(test, reverse ? 1 : 0);

    // Enable JSON output - CRITICAL for getting results!
    iperf_set_test_json_output(test, 1);
    LOGD("JSON output enabled");

    // Hook reporter callback so we can emit per-interval updates after iperf processes them.
    g_original_reporter_callback = test->reporter_callback;
    g_last_reported_interval = 0;
    test->reporter_callback = bridge_reporter_callback;

    LOGD("Test parameters configured");

    // Set protocol: UDP or TCP
    if (use_udp) {
        LOGI("Setting protocol to UDP");
        int proto_result = set_protocol(test, Pudp);
        if (proto_result != 0) {
            LOGE("Failed to set UDP protocol! Error code: %d, i_errno: %d", proto_result, i_errno);
            char* err_msg = iperf_strerror(i_errno);
            LOGE("Protocol error: %s", err_msg ? err_msg : "unknown");
            result->success = false;
            result->errorMessage = strdup(err_msg ? err_msg : "Failed to set UDP protocol");
            result->errorCode = proto_result;
            iperf_free_test(test);
            return result;
        }
        LOGI("UDP protocol set successfully");

        // Let iperf pick an MTU-friendly payload instead of TCP's default block size.
        iperf_set_test_blksize(test, 0);

        // Set bandwidth for UDP (-b flag)
        // UDP REQUIRES a target bandwidth, default is 1 Mbit/sec if not specified
        if (bandwidth > 0) {
            LOGI("Setting UDP bandwidth to %ld bps (%.2f Mbits/sec)", bandwidth, bandwidth / 1000000.0);
            iperf_set_test_rate(test, bandwidth);
        } else {
            // UDP default: 1 Mbit/sec = 1,000,000 bits/sec
            LOGI("No bandwidth specified, using default UDP bandwidth: 1,000,000 bps (1 Mbit/sec)");
            iperf_set_test_rate(test, 1000000);
        }

        // Verify the rate was set
        uint64_t actual_rate = iperf_get_test_rate(test);
        LOGI("UDP rate verified: %llu bps (%.2f Mbits/sec)",
             (unsigned long long)actual_rate, actual_rate / 1000000.0);
    } else {
        LOGD("Setting protocol to TCP");
        int proto_result = set_protocol(test, Ptcp);
        if (proto_result != 0) {
            LOGE("Failed to set TCP protocol! Error code: %d, i_errno: %d", proto_result, i_errno);
            char* err_msg = iperf_strerror(i_errno);
            LOGE("Protocol error: %s", err_msg ? err_msg : "unknown");
            result->success = false;
            result->errorMessage = strdup(err_msg ? err_msg : "Failed to set TCP protocol");
            result->errorCode = proto_result;
            iperf_free_test(test);
            return result;
        }
        // TCP can also use bandwidth limiting if specified
        if (bandwidth > 0) {
            LOGD("Setting TCP bandwidth limit to %ld bps", bandwidth);
            iperf_set_test_rate(test, bandwidth);
        }
    }

    // Register this test as the active client so cancellation can target it.
    pthread_mutex_lock(&g_client_mutex);
    g_active_client_test = test;
    g_cancel_client_requested = 0;
    pthread_mutex_unlock(&g_client_mutex);

    // Run the test
    LOGI("Connecting to server %s:%d...", host, port);
    LOGI("Starting iperf3 client test...");
    i_errno = IENONE; // Reset global errno before running the client
    int result_code = iperf_run_client(test);
    LOGI("iperf3 client test completed with result code: %d", result_code);
    int final_errno = i_errno; // Capture errno immediately after the run

    pthread_mutex_lock(&g_client_mutex);
    int was_cancelled = g_cancel_client_requested;
    g_active_client_test = NULL;
    g_cancel_client_requested = 0;
    pthread_mutex_unlock(&g_client_mutex);

    // Post-test diagnostics
    LOGI("=== Post-Test Diagnostics ===");
    LOGI("Final test state: %d", test->state);
    LOGI("i_errno: %d", final_errno);
    if (final_errno != 0) {
        char* err = iperf_strerror(final_errno);
        LOGE("iperf3 error detected: %s", err ? err : "unknown");
    }

    // Check if streams were created
    int stream_count = 0;
    struct iperf_stream *sp;
    SLIST_FOREACH(sp, &test->streams, streams) {
        stream_count++;
        LOGI("Stream %d: socket=%d", stream_count, sp->socket);
        if (sp->result) {
            LOGI("  bytes_sent=%llu, bytes_received=%llu",
                 (unsigned long long)sp->result->bytes_sent,
                 (unsigned long long)sp->result->bytes_received);
            LOGI("  packets (if UDP): count=%llu", (unsigned long long)sp->packet_count);
        }
    }
    if (stream_count > 0) {
        LOGI("Total streams created: %d", stream_count);
    } else {
        LOGE("NO STREAMS CREATED - this is why no data was sent!");
    }

    // Log interval data for debugging
    LOGI("=== JSON Intervals Check ===");
    if (test->json_intervals != NULL) {
        int interval_count = cJSON_GetArraySize(test->json_intervals);
        LOGI("json_intervals pointer exists, array size: %d", interval_count);

        if (interval_count == 0) {
            LOGE("CRITICAL: json_intervals array is EMPTY!");
            LOGE("This means NO intervals were recorded during the entire %d second test", duration);
            LOGE("Possible causes:");
            LOGE("  1. Test never reached TEST_RUNNING state");
            LOGE("  2. Interval timer didn't fire");
            LOGE("  3. No data was sent/received so intervals weren't logged");
        } else {
            LOGI("Found %d intervals - logging data:", interval_count);
            for (int i = 0; i < interval_count; i++) {
                cJSON *interval = cJSON_GetArrayItem(test->json_intervals, i);
                if (interval) {
                    cJSON *sum = cJSON_GetObjectItem(interval, "sum");
                    if (sum) {
                        cJSON *bytes = cJSON_GetObjectItem(sum, "bytes");
                        cJSON *bits_per_second = cJSON_GetObjectItem(sum, "bits_per_second");
                        cJSON *packets = cJSON_GetObjectItem(sum, "packets");
                        cJSON *start = cJSON_GetObjectItem(sum, "start");
                        cJSON *end = cJSON_GetObjectItem(sum, "end");

                        LOGI("Interval %d (%.3f - %.3f sec):", i + 1,
                             start ? start->valuedouble : 0.0,
                             end ? end->valuedouble : 0.0);
                        LOGI("  bytes: %lld", bytes ? (long long)bytes->valuedouble : 0LL);
                        LOGI("  bits_per_second: %.2f (%.2f Mbps)",
                             bits_per_second ? bits_per_second->valuedouble : 0.0,
                             bits_per_second ? bits_per_second->valuedouble / 1000000.0 : 0.0);
                        LOGI("  packets: %lld", packets ? (long long)packets->valuedouble : 0LL);
                    }
                }
            }
        }
    } else {
        LOGD("json_intervals is NULL after test (cleaned up by iperf_json_finish)");
    }
    LOGI("=== End JSON Intervals Check ===");

    bool cancelled = was_cancelled != 0;

    if (cancelled) {
        LOGI("iperf3 client test was cancelled by caller");
        result->success = false;
        result->errorMessage = strdup("Test cancelled by user");
        result->errorCode = IECLIENTTERM;
        i_errno = IECLIENTTERM;
    } else if (result_code == 0 && final_errno == 0) {
        // True success: result_code is 0 AND no errno
        LOGI("Test succeeded! Retrieving results...");
        result->success = true;

        // Get JSON output which contains all results
        char* jsonOutput = iperf_get_test_json_output_string(test);
        if (jsonOutput) {
            size_t json_len = strlen(jsonOutput);
            LOGI("JSON output retrieved (length: %zu bytes)", json_len);

            // Log last 800 chars of JSON for debugging (shows the "end" section with results)
            if (json_len > 0) {
                char preview[801];
                size_t preview_len = json_len < 800 ? json_len : 800;
                size_t start_pos = json_len > 800 ? json_len - 800 : 0;

                strncpy(preview, jsonOutput + start_pos, preview_len);
                preview[preview_len] = '\0';

                LOGD("JSON preview (last %zu chars): %s%s",
                     preview_len,
                     json_len > 800 ? "..." : "",
                     preview);
            }

            result->jsonOutput = strdup(jsonOutput);

            // For now, set basic values to 0
            // The Flutter layer will parse JSON for detailed results
            result->sentBitsPerSecond = 0;
            result->receivedBitsPerSecond = 0;
            result->sendMbps = 0;
            result->receiveMbps = 0;
            result->rtt = 0;
            result->jitter = 0;
            LOGI("Results prepared successfully (values set to 0 - Flutter will parse JSON)");
        } else {
            LOGE("No JSON output available from iperf3");
            result->success = false;
            result->errorMessage = strdup("No JSON output available");
            result->errorCode = -1;
        }
    } else if (result_code == 0 && final_errno != 0) {
        // Test appeared to succeed (result_code 0) but i_errno indicates error
        // This happens with errors like "server busy" (errno 121)
        LOGE("iperf3 test completed with result_code 0 but i_errno=%d indicates error", final_errno);

        char* error = iperf_strerror(final_errno);
        if (error) {
            LOGE("iperf3 error: %s", error);
            result->errorMessage = strdup(error);
        } else {
            result->errorMessage = strdup("Test encountered an error");
        }

        result->success = false;
        result->errorCode = final_errno;
    } else {
        // result_code is non-zero (actual failure)
        LOGE("iperf3 test failed with error code: %d", result_code);

        // Try to get error message from iperf3
        char* error = iperf_strerror(final_errno);
        if (error) {
            LOGE("iperf3 error: %s", error);
            result->errorMessage = strdup(error);
        } else {
            result->errorMessage = strdup("iperf3 test failed");
        }

        result->success = false;
        result->errorCode = result_code;
    }

    // Clear errno so future runs start clean
    i_errno = IENONE;

    LOGD("Cleaning up iperf3 test instance...");
    iperf_free_test(test);
    g_original_reporter_callback = NULL;
    g_last_reported_interval = 0;
    g_progress_callback = NULL;
    g_progress_context = NULL;
    LOGI("=== iperf3 Client Test Finished ===");
    return result;
}

void iperf3_request_client_cancel(void) {
    pthread_mutex_lock(&g_client_mutex);
    if (g_active_client_test) {
        LOGI("Cancellation requested - signalling active iperf3 client to stop");
        g_cancel_client_requested = 1;
        g_active_client_test->done = 1;
        iperf_set_test_state(g_active_client_test, CLIENT_TERMINATE);
        if (iperf_set_send_state(g_active_client_test, CLIENT_TERMINATE) != 0) {
            LOGW("Failed to send CLIENT_TERMINATE state to server: %s",
                 iperf_strerror(i_errno));
        }
    } else {
        LOGD("Cancellation requested but no active client test is running");
    }
    pthread_mutex_unlock(&g_client_mutex);
}

// Global server instance
static struct iperf_test* g_server_test = NULL;
static pthread_t g_server_thread;
static bool g_server_running = false;

static void* server_thread_func(void* arg) {
    struct iperf_test* test = (struct iperf_test*)arg;
    iperf_run_server(test);
    return NULL;
}

bool iperf3_start_server_test(int port, bool use_udp) {
    if (g_server_running) {
        return false; // Server already running
    }

    g_server_test = iperf_new_test();
    if (!g_server_test) {
        return false;
    }

    iperf_defaults(g_server_test);
    iperf_set_test_role(g_server_test, 's'); // Server mode
    iperf_set_test_server_port(g_server_test, port);

    // Set protocol for server
    if (use_udp) {
        set_protocol(g_server_test, Pudp);
    } else {
        set_protocol(g_server_test, Ptcp);
    }

    int result = pthread_create(&g_server_thread, NULL, server_thread_func, g_server_test);
    if (result != 0) {
        iperf_free_test(g_server_test);
        g_server_test = NULL;
        return false;
    }

    g_server_running = true;
    return true;
}

bool iperf3_stop_server_test(void) {
    if (!g_server_running || !g_server_test) {
        return false;
    }

    // Note: pthread_cancel is not supported on Android
    // For now, we'll just wait for the thread to finish
    // A production implementation might need a signal mechanism
    #ifndef __ANDROID__
    pthread_cancel(g_server_thread);
    #endif
    pthread_join(g_server_thread, NULL);

    iperf_free_test(g_server_test);
    g_server_test = NULL;
    g_server_running = false;

    return true;
}

const char* iperf3_get_version_string(void) {
    return IPERF_VERSION;
}

void iperf3_free_result(Iperf3Result* result) {
    if (result) {
        if (result->jsonOutput) {
            free(result->jsonOutput);
        }
        if (result->errorMessage) {
            free(result->errorMessage);
        }
        free(result);
    }
}
