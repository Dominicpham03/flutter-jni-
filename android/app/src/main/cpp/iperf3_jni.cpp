#include <jni.h>
#include <string>
#include <android/log.h>

// Include our shared platform-agnostic bridge
#include "iperf3_bridge.h"

#define LOG_TAG "iperf3_jni"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Helper function to create a Java HashMap
jobject createHashMap(JNIEnv* env) {
    jclass hashMapClass = env->FindClass("java/util/HashMap");
    jmethodID hashMapInit = env->GetMethodID(hashMapClass, "<init>", "()V");
    return env->NewObject(hashMapClass, hashMapInit);
}

// Helper function to put values in HashMap
void putInHashMap(JNIEnv* env, jobject hashMap, const char* key, jobject value) {
    jclass hashMapClass = env->FindClass("java/util/HashMap");
    jmethodID putMethod = env->GetMethodID(hashMapClass, "put",
                                           "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jstring jKey = env->NewStringUTF(key);
    env->CallObjectMethod(hashMap, putMethod, jKey, value);
    env->DeleteLocalRef(jKey);
}

// Helper to create Java Double
jobject createDouble(JNIEnv* env, double value) {
    jclass doubleClass = env->FindClass("java/lang/Double");
    jmethodID doubleInit = env->GetMethodID(doubleClass, "<init>", "(D)V");
    return env->NewObject(doubleClass, doubleInit, value);
}

// Helper to create Java Integer
jobject createInteger(JNIEnv* env, int value) {
    jclass integerClass = env->FindClass("java/lang/Integer");
    jmethodID integerInit = env->GetMethodID(integerClass, "<init>", "(I)V");
    return env->NewObject(integerClass, integerInit, value);
}

// Helper to create Java Boolean
jobject createBoolean(JNIEnv* env, bool value) {
    jclass booleanClass = env->FindClass("java/lang/Boolean");
    jmethodID booleanInit = env->GetMethodID(booleanClass, "<init>", "(Z)V");
    return env->NewObject(booleanClass, booleanInit, value);
}

// Progress callback context structure
struct ProgressContext {
    JNIEnv* env;
    jobject bridge;
};

// C callback function that will be called from iperf3 bridge
void progressCallback(void* context, int interval, long bytesTransferred,
                     double bitsPerSecond, double jitter, int lostPackets, double rtt) {
    ProgressContext* ctx = (ProgressContext*)context;
    if (!ctx || !ctx->env || !ctx->bridge) return;

    JNIEnv* env = ctx->env;
    jobject bridge = ctx->bridge;

    // Get the Java class and method
    jclass bridgeClass = env->GetObjectClass(bridge);
    jmethodID onProgressMethod = env->GetMethodID(bridgeClass, "onProgress", "(IJDDID)V");

    if (onProgressMethod) {
        env->CallVoidMethod(bridge, onProgressMethod,
            (jint)interval,
            (jlong)bytesTransferred,
            (jdouble)bitsPerSecond,
            (jdouble)jitter,
            (jint)lostPackets,
            (jdouble)rtt
        );
    }
}

// JNI function: Run iperf3 client
extern "C" JNIEXPORT jobject JNICALL
Java_com_example_hello_1world_1app_Iperf3Bridge_nativeRunClient(
        JNIEnv* env,
        jobject thiz,
        jstring host,
        jint port,
        jint duration,
        jint parallel,
        jboolean reverse,
        jboolean useUdp,
        jlong bandwidth) {

    const char* hostStr = env->GetStringUTFChars(host, nullptr);

    LOGI("JNI: nativeRunClient called");
    LOGI("JNI: Parameters - host=%s, port=%d, duration=%d, parallel=%d, reverse=%s, protocol=%s, bandwidth=%lld",
         hostStr, port, duration, parallel,
         reverse == JNI_TRUE ? "true" : "false",
         useUdp == JNI_TRUE ? "UDP" : "TCP",
         (long long)bandwidth);

    // Set up progress callback context
    ProgressContext progressCtx = {env, thiz};

    // Call our shared C bridge function with progress callback
    LOGD("JNI: Calling iperf3_run_client_test...");
    Iperf3Result* bridgeResult = iperf3_run_client_test(
        hostStr,
        port,
        duration,
        parallel,
        reverse == JNI_TRUE,
        useUdp == JNI_TRUE,
        bandwidth,
        progressCallback,
        &progressCtx
    );
    LOGD("JNI: iperf3_run_client_test returned");

    env->ReleaseStringUTFChars(host, hostStr);

    // Convert C result to Java HashMap
    LOGD("JNI: Converting result to Java HashMap...");
    jobject result = createHashMap(env);

    if (bridgeResult->success) {
        LOGI("JNI: Test successful, building result map");
        putInHashMap(env, result, "success", createBoolean(env, true));
        putInHashMap(env, result, "sentBitsPerSecond", createDouble(env, bridgeResult->sentBitsPerSecond));
        putInHashMap(env, result, "receivedBitsPerSecond", createDouble(env, bridgeResult->receivedBitsPerSecond));
        putInHashMap(env, result, "sendMbps", createDouble(env, bridgeResult->sendMbps));
        putInHashMap(env, result, "receiveMbps", createDouble(env, bridgeResult->receiveMbps));

        // Add protocol-specific metrics
        if (bridgeResult->rtt > 0) {
            // TCP: RTT data
            LOGD("JNI: Adding RTT data: %.2f ms", bridgeResult->rtt);
            putInHashMap(env, result, "rtt", createDouble(env, bridgeResult->rtt));
        }
        if (bridgeResult->jitter > 0) {
            // UDP: Jitter data
            LOGD("JNI: Adding jitter data: %.2f ms", bridgeResult->jitter);
            putInHashMap(env, result, "jitter", createDouble(env, bridgeResult->jitter));
        }

        if (bridgeResult->jsonOutput) {
            LOGD("JNI: Adding JSON output");
            putInHashMap(env, result, "jsonOutput", env->NewStringUTF(bridgeResult->jsonOutput));
        }
    } else {
        LOGE("JNI: Test failed with error code %d", bridgeResult->errorCode);
        putInHashMap(env, result, "success", createBoolean(env, false));
        if (bridgeResult->errorMessage) {
            LOGE("JNI: Error message: %s", bridgeResult->errorMessage);
            putInHashMap(env, result, "error", env->NewStringUTF(bridgeResult->errorMessage));
        }
        putInHashMap(env, result, "errorCode", createInteger(env, bridgeResult->errorCode));
    }

    // Clean up
    LOGD("JNI: Cleaning up bridge result...");
    iperf3_free_result(bridgeResult);

    LOGI("JNI: nativeRunClient completed, returning result");
    return result;
}

// JNI function: Cancel iperf3 client
extern "C" JNIEXPORT void JNICALL
Java_com_example_hello_1world_1app_Iperf3Bridge_nativeCancelClient(
        JNIEnv* env,
        jobject thiz) {
    LOGI("JNI: nativeCancelClient called");
    iperf3_request_client_cancel();
}

// JNI function: Start iperf3 server
extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_hello_1world_1app_Iperf3Bridge_nativeStartServer(
        JNIEnv* env,
        jobject thiz,
        jint port,
        jboolean useUdp) {

    bool success = iperf3_start_server_test(port, useUdp == JNI_TRUE);
    return success ? JNI_TRUE : JNI_FALSE;
}

// JNI function: Stop iperf3 server
extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_hello_1world_1app_Iperf3Bridge_nativeStopServer(
        JNIEnv* env,
        jobject thiz) {

    bool success = iperf3_stop_server_test();
    return success ? JNI_TRUE : JNI_FALSE;
}

// JNI function: Get iperf3 version
extern "C" JNIEXPORT jstring JNICALL
Java_com_example_hello_1world_1app_Iperf3Bridge_nativeGetVersion(
        JNIEnv* env,
        jobject thiz) {

    const char* version = iperf3_get_version_string();
    return env->NewStringUTF(version);
}
