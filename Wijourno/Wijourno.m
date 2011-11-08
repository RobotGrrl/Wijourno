//
//  Wijourno.m
//  Wijourno
//
/*
 Wijourno is licensed under the BSD 3-Clause License
 http://www.opensource.org/licenses/BSD-3-Clause
 
 Wijourno Copyright (c) 2011, RobotGrrl.com. All rights reserved.
 */

#import "Wijourno.h"
#import "GCDAsyncSocket.h"
#import "DDLog.h"
#import "DDTTYLogger.h"
#import "DDASLLogger.h"
#import "Wijourno_tags.h"

// Log levels: off, error, warn, info, verbose
static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@interface Wijourno (Private)
- (void) connectToNextAddress;
- (void) readFrame;
@end

@implementation Wijourno

@synthesize delegate, asyncSocket, isServer, givenServiceName, currentlyConnected;
@synthesize infoDict;

- (id)init {
    self = [super init];
    if (self) {
        // Configure logging framework
        currentlyConnected = NO;
        [DDLog addLogger:[DDTTYLogger sharedInstance]];
        [DDLog addLogger:[DDASLLogger sharedInstance]];
    }
    
    return self;
}

- (void) initClientWithServiceName:(NSString *)serviceName dictionary:(NSDictionary *)dictionary {

    isServer = NO;
    self.givenServiceName = serviceName;
    self.infoDict = dictionary;
    
    connectedSockets = [[NSMutableArray alloc] init];
    
    NSString *serviceType = [NSString stringWithFormat:@"_%@._tcp.", serviceName];
    
    // Start browsing for bonjour services
    netServiceBrowser = [[NSNetServiceBrowser alloc] init];
        
    [netServiceBrowser setDelegate:self];
    [netServiceBrowser searchForServicesOfType:serviceType inDomain:@"local."];
    
    DDLogVerbose(@"Net service browser searching for: %@", serviceType);

}

- (void) initServerWithServiceName:(NSString *)serviceName dictionary:(NSDictionary *)dictionary {

    isServer = YES;
    self.givenServiceName = serviceName;
    self.infoDict = dictionary;
    
    allClients = [[NSMutableArray alloc] initWithCapacity:3];
    
    NSString *serviceType = [NSString stringWithFormat:@"_%@._tcp.", serviceName];
    
    // Create an array to hold accepted incoming connections.
    connectedSockets = [[NSMutableArray alloc] init];
    
    // Create our socket.
	// We tell it to invoke our delegate methods on the main thread.
	asyncSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
	
	// Now we tell the socket to accept incoming connections.
	// We don't care what port it listens on, so we pass zero for the port number.
	// This allows the operating system to automatically assign us an available port.
	
	NSError *err = nil;
	if ([asyncSocket acceptOnPort:0 error:&err]) {
        
		// So what port did the OS give us?
		UInt16 port = [asyncSocket localPort];
		
		// Create and publish the bonjour service.
		// Obviously you will be using your own custom service type.
		netService = [[NSNetService alloc] initWithDomain:@"local."
		                                             type:serviceType
		                                             name:@""
		                                             port:port];
		
		[netService setDelegate:self];
		[netService publish];
        
        DDLogVerbose(@"Found an incomming connection!");
        
        //[self startTimer]; // TODO: Make this triggerable?
        
	} else {
		DDLogError(@"Error in acceptOnPort:error: -> %@", err);
	}
    
}

// Thanks to this gist for the code to send NSDictionarys
// https://gist.github.com/73027 <3 <3 <3
- (void) sendCommand:(NSString *)command dictionary:(NSDictionary *)dictionary {
    
    //DDLogVerbose(@"Sending the command");
    
    NSMutableString *frameString = [NSMutableString stringWithString: [command stringByAppendingString:@"\n"]];
	NSEnumerator *enumerator = [dictionary keyEnumerator];
	NSString *key;
	while (key = [enumerator nextObject]) {
		[frameString appendString:key];
		[frameString appendString:@":"];
		[frameString appendString:[dictionary objectForKey:key]];
		[frameString appendString:@"\n"];
	}
    [frameString appendString:[NSString stringWithFormat:@"\n%C", 0]]; // control char
        
    for(int i=0; i<[connectedSockets count]; i++) {
        [[connectedSockets objectAtIndex:i] writeData:[frameString dataUsingEncoding:NSASCIIStringEncoding] withTimeout:WRITE_TIMEOUT tag:0];
    }
    
	//[self.asyncSocket writeData:[frameString dataUsingEncoding:NSASCIIStringEncoding] withTimeout:5 tag:0];
}

