//
//  SkybandConnectionManager.h
//  SkybandConnectionManager
//
//  Created by vijayasimhareddy on 03/03/20.
//  Copyright © 2020 GirmitiSoftwares. All rights reserved.
//

#import "SKBCoreServices.h"
#include "SBCoreECR.h"
#include <CommonCrypto/CommonDigest.h>
#include "Utilities.h"
#include <UIKit/UIKit.h>

static BOOL kShouldReconnectAutomatically = FALSE;
static NSTimeInterval kReconnectTimeInterval = 3;
static NSTimeInterval kTimeoutTimeInterval = 5;
#define RESPONSE_BUFFER_SIZE 2000

@interface SKBCoreServices () <NSStreamDelegate>

@property (nonatomic) CFSocketRef socket;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic) BOOL connected;
@property (nonatomic) int transactionType;
@property (nonatomic) int summaryReportCalled;
@property (strong, nonatomic) NSTimer *timer;
@property (strong,nonatomic) NSMutableDictionary *summaryReport;

@end

@implementation SKBCoreServices

- (instancetype)init {
    
    self = [super init];
    if (self) {
        self.shouldReconnectAutomatically = kShouldReconnectAutomatically;
        self.reconnectTimeInterval = kReconnectTimeInterval;
        self.timeoutTimeInterval = kTimeoutTimeInterval;
        _summaryReport = [[NSMutableDictionary alloc]init];
    }
    return self;
}

+ (SKBCoreServices *)shareInstance {
    
    static dispatch_once_t once;
    static id socketService;
    dispatch_once(&once, ^{
        socketService = [[SKBCoreServices alloc]init];
    });
    return  socketService;
}

//MARK:  - Socket Connection -

- (void)connectSocket:(NSString *)ipAddress portNumber:(NSUInteger)portNumber {
    
    self.ipAdress = ipAddress;
    self.portNumber = portNumber;

    NSLog(@"connect to %@:%@", self.ipAdress, @(self.portNumber));
    
    [self disConnectSocket];
    
    // Create input and output streams
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    
    // Connect socket to host/port
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)(self.ipAdress), (UInt32)self.portNumber, &readStream, &writeStream);
    
    // Set VoIP properties on streams
    CFReadStreamSetProperty(readStream, kCFStreamNetworkServiceType, kCFStreamNetworkServiceTypeVoIP);
    CFWriteStreamSetProperty(writeStream, kCFStreamNetworkServiceType, kCFStreamNetworkServiceTypeVoIP);
    
    // Bridge old school CFStreams to NSStreams for delegates
    self.inputStream = (__bridge NSInputStream *)readStream;
    self.outputStream = (__bridge NSOutputStream *)writeStream;
    
    // Make sure VoIP properties on streams (could be redundant)
    [self.inputStream setProperty:NSStreamNetworkServiceTypeVoIP forKey:NSStreamNetworkServiceType];
    [self.outputStream setProperty:NSStreamNetworkServiceTypeVoIP forKey:NSStreamNetworkServiceType];
    
    // Set delegate on input and output streams
    [self.inputStream setDelegate:self];
    [self.outputStream setDelegate:self];
    
    // Run the stream loop
    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
    // Open connections
    [self.inputStream open];
    [self.outputStream open];
    
    // Set timeout and interval
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(timeout) object:nil];
    [self performSelector:@selector(timeout) withObject:nil afterDelay:self.timeoutTimeInterval];
}

//MARK:  - Socket Disconnect -

- (void)disConnectSocket {
    
    if (nil == self.inputStream && nil == self.outputStream) {
        return;
    }
    NSLog(@"disconnect");

    // Close streams
    [self.inputStream close];
    [self.outputStream close];

    // Remove streams from run loop
    [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

    // Dealloc streams
    self.inputStream = nil;
    self.outputStream = nil;
    self.connected = NO;
}

- (void)timeout {
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(timeout) object:nil];
    [self connectFailure];
}

- (void)reconnectAutomatically {
    
    NSLog(@"Will reconnect automatically in %@s", @(self.reconnectTimeInterval));
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(timeout) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(connect) object:nil];
    [self performSelector:@selector(connect) withObject:nil afterDelay:self.reconnectTimeInterval];
}

- (void)setShouldReconnectAutomatically:(BOOL)shouldReconnectAutomatically {
    
    _shouldReconnectAutomatically = shouldReconnectAutomatically;
    
    // Connect if set true
    if (!_shouldReconnectAutomatically) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(connect) object:nil];
    }
}

- (void)connect {
    
    [self connectSocket:self.ipAdress portNumber:self.portNumber];
}

- (void)connectSuccess:(NSStream *)theStream {
    
    NSLog(@"connectSuccess: Stream opened");
    
    if (theStream == self.outputStream) {
        // Cancel timeout call
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(timeout) object:nil];
        
        self.connected = YES;
        
        // Call delegate after successful connection
        if ([self.delegate respondsToSelector:@selector(socketConnectionStreamDidConnect:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate socketConnectionStreamDidConnect:self];
            });
        }
    }
}

- (void)connectFailure {
    
    NSLog(@"Can not connect to the host!");
    [self conectionfailDelegate];
    // Confirm disconnection
    [self disConnectSocket];

    // Retry if set
    if (self.shouldReconnectAutomatically) {
        [self reconnectAutomatically];
    }
}

-(void)conectionfailDelegate {
    
    // Call delegate after failure
    if ([self.delegate respondsToSelector:@selector(socketConnectionStreamDidFailToConnect:)]) {
        [self.delegate socketConnectionStreamDidFailToConnect:self ];
    }
}

//MARK:  - SHA256 Signature Encryption -

-(NSString*)computeSha256Hash:(NSString*)input {
    
    const char* str = [input UTF8String];
    unsigned char result[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(str, strlen(str), result);

    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    
    for(int i = 0; i<CC_SHA256_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%02x",result[i]];
    }
    return ret;
}

-(void)timeOutException:(NSTimer *)timer {
    
    [self.timer invalidate];
    if (self.transactionType != 23) {
        [[NSUserDefaults standardUserDefaults]setInteger:self.transactionType forKey:@"LAST_TRANSACTON_TYPE"];
    }
    NSMutableDictionary *responseData = [[NSMutableDictionary alloc]init];
    [responseData setValue:@"Timeout Please try again" forKey:@"responseMessage"];
    if ([self.delegate respondsToSelector:@selector(socketConnectionStream:didReceiveData:)]) {
        [self.delegate socketConnectionStream:self didReceiveData:responseData];
    }
    //Disconnect and ReConnect
    [self connect];
}


//MARK:  - Send Data to Socket -

- (void)doTCPIPTransaction:(NSString *)ipAddress portNumber:(NSUInteger)portNumber requestData:(NSString *)requestData transactionType:(int)transactionType signature:(NSString*)signature {
    int retVal = -1;
    NSLog(@"inputRequest:%@, TransactionType: %d", requestData,transactionType);
    const char *inputRequest = [requestData cStringUsingEncoding:NSUTF8StringEncoding];
    self.transactionType = transactionType;
    
    //Timer
    self.timer = [NSTimer scheduledTimerWithTimeInterval:150.0 target:self selector:@selector(timeOutException:) userInfo:nil repeats:NO];
    
    NSLog(@"Trnx:%d",self.transactionType);
    
    //Data for Pack
    unsigned char ecrBuffer[600];
    memset(ecrBuffer, 0x00, sizeof(ecrBuffer));
    if (transactionType == 17 || transactionType == 18 || transactionType == 19) {
        retVal = pack((char *)inputRequest, transactionType, "00000000000000000000000", (char *)ecrBuffer);
        if(retVal == -1) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Skyband ECR" message:@"Invalid input request packet. Please check input fields" preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction * ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
                [self.delegate socketConnectionStreamDidDisconnect:self willReconnectAutomatically:NO];
            }];
            [alert addAction:ok];
            UIViewController *currentTopVC = [self currentTopViewController];
            [currentTopVC presentViewController:alert animated:YES completion:nil];
            return;
        }
        else {
            NSLog(@"ecrbufferdata:%s ,%lu",ecrBuffer,strlen(ecrBuffer));
            
             NSData *inputData = [NSData dataWithBytes:ecrBuffer length:strlen(ecrBuffer)];
            [self.outputStream write:[inputData bytes] maxLength:[inputData length]];
        }
        
    }
    else {
 
        const char *sig = [signature cStringUsingEncoding:NSUTF8StringEncoding];
        
        //Packing the input data
        retVal = pack((char *)inputRequest, transactionType, (char *)sig, (char *)ecrBuffer);
        if(retVal == -1) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Skyband ECR" message:@"Invalid input request packet. Please check input fields" preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction * ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
                [self.delegate socketConnectionStreamDidDisconnect:self willReconnectAutomatically:NO];
            }];
            [alert addAction:ok];
            UIViewController *currentTopVC = [self currentTopViewController];
            [currentTopVC presentViewController:alert animated:YES completion:nil];
            return;
        }
        else {
            NSLog(@"ecrbufferdata:%s ,%lu",ecrBuffer,strlen(ecrBuffer));
            
            NSData *inputData = [NSData dataWithBytes:ecrBuffer length:strlen(ecrBuffer)];
            
            // Send string as bytes
            [self.outputStream write:[inputData bytes] maxLength:[inputData length]];
        }
    }
}

//MARK:  - Data Received From Socket -

