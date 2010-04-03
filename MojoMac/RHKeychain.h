#import <Foundation/Foundation.h>


@interface RHKeychain : NSObject

+ (NSString *)passwordForHTTPServer;
+ (BOOL)setPasswordForHTTPServer:(NSString *)password;

+ (NSString *)passwordForXMPPServer;
+ (BOOL)setPasswordForXMPPServer:(NSString *)password;

+ (NSString *)passwordForLibraryID:(NSString *)libID;
+ (BOOL)setPassword:(NSString *)password forLibraryID:(NSString *)libID;

+ (void)createNewIdentity;
+ (NSArray *)SSLIdentityAndCertificates;

+ (void)updateAllKeychainItems;

@end
