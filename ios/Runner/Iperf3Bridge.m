//
//  Iperf3Bridge.m
//  Runner
//
//  Created by Claude Code
//

#import "Iperf3Bridge.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>
#import <arpa/inet.h>

// Import iperf3 C bridge
#import "iperf3_bridge.h"

@implementation Iperf3ResultObjC
@end

@implementation Iperf3Bridge {
    // Store context for C callbacks
    void *_progressContext;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _progressContext = (__bridge void *)self;
    }
    return self;
}

#pragma mark - C Callback Bridge

// C function that bridges to Objective-C callback
static void iperf3_progress_callback_wrapper(void *context,
                                              int interval,
                                              long bytes_transferred,
                                              double bits_per_second,
                                              double jitter,
                                              int lost_packets,
                                              double rtt) {
    if (!context) return;

    Iperf3Bridge *bridge = (__bridge Iperf3Bridge *)context;
    if (bridge.progressCallback) {
        // Call Objective-C callback on main thread for UI updates
        dispatch_async(dispatch_get_main_queue(), ^{
            bridge.progressCallback(interval,
                                   bytes_transferred,
                                   bits_per_second,
                                   jitter,
                                   lost_packets,
                                   rtt);
        });
    }
}

#pragma mark - Public Methods

- (Iperf3ResultObjC *)runClientWithHost:(NSString *)host
                                    port:(NSInteger)port
                                duration:(NSInteger)duration
                                parallel:(NSInteger)parallel
                                 reverse:(BOOL)reverse
                                  useUdp:(BOOL)useUdp
                               bandwidth:(long long)bandwidth {

    NSLog(@"Iperf3Bridge: Running client test to %@:%ld", host, (long)port);
    NSLog(@"Iperf3Bridge: Protocol: %@, Duration: %lds, Streams: %ld",
          useUdp ? @"UDP" : @"TCP", (long)duration, (long)parallel);

    // Run iperf3 test (blocking call) with progress callback
    Iperf3Result *c_result = iperf3_run_client_test(
        [host UTF8String],
        (int)port,
        (int)duration,
        (int)parallel,
        reverse ? 1 : 0,
        useUdp ? 1 : 0,
        bandwidth,
        iperf3_progress_callback_wrapper,
        _progressContext
    );

    // Convert C result to Objective-C object
    Iperf3ResultObjC *result = [[Iperf3ResultObjC alloc] init];

    if (c_result) {
        result.success = c_result->success ? YES : NO;

        if (c_result->jsonOutput) {
            result.jsonOutput = [NSString stringWithUTF8String:c_result->jsonOutput];
        }

        if (c_result->errorMessage) {
            result.errorMessage = [NSString stringWithUTF8String:c_result->errorMessage];
        }

        result.errorCode = c_result->errorCode;
        result.sendMbps = c_result->sendMbps;
        result.receiveMbps = c_result->receiveMbps;
        result.sentBytes = (long long)(c_result->sendMbps * duration * 1000000 / 8);
        result.receivedBytes = (long long)(c_result->receiveMbps * duration * 1000000 / 8);

        // Free C result structure
        iperf3_free_result(c_result);

        NSLog(@"Iperf3Bridge: Test completed - Success: %@", result.success ? @"YES" : @"NO");
        if (!result.success && result.errorMessage) {
            NSLog(@"Iperf3Bridge: Error: %@", result.errorMessage);
        }
    } else {
        result.success = NO;
        result.errorMessage = @"Failed to create iperf3 test result";
        result.errorCode = -1;
        NSLog(@"Iperf3Bridge: Failed to get result from C layer");
    }

    return result;
}

- (void)cancelClient {
    NSLog(@"Iperf3Bridge: Cancelling client test");
    iperf3_request_client_cancel();
}

- (NSString *)getVersion {
    const char *version = iperf3_get_version_string();
    if (version) {
        return [NSString stringWithUTF8String:version];
    }
    return @"Unknown";
}

- (nullable NSString *)getDefaultGateway {
    NSLog(@"Iperf3Bridge: getDefaultGateway not yet implemented for iOS");
    // TODO: Implement iOS-specific gateway detection
    // SCDynamicStore APIs are macOS only
    // On iOS, we need to use different approach or return nil
    return nil;
}

@end