-(void)receivedData:(uint8_t[1024])receivedData {
    
    //Timer
    [self.timer invalidate];
    
    char ecrResponse[RESPONSE_BUFFER_SIZE];
    memset(ecrResponse, 0x00, sizeof(ecrResponse));
    
    parse(receivedData, ecrResponse);
    
    NSLog(@"output data parser for the Trnx:%d",self.transactionType);
    NSString *str = [NSString stringWithFormat:@"%s",ecrResponse];
    NSArray *szRespFiel = [str componentsSeparatedByString:@";"];
    NSMutableArray *szRespField = [[NSMutableArray alloc]initWithArray:szRespFiel];
    
    NSMutableDictionary *responseData = [[NSMutableDictionary alloc]init];
    
    if (self.transactionType == 23) { //REPEAT
        if ([[NSUserDefaults standardUserDefaults]valueForKey:@"LAST_TRANSACTON_TYPE"]) {
            unsigned int trnxType = [[[NSUserDefaults standardUserDefaults] objectForKey:@"LAST_TRANSACTON_TYPE"] unsignedIntValue];
             self.transactionType = trnxType;
            
            if (szRespField.count > 5 ) {
                for (int i = 3; i > -1; --i) {
                    [szRespField removeObjectAtIndex:i];
                }
            }
            if ([szRespField[1] isEqual:@"NO DATA FOUND"]) {
                [responseData setValue:@"NO DATA FOUND" forKey:@"responseMessage"];
                if ([self.delegate respondsToSelector:@selector(socketConnectionStream:didReceiveData:)]) {
                    [self.delegate socketConnectionStream:self didReceiveData:responseData];
                }
                return;
            }
        }
    }
    
    if (self.transactionType != 23) {
        [[NSUserDefaults standardUserDefaults]setInteger:self.transactionType forKey:@"LAST_TRANSACTON_TYPE"];
    }
    
    if (self.transactionType == 0) { // SALE
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"0"] forKey:@"Transaction type"];
        if (szRespField.count > 31) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"Response Message"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self maskedPan:[szRespField objectAtIndex:4]]] forKey:@"PAN Number"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"Transaction Amount"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Buss Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:7]] forKey:@"Stan No"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:8]] forKey:@"Date & Time "];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:9]] forKey:@"Card Exp Date"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:10]] forKey:@"RRN"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:11]] forKey:@"Auth Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:12]] forKey:@"TID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:13]] forKey:@"MID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:14]] forKey:@"Batch No"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:15]] forKey:@"AID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:16]] forKey:@"Application Cryptogram"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:17]] forKey:@"CID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:18]] forKey:@"CVR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:19]] forKey:@"TVR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:20]] forKey:@"TSI"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:21]] forKey:@"KERNEL-ID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:22]] forKey:@"PAR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:23]] forKey:@"PANSUFFIX"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:24]] forKey:@"Card Entry Mode"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:25]] forKey:@"Merchant Category Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:26]] forKey:@"Terminal Transaction Type"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:27]] forKey:@"Scheme Label"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:28]] forKey:@"Product Info"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:29]] forKey:@"Application Version"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:30]] forKey:@"Disclaimer"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:31]] forKey:@"Merchant Name"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:32]] forKey:@"Merchant Address"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:33]]]] forKey:@"MerchantName_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:34]]]] forKey:@"MerchantAddress_Arebic"];
            NSLog(@"MerchantName_Arebic encodingISO_8859_6: %@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:33]]]);
            NSLog(@"MerchantAddress_Arebic encodingISO_8859_6: %@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:34]]]);
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:35]] forKey:@"ECR Transaction Reference Number"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:36]] forKey:@"Signature"];
            
            if ([szRespField[3] isEqual: @"APPROVED"] || [szRespField[3] isEqual: @"DECLINED"] || [szRespField[3] isEqual: @"DECLINE"]) {
                NSString *htmlString = [self getHtmlString:@"Purchase(customer_copy)" transactionType:0 trxnResponse:szRespField];
               [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
            }
        }
        else if (szRespField.count >= 4) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
    }
    else if (self.transactionType == 1) { // SALE WITH CASHBACK
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"1"] forKey:@"Transaction type"];
        if (szRespField.count > 33) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
            
            [responseData setValue:[NSString stringWithFormat:@"%@", [self maskedPan:[szRespField objectAtIndex:4]]] forKey:@"panNo"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"Transaction Amount"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Cash Back Amount"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:7]] forKey:@"Total Amount"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:8]] forKey:@"Buss Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:9]] forKey:@"Stan No"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:10]] forKey:@"Date & Time "];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:11]] forKey:@"Card Exp Date"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:12]] forKey:@"RRN"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:13]] forKey:@"Auth Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:14]] forKey:@"TID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:15]] forKey:@"MID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:16]] forKey:@"Batch No"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:17]] forKey:@"AID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:18]] forKey:@"Application Cryptogram"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:19]] forKey:@"CID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:20]] forKey:@"CVR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:21]] forKey:@"TVR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:22]] forKey:@"TSI"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:23]] forKey:@"KERNEL-ID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:24]] forKey:@"PAR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:25]] forKey:@"PANSUFFIX"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:26]] forKey:@"Card Entry Mode"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:27]] forKey:@"Merchant Category Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:28]] forKey:@"Terminal Transaction Type"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:29]] forKey:@"Scheme Label"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:30]] forKey:@"Product Info"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:31]] forKey:@"Application Version"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:32]] forKey:@"Disclaimer"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:33]] forKey:@"Merchant Name"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:34]] forKey:@"Merchant Address"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:35]]]] forKey:@"MerchantName_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:36]]]] forKey:@"MerchantAddress_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:37]] forKey:@"ECR Transaction Reference Number"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:38]] forKey:@"Signature"];
            
            if ([szRespField[3] isEqual: @"APPROVED"] || [szRespField[3] isEqual: @"DECLINED"] || [szRespField[3] isEqual: @"DECLINE"]) {
               NSString *htmlString = [self getHtmlString:@"Purchase cashback(customer copy))" transactionType:1 trxnResponse:szRespField];
               [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
            }
        
        }
        else if (szRespField.count >= 4) {
           [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
           NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
           [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
    }
    else if (self.transactionType == 2) { // REFUND
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"2"] forKey:@"Transaction type"];
        if (szRespField.count > 31) {
             [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
             NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
             [responseData setValue:responseMsg forKey:@"responseMessage"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [self maskedPan:[szRespField objectAtIndex:4]]] forKey:@"panNo"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"Transaction Amount"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Buss Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:7]] forKey:@"Stan No"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:8]] forKey:@"Date & Time "];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:9]] forKey:@"Card Exp Date"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:10]] forKey:@"RRN"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:11]] forKey:@"Auth Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:12]] forKey:@"TID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:13]] forKey:@"MID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:14]] forKey:@"Batch No"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:15]] forKey:@"AID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:16]] forKey:@"Application Cryptogram"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:17]] forKey:@"CID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:18]] forKey:@"CVR"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:19]] forKey:@"TVR"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:20]] forKey:@"TSI"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:21]] forKey:@"KERNEL-ID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:22]] forKey:@"PAR"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:23]] forKey:@"PANSUFFIX"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:24]] forKey:@"Card Entry Mode"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:25]] forKey:@"Merchant Category Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:26]] forKey:@"Terminal Transaction Type"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:27]] forKey:@"Scheme Label"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:28]] forKey:@"Product Info"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:29]] forKey:@"Application Version"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:30]] forKey:@"Disclaimer"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:31]] forKey:@"Merchant Name"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:32]] forKey:@"Merchant Address"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:33]]]] forKey:@"MerchantName_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:34]]]] forKey:@"MerchantAddress_Arebic"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:35]] forKey:@"ECR Transaction Reference Number"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:36]] forKey:@"Signature"];
            
            if ([szRespField[3] isEqual: @"APPROVED"] || [szRespField[3] isEqual: @"DECLINED"] || [szRespField[3] isEqual: @"DECLINE"]) {
                NSString *htmlString = [self getHtmlString:@"Refund(customer_copy)" transactionType:2 trxnResponse:szRespField];
                [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
            }
        }
        else if (szRespField.count >= 4) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
    }
    else if (self.transactionType == 3) { // Preautharization
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"3"] forKey:@"Transaction type"];
        if (szRespField.count > 31 ) {
             [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
             NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
             [responseData setValue:responseMsg forKey:@"responseMessage"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [self maskedPan:[szRespField objectAtIndex:4]]] forKey:@"panNo"];
            
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"Transaction Amount"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Buss Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:7]] forKey:@"Stan No"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:8]] forKey:@"Date & Time "];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:9]] forKey:@"Card Exp Date"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:10]] forKey:@"RRN"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:11]] forKey:@"Auth Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:12]] forKey:@"TID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:13]] forKey:@"MID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:14]] forKey:@"Batch No"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:15]] forKey:@"AID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:16]] forKey:@"Application Cryptogram"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:17]] forKey:@"CID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:18]] forKey:@"CVR"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:19]] forKey:@"TVR"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:20]] forKey:@"TSI"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:21]] forKey:@"KERNEL-ID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:22]] forKey:@"PAR"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:23]] forKey:@"PANSUFFIX"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:24]] forKey:@"Card Entry Mode"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:25]] forKey:@"Merchant Category Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:26]] forKey:@"Terminal Transaction Type"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:27]] forKey:@"Scheme Label"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:28]] forKey:@"Product Info"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:29]] forKey:@"Application Version"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:30]] forKey:@"Disclaimer"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:31]] forKey:@"Merchant Name"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:32]] forKey:@"Merchant Address"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:33]]]] forKey:@"MerchantName_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:34]]]] forKey:@"MerchantAddress_Arebic"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:35]] forKey:@"ECR Transaction Reference Number"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:36]] forKey:@"Signature"];
            
            if ([szRespField[3] isEqual: @"APPROVED"] || [szRespField[3] isEqual: @"DECLINED"] || [szRespField[3] isEqual: @"DECLINE"]) {
               NSString *htmlString = [self getHtmlString:@"Pre-Auth(Customer_copy)" transactionType:3 trxnResponse:szRespField];
               [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
            }
        }
        else if (szRespField.count >= 4) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
    }
    else if (self.transactionType == 4 || self.transactionType == 27) { // PURCHASE ADVICE (FULL or PARTIAL)
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"4"] forKey:@"Transaction type"];
        if (szRespField.count > 31) {
             [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
             NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
             [responseData setValue:responseMsg forKey:@"responseMessage"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [self maskedPan:[szRespField objectAtIndex:4]]] forKey:@"panNo"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"Transaction Amount"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Buss Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:7]] forKey:@"Stan No"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:8]] forKey:@"Date & Time "];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:9]] forKey:@"Card Exp Date"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:10]] forKey:@"RRN"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:11]] forKey:@"Auth Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:12]] forKey:@"TID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:13]] forKey:@"MID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:14]] forKey:@"Batch No"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:15]] forKey:@"AID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:16]] forKey:@"Application Cryptogram"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:17]] forKey:@"CID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:18]] forKey:@"CVR"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:19]] forKey:@"TVR"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:20]] forKey:@"TSI"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:21]] forKey:@"KERNEL-ID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:22]] forKey:@"PAR"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:23]] forKey:@"PANSUFFIX"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:24]] forKey:@"Card Entry Mode"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:25]] forKey:@"Merchant Category Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:26]] forKey:@"Terminal Transaction Type"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:27]] forKey:@"Scheme Label"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:28]] forKey:@"Product Info"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:29]] forKey:@"Application Version"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:30]] forKey:@"Disclaimer"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:31]] forKey:@"Merchant Name"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:32]] forKey:@"Merchant Address"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:33]]]] forKey:@"MerchantName_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:34]]]] forKey:@"MerchantAddress_Arebic"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:35]] forKey:@"ECR Transaction Reference Number"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:36]] forKey:@"Signature"];
            
            if ([szRespField[3] isEqual: @"APPROVED"] || [szRespField[3] isEqual: @"DECLINED"] || [szRespField[3] isEqual: @"DECLINE"]) {
                NSString *htmlString = [self getHtmlString:@"Purchase Advice(Customer_copy)" transactionType:4 trxnResponse:szRespField];
                [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
            }
        }
        else if (szRespField.count >= 4) {
             [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
             NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
             [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
    }
    else if (self.transactionType == 5) { // PRE AUTH EXTENSION
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"5"] forKey:@"Transaction type"];
        if (szRespField.count > 31) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self maskedPan:[szRespField objectAtIndex:4]]] forKey:@"panNo"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"Transaction Amount"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Buss Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:7]] forKey:@"Stan No"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:8]] forKey:@"Date & Time "];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:9]] forKey:@"Card Exp Date"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:10]] forKey:@"RRN"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:11]] forKey:@"Auth Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:12]] forKey:@"TID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:13]] forKey:@"MID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:14]] forKey:@"Batch No"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:15]] forKey:@"AID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:16]] forKey:@"Application Cryptogram"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:17]] forKey:@"CID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:18]] forKey:@"CVR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:19]] forKey:@"TVR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:20]] forKey:@"TSI"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:21]] forKey:@"KERNEL-ID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:22]] forKey:@"PAR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:23]] forKey:@"PANSUFFIX"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:24]] forKey:@"Card Entry Mode"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:25]] forKey:@"Merchant Category Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:26]] forKey:@"Terminal Transaction Type"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:27]] forKey:@"Scheme Label"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:28]] forKey:@"Product Info"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:29]] forKey:@"Application Version"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:30]] forKey:@"Disclaimer"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:31]] forKey:@"Merchant Name"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:32]] forKey:@"Merchant Address"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:33]]]] forKey:@"MerchantName_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:34]]]] forKey:@"MerchantAddress_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:35]] forKey:@"ECR Transaction Reference Number"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:36]] forKey:@"Signature"];
            
            if ([szRespField[3] isEqual: @"APPROVED"] || [szRespField[3] isEqual: @"DECLINED"] || [szRespField[3] isEqual: @"DECLINE"]) {
                NSString *htmlString = [self getHtmlString:@"Pre-Extension(Customer_copy)" transactionType:5 trxnResponse:szRespField];
                [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
            }
        }
        else if (szRespField.count >= 4) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
    }
    else if (self.transactionType == 6) { // PRE AUTH VOID
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"6"] forKey:@"Transaction type"];
        if (szRespField.count > 31) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self maskedPan:[szRespField objectAtIndex:4]]] forKey:@"panNo"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"Transaction Amount"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Buss Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:7]] forKey:@"Stan No"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:8]] forKey:@"Date & Time "];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:9]] forKey:@"Card Exp Date"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:10]] forKey:@"RRN"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:11]] forKey:@"Auth Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:12]] forKey:@"TID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:13]] forKey:@"MID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:14]] forKey:@"Batch No"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:15]] forKey:@"AID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:16]] forKey:@"Application Cryptogram"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:17]] forKey:@"CID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:18]] forKey:@"CVR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:19]] forKey:@"TVR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:20]] forKey:@"TSI"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:21]] forKey:@"KERNEL-ID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:22]] forKey:@"PAR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:23]] forKey:@"PANSUFFIX"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:24]] forKey:@"Card Entry Mode"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:25]] forKey:@"Merchant Category Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:26]] forKey:@"Terminal Transaction Type"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:27]] forKey:@"Scheme Label"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:28]] forKey:@"Product Info"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:29]] forKey:@"Application Version"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:30]] forKey:@"Disclaimer"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:31]] forKey:@"Merchant Name"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:32]] forKey:@"Merchant Address"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:33]]]] forKey:@"MerchantName_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:34]]]] forKey:@"MerchantAddress_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:35]] forKey:@"ECR Transaction Reference Number"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:36]] forKey:@"Signature"];
            
            if ([szRespField[3] isEqual: @"APPROVED"] || [szRespField[3] isEqual: @"DECLINED"] || [szRespField[3] isEqual: @"DECLINE"]) {
               NSString *htmlString = [self getHtmlString:@"Pre-void(Customer_copy)" transactionType:6 trxnResponse:szRespField];
               [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
            }
        }
        else if (szRespField.count >= 4) {
           [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
           NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
           [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
           [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
        
    }
    else if (self.transactionType == 8) { // CASH ADVANCE
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"8"] forKey:@"Transaction type"];
        if (szRespField.count > 31) {
             [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
             NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
             [responseData setValue:responseMsg forKey:@"responseMessage"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [self maskedPan:[szRespField objectAtIndex:4]]] forKey:@"panNo"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"Transaction Amount"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Buss Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:7]] forKey:@"Stan No"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:8]] forKey:@"Date & Time "];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:9]] forKey:@"Card Exp Date"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:10]] forKey:@"RRN"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:11]] forKey:@"Auth Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:12]] forKey:@"TID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:13]] forKey:@"MID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:14]] forKey:@"Batch No"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:15]] forKey:@"AID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:16]] forKey:@"Application Cryptogram"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:17]] forKey:@"CID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:18]] forKey:@"CVR"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:19]] forKey:@"TVR"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:20]] forKey:@"TSI"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:21]] forKey:@"KERNEL-ID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:22]] forKey:@"PAR"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:23]] forKey:@"PANSUFFIX"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:24]] forKey:@"Card Entry Mode"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:25]] forKey:@"Merchant Category Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:26]] forKey:@"Terminal Transaction Type"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:27]] forKey:@"Scheme Label"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:28]] forKey:@"Product Info"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:29]] forKey:@"Application Version"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:30]] forKey:@"Disclaimer"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:31]] forKey:@"Merchant Name"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:32]] forKey:@"Merchant Address"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:33]]]] forKey:@"MerchantName_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:34]]]] forKey:@"MerchantAddress_Arebic"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:35]] forKey:@"ECR Transaction Reference Number"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:36]] forKey:@"Signature"];
            
            if ([szRespField[3] isEqual: @"APPROVED"] || [szRespField[3] isEqual: @"DECLINED"] || [szRespField[3] isEqual: @"DECLINE"]) {
               NSString *htmlString = [self getHtmlString:@"Cash_Advance(Customer_copy)" transactionType:8 trxnResponse:szRespField];
               [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
            }
        }
        else if (szRespField.count >= 4) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
        
    }
    else if (self.transactionType == 9) { // REVERSAL
        
       [responseData setValue:[NSString stringWithFormat:@"%@", @"9"] forKey:@"Transaction type"];
       if (szRespField.count > 31) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self maskedPan:[szRespField objectAtIndex:4]]] forKey:@"panNo"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"Transaction Amount"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Buss Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:7]] forKey:@"Stan No"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:8]] forKey:@"Date & Time "];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:9]] forKey:@"Card Exp Date"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:10]] forKey:@"RRN"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:11]] forKey:@"Auth Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:12]] forKey:@"TID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:13]] forKey:@"MID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:14]] forKey:@"Batch No"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:15]] forKey:@"AID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:16]] forKey:@"Application Cryptogram"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:17]] forKey:@"CID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:18]] forKey:@"CVR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:19]] forKey:@"TVR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:20]] forKey:@"TSI"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:21]] forKey:@"KERNEL-ID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:22]] forKey:@"PAR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:23]] forKey:@"PANSUFFIX"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:24]] forKey:@"Card Entry Mode"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:25]] forKey:@"Merchant Category Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:26]] forKey:@"Terminal Transaction Type"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:27]] forKey:@"Scheme Label"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:28]] forKey:@"Product Info"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:29]] forKey:@"Application Version"];
           [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:30]] forKey:@"Disclaimer"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:31]] forKey:@"Merchant Name"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:32]] forKey:@"Merchant Address"];
           [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:33]]]] forKey:@"MerchantName_Arebic"];
           [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:34]]]] forKey:@"MerchantAddress_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:35]] forKey:@"ECR Transaction Reference Number"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:36]] forKey:@"Signature"];

           if ([szRespField[2] isEqual: @"400"]) {
               NSString *htmlString = [self getHtmlString:@"Reversal(Customer_copy)" transactionType:9 trxnResponse:szRespField];
               [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
           }
           
        }
        else if (szRespField.count >= 3) {
           [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
           NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
           [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
        
    }
    else if (self.transactionType == 10) { // SETTLEMENT
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"10"] forKey:@"Transaction type"];
        
        if (szRespField.count >= 28 ) {
        
          if ([szRespField[2] isEqual: @"500"] || [szRespField[2] isEqual: @"501"] ) {

             NSString *htmlString = [self getHtmlString:@"Reconcilation" transactionType:10 trxnResponse:szRespField];
             responseData = _summaryReport;
             [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
             [responseData setValue:[NSString stringWithFormat:@"%@", @"10"] forKey:@"Transaction type"];
          }
          else {
             [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[2]] forKey:@"Response Code"];
             [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[3]] forKey:@"Response Message"];
             [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[4]] forKey:@"Merchant Name"];
             [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[5]] forKey:@"Merchant Address"];
              [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:szRespField[6]]]] forKey:@"MerchantName_Arebic"];
              [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:szRespField[7]]]] forKey:@"MerchantAddress_Arebic"];
             [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[8]] forKey:@"ECR Transaction Reference Number"];
             [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[9]] forKey:@"Signature"];
           }
        }
        else if (szRespField.count >= 4) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
    }
    else if (self.transactionType == 11) { // PARAMETER DOWNLOAD
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"11"] forKey:@"Transaction type"];
        if (szRespField.count > 5) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"Response Message"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:4]] forKey:@"Date Time Stamp"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"ECR Transaction Reference Number"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Signature"];
            
            if ([szRespField[2] isEqual: @"300"] || ![szRespField[3] isEqual: @"DECLINED"] || [szRespField[3] isEqual: @"DECLINE"]) {
               NSString *htmlString = [self getHtmlString:@"Parameter download" transactionType:11 trxnResponse:szRespField];
               [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
            }
        }
        else if (szRespField.count >= 4) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
        
    }
    else if (self.transactionType == 12) { // SET PARAMETER
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"12"] forKey:@"Transaction type"];
        if (szRespField.count >= 6) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"Response Message"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:4]] forKey:@"Date Time Stamp"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"ECR Transaction Reference Number"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Signature"];

        }
        else if (szRespField.count >= 3) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
    }
    else if (self.transactionType == 13) { // GET PARAMETER
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"13"] forKey:@"Transaction type"];
        if (szRespField.count >= 10) {
             [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
             NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
             [responseData setValue:responseMsg forKey:@"Response Message"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:4]] forKey:@"Date Time Stamp"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"Vendor ID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Vendor Terminal type"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:7]] forKey:@"TRSM ID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:8]] forKey:@"Vendor Key Index"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:9]] forKey:@"SAMA Key Index"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:10]] forKey:@"ECR Transaction Reference Number"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:11]] forKey:@"Signature"];
        }
        else if (szRespField.count >= 3) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
        
    }
    else if (self.transactionType == 14) { // SET TERMINAL LANGUAGE
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"14"] forKey:@"Transaction type"];
        if (szRespField.count >= 10) {
             [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
             NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
             [responseData setValue:responseMsg forKey:@"responseMessage"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:4]] forKey:@"VendorID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"VendorTerminaltype"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"TRSMID"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:7]] forKey:@"VendorKeyIndex"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:8]] forKey:@"SAMAKeyIndex"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:9]] forKey:@"POSTransactionReferenceNumber"];
        }
        else if (szRespField.count >= 3) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
        
    }
    else if (self.transactionType == 17) { // REGISTRATION
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"17"] forKey:@"Transaction type"];
        [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:2]] forKey:@"Response Code"];
        [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]] forKey:@"Terminal id"];
                
        NSLog(@"Terminal ID :%@",[szRespField objectAtIndex:3]);
        NSString *terminalNum = [NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]];
        if ([terminalNum length] > 16) {
            NSString *terminal = [terminalNum substringWithRange:NSMakeRange( 0, 16)];
            [[NSUserDefaults standardUserDefaults]setObject:terminal forKey:@"terminalSerialNumber"];
        }
        else {
            [[NSUserDefaults standardUserDefaults]setObject:terminalNum forKey:@"terminalSerialNumber"];
        }
        
    }
    else if (self.transactionType == 18) { // Start Session
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"18"] forKey:@"Transaction type"];
        if (szRespField.count >= 3) {
           [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
    }
    else if (self.transactionType == 19) { // End Session
        
          [responseData setValue:[NSString stringWithFormat:@"%@", @"19"] forKey:@"Transaction type"];
          if (szRespField.count >= 3) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
         }
         else {
             [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
         }
    }
    else if (self.transactionType == 20) { // Bill Payment
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"20"] forKey:@"Transaction type"];
         if (szRespField.count >= 31 ) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [self maskedPan:[szRespField objectAtIndex:4]]] forKey:@"panNo"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"Transaction Amount"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Buss Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:7]] forKey:@"Stan No"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:8]] forKey:@"Date & Time "];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:9]] forKey:@"Card Exp Date"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:10]] forKey:@"RRN"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:11]] forKey:@"Auth Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:12]] forKey:@"TID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:13]] forKey:@"MID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:14]] forKey:@"Batch No"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:15]] forKey:@"AID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:16]] forKey:@"Application Cryptogram"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:17]] forKey:@"CID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:18]] forKey:@"CVR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:19]] forKey:@"TVR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:20]] forKey:@"TSI"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:21]] forKey:@"KERNEL-ID"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:22]] forKey:@"PAR"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:23]] forKey:@"PANSUFFIX"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:24]] forKey:@"Card Entry Mode"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:25]] forKey:@"Merchant Category Code"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:26]] forKey:@"Terminal Transaction Type"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:27]] forKey:@"Scheme Label"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:28]] forKey:@"Product Info"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:29]] forKey:@"Application Version"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:30]] forKey:@"Disclaimer"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:31]] forKey:@"Merchant Name"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:32]] forKey:@"Merchant Address"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:33]]]] forKey:@"MerchantName_Arebic"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:[szRespField objectAtIndex:34]]]] forKey:@"MerchantAddress_Arebic"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:35]] forKey:@"ECR Transaction Reference Number"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:36]] forKey:@"Signature"];
             
            if ([szRespField[3] isEqual: @"APPROVED"] || [szRespField[3] isEqual: @"DECLINED"] || [szRespField[3] isEqual: @"DECLINE"]) {
               NSString *htmlString = [self getHtmlString:@"Bill Pyment(Customer_copy)" transactionType:20 trxnResponse:szRespField];
               [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
            }
         }
        else if (szRespField.count >= 3) {
             [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
             NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
             [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
    }
    else if (self.transactionType == 21) { // PRINT DETAIL REPORT OR Running Total
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"21"] forKey:@"Transaction type"];
        
        if (szRespField.count >= 28) {
                
           if ([szRespField[2] isEqual: @"00"]) {
 
              NSString *htmlString = [self getHtmlString:@"Detail_Report" transactionType:21 trxnResponse:szRespField];
              responseData = _summaryReport;
              [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
              [responseData setValue:[NSString stringWithFormat:@"%@", @"21"] forKey:@"Transaction type"];
           }
           else {
              
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[2]] forKey:@"Response Code"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[3]] forKey:@"Response Message"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[4]] forKey:@"Merchant Name"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[5]] forKey:@"Merchant Address"];
               [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:szRespField[6]]]] forKey:@"MerchantName_Arebic"];
               [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:szRespField[7]]]] forKey:@"MerchantAddress_Arebic"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[8]] forKey:@"ECR Transaction Reference Number"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[9]] forKey:@"Signature"];
            }
         }
         else if (szRespField.count >= 8) {
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[2]] forKey:@"Response Code"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[3]] forKey:@"Response Message"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[4]] forKey:@"Merchant Name"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[5]] forKey:@"Merchant Address"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:szRespField[6]]]] forKey:@"MerchantName_Arebic"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:szRespField[7]]]] forKey:@"MerchantAddress_Arebic"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[8]] forKey:@"ECR Transaction Reference Number"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[9]] forKey:@"Signature"];
         }
         else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
         }
    }
    else if (self.transactionType == 22) { //PRINT SUMMARY REPORT
        
        [responseData setValue:szRespField forKey:@"responseData"];
        if ([self.delegate respondsToSelector:@selector(socketConnectionStream:didReceiveData:)]) {
           [self.delegate socketConnectionStream:self didReceiveData:responseData];
        }
        return;
    }
    else if (self.transactionType == 24) { //CHECK STATUS
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"24"] forKey:@"Transaction type"];
        if (szRespField.count >= 6) {
             [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
             NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
             [responseData setValue:responseMsg forKey:@"responseMessage"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:4]] forKey:@"Date & Time"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"ECR Transaction Reference Number"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Signature"];
        }
        else if (szRespField.count >= 3) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
    }
    else if (self.transactionType == 25) { // PARTIAL DOWNLOAD
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"25"] forKey:@"Transaction type"];
        if (szRespField.count > 5) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"Response Message"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:4]] forKey:@"Date Time Stamp"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:5]] forKey:@"ECR Transaction Reference Number"];
            [responseData setValue:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:6]] forKey:@"Signature"];
            
            if ([szRespField[2] isEqual: @"300"] || ![szRespField[3] isEqual: @"DECLINED"] || [szRespField[3] isEqual: @"DECLINE"]) {
               NSString *htmlString = [self getHtmlString:@"Parameter download" transactionType:25 trxnResponse:szRespField];
               [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
            }
        }
        else if (szRespField.count >= 4) {
            [responseData setValue:[NSString stringWithFormat:@"%@",  [szRespField objectAtIndex:2]] forKey:@"Response Code"];
            NSString *responseMsg = [self getUpdatedResponseMessage:[NSString stringWithFormat:@"%@", [szRespField objectAtIndex:3]]];
            [responseData setValue:responseMsg forKey:@"responseMessage"];
        }
        else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
        }
        
    }
    else if (self.transactionType == 26) { // Snapshot Total
        
        [responseData setValue:[NSString stringWithFormat:@"%@", @"26"] forKey:@"Transaction type"];
        
        if (szRespField.count >= 28) {
                
           if ([szRespField[2] isEqual: @"00"]) {
 
              NSString *htmlString = [self getHtmlString:@"Detail_Report" transactionType:26 trxnResponse:szRespField];
              responseData = _summaryReport;
              [responseData setValue:[NSString stringWithFormat:@"%@", htmlString] forKey:@"receiptFormat"];
              [responseData setValue:[NSString stringWithFormat:@"%@", @"26"] forKey:@"Transaction type"];
           }
           else {
              
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[2]] forKey:@"Response Code"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[3]] forKey:@"Response Message"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[4]] forKey:@"Merchant Name"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[5]] forKey:@"Merchant Address"];
               [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:szRespField[6]]]] forKey:@"MerchantName_Arebic"];
               [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:szRespField[7]]]] forKey:@"MerchantAddress_Arebic"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[8]] forKey:@"ECR Transaction Reference Number"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[9]] forKey:@"Signature"];
            }
         }
         else if (szRespField.count >= 8) {
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[2]] forKey:@"Response Code"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[3]] forKey:@"Response Message"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[4]] forKey:@"Merchant Name"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[5]] forKey:@"Merchant Address"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:szRespField[6]]]] forKey:@"MerchantName_Arebic"];
             [responseData setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:szRespField[7]]]] forKey:@"MerchantAddress_Arebic"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[8]] forKey:@"ECR Transaction Reference Number"];
              [responseData setValue:[NSString stringWithFormat:@"%@", szRespField[9]] forKey:@"Signature"];
         }
         else {
            [responseData setValue:@"Error occurred Please try again" forKey:@"responseMessage"];
         }
    }
    else {
        NSLog(@"Deafault Transaction called");
    }
    
    if ([self.delegate respondsToSelector:@selector(socketConnectionStream:didReceiveData:)]) {
        [self.delegate socketConnectionStream:self didReceiveData:responseData];
    }
}
- (NSString *)maskedPan:(NSString*)inputPanNumber {
    
    if (inputPanNumber.length > 7) {
        NSString *firstSix = [inputPanNumber substringToIndex:6];
        NSString *lastFour = [inputPanNumber substringFromIndex: [inputPanNumber length] - 4];
        NSString *maskedPan = [NSString stringWithFormat:@"%@******%@",firstSix,lastFour];
        NSLog(@"maskedPan: %@",maskedPan);
        return maskedPan;
    }
    else {
        return @"";
    }
}