- (void) sendCommand:(NSString *)command  dictionary:(NSDictionary *)dictionary toClient:(NSString *)clientName {
    
    DDLogVerbose(@"Sending command specifically to client: %@", clientName);
    
    NSMutableString *frameString = [NSMutableString stringWithString: [command stringByAppendingString:@"\n"]];
	NSEnumerator *enumerator = [dictionary keyEnumerator];
	NSString *key;
	while (key = [enumerator nextObject]) {
		[frameString appendString:key];
		[frameString appendString:@":"];
		[frameString appendString:[dictionary objectForKey:key]];
		[frameString appendString:@"\n"];
	}
    [frameString appendString:[NSString stringWithFormat:@"\n%C", 0]]; // control char
    
    //DDLogVerbose(@"Clients: %@", allClients);
    
    for(int i=0; i<[allClients count]; i++) {
        NSDictionary *clientDict = [allClients objectAtIndex:i];
        NSString *theName = [clientDict objectForKey:@"name"];
        //DDLogVerbose(@"Name %d: %@", i, theName);
        if([clientName isEqualToString:theName]) {
            //DDLogVerbose(@"Sending");
            [[connectedSockets objectAtIndex:i] writeData:[frameString dataUsingEncoding:NSASCIIStringEncoding] withTimeout:WRITE_TIMEOUT tag:0];
        }
    }
}

- (void) readFrame {
	[self.asyncSocket readDataToData:[GCDAsyncSocket ZeroData] withTimeout:READ_TIMEOUT tag:0];
}

- (void) closeSocket {
    [asyncSocket disconnect];
}

#pragma mark - Server

// Thanks to this site for the code in -startTimer
// http://www.fieryrobot.com/blog/2010/07/10/a-watchdog-timer-in-gcd/
- (void) startTimer {
    
    // Default priority queue
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    // Create our timer source
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    
    // Set the time to fire
    dispatch_source_set_timer(_timer,
                              dispatch_time(DISPATCH_TIME_NOW, 1ull * NSEC_PER_SEC),
                              (1ull * NSEC_PER_SEC), 0);
    
    // Hey, let's actually do something when the timer fires!
    dispatch_source_set_event_handler(_timer, ^{
        //[self sendMessage];
    });
    
    // Now that our timer is all set to go, start it
    dispatch_resume(_timer);
    
}

#pragma mark - Shared GCDAsyncSocket

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    
    /*
    if(isServer) {
        DDLogVerbose(@"Server sent data with tag: %lu", tag);
    } else {
        DDLogVerbose(@"Client sent data with tag: %lu", tag);
    }
     */
     
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    
    dispatch_async(dispatch_get_main_queue(), ^{
    
        /*
    if(isServer) {
        DDLogVerbose(@"Server did read data with tag: %lu", tag);
    } else {
        DDLogVerbose(@"Client did read data with tag: %lu", tag);
    }
         */
    
    NSData *strData = [data subdataWithRange:NSMakeRange(0, [data length] - 2)];
    NSString *msg = [[[NSString alloc] initWithData:strData encoding:NSUTF8StringEncoding] autorelease];
    NSMutableArray *contents = (NSMutableArray *)[msg componentsSeparatedByString:@"\n"];
    if([[contents objectAtIndex:0] isEqual:@""]) {
        [contents removeObjectAtIndex:0];
    }
    NSString *command = [[[contents objectAtIndex:0] copy] autorelease];
    NSMutableDictionary *headers = [[[NSMutableDictionary alloc] init] autorelease];
    NSMutableString *body = [[[NSMutableString alloc] init] autorelease];
    BOOL hasHeaders = NO;
    [contents removeObjectAtIndex:0];
    for(NSString *line in contents) {
        if(hasHeaders) {
            [body appendString:line];
        } else {
            if ([line isEqual:@""]) {
                hasHeaders = YES;
            } else {
                NSMutableArray *parts = (NSMutableArray *)[line componentsSeparatedByString:@":"];
                [headers setObject:[parts objectAtIndex:1] forKey:[parts objectAtIndex:0]];
            }
        }
    }
    
        if([command isEqualToString:DATA]) {
            
            NSMutableDictionary *clientDict = [[NSMutableDictionary alloc] initWithDictionary:headers];
            
            [clientDict setObject:[sock connectedHost] forKey:@"host"];
            [clientDict setObject:[NSNumber numberWithInt:[sock connectedPort]] forKey:@"port"];
            
            DDLogVerbose(@"Added client to the all clients array ok");
            [allClients addObject:clientDict];
            
            [clientDict release];
            
        }
        
        [self.delegate didReadCommand:command dictionary:headers isServer:isServer];
       
        if(!isServer) {
            [sock readDataToData:[GCDAsyncSocket ZeroData] withTimeout:READ_TIMEOUT tag:0];
        } else {
            [sock readDataToData:[GCDAsyncSocket ZeroData] withTimeout:-1.0 tag:0];
        }
            
    //[self readFrame];
    
    });
    
    
}

