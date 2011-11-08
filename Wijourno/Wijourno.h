//
//  Wijourno.h
//  Wijourno
//
/*
 
 Wijourno is licensed under the BSD 3-Clause License
 http://www.opensource.org/licenses/BSD-3-Clause
 
 Wijourno Copyright (c) 2011, RobotGrrl.com. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 Neither the name of the RobotGrrl.com nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 */

//#import <Foundation/Foundation.h>

@class GCDAsyncSocket;

@protocol WijournoDelegate
- (void) didReadCommand:(NSString *)command dictionary:(NSDictionary *)dictionary isServer:(BOOL)isServer;
- (void) connectionStarted:(NSString *)host;
- (void) connectionFinished:(NSString *)details;
- (void) readTimedOut;
@end

@interface Wijourno : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate> {
    
    id<WijournoDelegate> delegate;
    
    // Shared
    BOOL isServer;
    NSNetService *netService;
    GCDAsyncSocket *asyncSocket;
    dispatch_source_t     _timer;
    
    BOOL currentlyConnected;
    NSDictionary *infoDict;
    
    // Server
    NSMutableArray *connectedSockets;
    NSString *givenServiceName;
    NSMutableArray *allClients;
    
    // Client
    NSNetServiceBrowser *netServiceBrowser;
	NSMutableArray *serverAddresses;
	BOOL connected;
    
}

@property (assign, readwrite) id<WijournoDelegate> delegate;

@property (assign) BOOL isServer;
@property (nonatomic, retain) GCDAsyncSocket *asyncSocket;

@property (readonly) BOOL currentlyConnected;
@property (nonatomic, retain) NSDictionary *infoDict;

@property (nonatomic, retain) NSString *givenServiceName;

- (void) initClientWithServiceName:(NSString *)serviceName dictionary:(NSDictionary *)dictionary;
- (void) initServerWithServiceName:(NSString *)serviceName dictionary:(NSDictionary *)dictionary;

- (void) sendCommand:(NSString *)command dictionary:(NSDictionary *)dictionary;
- (void) sendCommand:(NSString *)command  dictionary:(NSDictionary *)dictionary toClient:(NSString *)clientName;
- (void) sendCommand:(NSString *)command dictionary:(NSDictionary *)dictionary toSocket:(GCDAsyncSocket *)sock;
- (void) closeSocket;

- (void) reconnectClient;
- (void) disconnectClient;

@end