-(NSString*)getUpdatedResponseMessage:(NSString*)inputString {
    
    if ([inputString containsString:@"APPROVED"]) {
        return @"APPROVED";
    }
    else {
        return inputString;
    }
}
//MARK: - HTML Print Receipt -

-(NSString *)getHtmlString:(NSString*)fileName transactionType:(int)transactionType trxnResponse:(NSArray *)trxnResponse {
    
    NSString *htmlString = @"";
    NSURL *bundlePaths = [[NSBundle bundleForClass:[self class]] URLForResource:fileName withExtension:@"html"];
    htmlString = [NSString stringWithContentsOfURL:bundlePaths encoding:NSUTF8StringEncoding error:nil];
//    NSString *merchantNameArebic = @"معرض سليمان السيف ل لاواني المنزل";
//    NSString *mechantAddressArebic = @"طريق الملك خالد بريدة";
    
    if (transactionType == 0 && htmlString != nil) { // Purchase
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[8]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"arabicSAR" withString:[self checkingArabic:@"SAR"]];

        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ResponseCode" withString:[trxnResponse objectAtIndex:2]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approved" withString:[trxnResponse objectAtIndex:3]];
        
        NSString *res = trxnResponse[3];
        NSString *arabic = [self checkingArabic:res];
        arabic = [arabic stringByReplacingOccurrencesOfString:@"\u08F1" withString:@""];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"مقبولة" withString:arabic];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"panNumber" withString:[self maskedPan:[trxnResponse objectAtIndex:4]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CurrentAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"amountSAR" withString:[self numToArabicConverter:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Buzzcode" withString:trxnResponse [6]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"StanNo" withString:[trxnResponse objectAtIndex:7]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ExpiryDate" withString:[self expiryDate:[NSString stringWithFormat:@"%@", trxnResponse[9]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"RRN" withString:[trxnResponse objectAtIndex:10]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approovalcodearabic" withString:[self numToArabicConverter:[NSString stringWithFormat:@"%@", trxnResponse[11]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"authCode" withString:trxnResponse [11]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TID" withString:[trxnResponse objectAtIndex:12]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MID" withString:[trxnResponse objectAtIndex:13]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"AIDaid" withString:[trxnResponse objectAtIndex:15]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"applicationCryptogram" withString:[trxnResponse objectAtIndex:16]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CID" withString:[trxnResponse objectAtIndex:17]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CVR" withString:[trxnResponse objectAtIndex:18]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TVR" withString:[trxnResponse objectAtIndex:19]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TSI" withString:[trxnResponse objectAtIndex:20]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"KERNEL-ID" withString:[trxnResponse objectAtIndex:21]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PAR" withString:[trxnResponse objectAtIndex:22]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PANSUFFIX" withString:[trxnResponse objectAtIndex:23]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CONTACTLESS" withString:[trxnResponse objectAtIndex:24]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantCategoryCode" withString:[trxnResponse objectAtIndex:25]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeLabel" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Scheme Text" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:27]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ApplicationVersion" withString:[trxnResponse objectAtIndex:29]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Disclaimer Text" withString:[trxnResponse objectAtIndex:30]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"DisclaimerText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:30]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Name" withString:[trxnResponse objectAtIndex:31]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Address" withString:[trxnResponse objectAtIndex:32]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantName_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:33]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantAddress_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:34]]]];
        return htmlString;
        
    }
    else if (transactionType == 1 && htmlString != nil) { // Purchase with Cashback
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[10]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[10]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"arabicSAR" withString:[self checkingArabic:@"SAR"]];
        NSString *res = trxnResponse[3];
        NSString *arabic = [self checkingArabic:res];
        arabic = [arabic stringByReplacingOccurrencesOfString:@"\u08F1" withString:@""];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"مقبولة" withString:arabic];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ResponseCode" withString:[trxnResponse objectAtIndex:2]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approved" withString:[trxnResponse objectAtIndex:3]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"panNumber" withString:[self maskedPan:[trxnResponse objectAtIndex:4]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TransactionAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"amountSARPUR" withString:[self numToArabicConverter:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CashbackAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[6]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"amountSARcashback" withString:[self numToArabicConverter:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[6]]]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TotalAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[7]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"amountSARtotal" withString:[self numToArabicConverter:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[7]]]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Buzzcode" withString:[trxnResponse objectAtIndex:8]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"StanNo" withString:[trxnResponse objectAtIndex:9]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ExpiryDate" withString:[trxnResponse objectAtIndex:11]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"RRN" withString:[trxnResponse objectAtIndex:12]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"authCode" withString:[trxnResponse objectAtIndex:13]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approovalcodearabic" withString:[self numToArabicConverter:[NSString stringWithFormat:@"%@", trxnResponse[13]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TID" withString:[trxnResponse objectAtIndex:14]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MID" withString:[trxnResponse objectAtIndex:15]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"AIDaid" withString:[trxnResponse objectAtIndex:17]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"applicationCryptogram" withString:[trxnResponse objectAtIndex:18]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CID" withString:[trxnResponse objectAtIndex:19]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CVR" withString:[trxnResponse objectAtIndex:20]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TVR" withString:[trxnResponse objectAtIndex:21]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TSI" withString:[trxnResponse objectAtIndex:22]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"KERNEL-ID" withString:[trxnResponse objectAtIndex:23]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PAR" withString:[trxnResponse objectAtIndex:24]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PANSUFFIX" withString:[trxnResponse objectAtIndex:25]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CONTACTLESS" withString:[trxnResponse objectAtIndex:26]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantCategoryCode" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeLabel" withString:[trxnResponse objectAtIndex:29]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Scheme Text" withString:[trxnResponse objectAtIndex:29]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:29]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ApplicationVersion" withString:[trxnResponse objectAtIndex:31]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Disclaimer Text" withString:[trxnResponse objectAtIndex:32]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"DisclaimerText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:32]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Name" withString:[trxnResponse objectAtIndex:33]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Address" withString:[trxnResponse objectAtIndex:34]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantName_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:35]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantAddress_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:36]]]];
        return htmlString;
        
    }
    else if (transactionType == 2 && htmlString != nil) { // Refund
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ResponseCode" withString:[trxnResponse objectAtIndex:2]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approved" withString:[trxnResponse objectAtIndex:3]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"panNumber" withString:[self maskedPan:[trxnResponse objectAtIndex:4]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CurrentAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]];
         htmlString = [htmlString stringByReplacingOccurrencesOfString:@"amountSAR" withString:[self numToArabicConverter:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"arabicSAR" withString:[self checkingArabic:@"SAR"]];
         htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Buzzcode" withString:[trxnResponse objectAtIndex:6]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"StanNo" withString:[trxnResponse objectAtIndex:7]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ExpiryDate" withString:[trxnResponse objectAtIndex:9]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"RRN" withString:[trxnResponse objectAtIndex:10]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"authCode" withString:[trxnResponse objectAtIndex:11]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approovalcodearabic" withString:[self numToArabicConverter:[NSString stringWithFormat:@"%@", trxnResponse[11]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TID" withString:[trxnResponse objectAtIndex:12]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MID" withString:[trxnResponse objectAtIndex:13]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"AIDaid" withString:[trxnResponse objectAtIndex:15]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"applicationCryptogram" withString:[trxnResponse objectAtIndex:16]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CID" withString:[trxnResponse objectAtIndex:17]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CVR" withString:[trxnResponse objectAtIndex:18]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TVR" withString:[trxnResponse objectAtIndex:19]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TSI" withString:[trxnResponse objectAtIndex:20]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"KERNEL-ID" withString:[trxnResponse objectAtIndex:21]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PAR" withString:[trxnResponse objectAtIndex:22]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PANSUFFIX" withString:[trxnResponse objectAtIndex:23]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CONTACTLESS" withString:[trxnResponse objectAtIndex:24]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantCategoryCode" withString:[trxnResponse objectAtIndex:25]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeLabel" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Scheme Text" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:27]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ApplicationVersion" withString:[trxnResponse objectAtIndex:29]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Disclaimer Text" withString:[trxnResponse objectAtIndex:30]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"DisclaimerText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:30]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Name" withString:[trxnResponse objectAtIndex:31]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Address" withString:[trxnResponse objectAtIndex:32]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantName_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:33]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantAddress_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:34]]]];
        return htmlString;
        
    }
    else if (transactionType == 3 && htmlString != nil) { // Preautharization
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ResponseCode" withString:[trxnResponse objectAtIndex:2]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approved" withString:[trxnResponse objectAtIndex:3]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"panNumber" withString:[self maskedPan:[trxnResponse objectAtIndex:4]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CurrentAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"amountSAR" withString:[self numToArabicConverter:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approovalcodearabic" withString:[self numToArabicConverter:[NSString stringWithFormat:@"%@", trxnResponse[11]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"arabicSAR" withString:[self checkingArabic:@"SAR"]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Buzzcode" withString:[trxnResponse objectAtIndex:6]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"StanNo" withString:[trxnResponse objectAtIndex:7]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ExpiryDate" withString:[trxnResponse objectAtIndex:9]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"RRN" withString:[trxnResponse objectAtIndex:10]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"authCode" withString:[trxnResponse objectAtIndex:11]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TID" withString:[trxnResponse objectAtIndex:12]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MID" withString:[trxnResponse objectAtIndex:13]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"AIDaid" withString:[trxnResponse objectAtIndex:15]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"applicationCryptogram" withString:[trxnResponse objectAtIndex:16]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CID" withString:[trxnResponse objectAtIndex:17]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CVR" withString:[trxnResponse objectAtIndex:18]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TVR" withString:[trxnResponse objectAtIndex:19]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TSI" withString:[trxnResponse objectAtIndex:20]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"KERNEL-ID" withString:[trxnResponse objectAtIndex:21]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PAR" withString:[trxnResponse objectAtIndex:22]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PANSUFFIX" withString:[trxnResponse objectAtIndex:23]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CONTACTLESS" withString:[trxnResponse objectAtIndex:24]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantCategoryCode" withString:[trxnResponse objectAtIndex:25]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeLabel" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Scheme Text" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:27]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ApplicationVersion" withString:[trxnResponse objectAtIndex:29]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Disclaimer Text" withString:[trxnResponse objectAtIndex:30]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"DisclaimerText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:30]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Name" withString:[trxnResponse objectAtIndex:31]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Address" withString:[trxnResponse objectAtIndex:32]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantName_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:33]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantAddress_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:34]]]];
        return htmlString;
    }
    else if ((transactionType == 4 || transactionType == 27) && htmlString != nil) {  // PURCHASE ADVICE (FULL or PARTIAL)
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ResponseCode" withString:[trxnResponse objectAtIndex:2]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approved" withString:[trxnResponse objectAtIndex:3]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"panNumber" withString:[self maskedPan:[trxnResponse objectAtIndex:4]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CurrentAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"amountSAR" withString:[self numToArabicConverter:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approovalcodearabic" withString:[self numToArabicConverter:[NSString stringWithFormat:@"%@", trxnResponse[11]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"arabicSAR" withString:[self checkingArabic:@"SAR"]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Buzzcode" withString:[trxnResponse objectAtIndex:6]];
         htmlString = [htmlString stringByReplacingOccurrencesOfString:@"StanNo" withString:[trxnResponse objectAtIndex:7]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ExpiryDate" withString:[trxnResponse objectAtIndex:9]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"RRN" withString:[trxnResponse objectAtIndex:10]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"authCode" withString:[trxnResponse objectAtIndex:11]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TID" withString:[trxnResponse objectAtIndex:12]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MID" withString:[trxnResponse objectAtIndex:13]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"AIDaid" withString:[trxnResponse objectAtIndex:15]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"applicationCryptogram" withString:[trxnResponse objectAtIndex:16]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CID" withString:[trxnResponse objectAtIndex:17]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CVR" withString:[trxnResponse objectAtIndex:18]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TVR" withString:[trxnResponse objectAtIndex:19]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TSI" withString:[trxnResponse objectAtIndex:20]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"KERNEL-ID" withString:[trxnResponse objectAtIndex:21]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PAR" withString:[trxnResponse objectAtIndex:22]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PANSUFFIX" withString:[trxnResponse objectAtIndex:23]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CONTACTLESS" withString:[trxnResponse objectAtIndex:24]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantCategoryCode" withString:[trxnResponse objectAtIndex:25]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeLabel" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Scheme Text" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:27]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ApplicationVersion" withString:[trxnResponse objectAtIndex:29]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Disclaimer Text" withString:[trxnResponse objectAtIndex:30]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"DisclaimerText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:30]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Name" withString:[trxnResponse objectAtIndex:31]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Address" withString:[trxnResponse objectAtIndex:32]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantName_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:33]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantAddress_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:34]]]];
        return htmlString;
    }
    else if (transactionType == 5 && htmlString != nil) { // PRE AUTH EXTENSION
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ResponseCode" withString:[trxnResponse objectAtIndex:2]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approved" withString:[trxnResponse objectAtIndex:3]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"panNumber" withString:[self maskedPan:[trxnResponse objectAtIndex:4]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"amountSAR" withString:[self numToArabicConverter:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approovalcodearabic" withString:[self numToArabicConverter:[NSString stringWithFormat:@"%@", trxnResponse[11]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"arabicSAR" withString:[self checkingArabic:@"SAR"]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Buzzcode" withString:[trxnResponse objectAtIndex:6]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"StanNo" withString:[trxnResponse objectAtIndex:7]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ExpiryDate" withString:[trxnResponse objectAtIndex:9]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"RRN" withString:[trxnResponse objectAtIndex:10]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"authCode" withString:[trxnResponse objectAtIndex:11]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TID" withString:[trxnResponse objectAtIndex:12]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MID" withString:[trxnResponse objectAtIndex:13]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"AIDaid" withString:[trxnResponse objectAtIndex:15]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"applicationCryptogram" withString:[trxnResponse objectAtIndex:16]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CID" withString:[trxnResponse objectAtIndex:17]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CVR" withString:[trxnResponse objectAtIndex:18]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TVR" withString:[trxnResponse objectAtIndex:19]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TSI" withString:[trxnResponse objectAtIndex:20]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"KERNEL-ID" withString:[trxnResponse objectAtIndex:21]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PAR" withString:[trxnResponse objectAtIndex:22]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PANSUFFIX" withString:[trxnResponse objectAtIndex:23]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CONTACTLESS" withString:[trxnResponse objectAtIndex:24]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantCategoryCode" withString:[trxnResponse objectAtIndex:25]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeLabel" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Scheme Text" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:27]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ApplicationVersion" withString:[trxnResponse objectAtIndex:29]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Disclaimer Text" withString:[trxnResponse objectAtIndex:30]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"DisclaimerText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:30]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Name" withString:[trxnResponse objectAtIndex:31]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Address" withString:[trxnResponse objectAtIndex:32]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantName_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:33]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantAddress_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:34]]]];

        return htmlString;
    }
    else if (transactionType == 6 && htmlString != nil) { // PRE AUTH VOID
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ResponseCode" withString:[trxnResponse objectAtIndex:2]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approved" withString:[trxnResponse objectAtIndex:3]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"panNumber" withString:[self maskedPan:[trxnResponse objectAtIndex:4]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CurrentAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"amountSAR" withString:[self numToArabicConverter:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approovalcodearabic" withString:[self numToArabicConverter:[NSString stringWithFormat:@"%@", trxnResponse[11]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"arabicSAR" withString:[self checkingArabic:@"SAR"]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Buzzcode" withString:[trxnResponse objectAtIndex:6]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"StanNo" withString:[trxnResponse objectAtIndex:7]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ExpiryDate" withString:[trxnResponse objectAtIndex:9]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"RRN" withString:[trxnResponse objectAtIndex:10]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"authCode" withString:[trxnResponse objectAtIndex:11]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TID" withString:[trxnResponse objectAtIndex:12]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MID" withString:[trxnResponse objectAtIndex:13]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"AIDaid" withString:[trxnResponse objectAtIndex:15]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"applicationCryptogram" withString:[trxnResponse objectAtIndex:16]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CID" withString:[trxnResponse objectAtIndex:17]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CVR" withString:[trxnResponse objectAtIndex:18]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TVR" withString:[trxnResponse objectAtIndex:19]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TSI" withString:[trxnResponse objectAtIndex:20]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"KERNEL-ID" withString:[trxnResponse objectAtIndex:21]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PAR" withString:[trxnResponse objectAtIndex:22]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PANSUFFIX" withString:[trxnResponse objectAtIndex:23]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CONTACTLESS" withString:[trxnResponse objectAtIndex:24]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantCategoryCode" withString:[trxnResponse objectAtIndex:25]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeLabel" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Scheme Text" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:27]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ApplicationVersion" withString:[trxnResponse objectAtIndex:29]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Disclaimer Text" withString:[trxnResponse objectAtIndex:30]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"DisclaimerText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:30]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Name" withString:[trxnResponse objectAtIndex:31]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Address" withString:[trxnResponse objectAtIndex:32]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantName_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:33]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantAddress_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:34]]]];
        return htmlString;
    }
    else if (transactionType == 8 && htmlString != nil) {  // CASH ADVANCE
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ResponseCode" withString:[trxnResponse objectAtIndex:2]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approved" withString:[trxnResponse objectAtIndex:3]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"panNumber" withString:[self maskedPan:[trxnResponse objectAtIndex:4]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CurrentAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"amountSAR" withString:[self numToArabicConverter:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approovalcodearabic" withString:[self numToArabicConverter:[NSString stringWithFormat:@"%@", trxnResponse[11]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"arabicSAR" withString:[self checkingArabic:@"SAR"]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Buzzcode" withString:[trxnResponse objectAtIndex:6]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"StanNo" withString:[trxnResponse objectAtIndex:7]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ExpiryDate" withString:[trxnResponse objectAtIndex:9]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"RRN" withString:[trxnResponse objectAtIndex:10]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"authCode" withString:[trxnResponse objectAtIndex:11]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TID" withString:[trxnResponse objectAtIndex:12]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MID" withString:[trxnResponse objectAtIndex:13]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"AIDaid" withString:[trxnResponse objectAtIndex:15]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"applicationCryptogram" withString:[trxnResponse objectAtIndex:16]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CID" withString:[trxnResponse objectAtIndex:17]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CVR" withString:[trxnResponse objectAtIndex:18]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TVR" withString:[trxnResponse objectAtIndex:19]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TSI" withString:[trxnResponse objectAtIndex:20]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"KERNEL-ID" withString:[trxnResponse objectAtIndex:21]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PAR" withString:[trxnResponse objectAtIndex:22]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PANSUFFIX" withString:[trxnResponse objectAtIndex:23]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CONTACTLESS" withString:[trxnResponse objectAtIndex:24]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantCategoryCode" withString:[trxnResponse objectAtIndex:25]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeLabel" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Scheme Text" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:27]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ApplicationVersion" withString:[trxnResponse objectAtIndex:29]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Disclaimer Text" withString:[trxnResponse objectAtIndex:30]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"DisclaimerText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:30]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Name" withString:[trxnResponse objectAtIndex:31]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Address" withString:[trxnResponse objectAtIndex:32]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantName_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:33]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantAddress_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:34]]]];
        return htmlString;
    }
    else if (transactionType == 9 && htmlString != nil) { // REVERSAL
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ResponseCode" withString:[trxnResponse objectAtIndex:2]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approved" withString:[trxnResponse objectAtIndex:3]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"panNumber" withString:[self maskedPan:[trxnResponse objectAtIndex:4]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CurrentAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"amountSAR" withString:[self numToArabicConverter:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approovalcodearabic" withString:[self numToArabicConverter:[NSString stringWithFormat:@"%@", trxnResponse[11]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"arabicSAR" withString:[self checkingArabic:@"SAR"]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Buzzcode" withString:[trxnResponse objectAtIndex:6]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"StanNo" withString:[trxnResponse objectAtIndex:7]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ExpiryDate" withString:[trxnResponse objectAtIndex:9]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"RRN" withString:[trxnResponse objectAtIndex:10]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"authCode" withString:[trxnResponse objectAtIndex:11]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TID" withString:[trxnResponse objectAtIndex:12]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MID" withString:[trxnResponse objectAtIndex:13]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"AIDaid" withString:[trxnResponse objectAtIndex:15]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"applicationCryptogram" withString:[trxnResponse objectAtIndex:16]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CID" withString:[trxnResponse objectAtIndex:17]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CVR" withString:[trxnResponse objectAtIndex:18]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TVR" withString:[trxnResponse objectAtIndex:19]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TSI" withString:[trxnResponse objectAtIndex:20]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"KERNEL-ID" withString:[trxnResponse objectAtIndex:21]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PAR" withString:[trxnResponse objectAtIndex:22]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PANSUFFIX" withString:[trxnResponse objectAtIndex:23]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CONTACTLESS" withString:[trxnResponse objectAtIndex:24]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantCategoryCode" withString:[trxnResponse objectAtIndex:25]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeLabel" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Scheme Text" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:27]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ApplicationVersion" withString:[trxnResponse objectAtIndex:29]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Name" withString:[trxnResponse objectAtIndex:31]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Address" withString:[trxnResponse objectAtIndex:32]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantName_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:33]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantAddress_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:34]]]];
        return htmlString;

    }
    else if ((transactionType == 11 || transactionType == 25 ) && htmlString != nil) { // PARAMETER DOWNLOAD OR PARTIAL DOWNLOAD
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[4]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[4]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"responseCode" withString:[trxnResponse objectAtIndex:2]];
        NSString *teminalID = [[NSUserDefaults standardUserDefaults]valueForKey:@"terminalSerialNumber"];
        if (teminalID.length > 9) {
            NSString *terminal = [teminalID substringWithRange:NSMakeRange( 0, 8)];
            htmlString = [htmlString stringByReplacingOccurrencesOfString:@"terminalId" withString:terminal];
        }
        return htmlString;

    }

    else if (transactionType == 20 && htmlString != nil) { // BillPayment
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[8]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ResponseCode" withString:[trxnResponse objectAtIndex:2]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approved" withString:[trxnResponse objectAtIndex:3]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"panNumber" withString:[self maskedPan:[trxnResponse objectAtIndex:4]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CurrentAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]];
        
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"amountSAR" withString:[self numToArabicConverter:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[5]]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"approovalcodearabic" withString:[self numToArabicConverter:[NSString stringWithFormat:@"%@", trxnResponse[11]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"arabicSAR" withString:[self checkingArabic:@"SAR"]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Buzzcode" withString:[trxnResponse objectAtIndex:6]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"StanNo" withString:[trxnResponse objectAtIndex:7]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ExpiryDate" withString:[trxnResponse objectAtIndex:9]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"RRN" withString:[trxnResponse objectAtIndex:10]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"authCode" withString:[trxnResponse objectAtIndex:11]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TID" withString:[trxnResponse objectAtIndex:12]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MID" withString:[trxnResponse objectAtIndex:13]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"AIDaid" withString:[trxnResponse objectAtIndex:15]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"applicationCryptogram" withString:[trxnResponse objectAtIndex:16]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CID" withString:[trxnResponse objectAtIndex:17]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CVR" withString:[trxnResponse objectAtIndex:18]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TVR" withString:[trxnResponse objectAtIndex:19]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"TSI" withString:[trxnResponse objectAtIndex:20]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"KERNEL-ID" withString:[trxnResponse objectAtIndex:21]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PAR" withString:[trxnResponse objectAtIndex:22]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"PANSUFFIX" withString:[trxnResponse objectAtIndex:23]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"CONTACTLESS" withString:[trxnResponse objectAtIndex:24]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantCategoryCode" withString:[trxnResponse objectAtIndex:25]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeLabel" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Scheme Text" withString:[trxnResponse objectAtIndex:27]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"SchemeText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:27]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"ApplicationVersion" withString:[trxnResponse objectAtIndex:29]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Disclaimer Text" withString:[trxnResponse objectAtIndex:30]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"DisclaimerText_Arabic" withString:[self checkingArabic:[trxnResponse objectAtIndex:30]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Name" withString:[trxnResponse objectAtIndex:31]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"Merchant Address" withString:[trxnResponse objectAtIndex:32]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantName_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:33]]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"MerchantAddress_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:[trxnResponse objectAtIndex:34]]]];
        return htmlString;
    }
    else if ( transactionType == 10 && htmlString != nil) { // SETTLEMENT OR Reconciliation
       
         //Buffer Receive Parsing
         NSString *printSettlment = [NSString stringWithFormat:
                               
                               @"Scheme Name \t\t\t: SchemeName \n"
                               "Scheme HOST \t\t\t: SchemeHOST \n"
                               "Transaction Available Flag  \t\t: TransactionAvailableFlag \n"
                               "Total Debit Count \t\t\t : TotalDebitCount \n"
                               "Total Debit Amount \t\t: TotalDebitAmount \n"
                               "Total Credit Count \t\t\t: TotalCreditCount \n"
                               "Total Credit Amount \t\t: TotalCreditAmount \n"
                               "NAQD Count \t\t\t: NAQDCount \n"
                               "NAQD Amount \t\t\t: NAQDAmount \n"
                               "C/ADV Count \t\t\t: CADVCount \n"
                               "C/ADV Amount \t\t\t: CADVAmount \n"
                               "Auth Count \t\t\t: AuthCount \n"
                               "Auth Amount \t\t\t: AuthAmount \n"
                               "Total Count \t\t\t: TotalCount \n"
                               "Total Amount \t\t\t: TotalAmount \n"];
        
        NSString *printSettlmentPos = [NSString stringWithFormat:
                               
                               @"Transaction Available Flag  \t\t: TransactionAvailableFlag \n"
                                "Scheme Name \t\t\t: SchemeName \n"
                               "Total Debit Count \t\t\t : TotalDebitCount \n"
                               "Total Debit Amount \t\t: TotalDebitAmount \n"
                               "Total Credit Count \t\t\t: TotalCreditCount \n"
                               "Total Credit Amount \t\t: TotalCreditAmount \n"
                               "NAQD Count \t\t\t: NAQDCount \n"
                               "NAQD Amount \t\t\t: NAQDAmount \n"
                               "C/ADV Count \t\t\t: CADVCount \n"
                               "C/ADV Amount \t\t\t: CADVAmount \n"
                               "Auth Count \t\t\t: AuthCount \n"
                               "Auth Amount \t\t\t: AuthAmount \n"
                               "Total Count \t\t\t: TotalCount \n"
                               "Total Amount \t\t\t: TotalAmount \n"];
       
        NSString *printSettlmentPosDetails = [NSString stringWithFormat:
                               
                               @"Transaction Available Flag  \t\t: TransactionAvailableFlag \n"
                               "Scheme Name \t\t\t : SchemeName \n"
                               "P/OFF Count \t\t: POFFCount \n"
                               "P/OFF Amount \t\t\t: POFFAmount \n"
                               "P/ON Count \t\t: PONCount \n"
                               "P/ON Amount \t\t\t: PONAmount \n"
                               "NAQD Count \t\t\t: NAQDCount \n"
                               "NAQD Amount \t\t\t: NAQDAmount \n"
                               "REVERSAL Count \t\t\t: REVERSALCount \n"
                               "REVERSAL Amount \t\t\t: REVERSALAmount \n"
                               "REFUND Count \t\t\t: REFUNDCount \n"
                               "REFUND Amount \t\t\t: REFUNDAmount \n"
                               "COMP Count \t\t\t: COMPCount \n"
                               "COMP Amount \t\t\t: COMPAmount \n"];
       NSString *printSettlment1 = [[NSString alloc]initWithString:printSettlment];
       NSString *printSettlmentPos1 = [[NSString alloc]initWithString:printSettlmentPos];
       NSString *printSettlmentPosDetails1 = [[NSString alloc]initWithString:printSettlmentPosDetails];
       
       NSString *printFinalReport1 = @"";
       int k = 9;
       NSNumber* count = [trxnResponse objectAtIndex:9];
       int totalSchemeLength = [count intValue];
       
       for (int i = 1; i <= totalSchemeLength; i++)
       {
           if ([trxnResponse[k + 2] isEqual: @"0"])
           {
               NSString *printSettlmentNO = [NSString stringWithFormat:
                                          @"Scheme Name \t\t\t :  %@ \n"
                                          "<No Transactions> \n",trxnResponse[k + 1]];
               k = k + 2;
               NSString *printSettlment2 = [[NSString alloc]initWithString:printSettlmentNO];
               printFinalReport1 = [printSettlment2 stringByAppendingString:printSettlment2];
           }
           else
           {
               if ([trxnResponse[k + 3]  isEqual: @"mada HOST"]) {
                   
                   if (trxnResponse.count >= k+15) {
                      
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"SchemeName" withString:[trxnResponse objectAtIndex:k + 1]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"TransactionAvailableFlag" withString:[trxnResponse objectAtIndex:k + 2]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"SchemeHOST" withString:[trxnResponse objectAtIndex:k + 3]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"TotalDebitCount" withString:[trxnResponse objectAtIndex:k + 4]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"TotalDebitAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 5]]]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"TotalCreditCount" withString:[trxnResponse objectAtIndex:k + 6]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"TotalCreditAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 7]]]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"NAQDCount" withString:[trxnResponse objectAtIndex:k + 8]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"NAQDAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 9]]]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"CADVCount" withString:[trxnResponse objectAtIndex:k + 10]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"CADVAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 11]]]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"AuthCount" withString:[trxnResponse objectAtIndex:k + 12]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"AuthAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 13]]]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"TotalCount" withString:[trxnResponse objectAtIndex:k + 14]];
                       printSettlment1 = [printSettlment1 stringByReplacingOccurrencesOfString:@"TotalAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 15]]]];
                 }
                 else {
                    break;
                 }
                 k = k + 15;
                 printFinalReport1 = [printFinalReport1 stringByAppendingString:printSettlment1];
                 printSettlment1 = [[NSString alloc]initWithString:printSettlment];
             }
             else if ([trxnResponse[k + 2]  isEqual: @"POS TERMINAL"]) {
                 
                 i = i - 1;
                 if (trxnResponse.count >= k+14) {
                    
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TransactionAvailableFlag" withString:[trxnResponse objectAtIndex:k + 1]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"SchemeName" withString:[trxnResponse objectAtIndex:k + 2]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TotalDebitCount" withString:[trxnResponse objectAtIndex:k + 3]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TotalDebitAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 4]]]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TotalCreditCount" withString:[trxnResponse objectAtIndex:k + 5]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TotalCreditAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 6]]]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"NAQDCount" withString:[trxnResponse objectAtIndex:k + 7]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"NAQDAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 8]]]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"CADVCount" withString:[trxnResponse objectAtIndex:k + 9]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"CADVAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 10]]]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"AuthCount" withString:[trxnResponse objectAtIndex:k + 11]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"AuthAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 12]]]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TotalCount" withString:[trxnResponse objectAtIndex:k + 13]];
                     printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TotalAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 14]]]];
               }
               else {
                  break;
               }
               k = k + 14;
               printFinalReport1 = [printFinalReport1 stringByAppendingString:printSettlmentPos1];
               printSettlmentPos1 = [[NSString alloc]initWithString:printSettlmentPos];
           }

             else if ([trxnResponse[k + 2]  isEqual: @"POS TERMINAL DETAILS"]) {
                 
                    i = i - 1;
                   if (trxnResponse.count >= k+14) {
                 
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"TransactionAvailableFlag" withString:[trxnResponse objectAtIndex:k + 1]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"SchemeName" withString:[trxnResponse objectAtIndex:k + 2]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"POFFCount" withString:[trxnResponse objectAtIndex:k + 3]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"POFFAmount" withString:[trxnResponse objectAtIndex:k + 4]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"PONCount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 5]]]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"PONAmount" withString:[trxnResponse objectAtIndex:k + 6]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"NAQDCount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 7]]]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"NAQDAmount" withString:[trxnResponse objectAtIndex:k + 8]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"REVERSALCount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 9]]]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"REVERSALAmount" withString:[trxnResponse objectAtIndex:k + 10]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"REFUNDCount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 11]]]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"REFUNDAmount" withString:[trxnResponse objectAtIndex:k + 12]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"COMPCount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 13]]]];
                       printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"COMPAmount" withString:[trxnResponse objectAtIndex:k + 14]];
                 }
                 else {
                    break;
                 }
                 k = k + 14;
                 printFinalReport1 = [printFinalReport1 stringByAppendingString:printSettlmentPosDetails1];
                 printSettlmentPosDetails1 = [[NSString alloc]initWithString:printSettlmentPosDetails];
               }
             else if ([trxnResponse[k + 1]  isEqual: @"0"]) {
                 
                 NSString *printSettlmentNO1 = [NSString stringWithFormat:
                                            @"Scheme Name \t\t\t: POS TERMINAL \n"
                                            "<No Transactions> \n"
                                             "Scheme Name \t\t\t: POS TERMINAL Details\n"
                                             "<No Transactions> \n"];
                 k = k + 1;
                 NSString *printSettlment2 = [[NSString alloc]initWithString:printSettlmentNO1];
                 printFinalReport1 = [printFinalReport1 stringByAppendingString:printSettlment2];
             }
          }
         }
         [_summaryReport removeAllObjects];
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[1]] forKey:@"Transaction type"];
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[2]] forKey:@"Response Code"];
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[3]] forKey:@"Response Message"];
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[4]] forKey:@"Date Time Stamp"];
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[6]] forKey:@"Trace Number"];
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[7]] forKey:@"Buss Code"];
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[8]] forKey:@"Application Version"];
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[9]] forKey:@"Total Scheme Length"];
          
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", printFinalReport1] forKey:@"Schemes"];
        
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[k+1]] forKey:@"Merchant Name"];
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[k+2]] forKey:@"Merchant Address"];
        
        [_summaryReport setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:trxnResponse[k+3]]]] forKey:@"MerchantName_Arebic"];
        [_summaryReport setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:trxnResponse[k+4]]]] forKey:@"MerchantAddress_Arebic"];
        
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[k+5]] forKey:@"ECR Transaction Reference Number"];
         [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[k+6]] forKey:@"Signature"];
                
       //HTML Response parsing
       
       NSString *builder = [[NSString alloc]initWithString:htmlString];

       NSURL *summaryToHTMLFilePosTable = [[NSBundle bundleForClass:[self class]] URLForResource:@"PosTable" withExtension:@"html"];
       NSString *summaryhtmlStringPosTable = [NSString stringWithContentsOfURL:summaryToHTMLFilePosTable encoding:NSUTF8StringEncoding error:nil];
       NSString *htmlSummaryReportPosTable = summaryhtmlStringPosTable;
       
       NSURL *summaryToHTMLFileMadaHost = [[NSBundle bundleForClass:[self class]] URLForResource:@"madaHostTable" withExtension:@"html"];
       NSString *summaryhtmlStringMadaHost = [NSString stringWithContentsOfURL:summaryToHTMLFileMadaHost encoding:NSUTF8StringEncoding error:nil];
       NSString *htmlSummaryReportMadaHost = summaryhtmlStringMadaHost;
        
       NSURL *summaryToHTMLFilePosDetials = [[NSBundle bundleForClass:[self class]] URLForResource:@"PosTerminalDetails" withExtension:@"html"];
       NSString *summaryhtmlStringPosDetials = [NSString stringWithContentsOfURL:summaryToHTMLFilePosDetials encoding:NSUTF8StringEncoding error:nil];
       NSString *htmlSummaryReportPosDetials = summaryhtmlStringPosDetials;
       
       NSString *SummaryFinalReport = @"";
       
       int b = 9;
       NSNumber *coun = [trxnResponse objectAtIndex:9];
       int totalSchemeLengthL = [coun intValue];
       
       for (int j = 1; j <= totalSchemeLengthL; j++) {

           if ([trxnResponse[b + 2] isEqual: @"0"]) {
               
               NSURL *ReconcilationToHTMLFile = [[NSBundle bundleForClass:[self class]] URLForResource:@"ReconcilationTable" withExtension:@"html"];
               NSString *ReconcilationNoTable = [NSString stringWithContentsOfURL:ReconcilationToHTMLFile encoding:NSUTF8StringEncoding error:nil];
               NSString *htmlreconcilationNoTable = ReconcilationNoTable;
               
               NSString *res = trxnResponse[b + 1];
               NSString *arabi = [self checkingArabic:res];
               
               arabi = [arabi stringByReplacingOccurrencesOfString:@"\u08F1" withString:@""];

               htmlreconcilationNoTable = [htmlreconcilationNoTable stringByReplacingOccurrencesOfString:@"Scheme" withString:trxnResponse[b + 1]];
               htmlreconcilationNoTable = [htmlreconcilationNoTable stringByReplacingOccurrencesOfString:@"قَدِيرٞ" withString:arabi];
               
               b = b + 3;
               
               SummaryFinalReport = [SummaryFinalReport stringByAppendingString:htmlreconcilationNoTable];
               htmlreconcilationNoTable = ReconcilationNoTable;
               
           }
           else {
                if ([trxnResponse[b + 3]  isEqual: @"mada HOST"]) {
                    
                     if (trxnResponse.count >= b+15) {
                        j = j - 1;
                        NSString *res = trxnResponse[b + 1];
                        NSString *arabi = [self checkingArabic:res];
                        arabi = [arabi stringByReplacingOccurrencesOfString:@"\u08F1" withString:@""];
                        htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"مدى" withString:arabi];
                         
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"schemename" withString:[trxnResponse objectAtIndex: b + 1]];
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"totalDBCount" withString:[trxnResponse objectAtIndex:b + 4]];
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"totalDBAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 5]]]];
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"totalCBCount" withString:[trxnResponse objectAtIndex:b + 6]];
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"totalCBAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 7]]]];
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"NAQDCount" withString:[trxnResponse objectAtIndex:b + 8]];
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"NAQDAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 9]]]];
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"CADVCount" withString:[trxnResponse objectAtIndex:b + 10]];
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"CADVAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 11]]]];
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"AUTHCount" withString:[trxnResponse objectAtIndex:b + 12]];
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"AUTHAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 13]]]];
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"TOTALSCount" withString:[trxnResponse objectAtIndex:b + 14]];
                       htmlSummaryReportMadaHost = [htmlSummaryReportMadaHost stringByReplacingOccurrencesOfString:@"TOTALSAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 15]]]];

                       }else {
                         break;
                       }
                       b = b + 15;
                       SummaryFinalReport = [SummaryFinalReport stringByAppendingString:htmlSummaryReportMadaHost];
                       htmlSummaryReportMadaHost = [[NSString alloc]initWithString:summaryhtmlStringMadaHost];
                 }
                 else if ([trxnResponse[b + 2]  isEqual: @"POS TERMINAL"]) {
                   
                    if (trxnResponse.count >= b+14) {
                         
                      j = j - 1;
                         
                       htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"totalDBCount" withString:[trxnResponse objectAtIndex:b + 3]];
                       htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"totalDBAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 4]]]];
                       htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"totalCBCount" withString:[trxnResponse objectAtIndex:b + 5]];
                       htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"totalCBAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 6]]]];
                       htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"NAQDCount" withString:[trxnResponse objectAtIndex:b + 7]];
                       htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"NAQDAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 8]]]];
                       htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"CADVCount" withString:[trxnResponse objectAtIndex:b + 9]];
                       htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"CADVAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 10]]]];
                       htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"AUTHCount" withString:[trxnResponse objectAtIndex:b + 11]];
                       htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"AUTHAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 12]]]];
                       htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"TOTALSCount" withString:trxnResponse[13]];
                       htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"TOTALSAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[14]]]];

                       }else {
                         break;
                       }
                       b = b + 14;
                       SummaryFinalReport = [SummaryFinalReport stringByAppendingString:htmlSummaryReportPosTable];
                       htmlSummaryReportPosTable = [[NSString alloc]initWithString:summaryhtmlStringPosTable];
                 }
                 else if ([trxnResponse[b + 2]  isEqual: @"POS TERMINAL DETAILS"]) {
                    
                   if (trxnResponse.count >= b+14) {
                       
                         j = j - 1;
                         htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"totalDBCount" withString:[trxnResponse objectAtIndex:b + 3]];
                         htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"totalDBAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 4]]]];
                         htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"totalCBCount" withString:[trxnResponse objectAtIndex:b + 5]];
                         htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"totalCBAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 6]]]];
                         htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"NAQDCount" withString:[trxnResponse objectAtIndex:b + 7]];
                         htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"NAQDAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 8]]]];
                         htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"CADVCount" withString:[trxnResponse objectAtIndex:b + 9]];
                         htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"CADVAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 10]]]];
                         htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"AUTHCount" withString:[trxnResponse objectAtIndex:b + 11]];
                         htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"AUTHAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[b + 12]]]];
                         
                         htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"TOTALSCount" withString:trxnResponse[13]];
                         htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"TOTALSAmount" withString:[self decimalWithCommaSeperated:[NSString stringWithFormat:@"%@", trxnResponse[14]]]];

                     }else {
                       break;
                     }
                     b = b + 14;
                     SummaryFinalReport = [SummaryFinalReport stringByAppendingString:htmlSummaryReportPosDetials];
                     htmlSummaryReportPosDetials = [[NSString alloc]initWithString:summaryhtmlStringPosDetials];
                }
                else if ([trxnResponse[b + 2]  isEqual: @"POS TERMINAL DETAILS"]) {
                     NSURL *ReconcilationToHTMLFile = [[NSBundle bundleForClass:[self class]] URLForResource:@"ReconcilationTable1" withExtension:@"html"];
                     NSString *ReconcilationNoTable = [NSString stringWithContentsOfURL:ReconcilationToHTMLFile encoding:NSUTF8StringEncoding error:nil];
                     NSString *SummaryFinalReport = ReconcilationNoTable;
                     b = b + 1;
                }
           }
       }
       
       builder = [builder stringByReplacingOccurrencesOfString:@"PosTable" withString:SummaryFinalReport];
       builder = [builder stringByReplacingOccurrencesOfString:@"merchantId" withString:trxnResponse[5]];
       builder = [builder stringByReplacingOccurrencesOfString:@"busscode" withString:trxnResponse[6]];
       builder = [builder stringByReplacingOccurrencesOfString:@"traceNumber" withString:trxnResponse[7]];
       builder = [builder stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[4]]];
       builder = [builder stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[4]]];
       builder = [builder stringByReplacingOccurrencesOfString:@"AppVersion" withString:trxnResponse[8]];
       
       NSString *teminalID = [[NSUserDefaults standardUserDefaults]valueForKey:@"terminalSerialNumber"];
       if (teminalID.length > 9) {
           NSString *terminal = [teminalID substringWithRange:NSMakeRange( 0, 8)];
           builder = [builder stringByReplacingOccurrencesOfString:@"TerminalId" withString:terminal];
       }
        
        b = (int)trxnResponse.count - 8;
       builder = [builder stringByReplacingOccurrencesOfString:@"Merchant Name" withString:trxnResponse[b+1]];
       builder = [builder stringByReplacingOccurrencesOfString:@"Merchant Address" withString:trxnResponse[b+2]];
       builder = [builder stringByReplacingOccurrencesOfString:@"MerchantName_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:trxnResponse[b+3]]]];
       builder = [builder stringByReplacingOccurrencesOfString:@"MerchantAddress_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:trxnResponse[b+4]]]];
       builder = [builder stringByReplacingOccurrencesOfString:@"MADA" withString:@"mada"];    
       return builder;
   }
   else if ((transactionType == 21 || transactionType == 26) && htmlString != nil) {   // PRINT DETAIL REPORT OR RUNNING TOTAL
        
          //Buffer Receive Parsing
          NSString *printSettlmentPos = [NSString stringWithFormat:
                                
                                @"Scheme Name \t\t\t: SchemeName \n"
                                "Scheme HOST \t\t\t: SchemeHOST \n"
                                "Transaction Available Flag  \t\t: TransactionAvailableFlag \n"
                                "Total Debit Count \t\t\t : TotalDebitCount \n"
                                "Total Debit Amount \t\t: TotalDebitAmount \n"
                                "Total Credit Count \t\t\t: TotalCreditCount \n"
                                "Total Credit Amount \t\t: TotalCreditAmount \n"
                                "NAQD Count \t\t\t: NAQDCount \n"
                                "NAQD Amount \t\t\t: NAQDAmount \n"
                                "C/ADV Count \t\t\t: CADVCount \n"
                                "C/ADV Amount \t\t\t: CADVAmount \n"
                                "Auth Count \t\t\t: AuthCount \n"
                                "Auth Amount \t\t\t: AuthAmount \n"
                                "Total Count \t\t\t: TotalCount \n"
                                "Total Amount \t\t\t: TotalAmount \n"];
        
         NSString *printSettlmentPosDetails = [NSString stringWithFormat:
                                
                                @"Transaction Available Flag  \t\t: TransactionAvailableFlag \n"
                                "Scheme Name \t\t\t : SchemeName \n"
                                "P/OFF Count \t\t: POFFCount \n"
                                "P/OFF Amount \t\t\t: POFFAmount \n"
                                "P/ON Count \t\t: PONCount \n"
                                "P/ON Amount \t\t\t: PONAmount \n"
                                "NAQD Count \t\t\t: NAQDCount \n"
                                "NAQD Amount \t\t\t: NAQDAmount \n"
                                "REVERSAL Count \t\t\t: REVERSALCount \n"
                                "REVERSAL Amount \t\t\t: REVERSALAmount \n"
                                "REFUND Count \t\t\t: REFUNDCount \n"
                                "REFUND Amount \t\t\t: REFUNDAmount \n"
                                "COMP Count \t\t\t: COMPCount \n"
                                "COMP Amount \t\t\t: COMPAmount \n"];
        NSString *printSettlmentPos1 = [[NSString alloc]initWithString:printSettlmentPos];
        NSString *printSettlmentPosDetails1 = [[NSString alloc]initWithString:printSettlmentPosDetails];
        
        NSString *printFinalReport1 = @"";
        int k = 8;
        NSNumber* count = [trxnResponse objectAtIndex:8];
        int totalSchemeLength = [count intValue];
        
        for (int i = 1; i <= totalSchemeLength; i++)
        {
            if ([trxnResponse[k + 2] isEqual: @"0"])
            {
                NSString *printSettlmentNO = [NSString stringWithFormat:
                                           @"Scheme Name \t\t\t :  %@ \n"
                                           "<No Transactions> \n",trxnResponse[k + 1]];
                k = k + 2;
                NSString *printSettlment2 = [[NSString alloc]initWithString:printSettlmentNO];
                printFinalReport1 = [printFinalReport1 stringByAppendingString:printSettlment2];
            }
            else
            {
                if ([trxnResponse[k + 3]  isEqual: @"POS TERMINAL"]) {
                    
                    if (trxnResponse.count >= k+15) {
                       
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"SchemeName" withString:[trxnResponse objectAtIndex:k + 1]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TransactionAvailableFlag" withString:[trxnResponse objectAtIndex:k + 2]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"SchemeHOST" withString:[trxnResponse objectAtIndex:k + 3]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TotalDebitCount" withString:[trxnResponse objectAtIndex:k + 4]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TotalDebitAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 5]]]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TotalCreditCount" withString:[trxnResponse objectAtIndex:k + 6]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TotalCreditAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 7]]]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"NAQDCount" withString:[trxnResponse objectAtIndex:k + 8]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"NAQDAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 9]]]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"CADVCount" withString:[trxnResponse objectAtIndex:k + 10]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"CADVAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 11]]]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"AuthCount" withString:[trxnResponse objectAtIndex:k + 12]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"AuthAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 13]]]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TotalCount" withString:[trxnResponse objectAtIndex:k + 14]];
                        printSettlmentPos1 = [printSettlmentPos1 stringByReplacingOccurrencesOfString:@"TotalAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 15]]]];
                  }
                  else {
                     break;
                  }
                  k = k + 15;
                  printFinalReport1 = [printFinalReport1 stringByAppendingString:printSettlmentPos1];
                  printSettlmentPos1 = [[NSString alloc]initWithString:printSettlmentPos];
              }
              else if ([trxnResponse[k + 2]  isEqual: @"POS TERMINAL DETAILS"]) {
                  
                     i = i - 1;
                    if (trxnResponse.count >= k+14) {
                  
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"TransactionAvailableFlag" withString:[trxnResponse objectAtIndex:k + 1]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"SchemeName" withString:[trxnResponse objectAtIndex:k + 2]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"POFFCount" withString:[trxnResponse objectAtIndex:k + 3]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"POFFAmount" withString:[trxnResponse objectAtIndex:k + 4]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"PONCount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 5]]]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"PONAmount" withString:[trxnResponse objectAtIndex:k + 6]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"NAQDCount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 7]]]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"NAQDAmount" withString:[trxnResponse objectAtIndex:k + 8]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"REVERSALCount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 9]]]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"REVERSALAmount" withString:[trxnResponse objectAtIndex:k + 10]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"REFUNDCount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 11]]]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"REFUNDAmount" withString:[trxnResponse objectAtIndex:k + 12]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"COMPCount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[k + 13]]]];
                        printSettlmentPosDetails1 = [printSettlmentPosDetails1 stringByReplacingOccurrencesOfString:@"COMPAmount" withString:[trxnResponse objectAtIndex:k + 14]];
                  }
                  else {
                     break;
                  }
                  k = k + 14;
                  printFinalReport1 = [printFinalReport1 stringByAppendingString:printSettlmentPosDetails1];
                  printSettlmentPosDetails1 = [[NSString alloc]initWithString:printSettlmentPosDetails];
             }
           }
          }
          [_summaryReport removeAllObjects];
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[1]] forKey:@"Transaction type"];
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[2]] forKey:@"Response Code"];
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[3]] forKey:@"Response Message"];
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[4]] forKey:@"Date Time Stamp"];
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[5]] forKey:@"Merchant id"];
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[6]] forKey:@"Buss Code"];
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[7]] forKey:@"Application Version"];
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[8]] forKey:@"Total Scheme Length"];
           
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", printFinalReport1] forKey:@"Schemes"];
       
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[k+1]] forKey:@"Merchant Name"];
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[k+2]] forKey:@"Merchant Address"];
       
           [_summaryReport setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:trxnResponse[k+3]]]] forKey:@"MerchantName_Arebic"];
            [_summaryReport setValue:[NSString stringWithFormat:@"%@", [self encodingISO_8859_6:[self hexStringToData:trxnResponse[k+4]]]] forKey:@"MerchantAddress_Arebic"];
       
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[k+5]] forKey:@"ECR Transaction Reference Number"];
          [_summaryReport setValue:[NSString stringWithFormat:@"%@", trxnResponse[k+6]] forKey:@"Signature"];
                 
        //HTML Response parsing
        
        NSString *builder = [[NSString alloc]initWithString:htmlString];

        NSURL *bundlePaths = [[NSBundle bundleForClass:[self class]] URLForResource:@"PosTableRunning" withExtension:@"html"];
        NSString *summaryhtmlStringPosTable = [NSString stringWithContentsOfURL:bundlePaths encoding:NSUTF8StringEncoding error:nil];
        NSString *htmlSummaryReportPosTable = summaryhtmlStringPosTable;
        
        NSURL *summaryToHTMLFilePosDetials = [[NSBundle bundleForClass:[self class]] URLForResource:@"PosTerminalDetails" withExtension:@"html"];
        NSString *summaryhtmlStringPosDetials = [NSString stringWithContentsOfURL:summaryToHTMLFilePosDetials encoding:NSUTF8StringEncoding error:nil];
        NSString *htmlSummaryReportPosDetials = summaryhtmlStringPosDetials;
        
        NSString *SummaryFinalReport = @"";
        
        int b = 8;
        NSNumber *coun = [trxnResponse objectAtIndex:8];
        int totalSchemeLengthL = [coun intValue];
        
        for (int j = 1; j <= totalSchemeLengthL; j++) {

            if ([trxnResponse[b + 2] isEqual: @"0"]) {
                
                NSURL *tableUrl = [[NSBundle bundleForClass:[self class]] URLForResource:@"ReconcilationTable" withExtension:@"html"];
                NSString *ReconcilationNoTable = [NSString stringWithContentsOfURL:tableUrl encoding:NSUTF8StringEncoding error:nil];
                NSString *htmlreconcilationNoTable = ReconcilationNoTable;
                
                NSString *res = trxnResponse[b + 1];
                NSString *arabi = [self checkingArabic:res];
                
                arabi = [arabi stringByReplacingOccurrencesOfString:@"\u08F1" withString:@""];

                htmlreconcilationNoTable = [htmlreconcilationNoTable stringByReplacingOccurrencesOfString:@"Scheme" withString:trxnResponse[b + 1]];
                htmlreconcilationNoTable = [htmlreconcilationNoTable stringByReplacingOccurrencesOfString:@"قَدِيرٞ" withString:arabi];
                
                b = b + 2;
                
                SummaryFinalReport = [SummaryFinalReport stringByAppendingString:htmlreconcilationNoTable];
                htmlreconcilationNoTable = ReconcilationNoTable;
                
            }
            else {
                if ([trxnResponse[b + 3]  isEqual: @"POS TERMINAL"]) {
                    
                      if (trxnResponse.count >= b+15) {
                          
                         NSString *res = trxnResponse[b + 1];
                         NSString *arabi = [self checkingArabic:res];
                         arabi = [arabi stringByReplacingOccurrencesOfString:@"\u08F1" withString:@""];
                         htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"مدى" withString:arabi];
                          
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"schemename" withString:[trxnResponse objectAtIndex: b + 1]];
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"totalDBCount" withString:[trxnResponse objectAtIndex:b + 4]];
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"totalDBAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[b + 5]]]];
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"totalCBCount" withString:[trxnResponse objectAtIndex:b + 6]];
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"totalCBAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[b + 7]]]];
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"NAQDCount" withString:[trxnResponse objectAtIndex:b + 8]];
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"NAQDAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[b + 9]]]];
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"CADVCount" withString:[trxnResponse objectAtIndex:b + 10]];
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"CADVAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[b + 11]]]];
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"AUTHCount" withString:[trxnResponse objectAtIndex:b + 12]];
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"AUTHAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[b + 13]]]];
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"TOTALSCount" withString:trxnResponse[14]];
                        htmlSummaryReportPosTable = [htmlSummaryReportPosTable stringByReplacingOccurrencesOfString:@"TOTALSAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[15]]]];

                        }else {
                          break;
                        }
                        b = b + 15;
                        SummaryFinalReport = [SummaryFinalReport stringByAppendingString:htmlSummaryReportPosTable];
                        htmlSummaryReportPosTable = [[NSString alloc]initWithString:summaryhtmlStringPosTable];
                  }
                  else if ([trxnResponse[b + 2]  isEqual: @"POS TERMINAL DETAILS"]) {
                     
                    if (trxnResponse.count >= b+14) {
                        
                          j = j - 1;
                          htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"totalDBCount" withString:[trxnResponse objectAtIndex:b + 3]];
                          htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"totalDBAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[b + 4]]]];
                          htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"totalCBCount" withString:[trxnResponse objectAtIndex:b + 5]];
                          htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"totalCBAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[b + 6]]]];
                          htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"NAQDCount" withString:[trxnResponse objectAtIndex:b + 7]];
                          htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"NAQDAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[b + 8]]]];
                          htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"CADVCount" withString:[trxnResponse objectAtIndex:b + 9]];
                          htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"CADVAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[b + 10]]]];
                          htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"AUTHCount" withString:[trxnResponse objectAtIndex:b + 11]];
                          htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"AUTHAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[b + 12]]]];
                          
                          htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"TOTALSCount" withString:trxnResponse[13]];
                          htmlSummaryReportPosDetials = [htmlSummaryReportPosDetials stringByReplacingOccurrencesOfString:@"TOTALSAmount" withString:[self decimalValue:[NSString stringWithFormat:@"%@", trxnResponse[14]]]];

                      }else {
                        break;
                      }
                      b = b + 14;
                      SummaryFinalReport = [SummaryFinalReport stringByAppendingString:htmlSummaryReportPosDetials];
                      htmlSummaryReportPosDetials = [[NSString alloc]initWithString:summaryhtmlStringPosDetials];
                 }
            }
        }
        
        builder = [builder stringByReplacingOccurrencesOfString:@"PosTable" withString:SummaryFinalReport];
        builder = [builder stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[4]]];
        builder = [builder stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[4]]];
        builder = [builder stringByReplacingOccurrencesOfString:@"RetailerId" withString:trxnResponse[5]];
        builder = [builder stringByReplacingOccurrencesOfString:@"Buzzcode" withString:trxnResponse[6]];
        builder = [builder stringByReplacingOccurrencesOfString:@"AppVersion" withString:trxnResponse[7]];
        
        NSString *teminalID = [[NSUserDefaults standardUserDefaults]valueForKey:@"terminalSerialNumber"];
