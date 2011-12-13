//
//  UsbHidDevice.m
//  LogitechLCDTool
//
//  Created by Marc Liyanage on 26.12.06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "UsbHidDevice.h"


@implementation UsbHidDevice

- (id)init {
	if (!(self = [super init])) return nil;
	hidDeviceInterfaceVendorPage = hidDeviceInterfaceConsumerPage = NULL;
	hidQueueVendorPage = hidQueueConsumerPage = NULL;
	return self;
}


- (BOOL)sendTestImage1 {
	return [self sendFormattedBitmap:report1];
}

- (BOOL)sendTestImage2 {
	return [self sendFormattedBitmap:report2];
}


- (BOOL)sendImage:(NSBitmapImageRep *)rep {
	if (!rep) {
		NSLog(@"sendImage: NULL NSBitmapImageRep");
		return NO;
	}
	
	unsigned char blackwhite_buffer[G15_BUFFER_LEN];
	memset(blackwhite_buffer, 0, G15_BUFFER_LEN);

	int repW = [rep pixelsWide];
	int repH = [rep pixelsHigh];
	int samples = [rep samplesPerPixel];
	int x, y;
	for (y = 0; y < G15_LCD_HEIGHT && y < repH; y++) {
		for (x = 0; x < G15_LCD_WIDTH && x < repW; x++) {
			unsigned int data[4] = {0, 0, 0, 0};
			[rep getPixel:data atX:x y:y]; // fixme: this is fairly expensive, need to optimize
			unsigned int value = (samples > 1 ? data[0] + data[1] + data[2] : data[0]) / samples; // reduce 24-bit RGB to 8-bit with average
			value = value > 150 ? 0 : 1; // reduce 8-bit to 1 bit with threshold
			value = value << 7 - x % 8; // shift the bit value to its position in the output buffer byte
			int index = y * (G15_LCD_WIDTH / 8) + x / 8; // output buffer byte index
			blackwhite_buffer[index] = blackwhite_buffer[index] | value;
		}
	}
	return [self sendLinearBitmap:blackwhite_buffer];
}


- (BOOL)sendLinearBitmap:(unsigned char *)data {
	unsigned char lcd_buffer[G15_BUFFER_LEN];
	memset(lcd_buffer, 0, G15_BUFFER_LEN);
	dumpPixmapIntoLCDFormat(lcd_buffer, data);
	lcd_buffer[0] = 0x03; // The USB HID report ID?
	return [self sendFormattedBitmap:lcd_buffer];
}


- (BOOL)sendFormattedBitmap:(unsigned char *)data {
	if (![self openHidDeviceInterfaces]) return NO;
	IOReturn ioReturnValue = (*hidDeviceInterfaceVendorPage)->setReport(
		hidDeviceInterfaceVendorPage, kIOHIDReportTypeOutput,
		0, data, G15_BUFFER_LEN, 5000, NULL, NULL, NULL
	);
	if (ioReturnValue) {
		[self closeAndReleaseHidDeviceInterfaces];
		return NO;
	}
	return YES;
}




- (BOOL)sendImageAtUrl:(NSString *)url {
	if (!url) {
		NSLog(@"sendImageAtUrl: NULL URL");
		return NO;
	}
	// This assumes that url points to a bitmap image, not PDF
	NSImage *img = [[[NSImage alloc] initWithContentsOfURL:[NSURL URLWithString:url]] autorelease];
	return [self sendImage:[[img representations] objectAtIndex:0]];
}



- (BOOL)openHidDeviceInterfaces {
	if (hidDeviceInterfaceVendorPage && hidDeviceInterfaceConsumerPage) return YES;
	if (!([self openHidDeviceInterfaceVendorPage] && [self openHidDeviceInterfaceConsumerPage])) {
		[self closeAndReleaseHidDeviceInterfaces];
		return NO;
	};	
	return YES;
}


