#import "SkybandEcrPlugin.h"
#import <SkyBandECRSDK/SkyBandECRSDK.h>

@interface SkybandEcrPlugin () <SocketConnectionDelegate>
@property (nonatomic, strong) SKBCoreServices *ecrService;
@property (nonatomic, strong) FlutterEventSink eventSink;
@end

@implementation SkybandEcrPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                   methodChannelWithName:@"skyband_ecr_plugin"
                                   binaryMessenger:[registrar messenger]];
    
    FlutterEventChannel* eventChannel = [FlutterEventChannel
                                        eventChannelWithName:@"skyband_ecr_events"
                                        binaryMessenger:[registrar messenger]];
    
    SkybandEcrPlugin* instance = [[SkybandEcrPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
    [eventChannel setStreamHandler:instance];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _ecrService = [SKBCoreServices shareInstance];
        _ecrService.delegate = self;
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"initialize" isEqualToString:call.method]) {
        result(nil);
    } else if ([@"connectDevice" isEqualToString:call.method]) {
        NSDictionary *args = call.arguments;
        NSString *ipAddress = args[@"ipAddress"];
        NSNumber *port = args[@"port"];
        
        [_ecrService connectSocket:ipAddress portNumber:[port unsignedIntegerValue]];
        result(@YES);
    } else if ([@"disconnectDevice" isEqualToString:call.method]) {
        [_ecrService disConnectSocket];
        result(nil);
    } else if ([@"getDeviceStatus" isEqualToString:call.method]) {
        result(@(_ecrService.connected));
    } else if ([@"initiatePayment" isEqualToString:call.method]) {
        NSDictionary *args = call.arguments;
        NSString *dateFormat = args[@"dateFormat"];
        NSNumber *amount = args[@"amount"];
        NSNumber *printReceipt = args[@"printReceipt"];
        NSString *ecrRefNum = args[@"ecrRefNum"];
        NSNumber *transactionType = args[@"transactionType"];
        NSNumber *signature = args[@"signature"];
        
        // Format the request data according to your requirements
        NSString *requestData = [NSString stringWithFormat:@"%@|%@|%@|%@",
                               dateFormat,
                               [amount stringValue],
                               [printReceipt boolValue] ? @"1" : @"0",
                               ecrRefNum];
        
        [_ecrService doTCPIPTransaction:_ecrService.ipAdress
                            portNumber:_ecrService.portNumber
                           requestData:requestData
                      transactionType:[transactionType intValue]
                           signature:[signature boolValue] ? @"1" : @"0"];
        
        result(@{@"status": @"processing"});
    } else if ([@"getPlatformVersion" isEqualToString:call.method]) {
        result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

#pragma mark - FlutterStreamHandler

- (FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)eventSink {
    self.eventSink = eventSink;
    return nil;
}

- (FlutterError*)onCancelWithArguments:(id)arguments {
    self.eventSink = nil;
    return nil;
}

#pragma mark - SocketConnectionDelegate

- (void)socketConnectionStream:(SKBCoreServices *)connection didReceiveData:(NSMutableDictionary *)responseData {
    if (self.eventSink) {
        self.eventSink(responseData);
    }
}

- (void)socketConnectionStreamDidConnect:(SKBCoreServices *)connection {
    if (self.eventSink) {
        self.eventSink(@{@"status": @"connected"});
    }
}

- (void)socketConnectionStreamDidDisconnect:(SKBCoreServices *)connection willReconnectAutomatically:(BOOL)willReconnectAutomatically {
    if (self.eventSink) {
        self.eventSink(@{
            @"status": @"disconnected",
            @"willReconnect": @(willReconnectAutomatically)
        });
    }
}

- (void)socketConnectionStreamDidFailToConnect:(SKBCoreServices *)connection {
    if (self.eventSink) {
        self.eventSink(@{@"status": @"connection_failed"});
    }
}

@end 