//        if (teminalID.length > 9) {
//            NSString *terminal = [teminalID substringWithRange:NSMakeRange( 0, 8)];
//            builder = [builder stringByReplacingOccurrencesOfString:@"TerminalId" withString:terminal];
//        }
       builder = [builder stringByReplacingOccurrencesOfString:@"TerminalId" withString:teminalID];
       
       builder = [builder stringByReplacingOccurrencesOfString:@"Merchant Name" withString:trxnResponse[b+1]];
       builder = [builder stringByReplacingOccurrencesOfString:@"Merchant Address" withString:trxnResponse[b+2]];
       builder = [builder stringByReplacingOccurrencesOfString:@"MerchantName_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:trxnResponse[b+3]]]];
       builder = [builder stringByReplacingOccurrencesOfString:@"MerchantAddress_Arebic" withString:[self encodingISO_8859_6:[self hexStringToData:trxnResponse[b+4]]]];
       builder = [builder stringByReplacingOccurrencesOfString:@"MADA" withString:@"mada"];
       if(transactionType == 21)
           builder = [builder stringByReplacingOccurrencesOfString:@"running balance" withString:@"RUNNING BALANCE"];
       else
           builder = [builder stringByReplacingOccurrencesOfString:@"running balance" withString:@"SNAPSHOT BALANCE"];
       return builder;
    }
    else if (transactionType == 22 && htmlString != nil) { // PRINT SUMMARY REPORT
                
        NSString *builder = [[NSString alloc]initWithString:htmlString];

        NSString *summaryhtmlString = @"";
        NSURL *bundlePaths = [[NSBundle bundleForClass:[self class]] URLForResource:@"Summary" withExtension:@"html"];
        summaryhtmlString = [NSString stringWithContentsOfURL:bundlePaths encoding:NSUTF8StringEncoding error:nil];
        
        NSString *htmlSummaryReport = [[NSString alloc]initWithString:summaryhtmlString];
        NSString *SummaryFinalReport = @"";

        int j = 5;
        NSNumber* count = [trxnResponse objectAtIndex:4];
        int transactionsLength = [count intValue];
        
        for (int i = 1; i <= transactionsLength; i++) {
               
            if (trxnResponse.count >= j+8) {
                htmlSummaryReport = [htmlSummaryReport stringByReplacingOccurrencesOfString:@"transactionType" withString:[trxnResponse objectAtIndex:j]];
                htmlSummaryReport = [htmlSummaryReport stringByReplacingOccurrencesOfString:@"transactionDate" withString:[trxnResponse objectAtIndex:j+1]];
                htmlSummaryReport = [htmlSummaryReport stringByReplacingOccurrencesOfString:@"transactionRRN" withString:[trxnResponse objectAtIndex:j+2]];
                htmlSummaryReport = [htmlSummaryReport stringByReplacingOccurrencesOfString:@"transactionAmount" withString:[trxnResponse objectAtIndex:j+3]];
                htmlSummaryReport = [htmlSummaryReport stringByReplacingOccurrencesOfString:@"transactionState" withString:[trxnResponse objectAtIndex:j+4]];
                htmlSummaryReport = [htmlSummaryReport stringByReplacingOccurrencesOfString:@"transactionTime" withString:[trxnResponse objectAtIndex:j+5]];
                htmlSummaryReport = [htmlSummaryReport stringByReplacingOccurrencesOfString:@"transactionPANNumber" withString:[trxnResponse objectAtIndex:j+6]];
                htmlSummaryReport = [htmlSummaryReport stringByReplacingOccurrencesOfString:@"authCode" withString:[trxnResponse objectAtIndex:j+7]];
                htmlSummaryReport = [htmlSummaryReport stringByReplacingOccurrencesOfString:@"transactionNumber" withString:[trxnResponse objectAtIndex:j+8]];

            }else {
              break;
            }
            SummaryFinalReport = [NSString stringWithFormat:@"%@%@",SummaryFinalReport,htmlSummaryReport];
            htmlSummaryReport = [[NSString alloc]initWithString:summaryhtmlString];

            j = j + 9;
        }
        
        builder = [builder stringByReplacingOccurrencesOfString:@"no_Transaction" withString:SummaryFinalReport];
        builder = [builder stringByReplacingOccurrencesOfString:@"currentTime" withString:[self getTime:trxnResponse[4]]];
        builder = [builder stringByReplacingOccurrencesOfString:@"currentDate" withString:[self getDate:trxnResponse[4]]];
        
        NSString *teminalID = [[NSUserDefaults standardUserDefaults]valueForKey:@"terminalSerialNumber"];
        if (teminalID.length > 9) {
            NSString *terminal = [teminalID substringWithRange:NSMakeRange( 0, 8)];
            builder = [builder stringByReplacingOccurrencesOfString:@"terminalId" withString:terminal];
        }
        return builder;
    }

    return htmlString;
}

