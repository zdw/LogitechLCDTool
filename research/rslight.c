/*
	rslight
	rslight.c

	Quentin D. Carnicelli - qdc@rogueamoeba.com
*/

#include <stdio.h>
#include <getopt.h>

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/IOCFPlugIn.h>

enum
{
	kRadioSharkVendorID  = 0x077D,
	kRadioSharkProductID = 0x627A,
};

typedef struct
{
	unsigned char fBlueLightLevel;
	unsigned char fRedLightLevel;
}rsLightSettings;

int _parseArguements( int argc, const char* argv[], rsLightSettings* settings )
{
	int opt;
	int arg;
	
	if( !settings )
		return 0;
	
	if( argc < 2 )
		return 0;
			
	settings->fBlueLightLevel = 0;
	settings->fRedLightLevel = 0;

	while( (opt = getopt( argc, (char* const*)argv, "b:r:" )) != -1 )
	{
		switch( opt )
		{
			case 'b':
				if( !isdigit( optarg[0] ) )
					return 0;
				
				arg = atoi( optarg );
				arg = arg < 0 ? 0 : (arg > 128 ? 128 : arg);
				settings->fBlueLightLevel = arg;
			break;
		
			case 'r':
				if( !isdigit( optarg[0] ) )
					return 0;

				arg = atoi( optarg );
				arg = arg < 0 ? 0 : (arg > 128 ? 128 : arg);
				settings->fRedLightLevel = arg;
			break;
			
			case '?':
			default:
				return 0;
		}
	}

	return 1;

}

void _printUsage( const char* selfName )
{
	FILE* out = stderr;

	fprintf( out, "Usage: %s [-b <0-128>] [-r <0 or 128>]\n", selfName );
	fprintf( out, "    -b    Set the blue light brightness, value range is 0 to 128.\n" );
	fprintf( out, "    -r    Set the red light brightness, values are 0 and 128.\n" );
	fprintf( out, "\n" );
	fprintf( out, "%s controls a radioSHARK's lights\n", selfName );
}

CFMutableDictionaryRef _getMatchingDictionary( void )
{
    CFMutableDictionaryRef 	matchingDict = NULL;
	int val;
	CFNumberRef valRef;

    matchingDict = IOServiceMatching(kIOHIDDeviceKey);
	if( matchingDict )
	{
		val = kRadioSharkVendorID;
		valRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &val);
		CFDictionarySetValue(matchingDict, CFSTR(kIOHIDVendorIDKey), valRef);
		CFRelease(valRef);

		val = kRadioSharkProductID;
		valRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &val);
		CFDictionarySetValue(matchingDict, CFSTR(kIOHIDProductIDKey), valRef);
		CFRelease(valRef);
	}
	
	
	return matchingDict;

}

io_service_t _getIOService( CFMutableDictionaryRef matchingDict )
{
	if( !matchingDict ) return NULL;
	return IOServiceGetMatchingService( kIOMasterPortDefault, matchingDict );
}

IOHIDDeviceInterface** _getHIDInterface( io_service_t service )
{
	IOCFPlugInInterface**	iodev = NULL;
	IOHIDDeviceInterface**	hidInterface = NULL;
	kern_return_t			result;
	SInt32					score;

	if( !service ) return NULL;

	result = IOCreatePlugInInterfaceForService(service, kIOHIDDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &iodev, &score);
	if( result == KERN_SUCCESS && iodev )
	{
			result = (*iodev)->QueryInterface(iodev, CFUUIDGetUUIDBytes(kIOHIDDeviceInterfaceID), (LPVOID) &hidInterface);
			if (result != KERN_SUCCESS )
				hidInterface = NULL;

		(*iodev)->Release(iodev);
	}

	return hidInterface;
}

kern_return_t _setBlueLight( IOHIDDeviceInterface** hidInterface, unsigned char level )
{
	char report[6] = { 0xA0, level, 0, 0, 0, 0 };
	return (*hidInterface)->setReport( hidInterface, kIOHIDReportTypeOutput, 0, report, sizeof(report), 1000, NULL, NULL, NULL );
}

kern_return_t _setRedLight( IOHIDDeviceInterface** hidInterface, unsigned char level )
{
    char report[6] = { (level > 0 ? 0xA9 : 0xA8), 0, 0, 0, 0, 0 }; //Red light roll on
    return (*hidInterface)->setReport( hidInterface, kIOHIDReportTypeOutput, 0, report, sizeof(report), 1000, NULL, NULL, NULL );
}

int main (int argc, const char * argv[])
{
	rsLightSettings			settings = { 0, 0 };
	CFMutableDictionaryRef	matchingDict = NULL;
	io_service_t			service = NULL;
	IOHIDDeviceInterface**	hidInterface = NULL;
	kern_return_t			result;

	if( !_parseArguements( argc, argv, &settings ) )
	{
		_printUsage( /*argc ? argv[0] :*/ "rslight" );
		return -1;
	}

	matchingDict = _getMatchingDictionary();
	if( !matchingDict )
	{
		fprintf( stderr, "InternalError: Could not create io service matching dictionary\n" );
		return -1;
	}

	service = _getIOService( matchingDict );
	if( !service )
	{
		fprintf( stderr, "IOError: Could not find attached radioSHARK device\n" );
		return -1;
	}

	hidInterface = _getHIDInterface( service );
	if( !hidInterface )
	{
		fprintf( stderr, "IOError: Could find the HID interface of the radioSHARK device\n" );
		return -1;
	}

	result = (*hidInterface)->open(hidInterface, 0);
	if( result != KERN_SUCCESS )
	{
		fprintf( stderr, "IOError: Could open the HID interface of the radioSHARK device (0x%8X)\n", result );
		return -1;
	}
	
	result = _setBlueLight( hidInterface, settings.fBlueLightLevel );
	if( result != KERN_SUCCESS )
		fprintf( stderr, "IOError: Setting the blue light failed (0x%8X)\n", result );

	result = _setRedLight( hidInterface, settings.fRedLightLevel );
	if( result != KERN_SUCCESS )
		fprintf( stderr, "IOError: Setting the red light failed (0x%8X)\n", result );

	(*hidInterface)->close( hidInterface );
	(*hidInterface)->Release(hidInterface);
	IOObjectRelease( service );

    return 0;
}
