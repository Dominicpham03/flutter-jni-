//
//  Iperf3Bridge.h
//  Runner
//
//  Created by Claude Code
//

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

/// Result object returned from iperf3 tests
@interface Iperf3ResultObjC : NSObject

@property (nonatomic) BOOL success;
@property (nonatomic, strong, nullable) NSString *jsonOutput;
@property (nonatomic, strong, nullable) NSString *errorMessage;
@property (nonatomic) NSInteger errorCode;
@property (nonatomic) double sendMbps;
@property (nonatomic) double receiveMbps;
@property (nonatomic) long long sentBytes;
@property (nonatomic) long long receivedBytes;

@end

/// Progress callback block type (Objective-C block)
typedef void (^Iperf3ProgressCallbackBlock)(NSInteger interval,
                                             long long bytesTransferred,
                                             double bitsPerSecond,
                                             double jitter,
                                             NSInteger lostPackets,
                                             double rtt);

/// Main bridge class for iperf3 integration
@interface Iperf3Bridge : NSObject

/// Progress callback handler
@property (nonatomic, copy, nullable) Iperf3ProgressCallbackBlock progressCallback;

/// Run iperf3 client test
/// @param host Server hostname or IP address
/// @param port Server port (default: 5201)
/// @param duration Test duration in seconds
/// @param parallel Number of parallel streams
/// @param reverse Use reverse mode (server sends, client receives)
/// @param useUdp Use UDP protocol (default is TCP)
/// @param bandwidth Target bandwidth in bits/sec for UDP (0 = default)
/// @return Iperf3ResultObjC object with test results
- (Iperf3ResultObjC *)runClientWithHost:(NSString *)host
                                   port:(NSInteger)port
                               duration:(NSInteger)duration
                               parallel:(NSInteger)parallel
                                reverse:(BOOL)reverse
                                 useUdp:(BOOL)useUdp
                              bandwidth:(long long)bandwidth;

/// Cancel running iperf3 client test
- (void)cancelClient;

/// Get iperf3 version string
- (NSString *)getVersion;

/// Get default gateway IP address
- (nullable NSString *)getDefaultGateway;

@end

NS_ASSUME_NONNULL_END