-(NSString*)getDate:(NSString*)inputDate {
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc]init];
    [dateFormatter setDateFormat:@"YYYY"];
    NSString *year = [dateFormatter stringFromDate:[NSDate date]];
    NSLog(@"%@",year);
    
    if (inputDate.length > 3) {
        NSString *date = [inputDate substringWithRange:NSMakeRange( 2, 2)];
        NSString *month =  [inputDate substringWithRange:NSMakeRange( 0, 2)];
        return [NSString stringWithFormat:@"%@/%@/%@",date,month,year];
    }
    return @"";
}

-(NSString*)getTime:(NSString*)inputDate {
    
    if (inputDate.length > 9) {
        NSString *hours   =  [inputDate substringWithRange:NSMakeRange( 4, 2)];
        NSString *mins    =  [inputDate substringWithRange:NSMakeRange( 6, 2)];
        NSString *seconds =  [inputDate substringWithRange:NSMakeRange( 8, 2)];
        return [NSString stringWithFormat:@"%@:%@:%@",hours,mins,seconds];
    }
    return @"";
}

-(NSString*)expiryDate:(NSString*)expDate {
    
    if (expDate.length > 3) {
        NSString *month = [expDate substringWithRange:NSMakeRange( 0, 2)];
        NSString *year =  [expDate substringWithRange:NSMakeRange( 2, 2)];
        return [NSString stringWithFormat:@"%@/%@",month,year];
    }
    return expDate;
}

