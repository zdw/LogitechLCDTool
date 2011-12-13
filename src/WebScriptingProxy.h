//
//  WebScriptingProxy.h
//  LogitechLCDTool
//
//  Created by Marc Liyanage on 28.12.06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@protocol WebScriptingProxyAppDelegate <NSObject>
- (BOOL)webViewUpdatesAllowed;
- (void)clearOffscreenWebView;
- (NSString *)getAppVersion;
@end

@interface WebScriptingProxy : NSObject {
	id<WebScriptingProxyAppDelegate> delegate;
	NSMutableDictionary *appleScripts;
	struct timeval lastUpdateTime;
}

- (id)initWithAppDelegate:(id)aDelegate;
- (void)setupAppleScripts;
- (BOOL)updateTooFrequent;
- (NSString *)runSystemScript:(NSString *)key;
- (void)registerUserScript:(NSString *)key code:(NSString *)code;
- (NSString *)runUserScript:(NSString *)key;
- (NSAppleScript *)compileAppleScript:(NSString *)code;
@end