// This method is called if a read has timed out.
// It allows us to optionally extend the timeout.
// We use this method to issue a warning to the user prior to disconnecting them.
// For the purposes of Wijourno, this probably won't be used that often, as we
// don't set any read timeouts
- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutReadWithTag:(long)tag
                 elapsed:(NSTimeInterval)elapsed
               bytesDone:(NSUInteger)length {
    
    
    
	if (elapsed <= READ_TIMEOUT) {
        
        if(isServer) {
            DDLogVerbose(@"Server read timeout");
        } else {
            DDLogVerbose(@"Client read timeout");
        }
        
		//NSString *warningMsg = @"Are you still there?\r\n";
		//NSData *warningData = [warningMsg dataUsingEncoding:NSUTF8StringEncoding];
		
		//[sock writeData:warningData withTimeout:-1 tag:WARNING_MSG];
		
		return READ_TIMEOUT_EXTENSION;
	}
	
    [self.delegate readTimedOut];
    
    //if(isServer) return READ_TIMEOUT_EXTENSION;
    
	return READ_TIMEOUT_EXTENSION;// -1;
}

/*
- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutWriteWithTag:(long)tag
                 elapsed:(NSTimeInterval)elapsed
               bytesDone:(NSUInteger)length {
    
    DDLogVerbose(@"Write timed out!");
    
    return 0.0;
    
}
*/ 

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    
    [delegate connectionFinished:[err localizedDescription]];
    
    if(isServer) {
        
        DDLogVerbose(@"Server socket did disconnect w/error: %@", err);
        
        currentlyConnected = NO;
         
        for(int i=0; i<[connectedSockets count]; i++) {
            if([connectedSockets objectAtIndex:i] == sock) {
                DDLogVerbose(@"Equal!");
                if([allClients count] > 0) {
                    [allClients removeObjectAtIndex:i];
                } else {
                    DDLogError(@"There wasn't enough clients to remove it? Yikes!");
                }
            }
        }
        
        [connectedSockets removeObject:sock];
        [netService publish];
        
    } else {
        DDLogVerbose(@"Client socket did disconnect w/error: %@", err);
        //if (!connected) [self connectToNextAddress];
        [self connectToNextAddress]; // TODO: Testing this
    }
}

#pragma mark - Server GCDAsyncSocket

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
	DDLogInfo(@"Accepted new socket from %@:%hu", [newSocket connectedHost], [newSocket connectedPort]);

	currentlyConnected = YES;
    
	// The newSocket automatically inherits its delegate & delegateQueue from its parent.    
    self.asyncSocket = newSocket;
    
    @synchronized(connectedSockets) {
		[connectedSockets addObject:newSocket];
	}
	
	NSString *host = [newSocket connectedHost];
	UInt16 port = [newSocket connectedPort];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
        DDLogVerbose(@"Accepted client %@:%hu", host, port);
		
        [delegate connectionStarted:host];
        
		[pool release];
	});
    
    [self sendCommand:DATA dictionary:infoDict toSocket:asyncSocket];
    
    // Read forever
    [asyncSocket readDataToData:[GCDAsyncSocket ZeroData] withTimeout:-1.0 tag:0];
    
}

- (void) sendCommand:(NSString *)command dictionary:(NSDictionary *)dictionary toSocket:(GCDAsyncSocket *)sock {
    
    DDLogVerbose(@"Sending the command");
    
    NSMutableString *frameString = [NSMutableString stringWithString: [command stringByAppendingString:@"\n"]];
	NSEnumerator *enumerator = [dictionary keyEnumerator];
	NSString *key;
	while (key = [enumerator nextObject]) {
		[frameString appendString:key];
		[frameString appendString:@":"];
		[frameString appendString:[dictionary objectForKey:key]];
		[frameString appendString:@"\n"];
	}
    [frameString appendString:[NSString stringWithFormat:@"\n%C", 0]]; // control char
    
    [sock writeData:[frameString dataUsingEncoding:NSASCIIStringEncoding] withTimeout:WRITE_TIMEOUT tag:0];
    
}

#pragma mark - Server NSNetService

- (void)netServiceDidPublish:(NSNetService *)ns {
	DDLogInfo(@"Bonjour Service Published: domain(%@) type(%@) name(%@) port(%i)",
			  [ns domain], [ns type], [ns name], (int)[ns port]);
}