- (BOOL)openHidDeviceInterfaceVendorPage {
	hidDeviceInterfaceVendorPage = [self openHidDeviceForUsagePage:0xff00];
	unsigned int cookies[] = {2, 4, 5, 6, 7, 8, 9, 10, 0};
	hidQueueVendorPage = [self openHidQueueOnDevice:hidDeviceInterfaceVendorPage forCookies:cookies];
	return hidDeviceInterfaceVendorPage && hidQueueVendorPage;
}


- (BOOL)openHidDeviceInterfaceConsumerPage {
	hidDeviceInterfaceConsumerPage = [self openHidDeviceForUsagePage:0x000c];
	unsigned int cookies[] = {2, 3, 4, 5, 6, 7, 8, 9, 10, 0};
	hidQueueConsumerPage = [self openHidQueueOnDevice:hidDeviceInterfaceConsumerPage forCookies:cookies];
	return hidDeviceInterfaceConsumerPage && hidQueueConsumerPage;
}


- (IOHIDQueueInterface **)openHidQueueOnDevice:(IOHIDDeviceInterface **)device forCookies:(unsigned int [])cookies {
	if (!device) return NULL;
	IOHIDQueueInterface **queue;
	queue = (*device)->allocQueue(device);
	HRESULT result = (*queue)->create(queue, 0, 8); 
	if (result != S_OK) return NULL;
	
	int i = 0;
	while(cookies[i]) {
		result = (*queue)->addElement(queue, (IOHIDElementCookie)cookies[i], 0);
		if (result != S_OK) NSLog(@"Unable to add element with cookie value %x", cookies[i]);
		i++;
	}
	
	result = (*queue)->start(queue);

	CFRunLoopSourceRef eventSource;
	result = (*queue)->createAsyncEventSource(queue, &eventSource);
	if (result != S_OK) {
		NSLog(@"Unable to create event source");
		[self closeQueue:queue];
		return NULL;
	}

	result = (*queue)->setEventCallout(queue, QueueCallbackFunction, self, queue);
	if (result != S_OK) {
		NSLog(@"Unable to register event callback");
		[self closeQueue:queue];
		return NULL;
	}
	
    CFRunLoopAddSource(CFRunLoopGetCurrent(), eventSource, kCFRunLoopDefaultMode);

	return queue;
}


static void QueueCallbackFunction(void *target, IOReturn result, void *refcon, void *sender) {
	UsbHidDevice *self = (UsbHidDevice *)target;
	[self handleHidEvent:(IOHIDQueueInterface **)sender];
}


- (void)handleHidEvent:(IOHIDQueueInterface **)queue {
//	NSLog(@"event queue change %p", queue);

    AbsoluteTime zeroTime = {0, 0};
    IOHIDEventStruct event;

	IOReturn result = kIOReturnSuccess; 
    while (result == kIOReturnSuccess) {
		result = (*queue)->getNextEvent(queue, &event, zeroTime, 0);
		if (result != kIOReturnSuccess) continue;

        if ((event.longValueSize != 0) && (event.longValue != NULL)) {
			//NSLog(@"longvalue %p", event.longValue);
            free(event.longValue);
        }
		
		NSString *button;
		BOOL isApplicationButton = NO;
		if (queue == hidQueueVendorPage) {
			if (event.elementCookie == COOKIE_SOFTKEY1) {
				button = @"Softkey1";
			} else if (event.elementCookie == COOKIE_SOFTKEY2) {
				button = @"Softkey2";
			} else if (event.elementCookie == COOKIE_SOFTKEY3) {
				button = @"Softkey3";
			} else if (event.elementCookie == COOKIE_SOFTKEY4) {
				button = @"Softkey4";
			} else if (event.elementCookie == COOKIE_DISPLAY) {
				button = @"Display";
			}
			isApplicationButton = YES;
		} else {
			if (event.elementCookie == COOKIE_VOLUME_UP) {
				button = @"VolumeUp";
			} else if (event.elementCookie == COOKIE_VOLUME_DOWN) {
				button = @"VolumeDown";
			} else if (event.elementCookie == COOKIE_MUTE) {
				button = @"Mute";
			} else if (event.elementCookie == COOKIE_FORWARD) {
				button = @"FastForward";
			} else if (event.elementCookie == COOKIE_REWIND) {
				button = @"Rewind";
			} else if (event.elementCookie == COOKIE_NEXT) {
				button = @"NextTrack";
			} else if (event.elementCookie == COOKIE_PREVIOUS) {
				button = @"PreviousTrack";
			} else if (event.elementCookie == COOKIE_STOP) {
				button = @"Stop";
			} else if (event.elementCookie == COOKIE_PLAYPAUSE) {
				button = @"PlayPause";
			}
		}
		
		NSDictionary *userInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
			button, @"button",
			event.value ? @"down" : @"up", @"upDown",
			nil];
		if (isApplicationButton) [userInfo setValue:@"YES" forKey:@"isApplicationButton"];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"ButtonEvent" object:self userInfo:userInfo];
		
