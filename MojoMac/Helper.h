#import <Cocoa/Cocoa.h>
#import "HelperProtocol.h"

/**
 * This class is the Root Object of the vended Distributed Object of MojoHelper.
 * It provides the implementation of the HelperProtocol.
**/
@interface Helper : NSObject <HelperProtocol>
{
	NSMutableDictionary *gateways;
	
    IBOutlet id menuController;
}
@end
