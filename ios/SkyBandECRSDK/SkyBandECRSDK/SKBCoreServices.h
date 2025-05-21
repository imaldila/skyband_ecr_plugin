//
//  SkybandConnectionManager.h
//  SkybandConnectionManager
//
//  Created by vijayasimhareddy on 03/03/20.
//  Copyright © 2020 GirmitiSoftwares. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SocketConnectionDelegate;

@interface SKBCoreServices : NSObject

//MARK: - Connection Properties -

@property (nonatomic, assign) id<SocketConnectionDelegate> delegate;
@property (nonatomic, readonly) BOOL connected;
@property (nonatomic) BOOL shouldReconnectAutomatically;
@property (nonatomic) NSTimeInterval reconnectTimeInterval;
@property (nonatomic) NSTimeInterval timeoutTimeInterval;
@property (nonatomic, strong) NSString *ipAdress;
@property (nonatomic) NSUInteger portNumber;

+ (SKBCoreServices *)shareInstance;

//MARK: - Connection Methods -
- (void)connectSocket:(NSString *)ipAddress portNumber:(NSUInteger)portNumber;
- (void)disConnectSocket;
- (NSString*)computeSha256Hash:(NSString *)inputString;
//MARK: - Transaction Method -

- (void)doTCPIPTransaction:(NSString *)ipAddress portNumber:(NSUInteger)portNumber requestData:(NSString *)requestData transactionType:(int)transactionType signature:(NSString*)signature;

@end

@protocol SocketConnectionDelegate <NSObject>

@optional
- (void)socketConnectionStream:(SKBCoreServices *)connection didReceiveData:(NSMutableDictionary *)responseData;
- (void)socketConnectionStreamDidConnect:(SKBCoreServices *)connection;
- (void)socketConnectionStreamDidDisconnect:(SKBCoreServices *)connection willReconnectAutomatically:(BOOL)willReconnectAutomatically;
- (void)socketConnectionStream:(SKBCoreServices *)connection didSendString:(NSString *)string;
- (void)socketConnectionStreamDidFailToConnect:(SKBCoreServices *)connection;

@end