//MARK: - NSStreamDelegate Methods -

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent {
    
    NSLog(@"NSStreamDelegate Stream Event: %@", @(streamEvent));
    
    switch (streamEvent) {
        case NSStreamEventNone:
            NSLog(@"NSStreamEventNone");
            break;

        case NSStreamEventOpenCompleted:
            NSLog(@"NSStreamEventOpenCompleted");
            [self connectSuccess:theStream];
            break;

        case NSStreamEventHasBytesAvailable:
            NSLog(@"NSStreamEventOpenCompleted");
            if (theStream == self.inputStream) {

                uint8_t buffer[1024];
                NSInteger len;

                while ([self.inputStream hasBytesAvailable]) {
                    memset(buffer, 0x00, sizeof(buffer));
                    len = [self.inputStream read:buffer maxLength:sizeof(buffer)];
                    if (len > 0) {
                        NSString *output = [[NSString alloc] initWithBytes:buffer length:len encoding:NSASCIIStringEncoding];
                        if (nil != output) {
                            NSLog(@"Server Output: %@", output);
                            [self receivedData:buffer];
                        }
                    }
                }
            }
            break;

        case NSStreamEventHasSpaceAvailable:
            NSLog(@"NSStreamEventHasSpaceAvailable");
            break;
            
        case NSStreamEventErrorOccurred:
            NSLog(@"NSStreamEventErrorOccurred: %@", theStream.streamError);
            [self connectFailure];
            break;

        case NSStreamEventEndEncountered:
            NSLog(@"NSStreamEventEndEncountered");
            
            [self disConnectSocket];
            
            if ([self.delegate respondsToSelector:@selector(socketConnectionStreamDidDisconnect:willReconnectAutomatically:)]) {
                
                [self.delegate socketConnectionStreamDidDisconnect:self willReconnectAutomatically:self.shouldReconnectAutomatically];
            }
            if (self.shouldReconnectAutomatically) {
                
                [self reconnectAutomatically];
            }
            break;

        default:
            NSLog(@"Unknown NSStreamEvent");
    }
 }

