//
//  WebScriptingProxy.m
//  LogitechLCDTool
//
//  Created by Marc Liyanage on 28.12.06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "WebScriptingProxy.h"


@implementation WebScriptingProxy

- (id)initWithAppDelegate:(id)aDelegate {
	if (!(self = [super init])) return self;
	delegate = aDelegate;
	[self setupAppleScripts];
	gettimeofday(&lastUpdateTime, NULL);
	return self;
}	

- (void)dealloc {
	[appleScripts release];
	[super dealloc];
}


- (void)setupAppleScripts {
	NSString *sourceFile = [[NSBundle mainBundle] pathForResource:@"SystemAppleScripts" ofType:@"plist"];
	NSDictionary *sources = [NSDictionary dictionaryWithContentsOfFile:sourceFile];
	appleScripts = [[NSMutableDictionary dictionary] retain];

	id key, keys = [sources keyEnumerator];
	while (key = [keys nextObject]) {
		NSAppleScript *script = [self compileAppleScript:[sources valueForKey:key]];
		if (script) [appleScripts setValue:script forKey:key];
	}
}


- (unsigned long)millisecondsSinceLastUpdate {
	struct timeval now;
	gettimeofday(&now, NULL);
	unsigned int delta_sec = now.tv_sec - lastUpdateTime.tv_sec;
	long delta_usec = now.tv_usec - lastUpdateTime.tv_usec;
	unsigned long delta = delta_sec * 1000 + delta_usec / 1000;
	return delta;
}

- (BOOL)updateTooFrequent {
	return [self millisecondsSinceLastUpdate] < 50;
}


- (NSAppleScript *)compileAppleScript:(NSString *)code {
	NSAppleScript *script = [[[NSAppleScript alloc] initWithSource:code] autorelease];
	NSDictionary *errorInfo;
	if (![script compileAndReturnError:&errorInfo]) {
		NSLog(@"Failed to compile AppleScript code: '%@', offending code: '%@'", [errorInfo valueForKey:NSAppleScriptErrorMessage], code);
		return nil;
	}
	return script;
}



+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector {
	if (
		aSelector == @selector(updateDisplay) ||
		aSelector == @selector(getVersion) ||
		aSelector == @selector(runSystemScript:) ||
		aSelector == @selector(registerUserScript:code:) ||
		aSelector == @selector(runUserScript:)
	) return NO;
	return [super isSelectorExcludedFromWebScript:aSelector];
}


+ (NSString *)webScriptNameForSelector:(SEL)sel {
    if (sel == @selector(runSystemScript:)) return @"runSystemScript";
    if (sel == @selector(runUserScript:)) return @"runUserScript";
    if (sel == @selector(registerUserScript:code:)) return @"registerUserScript";
	return nil;
}


/* The following methods are called from JavaScript */

- (BOOL)updateDisplay {
	if (![delegate webViewUpdatesAllowed]) return NO;
	if ([self updateTooFrequent]) {
		NSLog(@"Update JavaScript call to updateDisplay() too frequent, stopping...");
		[delegate clearOffscreenWebView];
		return NO;
	}
//	NSLog(@"updateDisplay from JavaScript");
	[delegate performSelectorOnMainThread:@selector(captureWebView) withObject:nil waitUntilDone:NO];
	gettimeofday(&lastUpdateTime, NULL);
	return YES;
}


- (NSString *)runSystemScript:(NSString *)key {
	NSAppleEventDescriptor *result;
	NSAppleScript *script = [appleScripts valueForKey:key];
	if (!script) {
		NSLog(@"Invalid script key %@", key);
		return nil;
	}
	NSDictionary *errorInfo;
	result = [script executeAndReturnError:&errorInfo];
	if (!result) NSLog(@"AppleScript error for script with key '%@': %@", key, [errorInfo valueForKey:NSAppleScriptErrorMessage]);
	return [result stringValue];
}

- (void)registerUserScript:(NSString *)key code:(NSString *)code {
	NSAppleScript *script = [self compileAppleScript:code];
	if (script) [appleScripts setValue:script forKey:key];
}

- (NSString *)runUserScript:(NSString *)key {
	return [self runSystemScript:key];
}

- (NSString *)getVersion {
	return [delegate getAppVersion];
}


@end