//		NSLog(@"queue %p, type: %d, cookie %d, value %d", queue, event.type, event.elementCookie, event.value);

	}

}


- (IOHIDDeviceInterface **)openHidDeviceForUsagePage:(unsigned int)usagePage {

	SInt32 usbVendor = 0x046d;  // Logitech
	SInt32 usbProduct = 0x0a07; // Z-10 I guess
//	SInt32 usbProduct = 0xc222; // G15
	SInt32 usbUsagePage = usagePage;

	NSMutableDictionary *matchDict = (NSMutableDictionary *)IOServiceMatching(kIOHIDDeviceKey);
	[matchDict setObject:[NSNumber numberWithInt:usbVendor] forKey:[NSString stringWithUTF8String:kIOHIDVendorIDKey]];
	[matchDict setObject:[NSNumber numberWithInt:usbProduct] forKey:[NSString stringWithUTF8String:kIOHIDProductIDKey]];
	[matchDict setObject:[NSNumber numberWithInt:usbUsagePage] forKey:[NSString stringWithUTF8String:kIOHIDPrimaryUsagePageKey]];
	//NSLog(@"matching dict %@", matchDict);
	[matchDict retain]; // fixme: I believe this is required because IOServiceGetMatchingServices() consumes a reference, but need to make sure otherwise this leaks.
	
    // Search I/O registry for matching devices
	io_iterator_t hidObjectIterator = 0;
    IOReturn ioReturnValue = IOServiceGetMatchingServices(kIOMasterPortDefault, (CFMutableDictionaryRef)matchDict, &hidObjectIterator);
    BOOL noMatchingDevices = (ioReturnValue != kIOReturnSuccess) || (!hidObjectIterator);
    if (noMatchingDevices) {
		NSLog(@"No matching devices found, IO Return Value = %d", ioReturnValue);
		return NO;
	}
 
	io_object_t hidDevice;
	hidDevice = IOIteratorNext(hidObjectIterator);
	IOObjectRelease(hidObjectIterator);

	if (!hidDevice) {
		NSLog(@"Unable to get hidDevices");
		return NULL;
	}
	//NSLog(@"hidDevice %d", hidDevice);

	IOCFPlugInInterface **plugInInterface = NULL;
	SInt32 score = 0;
	ioReturnValue = IOCreatePlugInInterfaceForService(hidDevice, kIOHIDDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);
	IOObjectRelease(hidDevice);
	if (ioReturnValue != kIOReturnSuccess) {
		NSLog(@"Unable to IOCreatePlugInInterfaceForService(): %d", ioReturnValue);
		return NULL;
	}

	IOHIDDeviceInterface **hidDeviceInterface = NULL;

	CFUUIDBytes uuid = CFUUIDGetUUIDBytes(kIOHIDDeviceInterfaceID);
	HRESULT plugInResult = (*plugInInterface)->QueryInterface(plugInInterface, uuid, (LPVOID)&hidDeviceInterface);
	(*plugInInterface)->Release(plugInInterface); // don't need this any longer
	if (plugInResult != S_OK) {
		NSLog(@"Unable to create device interface: %d", plugInResult);
		return NULL;
	}

	ioReturnValue = (*hidDeviceInterface)->open(hidDeviceInterface, 0);
	if (ioReturnValue != kIOReturnSuccess) {
		NSLog(@"Unable to open device interface: %d", ioReturnValue);
		ioReturnValue = (*hidDeviceInterface)->Release(hidDeviceInterface);
		if (ioReturnValue) NSLog(@"Error releasing hidDeviceInterfaceVendorPage: %d", ioReturnValue);
		return NULL;
	}

	return hidDeviceInterface;
	
}