-(NSString *)checkingArabic:(NSString *)inputCommand {
    
    NSString *arabic = @"";
    
    if ([inputCommand  isEqual: @"mada"]) {
      arabic = @"مدى";
    }
    else if ([inputCommand  isEqual: @"VISA ELECTRON"]) {
        arabic = @"فيزا";
    }
    else if ([inputCommand  isEqual: @"MAESTRO"] ) {
        arabic = @"مايسترو";
    }
    else if ([inputCommand  isEqual: @"AMEX"]) {
        arabic = @"امريكان اكسبرس";
    }
    else if ([inputCommand  isEqual: @"AMERICAN EXPRESS"]) {
        arabic = @"امريكان اكسبرس";
    }
    else if ([inputCommand  isEqual: @"MASTER"] ) {
        arabic = @"ماستر كارد";
    }
    else if ([inputCommand  isEqual: @"MASTERCARD"] ) {
        arabic = @"ماستر كارد";
    }
    else if ([inputCommand  isEqual: @"VISA"]) {
        arabic = @"فيزا";
    }
    else if ([inputCommand  isEqual: @"GCCNET"]) {
        arabic = @"الشبكة الخليجية";
    }
    else if ([inputCommand  isEqual: @"JCB"]) {
        arabic = @"ج س ب";
    }
    else if ([inputCommand  isEqual: @"DISCOVER"] ) {
        arabic = @"ديسكفر";
    }
    else if ([inputCommand  isEqual: @"SAR"] ) {
       arabic = @"ريال";
    }
    else if ([inputCommand  isEqual: @"MADA"] ) {
       arabic = @"مدى";
    }
    else if ([inputCommand  isEqual: @"APPROVED"] ) {
       arabic = @"مقبولة";
    }
    else if ([inputCommand  isEqual: @"DECLINED"] || [inputCommand  isEqual: @"DECLINE"]  ) {
       arabic = @"العملية مرفوضه";
    }
    else if ([inputCommand  isEqual: @"ACCEPTED"] ) {
       arabic = @"مستلمة";
    }
    else if ([inputCommand  isEqual: @"NOT ACCEPTED"] ) {
       arabic = @"غير مستلمة";
    }
    else if ([inputCommand  isEqual: @"CARDHOLDER VERIFIED BY SIGNATURE"] ) {
       arabic = @"تم التحقق بتوقيع العميل";
    }
    else if ([inputCommand  isEqual: @"CARDHOLDER PIN VERIFIED"] ) {
        arabic = @"تم التحقق من الرقم السري للعميل";
    }
    else if ([inputCommand  isEqual: @"DEVICE OWNER IDENTITY VERIFIED"] ) {
        arabic = @"تم التحقق من هوية حامل الجهاز";
    }
    else if ([inputCommand  isEqual: @"NO VERIFICATION REQUIRED"] ) {
        arabic = @"لا يتطلب التحقق";
    }
    else if ([inputCommand  isEqual: @"INCORRECT PIN"] ) {
        arabic = @"رقم التعريف الشخصي غير صحيح";
    }
    else {
        arabic = @"";
    }
    return arabic;
  }