- (void)netService:(NSNetService *)ns didNotPublish:(NSDictionary *)errorDict {
	// Override me to do something here...
	// Note: This method in invoked on our bonjour thread.
	DDLogError(@"Failed to Publish Service: domain(%@) type(%@) name(%@) - %@",
               [ns domain], [ns type], [ns name], errorDict);
}

#pragma mark - Client GCDAsyncSocket

- (void) reconnectClient {
    
    [self disconnectClient]; // TODO: Editing this now
    
    netServiceBrowser = nil;
    [netServiceBrowser release];
    
    NSString *serviceType = [NSString stringWithFormat:@"_%@._tcp.", givenServiceName];
    
    DDLogVerbose(@"service type: %@", serviceType);
    
    
    // Start browsing for bonjour services
    netServiceBrowser = [[NSNetServiceBrowser alloc] init];
    
    [netServiceBrowser setDelegate:self];
    [netServiceBrowser searchForServicesOfType:serviceType inDomain:@"local."];
    
    
    //[self connectToNextAddress];
}

- (void) disconnectClient {
    
    netService = nil;
    serverAddresses = nil;
    [asyncSocket disconnect];
    asyncSocket = nil;
    
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port {
	
    DDLogInfo(@"Socket:DidConnectToHost: %@ Port: %hu", host, port);
	
	connected = YES; // TODO: What exactly is the point of this var?
    currentlyConnected = YES;
    
    [delegate connectionStarted:host];
    
    asyncSocket = sock;
    [connectedSockets addObject:sock];
    
    DDLogVerbose(@"Connected sockets count: %d", [connectedSockets count]);
    
    [self sendCommand:DATA dictionary:infoDict toSocket:asyncSocket];
    
    // Read forever
    [asyncSocket readDataToData:[GCDAsyncSocket ZeroData] withTimeout:READ_TIMEOUT tag:0];
    
}

- (void)connectToNextAddress {
	BOOL done = NO;
	
    DDLogVerbose(@"Number of server addresses: %d", [serverAddresses count]);
    
	while (!done && ([serverAddresses count] > 0)) {
		NSData *addr;
		
		// Note: The serverAddresses array probably contains both IPv4 and IPv6 addresses.
		// If your server is also using GCDAsyncSocket then you don't have to worry about it,
		// as the socket automatically handles both protocols for you transparently.
		
		if (YES) { // Iterate forwards
			addr = [[serverAddresses objectAtIndex:0] retain];
			[serverAddresses removeObjectAtIndex:0];
		} else { // Iterate backwards
			addr = [[serverAddresses lastObject] retain];
			[serverAddresses removeLastObject];
		}
		
		DDLogVerbose(@"Attempting connection to %@", addr);
		
		NSError *err = nil;
		if ([asyncSocket connectToAddress:addr error:&err]) {
			done = YES;
		} else {
			DDLogWarn(@"Unable to connect: %@", err);
		}
		
		[addr release];
	}
	
	if (!done) {
		DDLogWarn(@"Unable to connect to any resolved address");
        [self reconnectClient]; // TODO: Editing this now
        //[self connectToNextAddress];
	}
}

#pragma mark - Client NSNetServer

- (void)netServiceBrowser:(NSNetServiceBrowser *)sender didNotSearch:(NSDictionary *)errorInfo {
	DDLogError(@"NSNetServiceBrowser DidNotSearch: %@", errorInfo);
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)sender
           didFindService:(NSNetService *)ns
               moreComing:(BOOL)moreServicesComing {
    
	DDLogVerbose(@"NSNetServiceBrowser DidFindService: %@", [ns name]);
	
	// Connect to the first service we find	
	if (netService == nil) {
		DDLogVerbose(@"Resolving...");
		
		netService = [ns retain];
		
		[netService setDelegate:self];
		[netService resolveWithTimeout:5.0];
	}
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)sender
         didRemoveService:(NSNetService *)ns
               moreComing:(BOOL)moreServicesComing {
	DDLogVerbose(@"NSNetServiceBrowser DidRemoveService: %@", [ns name]);
    
    currentlyConnected = NO;
    
    netService = nil;
    serverAddresses = nil;
    asyncSocket = nil;
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)sender {
	DDLogVerbose(@"NSNetServiceBrowser DidStopSearch");
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict {
	DDLogError(@"NSNetServiceBrowser DidNotResolve: %@", errorDict);
}

- (void)netServiceDidResolveAddress:(NSNetService *)sender {
	DDLogVerbose(@"NSNetServiceBrowser DidResolve: %@", [sender addresses]);
	
	if (serverAddresses == nil) {
		serverAddresses = [[sender addresses] mutableCopy];
	}
	
	if (asyncSocket == nil) {
		self.asyncSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
		[self connectToNextAddress];
	}
}

@end
