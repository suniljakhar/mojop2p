#import <Cocoa/Cocoa.h>
#import <Security/Security.h>
#import "RHKeychain.h"
#import "RHCalendarDate.h"
#import "AppDelegate.h"

// APPLE BUG RADAR 3425797:
// You can't get the 'kSecLabelItemAttr' using SecKeychainItemCopyAttributesAndData().
// So either we have to use the number '7' or use SecKeychainItemCopyContent().
// See http://lists.apple.com/archives/Apple-cdsa/2006/May/msg00037.html
#define HACK_FOR_LABEL (7)

@interface RHKeychain (PrivateAPI)
+ (NSString *)stringForSecExternalFormat:(SecExternalFormat)extFormat;
+ (NSString *)stringForSecExternalItemType:(SecExternalItemType)itemType;
+ (NSString *)stringForSecKeychainAttrType:(SecKeychainAttrType)attrType;
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation RHKeychain

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Server:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Retrieves the password stored in the keychain for the Mojo server.
**/
+ (NSString *)passwordForHTTPServer
{
	NSString *password = nil;
	
	const char *service = [@"Mojo Server" UTF8String];
	const char *account = [@"Mojo" UTF8String];
	
	UInt32 passwordLength = 0;
	void *passwordBytes = nil;
	
	OSStatus status;
	status = SecKeychainFindGenericPassword(NULL,            // default keychain
											strlen(service), // length of service name
											service,         // service name
											strlen(account), // length of account name
											account,         // account name
											&passwordLength, // length of password
											&passwordBytes,  // pointer to password data
											NULL);           // keychain item reference (NULL if unneeded)
	
	if(status == noErr)
	{
		NSData *passwordData = [NSData dataWithBytesNoCopy:passwordBytes length:passwordLength freeWhenDone:NO];
		password = [[[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding] autorelease];
	}
	
	// SecKeychainItemFreeContent(attrList, data)
	// attrList - previously returned attributes
	// data - previously returned password
	
	if(passwordBytes) SecKeychainItemFreeContent(NULL, passwordBytes);
	
	return password;
}


/**
 * This method sets the password for the Mojo server.
**/
+ (BOOL)setPasswordForHTTPServer:(NSString *)password
{
	const char *service = [@"Mojo Server" UTF8String];
	const char *account = [@"Mojo" UTF8String];
	const char *kind    = [@"Mojo password" UTF8String];
	const char *passwd  = [password UTF8String];
	
	SecTrustedApplicationRef mojo = NULL;
	SecTrustedApplicationRef mojoHelper = NULL;
	SecAccessRef access = NULL;
	SecKeychainItemRef itemRef = NULL;
	
	// The first thing we need to do is check to see a password for the library already exists in the keychain
	OSStatus status;
	status = SecKeychainFindGenericPassword(NULL,            // default keychain
											strlen(service), // length of service name
											service,         // service name
											strlen(account), // length of account name
											account,         // account name
											NULL,            // length of password (NULL if unneeded)
											NULL,            // pointer to password data (NULL if unneeded)
											&itemRef);       // the keychain item reference
	
	if(status == errSecItemNotFound)
	{
		// Configure the access list to include both Mojo and MojoHelper
		NSString *mojoPath       = [[NSApp delegate] mojoPath];
		NSString *mojoHelperPath = [[NSApp delegate] mojoHelperPath];
		
		SecTrustedApplicationCreateFromPath([mojoPath UTF8String], &mojo);
		SecTrustedApplicationCreateFromPath([mojoHelperPath UTF8String], &mojoHelper);
		
		NSArray *trustedApplications = [NSArray arrayWithObjects:(id)mojo, (id)mojoHelper, nil];
		
		SecAccessCreate((CFStringRef)@"Mojo", (CFArrayRef)trustedApplications, &access);
		
		// Setup the attributes the for the keychain item
		SecKeychainAttribute attrs[] = {
			{ kSecServiceItemAttr, strlen(service), (char *)service },
			{ kSecAccountItemAttr, strlen(account), (char *)account },
			{ kSecDescriptionItemAttr, strlen(kind), (char *)kind }
		};
		SecKeychainAttributeList attributes = { sizeof(attrs) / sizeof(attrs[0]), attrs };
		
		status = SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass, // class of item to create
												  &attributes,                  // pointer to the list of attributes
												  strlen(passwd),               // length of password
												  passwd,                       // pointer to password data
												  NULL,                         // default keychain
												  access,                       // our access list
												  &itemRef);                    // the keychain item reference
	}
	else if(status == noErr)
	{
		// A keychain item for the library already exists
		// All we need to do is update it with the new password
		status = SecKeychainItemModifyAttributesAndData(itemRef,        // the keychain item reference
														NULL,           // no change to attributes
														strlen(passwd),	// length of password
														passwd);        // pointer to password data
	}
	
	// Don't forget to release anything we create
	if(mojo)       CFRelease(mojo);
	if(mojoHelper) CFRelease(mojoHelper);
	if(access)     CFRelease(access);
	if(itemRef)    CFRelease(itemRef);
	
	return (status == noErr);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPP:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the password used to connect to the XMPP server.
 * The username plus server address, port, and connection options are stored in plaintext in the user defaults system.
**/
+ (NSString *)passwordForXMPPServer
{
	NSString *password = nil;
	
	const char *service = [@"XMPP Server" UTF8String];
	const char *account = [@"Mojo" UTF8String];
	
	UInt32 passwordLength = 0;
	void *passwordBytes = nil;
	
	OSStatus status;
	status = SecKeychainFindGenericPassword(NULL,             // default keychain
											strlen(service),  // length of service name
											service,          // service name
											strlen(account),  // length of account name
											account,          // account name
											&passwordLength,  // length of password
											&passwordBytes,   // pointer to password data
											NULL);            // keychain item reference (NULL if unneeded)
	
	if(status == noErr)
	{
		NSData *passwordData = [NSData dataWithBytesNoCopy:passwordBytes length:passwordLength freeWhenDone:NO];
		password = [[[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding] autorelease];
	}
	
	// SecKeychainItemFreeContent(attrList, data)
	// attrList - previously returned attributes
	// data - previously returned password
	
	if(passwordBytes) SecKeychainItemFreeContent(NULL, passwordBytes);
	
	return password;
}

/**
 * Sets the password used to connect to the XMPP server.
 * The username plus server address, port, and connection options are stored in plaintext in the user defaults system.
**/
+ (BOOL)setPasswordForXMPPServer:(NSString *)password
{
	const char *service = [@"XMPP Server" UTF8String];
	const char *account = [@"Mojo" UTF8String];
	const char *kind    = [@"Mojo password" UTF8String];
	const char *passwd  = [password UTF8String];
	
	SecTrustedApplicationRef mojo = NULL;
	SecTrustedApplicationRef mojoHelper = NULL;
	SecAccessRef access = NULL;
	SecKeychainItemRef itemRef = NULL;
	
	// The first thing we need to do is check to see a password for the library already exists in the keychain
	OSStatus status;
	status = SecKeychainFindGenericPassword(NULL,             // default keychain
											strlen(service),  // length of service name
											service,          // service name
											strlen(account),  // length of account name
											account,          // account name
											NULL,             // length of password (NULL if unneeded)
											NULL,             // pointer to password data (NULL if unneeded)
											&itemRef);        // the keychain item reference
	
	if(status == errSecItemNotFound)
	{
		// Configure the access list to include both Mojo and MojoHelper
		NSString *mojoPath       = [[NSApp delegate] mojoPath];
		NSString *mojoHelperPath = [[NSApp delegate] mojoHelperPath];
		
		SecTrustedApplicationCreateFromPath([mojoPath UTF8String], &mojo);
		SecTrustedApplicationCreateFromPath([mojoHelperPath UTF8String], &mojoHelper);
		
		NSArray *trustedApplications = [NSArray arrayWithObjects:(id)mojo, (id)mojoHelper, nil];
		
		SecAccessCreate((CFStringRef)@"Mojo", (CFArrayRef)trustedApplications, &access);
		
		// Setup the attributes the for the keychain item
		SecKeychainAttribute attrs[] = {
			{ kSecServiceItemAttr, strlen(service), (char *)service },
			{ kSecAccountItemAttr, strlen(account), (char *)account },
			{ kSecDescriptionItemAttr, strlen(kind), (char *)kind }
		};
		SecKeychainAttributeList attributes = { sizeof(attrs) / sizeof(attrs[0]), attrs };
		
		status = SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass,  // class of item to create
												  &attributes,                   // pointer to the list of attributes
												  strlen(passwd),                // length of password
												  passwd,                        // pointer to password data
												  NULL,                          // default keychain
												  access,                        // our access list
												  &itemRef);                     // the keychain item reference
	}
	else if(status == noErr)
	{
		// A keychain item for the library already exists
		// All we need to do is update it with the new password
		status = SecKeychainItemModifyAttributesAndData(itemRef,         // the keychain item reference
														NULL,            // no change to attributes
														strlen(passwd),  // length of password
														passwd);         // pointer to password data
	}
	
	// Don't forget to release anything we create
	if(mojo)       CFRelease(mojo);
	if(mojoHelper) CFRelease(mojoHelper);
	if(access)     CFRelease(access);
	if(itemRef)    CFRelease(itemRef);
	
	return (status == noErr);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Libraries:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Retrieves the password stored in the keychain for the given library.
**/
+ (NSString *)passwordForLibraryID:(NSString *)libID
{
	NSString *serviceName = [NSString stringWithFormat:@"Mojo: %@", libID];
	NSString *password = nil;
	
	const char *service = [serviceName UTF8String];
	const char *account = [libID UTF8String];
	
	UInt32 passwordLength = 0;
	void *passwordBytes = nil;
	
	OSStatus status;
	status = SecKeychainFindGenericPassword(NULL,             // default keychain
											strlen(service),  // length of service name
											service,          // service name
											strlen(account),  // length of account name
											account,          // account name
											&passwordLength,  // length of password
											&passwordBytes,   // pointer to password data
											NULL);            // keychain item reference (NULL if unneeded)
	
	if(status == noErr)
	{
		NSData	*passwordData = [NSData dataWithBytes:passwordBytes length:passwordLength];
		password = [[[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding] autorelease];
	}
	
	// SecKeychainItemFreeContent(attrList, data)
	// attrList - previously returned attributes
	// data - previously returned password
	
	if(passwordBytes) SecKeychainItemFreeContent(NULL, passwordBytes);
	
	return password;
}


/**
 * Sets the password stored in the keychain for the given library.
 * The name of the keychain item will be set to "Mojo: <libID>", and the account will be set to "<libID>"
 * If a keychain item already exists for the given library, it is updated with the given password.
**/
+ (BOOL)setPassword:(NSString *)password forLibraryID:(NSString *)libID
{
	const char *service = [[NSString stringWithFormat:@"Mojo: %@", libID] UTF8String];
	const char *account = [libID UTF8String];
	const char *kind    = [@"Mojo password" UTF8String];
	const char *passwd  = [password UTF8String];
	
	SecTrustedApplicationRef mojo = NULL;
	SecTrustedApplicationRef mojoHelper = NULL;
	SecAccessRef access = NULL;
	SecKeychainItemRef itemRef = NULL;
	
	// The first thing we need to do is check to see a password for the library already exists in the keychain
	OSStatus status;
	status = SecKeychainFindGenericPassword(NULL,            // default keychain
											strlen(service), // length of service name
											service,         // service name
											strlen(account), // length of account name
											account,         // account name
											NULL,            // length of password (NULL if unneeded)
											NULL,            // pointer to password data (NULL if unneeded)
											&itemRef);       // the keychain item reference
	
	if(status == errSecItemNotFound)
	{
		// Configure the access list to include both Mojo and MojoHelper
		NSString *mojoPath       = [[NSApp delegate] mojoPath];
		NSString *mojoHelperPath = [[NSApp delegate] mojoHelperPath];
		
		SecTrustedApplicationCreateFromPath([mojoPath UTF8String], &mojo);
		SecTrustedApplicationCreateFromPath([mojoHelperPath UTF8String], &mojoHelper);
		
		NSArray *trustedApplications = [NSArray arrayWithObjects:(id)mojo, (id)mojoHelper, nil];
		
		SecAccessCreate((CFStringRef)@"Mojo", (CFArrayRef)trustedApplications, &access);
		
		// Setup the attributes the for the keychain item
		SecKeychainAttribute attrs[] = {
		{ kSecServiceItemAttr, strlen(service), (char *)service },
		{ kSecAccountItemAttr, strlen(account), (char *)account },
		{ kSecDescriptionItemAttr, strlen(kind), (char *)kind }
		};
		SecKeychainAttributeList attributes = { sizeof(attrs) / sizeof(attrs[0]), attrs };
		
		status = SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass, // class of item to create
												  &attributes,                  // pointer to the list of attributes
												  strlen(passwd),               // length of password
												  passwd,                       // pointer to password data
												  NULL,                         // default keychain
												  access,                       // our access list
												  &itemRef);                    // the keychain item reference
	}
	else if(status == noErr)
	{
		// A keychain item for the library already exists
		// All we need to do is update it with the new password
		status = SecKeychainItemModifyAttributesAndData(itemRef,        // the keychain item reference
														NULL,           // no change to attributes
														strlen(passwd),	// length of password
														passwd);        // pointer to password data
	}
	
	// Don't forget to release anything we create
	if(mojo)       CFRelease(mojo);
	if(mojoHelper) CFRelease(mojoHelper);
	if(access)     CFRelease(access);
	if(itemRef)    CFRelease(itemRef);
	
	return (status == noErr);	
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Identity:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method creates a new identity, and adds it to the keychain.
 * An identity is simply a certificate (public key and public information) along with a matching private key.
 * This method generates a new private key, and then uses the private key to generate a new self-signed certificate.
**/
+ (void)createNewIdentity
{
	// Declare any Carbon variables we may create
	// We do this here so it's easier to compare to the bottom of this method where we release them all
	SecTrustedApplicationRef mojo = NULL;
	SecTrustedApplicationRef mojoHelper = NULL;
	SecAccessRef access = NULL;
	SecKeychainRef keychain = NULL;
	CFArrayRef outItems = NULL;
	
	// Configure the paths where we'll create all of our identity files
	NSString *basePath = [[NSApp delegate] applicationSupportDirectory];
	
	NSString *privateKeyPath  = [basePath stringByAppendingPathComponent:@"private.pem"];
	NSString *reqConfPath     = [basePath stringByAppendingPathComponent:@"req.conf"];
	NSString *certificatePath = [basePath stringByAppendingPathComponent:@"certificate.crt"];
	NSString *certWrapperPath = [basePath stringByAppendingPathComponent:@"certificate.p12"];
	
	// You can generate your own private key by running the following command in the terminal:
	// openssl genrsa -out private.pem 1024
	//
	// Where 1024 is the size of the private key.
	// You may used a bigger number.
	// It is probably a good recommendation to use at least 1024...
	
	NSArray *privateKeyArgs = [NSArray arrayWithObjects:@"genrsa", @"-out", privateKeyPath, @"1024", nil];
	
	NSTask *genPrivateKeyTask = [[[NSTask alloc] init] autorelease];
	
	[genPrivateKeyTask setLaunchPath:@"/usr/bin/openssl"];
	[genPrivateKeyTask setArguments:privateKeyArgs];
    [genPrivateKeyTask launch];
	
	// Don't use waitUntilExit - I've had too many problems with it in the past
	do {
		[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
	} while([genPrivateKeyTask isRunning]);
	
	// Now we want to create a configuration file for our certificate
	// This is an optional step, but we do it so people who are browsing their keychain
	// know exactly where the certificate came from, and don't delete it.
	
	NSMutableString *mStr = [NSMutableString stringWithCapacity:250];
	[mStr appendFormat:@"%@\n", @"[ req ]"];
	[mStr appendFormat:@"%@\n", @"distinguished_name  = req_distinguished_name"];
	[mStr appendFormat:@"%@\n", @"prompt              = no"];
	[mStr appendFormat:@"%@\n", @""];
	[mStr appendFormat:@"%@\n", @"[ req_distinguished_name ]"];
	[mStr appendFormat:@"%@\n", @"C                   = US"];
	[mStr appendFormat:@"%@\n", @"ST                  = Missouri"];
	[mStr appendFormat:@"%@\n", @"L                   = Springfield"];
	[mStr appendFormat:@"%@\n", @"O                   = Deusty Designs, LLC"];
	[mStr appendFormat:@"%@\n", @"OU                  = Mojo"];
	[mStr appendFormat:@"%@\n", @"CN                  = Mojo User"];
	[mStr appendFormat:@"%@\n", @"emailAddress        = mojo@deusty.com"];
	
	[mStr writeToFile:reqConfPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
	
	// You can generate your own certificate by running the following command in the terminal:
	// openssl req -new -x509 -key private.pem -out certificate.crt -text -days 365 -batch
	// 
	// You can optionally create a configuration file, and pass an extra command to use it:
	// -config req.conf
	
	NSArray *certificateArgs = [NSArray arrayWithObjects:@"req", @"-new", @"-x509",
														 @"-key", privateKeyPath,
	                                                     @"-config", reqConfPath,
	                                                     @"-out", certificatePath,
	                                                     @"-text", @"-days", @"365", @"-batch", nil];
	
	NSTask *genCertificateTask = [[[NSTask alloc] init] autorelease];
	
	[genCertificateTask setLaunchPath:@"/usr/bin/openssl"];
	[genCertificateTask setArguments:certificateArgs];
    [genCertificateTask launch];
	
	// Don't use waitUntilExit - I've had too many problems with it in the past
	do {
		[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
	} while([genCertificateTask isRunning]);
	
	// Mac OS X has problems importing private keys, so we wrap everything in PKCS#12 format
	// You can create a p12 wrapper by running the following command in the terminal:
	// openssl pkcs12 -export -in certificate.crt -inkey private.pem \
	//   -passout pass:password -out certificate.p12 -name "Mojo User"
	
	NSArray *certWrapperArgs = [NSArray arrayWithObjects:@"pkcs12", @"-export", @"-export",
														 @"-in", certificatePath,
	                                                     @"-inkey", privateKeyPath,
	                                                     @"-passout", @"pass:password",
	                                                     @"-out", certWrapperPath,
	                                                     @"-name", @"Mojo User", nil];
	
	NSTask *genCertWrapperTask = [[[NSTask alloc] init] autorelease];
	
	[genCertWrapperTask setLaunchPath:@"/usr/bin/openssl"];
	[genCertWrapperTask setArguments:certWrapperArgs];
    [genCertWrapperTask launch];
	
	// Don't use waitUntilExit - I've had too many problems with it in the past
	do {
		[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
	} while([genCertWrapperTask isRunning]);
	
	// At this point we've created all the identity files that we need
	// Our next step is to import the identity into the keychain
	// We can do this by using the SecKeychainItemImport() method.
	// But of course this method is "Frozen in Carbonite"...
	// So it's going to take us 100 lines of code to build up the parameters needed to make the method call
	NSData *certData = [NSData dataWithContentsOfFile:certWrapperPath];
	
	/* SecKeyImportExportFlags - typedef uint32_t
	 * Defines values for the flags field of the import/export parameters.
	 * 
	 * enum 
	 * {
	 *    kSecKeyImportOnlyOne        = 0x00000001,
	 *    kSecKeySecurePassphrase     = 0x00000002,
	 *    kSecKeyNoAccessControl      = 0x00000004
	 * };
	 * 
	 * kSecKeyImportOnlyOne
	 *     Prevents the importing of more than one private key by the SecKeychainItemImport function.
	 *     If the importKeychain parameter is NULL, this bit is ignored. Otherwise, if this bit is set and there is
	 *     more than one key in the incoming external representation,
	 *     no items are imported to the specified keychain and the error errSecMultipleKeys is returned.
	 * kSecKeySecurePassphrase
	 *     When set, the password for import or export is obtained by user prompt. Otherwise, you must provide the
	 *     password in the passphrase field of the SecKeyImportExportParameters structure.
	 *     A user-supplied password is preferred, because it avoids having the cleartext password appear in the
	 *     application’s address space at any time.
	 * kSecKeyNoAccessControl
	 *     When set, imported private keys have no access object attached to them. In the absence of both this bit and
	 *     the accessRef field in SecKeyImportExportParameters, imported private keys are given default access controls
	**/
	
	SecKeyImportExportFlags importFlags = kSecKeyImportOnlyOne;
	
	// Configure the access list to include both Mojo and MojoHelper
	NSString *mojoPath       = [[NSApp delegate] mojoPath];
	NSString *mojoHelperPath = [[NSApp delegate] mojoHelperPath];
	
	SecTrustedApplicationCreateFromPath([mojoPath UTF8String], &mojo);
	SecTrustedApplicationCreateFromPath([mojoHelperPath UTF8String], &mojoHelper);
	
	NSArray *trustedApplications = [NSArray arrayWithObjects:(id)mojo, (id)mojoHelper, nil];
	
	SecAccessCreate((CFStringRef)@"Mojo", (CFArrayRef)trustedApplications, &access);
	
	/* SecKeyImportExportParameters - typedef struct
	 *
	 * FOR IMPORT AND EXPORT:
	 * uint32_t version
	 *     The version of this structure; the current value is SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION.
	 * SecKeyImportExportFlags flags
	 *     A set of flag bits, defined in "Keychain Item Import/Export Parameter Flags".
	 * CFTypeRef passphrase
	 *     A password, used for kSecFormatPKCS12 and kSecFormatWrapped formats only...
	 *     IE - kSecFormatWrappedOpenSSL, kSecFormatWrappedSSH, or kSecFormatWrappedPKCS8
	 * CFStringRef alertTitle
	 *     Title of secure password alert panel.
	 *     When importing or exporting a key, if you set the kSecKeySecurePassphrase flag bit,
	 *     you can optionally use this field to specify a string for the password panel’s title bar.
	 * CFStringRef alertPrompt
	 *     Prompt in secure password alert panel.
	 *     When importing or exporting a key, if you set the kSecKeySecurePassphrase flag bit,
	 *     you can optionally use this field to specify a string for the prompt that appears in the password panel.
	 *
	 * FOR IMPORT ONLY:
	 * SecAccessRef accessRef
	 *     Specifies the initial access controls of imported private keys.
	 *     If more than one private key is being imported, all private keys get the same initial access controls.
	 *     If this field is NULL when private keys are being imported, then the access object for the keychain item
	 *     for an imported private key depends on the kSecKeyNoAccessControl bit in the flags parameter.
	 *     If this bit is 0 (or keyParams is NULL), the default access control is used.
	 *     If this bit is 1, no access object is attached to the keychain item for imported private keys.
	 * CSSM_KEYUSE keyUsage
	 *     A word of bits constituting the low-level use flags for imported keys as defined in cssmtype.h.
	 *     If this field is 0 or keyParams is NULL, the default value is CSSM_KEYUSE_ANY.
	 * CSSM_KEYATTR_FLAGS keyAttributes
	 *     The following are valid values for these flags:
	 *     CSSM_KEYATTR_PERMANENT, CSSM_KEYATTR_SENSITIVE, and CSSM_KEYATTR_EXTRACTABLE.
	 *     The default value is CSSM_KEYATTR_SENSITIVE | CSSM_KEYATTR_EXTRACTABLE
	 *     The CSSM_KEYATTR_SENSITIVE bit indicates that the key can only be extracted in wrapped form.
	 *     Important: If you do not set the CSSM_KEYATTR_EXTRACTABLE bit,
	 *     you cannot extract the imported key from the keychain in any form, including in wrapped form.
	**/
	
	SecKeyImportExportParameters importParameters;
	importParameters.version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION;
	importParameters.flags = importFlags;
	importParameters.passphrase = CFSTR("password");
	importParameters.accessRef = access;
	importParameters.keyUsage = CSSM_KEYUSE_ANY;
	importParameters.keyAttributes = CSSM_KEYATTR_SENSITIVE | CSSM_KEYATTR_EXTRACTABLE;
	
	/* SecKeychainItemImport - Imports one or more certificates, keys, or identities and adds them to a keychain.
	 * 
	 * Parameters:
	 * CFDataRef importedData
	 *     The external representation of the items to import.
	 * CFStringRef fileNameOrExtension
	 *     The name or extension of the file from which the external representation was obtained.
	 *     Pass NULL if you don’t know the name or extension.
	 * SecExternalFormat *inputFormat
	 *     On input, points to the format of the external representation.
	 *     Pass kSecFormatUnknown if you do not know the exact format.
	 *     On output, points to the format that the function has determined the external representation to be in.
	 *     Pass NULL if you don’t know the format and don’t want the format returned to you.
	 * SecExternalItemType *itemType
	 *     On input, points to the item type of the item or items contained in the external representation.
	 *     Pass kSecItemTypeUnknown if you do not know the item type.
	 *     On output, points to the item type that the function has determined the external representation to contain.
	 *     Pass NULL if you don’t know the item type and don’t want the type returned to you.
	 * SecItemImportExportFlags flags
	 *     Unused; pass in 0.
	 * const SecKeyImportExportParameters *keyParams
	 *     A pointer to a structure containing a set of input parameters for the function.
	 *     If no key items are being imported, these parameters are optional
	 *     and you can set the keyParams parameter to NULL.
	 * SecKeychainRef importKeychain
	 *     A keychain object indicating the keychain to which the key or certificate should be imported.
	 *     If you pass NULL, the item is not imported.
	 *     Use the SecKeychainCopyDefault function to get a reference to the default keychain.
	 *     If the kSecKeyImportOnlyOne bit is set and there is more than one key in the
	 *     incoming external representation, no items are imported to the specified keychain and the
	 *     error errSecMultiplePrivKeys is returned.
	 * CFArrayRef *outItems
	 *     On output, points to an array of SecKeychainItemRef objects for the imported items.
	 *     You must provide a valid pointer to a CFArrayRef object to receive this information.
	 *     If you pass NULL for this parameter, the function does not return the imported items.
	 *     Release this object by calling the CFRelease function when you no longer need it.
	**/
	
	SecExternalFormat inputFormat = kSecFormatPKCS12;
	SecExternalItemType itemType = kSecItemTypeUnknown;
	
	SecKeychainCopyDefault(&keychain);
	
	OSStatus err = 0;
	err = SecKeychainItemImport((CFDataRef)certData,   // CFDataRef importedData
								NULL,                  // CFStringRef fileNameOrExtension
								&inputFormat,          // SecExternalFormat *inputFormat
								&itemType,             // SecExternalItemType *itemType
								0,                     // SecItemImportExportFlags flags (Unused)
								&importParameters,     // const SecKeyImportExportParameters *keyParams
								keychain,              // SecKeychainRef importKeychain
								&outItems);            // CFArrayRef *outItems
	
	NSLog(@"OSStatus: %i", err);
	
	NSLog(@"SecExternalFormat: %@", [RHKeychain stringForSecExternalFormat:inputFormat]);
	NSLog(@"SecExternalItemType: %@", [RHKeychain stringForSecExternalItemType:itemType]);
	
	NSLog(@"outItems: %@", (NSArray *)outItems);
	
	// Don't forget to delete the temporary files
	[[NSFileManager defaultManager] removeFileAtPath:privateKeyPath handler:nil];
	[[NSFileManager defaultManager] removeFileAtPath:reqConfPath handler:nil];
	[[NSFileManager defaultManager] removeFileAtPath:certificatePath handler:nil];
	[[NSFileManager defaultManager] removeFileAtPath:certWrapperPath handler:nil];
	
	// Don't forget to release anything we may have created
	if(mojo)       CFRelease(mojo);
	if(mojoHelper) CFRelease(mojoHelper);
	if(access)     CFRelease(access);
	if(keychain)   CFRelease(keychain);
	if(outItems)   CFRelease(outItems);
}

/**
 * Returns an array of SecCertificateRefs except for the first element in the array, which is a SecIdentityRef.
**/
+ (NSArray *)SSLIdentityAndCertificates
{
	// Declare any Carbon variables we may create
	// We do this here so it's easier to compare to the bottom of this method where we release them all
	SecKeychainRef keychain = NULL;
	SecIdentitySearchRef searchRef = NULL;
	
	// Create array to hold the results
	NSMutableArray *result = [NSMutableArray array];
	
	/* SecKeychainAttribute - typedef struct
	 * Contains keychain attributes.
	 *
	 * struct SecKeychainAttribute
	 * {
	 *   SecKeychainAttrType tag;
	 *   UInt32 length;
	 *   void *data;
	 * };
	 *
	 * Fields:
	 * tag
	 *     A 4-byte attribute tag. See “Keychain Item Attribute Constants” for valid attribute types.
	 * length
	 *     The length of the buffer pointed to by data.
	 * data
	 *     A pointer to the attribute data.
	**/

	/* SecKeychainAttributeList - typedef struct
	 * Represents a list of keychain attributes.
	 * 
	 * struct SecKeychainAttributeList
	 * {
	 *   UInt32 count;
	 *   SecKeychainAttribute *attr;
	 * };
	 *
	 * Fields:
	 * count
	 *     An unsigned 32-bit integer that represents the number of keychain attributes in the array.
	 * attr
	 *     A pointer to the first keychain attribute in the array.
	**/
	
	SecKeychainCopyDefault(&keychain);
	
	SecIdentitySearchCreate(keychain, CSSM_KEYUSE_ANY, &searchRef);
	
	SecIdentityRef currentIdentityRef = NULL;
	while(searchRef && (SecIdentitySearchCopyNext(searchRef, &currentIdentityRef) != errSecItemNotFound))
	{
		// Extract the private key from the identity, and examine it to see if it will work for Mojo
		SecKeyRef privateKeyRef = NULL;
		SecIdentityCopyPrivateKey(currentIdentityRef, &privateKeyRef);
		
		if(privateKeyRef)
		{
			// Get the name attribute of the private key
			// We're looking for a private key with the name of "Mojo User"
			
			SecItemAttr itemAttributes[] = {kSecKeyPrintName};
			
			SecExternalFormat externalFormats[] = {kSecFormatUnknown};
			
			int itemAttributesSize  = sizeof(itemAttributes) / sizeof(*itemAttributes);
			int externalFormatsSize = sizeof(externalFormats) / sizeof(*externalFormats);
			NSAssert(itemAttributesSize == externalFormatsSize, @"Arrays must have identical counts!");
			
			SecKeychainAttributeInfo info = {itemAttributesSize, (void *)&itemAttributes, (void *)&externalFormats};
			
			SecKeychainAttributeList *privateKeyAttributeList = NULL;
			SecKeychainItemCopyAttributesAndData((SecKeychainItemRef)privateKeyRef,
			                                     &info, NULL, &privateKeyAttributeList, NULL, NULL);
			
			if(privateKeyAttributeList)
			{
				SecKeychainAttribute nameAttribute = privateKeyAttributeList->attr[0];
				
				NSString *name = [[[NSString alloc] initWithBytes:nameAttribute.data
														   length:(nameAttribute.length)
														 encoding:NSUTF8StringEncoding] autorelease];
				
				// Ugly Hack
				// For some reason, name sometimes contains odd characters at the end of it
				// I'm not sure why, and I don't know of a proper fix, thus the use of the hasPrefix: method
				if([name hasPrefix:@"Mojo User"])
				{
					// It's possible for there to be more than one private key with the above prefix
					// But we're only allowed to have one identity, so we make sure to only add one to the array
					if([result count] == 0)
					{
						[result addObject:(id)currentIdentityRef];
					}
				}
				
				SecKeychainItemFreeAttributesAndData(privateKeyAttributeList, NULL);
			}
			
			CFRelease(privateKeyRef);
		}
		
		CFRelease(currentIdentityRef);
	}
	
	if(keychain)  CFRelease(keychain);
	if(searchRef) CFRelease(searchRef);
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Simple utility class to convert a SecExternalFormat into a string suitable for printing/logging.
**/
+ (NSString *)stringForSecExternalFormat:(SecExternalFormat)extFormat
{
	switch(extFormat)
	{
		case kSecFormatUnknown              : return @"kSecFormatUnknown";
			
		/* Asymmetric Key Formats */
		case kSecFormatOpenSSL              : return @"kSecFormatOpenSSL";
		case kSecFormatSSH                  : return @"kSecFormatSSH - Not Supported";
		case kSecFormatBSAFE                : return @"kSecFormatBSAFE";
			
		/* Symmetric Key Formats */
		case kSecFormatRawKey               : return @"kSecFormatRawKey";
			
		/* Formats for wrapped symmetric and private keys */
		case kSecFormatWrappedPKCS8         : return @"kSecFormatWrappedPKCS8";
		case kSecFormatWrappedOpenSSL       : return @"kSecFormatWrappedOpenSSL";
		case kSecFormatWrappedSSH           : return @"kSecFormatWrappedSSH - Not Supported";
		case kSecFormatWrappedLSH           : return @"kSecFormatWrappedLSH - Not Supported";
			
		/* Formats for certificates */
		case kSecFormatX509Cert             : return @"kSecFormatX509Cert";
			
		/* Aggregate Types */
		case kSecFormatPEMSequence          : return @"kSecFormatPEMSequence";
		case kSecFormatPKCS7                : return @"kSecFormatPKCS7";
		case kSecFormatPKCS12               : return @"kSecFormatPKCS12";
		case kSecFormatNetscapeCertSequence : return @"kSecFormatNetscapeCertSequence";
			
		default                             : return @"Unknown";
	}
}

/**
 * Simple utility class to convert a SecExternalItemType into a string suitable for printing/logging.
**/
+ (NSString *)stringForSecExternalItemType:(SecExternalItemType)itemType
{
	switch(itemType)
	{
		case kSecItemTypeUnknown     : return @"kSecItemTypeUnknown";
			
		case kSecItemTypePrivateKey  : return @"kSecItemTypePrivateKey";
		case kSecItemTypePublicKey   : return @"kSecItemTypePublicKey";
		case kSecItemTypeSessionKey  : return @"kSecItemTypeSessionKey";
		case kSecItemTypeCertificate : return @"kSecItemTypeCertificate";
		case kSecItemTypeAggregate   : return @"kSecItemTypeAggregate";
		
		default                      : return @"Unknown";
	}
}

/**
 * Simple utility class to convert a SecKeychainAttrType into a string suitable for printing/logging.
**/
+ (NSString *)stringForSecKeychainAttrType:(SecKeychainAttrType)attrType
{
	switch(attrType)
	{
		case kSecCreationDateItemAttr       : return @"kSecCreationDateItemAttr";
		case kSecModDateItemAttr            : return @"kSecModDateItemAttr";
		case kSecDescriptionItemAttr        : return @"kSecDescriptionItemAttr";
		case kSecCommentItemAttr            : return @"kSecCommentItemAttr";
		case kSecCreatorItemAttr            : return @"kSecCreatorItemAttr";
		case kSecTypeItemAttr               : return @"kSecTypeItemAttr";
		case kSecScriptCodeItemAttr         : return @"kSecScriptCodeItemAttr";
		case kSecLabelItemAttr              : return @"kSecLabelItemAttr";
		case kSecInvisibleItemAttr          : return @"kSecInvisibleItemAttr";
		case kSecNegativeItemAttr           : return @"kSecNegativeItemAttr";
		case kSecCustomIconItemAttr         : return @"kSecCustomIconItemAttr";
		case kSecAccountItemAttr            : return @"kSecAccountItemAttr";
		case kSecServiceItemAttr            : return @"kSecServiceItemAttr";
		case kSecGenericItemAttr            : return @"kSecGenericItemAttr";
		case kSecSecurityDomainItemAttr     : return @"kSecSecurityDomainItemAttr";
		case kSecServerItemAttr             : return @"kSecServerItemAttr";
		case kSecAuthenticationTypeItemAttr : return @"kSecAuthenticationTypeItemAttr";
		case kSecPortItemAttr               : return @"kSecPortItemAttr";
		case kSecPathItemAttr               : return @"kSecPathItemAttr";
		case kSecVolumeItemAttr             : return @"kSecVolumeItemAttr";
		case kSecAddressItemAttr            : return @"kSecAddressItemAttr";
		case kSecSignatureItemAttr          : return @"kSecSignatureItemAttr";
		case kSecProtocolItemAttr           : return @"kSecProtocolItemAttr";
		case kSecCertificateType            : return @"kSecCertificateType";
		case kSecCertificateEncoding        : return @"kSecCertificateEncoding";
		case kSecCrlType                    : return @"kSecCrlType";
		case kSecCrlEncoding                : return @"kSecCrlEncoding";
		case kSecAlias                      : return @"kSecAlias";
		default                             : return @"Unknown";
	}
}

/**
 * Returns an array of dictionaries.
 * Each item in the array represents a keychain item in the given class.
 * The KeychainItem itself may be referenced in the dictionary using the key "SecKeychainItemRef".
 * 
 * Note: I've never been able to get the SecKeychainSearchCreateFromAttributes method to work properly for me.
 * I think I package all the parameters up properly to fetch only the keychain items I want,
 * but I end up with an empty search. This is probably due to the fact that the keychain is "Frozen in Carbonite!"
 * 
 * Thus, I use this method to get all the keychain items, convert everything into proper Cocoa, and then simply
 * loop over the items quickly, easily, and cleanly using Cocoa, as opposed to the fucking, shit stinking,
 * asshole ripping, flaming pile of dog shit, fuck you dumb ass fuckers for not making a decent Cocoa wrapper, I hope
 * you rot in hell you incompetent framework designer, go die of gonnerea!
**/
+ (NSMutableArray *)allGenericKeychainItems
{
	// Declare any Carbon variables we may create
	// We do this here so it's easier to compare to the bottom of this method where we release them all
	SecKeychainRef keychain = NULL;
	SecKeychainSearchRef searchRef = NULL;
	
	// Create array to hold all the generic keychain items we find
	NSMutableArray *results = [NSMutableArray array];
	
	/* SecKeychainAttribute - typedef struct
	 * Contains keychain attributes.
	 *
	 * struct SecKeychainAttribute
	 * {
	 *   SecKeychainAttrType tag;
	 *   UInt32 length;
	 *   void *data;
	 * };
	 *
	 * Fields:
	 * tag
	 *     A 4-byte attribute tag. See “Keychain Item Attribute Constants” for valid attribute types.
	 * length
	 *     The length of the buffer pointed to by data.
	 * data
	 *     A pointer to the attribute data.
	**/

	/* SecKeychainAttributeList - typedef struct
	 * Represents a list of keychain attributes.
	 * 
	 * struct SecKeychainAttributeList
	 * {
	 *   UInt32 count;
	 *   SecKeychainAttribute *attr;
	 * };
	 *
	 * Fields:
	 * count
	 *     An unsigned 32-bit integer that represents the number of keychain attributes in the array.
	 * attr
	 *     A pointer to the first keychain attribute in the array.
	**/
	
	SecKeychainCopyDefault(&keychain);
	
	SecKeychainSearchCreateFromAttributes(keychain, kSecGenericPasswordItemClass, NULL, &searchRef);
	
	SecKeychainItemRef currentItem = NULL;
	while(searchRef && (SecKeychainSearchCopyNext(searchRef, &currentItem) != errSecItemNotFound))
	{
		SecItemAttr itemAttributes[] = {kSecCreationDateItemAttr,
									    kSecModDateItemAttr,
			                            kSecDescriptionItemAttr,
		                                kSecAccountItemAttr,
		                                kSecServiceItemAttr,
		                                kSecCommentItemAttr,
		                                HACK_FOR_LABEL};
		
		SecExternalFormat externalFormats[] = {kSecFormatUnknown,
		                                       kSecFormatUnknown,
		                                       kSecFormatUnknown,
											   kSecFormatUnknown,
		                                       kSecFormatUnknown,
		                                       kSecFormatUnknown,
		                                       kSecFormatUnknown};
		
		int itemAttributesSize  = sizeof(itemAttributes) / sizeof(*itemAttributes);
		int externalFormatsSize = sizeof(externalFormats) / sizeof(*externalFormats);
		NSAssert(itemAttributesSize == externalFormatsSize, @"Arrays must have identical counts!");
		
		SecKeychainAttributeInfo info = {itemAttributesSize, (void *)&itemAttributes, (void *)&externalFormats};
		
		SecKeychainAttributeList *currentItemAttributeList = NULL;
		SecKeychainItemCopyAttributesAndData(currentItem, &info, NULL, &currentItemAttributeList, NULL, NULL);
		
		if(currentItemAttributeList)
		{
			NSMutableDictionary *siteDictionary = [NSMutableDictionary dictionary];
			
			// Store a reference to the original SecKeychainItemRef
			[siteDictionary setObject:(id)currentItem forKey:@"SecKeychainItemRef"];
			
			unsigned int attributeIndex;
			for(attributeIndex = 0; attributeIndex < currentItemAttributeList->count; attributeIndex++)
			{
				SecKeychainAttribute currentItemAttribute = currentItemAttributeList->attr[attributeIndex];
				
				SecKeychainAttrType tag = currentItemAttribute.tag;
				if(tag == HACK_FOR_LABEL) tag = kSecLabelItemAttr;
				
				id value;
				if(tag == kSecCreationDateItemAttr || tag == kSecModDateItemAttr)
				{
					// Identifies the creation date attribute.
					// The value for kSecCreationDateItemAttr and kSecModDateItemAttr is a string
					// in Zulu time format (e.g. '20060622164812Z').
					NSString *temp = [[[NSString alloc] initWithBytes:currentItemAttribute.data
															   length:currentItemAttribute.length
															 encoding:NSUTF8StringEncoding] autorelease];
					value = [NSCalendarDate calendarDateWithZuluDateString:temp];
				}
				else
				{
					value = [[[NSString alloc] initWithBytes:currentItemAttribute.data
													  length:currentItemAttribute.length
													encoding:NSUTF8StringEncoding] autorelease];
				}
				
				[siteDictionary setObject:value forKey:[self stringForSecKeychainAttrType:tag]];
			}
			
			[results addObject:siteDictionary];
			
			SecKeychainItemFreeAttributesAndData(currentItemAttributeList, NULL);
		}
		
		CFRelease(currentItem);
	}
	
	if(searchRef) CFRelease(searchRef);
	if(keychain)  CFRelease(keychain);
	
	return results;
}

/**
 * This method updates all the keychain items so that the access list
 * contains the correct version of Mojo or MojoHelper (whichever application calls this method).
 * This is recommended for MojoHelper, as it is supposed to be able to run in the background without user intervention.
**/
+ (void)updateAllKeychainItems
{
	// When an updated application attempts to access the keychain, the user is prompted to
	// update all keychain items.  Thus we'll search the keychain until we're able to access an item.
	// At that point we'll know we have access to the keychain, and we can return.
	// 
	// But wait!
	// Apparently this doesn't work, and occasionally the SSLIdentity requires another prompt.
	// So we'll just go ahead and loop through every item just to be sure.
	
	// First we try to update the HTTP server keychain item
	NSString *httpPassword = [self passwordForHTTPServer];
	if(httpPassword)
	{
		// Keep going...
	}
	
	// Next we try to update the XMPP server keychain item
	NSString *xmppPassword = [self passwordForXMPPServer];
	if(xmppPassword)
	{
		// Keep going...
	}
	
	NSArray *identityArray = [self SSLIdentityAndCertificates];
	if([identityArray count] > 0)
	{
		// Keep going...
	}
	
	// Now we need to loop over all the service keychain items
	NSArray *genericKeychainItems = [self allGenericKeychainItems];
	
	NSString *descriptionKey = [self stringForSecKeychainAttrType:kSecDescriptionItemAttr];
	NSString *accountKey     = [self stringForSecKeychainAttrType:kSecAccountItemAttr];
	
	unsigned int i;
	for(i = 0; i < [genericKeychainItems count]; i++)
	{
		NSDictionary *currentKeychainItem = [genericKeychainItems objectAtIndex:i];
		
		if([[currentKeychainItem objectForKey:descriptionKey] isEqualToString:@"Mojo password"])
		{
			NSString *account = [currentKeychainItem objectForKey:accountKey];
			
			// Ignore the server keychain, which we've already taken care of
			if(![account isEqualToString:@"Mojo"])
			{
				NSString *libraryPassword = [self passwordForLibraryID:account];
				
				if(libraryPassword)
				{
					// Keep going...
				}
			}
		}
	}
}

@end