- (void)closeAndReleaseHidDeviceInterfaces {
	[self closeAndNullQueue:&hidQueueVendorPage];
	if (hidDeviceInterfaceVendorPage) {
		int ioReturnValue = (*hidDeviceInterfaceVendorPage)->close(hidDeviceInterfaceVendorPage);
		if (ioReturnValue) NSLog(@"Error closing hidDeviceInterfaceVendorPage: %d", ioReturnValue);
	}

	[self closeAndNullQueue:&hidQueueConsumerPage];
	if (hidDeviceInterfaceConsumerPage) {
		int ioReturnValue = (*hidDeviceInterfaceConsumerPage)->close(hidDeviceInterfaceConsumerPage);
		if (ioReturnValue) NSLog(@"Error closing hidDeviceInterfaceConsumerPage: %d", ioReturnValue);
	}
	[self releaseHidDeviceInterfaces];
}


- (void)closeAndNullQueue:(IOHIDQueueInterface ***)queueRef {
	if (!queueRef) return;
	[self closeQueue:*queueRef];
	*queueRef = NULL;
}

- (void)closeQueue:(IOHIDQueueInterface **)queue {
	if (!queue) return;
	(*queue)->stop(queue);
	(*queue)->dispose(queue);
	(*queue)->Release(queue);
}

- (void)releaseHidDeviceInterfaces {
	if (hidDeviceInterfaceVendorPage) {
		(*hidDeviceInterfaceVendorPage)->Release(hidDeviceInterfaceVendorPage);
		hidDeviceInterfaceVendorPage = NULL;
	}
	if (hidDeviceInterfaceConsumerPage) {
		(*hidDeviceInterfaceConsumerPage)->Release(hidDeviceInterfaceConsumerPage);
		hidDeviceInterfaceConsumerPage = NULL;
	}
}


- (void)dealloc {
	[self closeAndReleaseHidDeviceInterfaces];
	[super dealloc];
}




/*
 * Taken from libg15 / g15tools with permission, many thanks :-)
 * See http://g15tools.sourceforge.net/
 */
static void dumpPixmapIntoLCDFormat(unsigned char *lcd_buffer, unsigned char const *data)
{
  unsigned int offset_from_start = G15_LCD_OFFSET;
  unsigned int curr_row = 0;
  unsigned int curr_col = 0;
  
  for (curr_row=0;curr_row<G15_LCD_HEIGHT;++curr_row)
  {
    for (curr_col=0;curr_col<G15_LCD_WIDTH;++curr_col)
    {
      unsigned int pixel_offset = curr_row*G15_LCD_WIDTH + curr_col;
      unsigned int byte_offset = pixel_offset / 8;
      unsigned int bit_offset = pixel_offset % 8;
      unsigned int val = data[byte_offset] & 1<<(7-bit_offset);
      
      unsigned int row = curr_row / 8;
      unsigned int offset = G15_LCD_WIDTH*row + curr_col;
      unsigned int bit = curr_row % 8;
    
/*
      if (val)
        printf("Setting pixel at row %d col %d to %d offset %d bit %d\n",curr_row,curr_col, val, offset, bit);
      */
      if (val)
        lcd_buffer[offset_from_start + offset] = lcd_buffer[offset_from_start + offset] | 1 << bit;
      else
        lcd_buffer[offset_from_start + offset] = lcd_buffer[offset_from_start + offset]  &  ~(1 << bit);
    }
  }
}






@end