-(NSString *)numToArabicConverter:(NSString *)input {
    
    if ( [input isEqual:[NSNull null]] )
        return @"";

    NSString *myString = [input stringByReplacingOccurrencesOfString:@"1" withString:@"۱"];
    myString = [myString stringByReplacingOccurrencesOfString:@"2" withString:@"۲"];
    myString =[myString stringByReplacingOccurrencesOfString:@"3" withString:@"۳"];
    myString =[myString stringByReplacingOccurrencesOfString:@"4" withString:@"۴"];
    myString =[myString stringByReplacingOccurrencesOfString:@"5" withString:@"۵"];
    myString =[myString stringByReplacingOccurrencesOfString:@"6" withString:@"۶"];
    myString =[myString stringByReplacingOccurrencesOfString:@"7" withString:@"۷"];
    myString =[myString stringByReplacingOccurrencesOfString:@"8" withString:@"۸"];
    myString =[myString stringByReplacingOccurrencesOfString:@"9" withString:@"۹"];
    myString =[myString stringByReplacingOccurrencesOfString:@"0" withString:@"۰"];
    return myString;
}

-(NSString *)decimalValue:(NSString*)inputString {
    
    float floatAmt = [inputString floatValue]/100;
    NSString *response = [NSString stringWithFormat:@"%0.2f",floatAmt];
    return response;
}

-(NSString *)decimalWithCommaSeperated:(NSString*)inputString {
    NSLog(@"decimalWithCommaSeperated: inputString = %@", inputString);
    float floatAmt = [inputString floatValue]/100;
    
    NSNumberFormatter * formatter = [NSNumberFormatter new];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_IN"]];
    //[formatter setMinimumFractionDigits:2]; // Set this if you need 2 digits
    [formatter setMaximumFractionDigits:2]; // Set this if you need 2 digits
    NSString * response =  [formatter stringFromNumber:[NSNumber numberWithFloat:floatAmt]];
    NSLog(@"decimalWithCommaSeperated: response = %@", response);
    return response;
}

-(NSString *) encodingISO_8859_6:(NSData *)data
{
    CFStringEncoding cfEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)@"iso-8859-6");
    unsigned long nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding);
    NSString *encodedSting = [[NSString alloc] initWithData:data encoding:nsEncoding];
    return encodedSting;
}

-(NSData *) hexStringToData:(NSString*)inputString
{
    NSUInteger inLength = [inputString length];
    unichar *inCharacters = alloca(sizeof(unichar) * inLength);
    [inputString getCharacters:inCharacters range:NSMakeRange(0, inLength)];

    UInt8 *outBytes = malloc(sizeof(UInt8) * ((inLength / 2) + 1));

    NSInteger i, o = 0;
    UInt8 outByte = 0;

    for (i = 0; i < inLength; i++) {
        UInt8 c = inCharacters[i];
        SInt8 value = -1;

        if      (c >= '0' && c <= '9') value =      (c - '0');
        else if (c >= 'A' && c <= 'F') value = 10 + (c - 'A');
        else if (c >= 'a' && c <= 'f') value = 10 + (c - 'a');

        if (value >= 0) {
            if (i % 2 == 1) {
                outBytes[o++] = (outByte << 4) | value;
                outByte = 0;
            } else {
                outByte = value;
            }

        } else {
            if (o != 0) break;
        }
    }
    NSData *a = [[NSData alloc] initWithBytesNoCopy:outBytes length:o freeWhenDone:YES];
    return a;

}

- (UIViewController *)currentTopViewController {
    UIViewController *topVC = [[[UIApplication sharedApplication] keyWindow] rootViewController];
    while (topVC.presentedViewController)
    {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

@end
