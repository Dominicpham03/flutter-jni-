//
//  Iperf3Plugin.m
//  Runner
//
//  Created by Claude Code
//

#import "Iperf3Plugin.h"
#import "Iperf3Bridge.h"

@interface Iperf3Plugin()

@property (nonatomic, strong) Iperf3Bridge *bridge;
@property (nonatomic, strong) FlutterEventSink eventSink;
@property (nonatomic, strong) dispatch_queue_t testQueue;

@end

@implementation Iperf3Plugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    // Create MethodChannel for request/response
    FlutterMethodChannel *methodChannel = [FlutterMethodChannel
        methodChannelWithName:@"com.example.hello_world_app/iperf3"
        binaryMessenger:[registrar messenger]];

    // Create EventChannel for progress updates
    FlutterEventChannel *eventChannel = [FlutterEventChannel
        eventChannelWithName:@"com.example.hello_world_app/iperf3_progress"
        binaryMessenger:[registrar messenger]];

    // Create plugin instance
    Iperf3Plugin *instance = [[Iperf3Plugin alloc] init];

    // Register handlers
    [registrar addMethodCallDelegate:instance channel:methodChannel];
    [eventChannel setStreamHandler:instance];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _bridge = [[Iperf3Bridge alloc] init];
        _testQueue = dispatch_queue_create("com.example.hello_world_app.iperf3", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - FlutterPlugin

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSLog(@"Iperf3Plugin: Received method call: %@", call.method);

    if ([@"runClient" isEqualToString:call.method]) {
        [self handleRunClient:call result:result];
    } else if ([@"cancelClient" isEqualToString:call.method]) {
        [self handleCancelClient:call result:result];
    } else if ([@"getVersion" isEqualToString:call.method]) {
        [self handleGetVersion:call result:result];
    } else if ([@"getDefaultGateway" isEqualToString:call.method]) {
        [self handleGetDefaultGateway:call result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

#pragma mark - Method Handlers

- (void)handleRunClient:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSDictionary *args = call.arguments;

    NSString *host = args[@"host"] ?: @"";
    NSNumber *port = args[@"port"] ?: @5201;
    NSNumber *duration = args[@"duration"] ?: @10;
    NSNumber *parallel = args[@"parallel"] ?: @1;
    NSNumber *reverse = args[@"reverse"] ?: @NO;
    NSNumber *useUdp = args[@"useUdp"] ?: @NO;
    NSNumber *bandwidthBps = args[@"bandwidthBps"] ?: @0;

    NSLog(@"Iperf3Plugin: Starting client test to %@:%@", host, port);
    NSLog(@"Iperf3Plugin: Parameters - Duration:%@s, Streams:%@, Protocol:%@, Reverse:%@",
          duration, parallel, [useUdp boolValue] ? @"UDP" : @"TCP", [reverse boolValue] ? @"YES" : @"NO");

    // Send "starting" status
    [self sendStatus:@"starting" details:nil];

    // Run test on background queue
    dispatch_async(_testQueue, ^{
        // Send "running" status
        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendStatus:@"running" details:nil];
        });

        // Run the test (blocking call)
        Iperf3ResultObjC *testResult = [self.bridge runClientWithHost:host
                                                              port:[port integerValue]
                                                          duration:[duration integerValue]
                                                          parallel:[parallel integerValue]
                                                           reverse:[reverse boolValue]
                                                            useUdp:[useUdp boolValue]
                                                         bandwidth:[bandwidthBps longLongValue]];

        // Return result on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if (testResult.success) {
                NSLog(@"Iperf3Plugin: Test succeeded");
                [self sendStatus:@"completed" details:nil];

                result(@{
                    @"success": @YES,
                    @"jsonOutput": testResult.jsonOutput ?: @"",
                    @"sendMbps": @(testResult.sendMbps),
                    @"receiveMbps": @(testResult.receiveMbps),
                    @"sentBytes": @(testResult.sentBytes),
                    @"receivedBytes": @(testResult.receivedBytes)
                });
            } else {
                NSLog(@"Iperf3Plugin: Test failed - %@", testResult.errorMessage);
                [self sendStatus:@"error" details:@{
                    @"message": testResult.errorMessage ?: @"iperf3 test failed",
                    @"code": @(testResult.errorCode)
                }];

                result(@{
                    @"success": @NO,
                    @"error": testResult.errorMessage ?: @"iperf3 test failed",
                    @"errorCode": @(testResult.errorCode)
                });
            }
        });
    });
}

- (void)handleCancelClient:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSLog(@"Iperf3Plugin: Cancel client requested");
    [_bridge cancelClient];

    [self sendStatus:@"cancelled" details:nil];
    result(@YES);
}

- (void)handleGetVersion:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *version = [_bridge getVersion];
    NSLog(@"Iperf3Plugin: Version: %@", version);
    result(version);
}

- (void)handleGetDefaultGateway:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *gateway = [_bridge getDefaultGateway];
    NSLog(@"Iperf3Plugin: Default gateway: %@", gateway ?: @"(null)");
    result(gateway ?: @"");
}

#pragma mark - FlutterStreamHandler

- (FlutterError * _Nullable)onListenWithArguments:(id _Nullable)arguments
                                        eventSink:(nonnull FlutterEventSink)events {
    NSLog(@"Iperf3Plugin: EventChannel listener attached");
    _eventSink = events;

    // Set progress callback
    __weak typeof(self) weakSelf = self;
    _bridge.progressCallback = ^(NSInteger interval,
                                  long long bytesTransferred,
                                  double bitsPerSecond,
                                  double jitter,
                                  NSInteger lostPackets,
                                  double rtt) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.eventSink) {
            NSMutableDictionary *progress = [NSMutableDictionary dictionary];
            progress[@"interval"] = @(interval);
            progress[@"bytesTransferred"] = @(bytesTransferred);
            progress[@"bitsPerSecond"] = @(bitsPerSecond);
            progress[@"mbps"] = @(bitsPerSecond / 1000000.0);

            // Add protocol-specific metrics
            if (rtt > 0) {
                progress[@"rtt"] = @(rtt);
            }
            if (jitter > 0) {
                progress[@"jitter"] = @(jitter);
                progress[@"lostPackets"] = @(lostPackets);
            }

            NSLog(@"Iperf3Plugin: Sending progress - Interval:%ld, Mbps:%.2f",
                  (long)interval, bitsPerSecond / 1000000.0);

            strongSelf.eventSink([progress copy]);
        }
    };

    return nil;
}

- (FlutterError * _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    NSLog(@"Iperf3Plugin: EventChannel listener cancelled");
    _eventSink = nil;
    _bridge.progressCallback = nil;
    return nil;
}

#pragma mark - Helper Methods

- (void)sendStatus:(NSString *)status details:(NSDictionary * _Nullable)details {
    if (_eventSink) {
        NSMutableDictionary *message = [NSMutableDictionary dictionary];
        message[@"status"] = status;
        if (details) {
            message[@"details"] = details;
        }
        _eventSink([message copy]);
    }
}

@end