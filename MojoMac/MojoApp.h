#import <Cocoa/Cocoa.h>

@interface MojoApp : NSApplication
{
    IBOutlet id preferencesWindow;
    IBOutlet id serviceListWindow;
}
- (void)scripterSaysViewLibrary:(NSScriptCommand *)command;
- (void)scripterSaysViewPreferences:(NSScriptCommand *)command;
@end
