#import "WelcomeController.h"
#import "XMPPStream.h"
#import "NSXMLElementAdditions.h"
#import "MojoAppDelegate.h"
#import "MojoDefinitions.h"
#import "RHKeychain.h"
#import "PreferencesController.h"
#import "ServerListManager.h"

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 4
#else
  #define DEBUG_LEVEL 2
#endif
#include "DDLog.h"

@interface WelcomeController (PrivateAPI)
- (void)updateServerList;
@end


@implementation WelcomeController

/**
 * Standard Constructor.
**/
- (id)init
{
	if((self = [super initWithWindowNibName:@"Welcome"]))
	{
		isConnecting = NO;
		manualDisconnect = NO;
		xmppStream = [[XMPPStream alloc] initWithDelegate:self];
	}
	return self;
}

- (void)awakeFromNib
{
	[contentBox setContentView:view1];
	[[self window] center];
	[[self window] makeKeyAndOrderFront:self];
	[[self window] makeFirstResponder:nextButton];
	
	[self updateServerList];
}

/**
 * Called immediately before the window closes.
 * 
 * This method's job is to release the WindowController (self)
 * This is so that the nib file is released from memory.
**/
- (void)windowWillClose:(NSNotification *)aNotification
{
	[self autorelease];
}

/**
 * Standard Deconstructor
**/
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[xmppStream setDelegate:nil];
	[xmppStream disconnect];
	[xmppStream release];
	[regServer release];
	[regUsername release];
	[regPassword release];
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Interface Builder Actions:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)next:(id)sender
{
	[contentBox setContentView:view2];
	[[self window] makeFirstResponder:usernameField];
}

- (IBAction)toggleShowPassword:(id)sender
{
	if([sender state] == NSOnState)
	{
		// The shadowPasswordField is currently visible - Switch to clearPasswordField
		[clearPasswordField setStringValue:[shadowPasswordField stringValue]];
		[clearPasswordField setHidden:NO];
		[shadowPasswordField setHidden:YES];
		[[self window] makeFirstResponder:clearPasswordField];
	}
	else
	{
		// The clearPasswordField is currently visible - Switch to shadowPasswordField
		[shadowPasswordField setStringValue:[clearPasswordField stringValue]];
		[shadowPasswordField setHidden:NO];
		[clearPasswordField setHidden:YES];
		[[self window] makeFirstResponder:shadowPasswordField];
	}
}

- (IBAction)cancel:(id)sender
{
	if(isConnecting)
	{
		// User is clicking cancel while we're still trying to connect to the xmpp server.
		// Simply cancel the connection attempt, and let the user pick another server.
		
		[xmppStream disconnect];
	}
	else
	{
		[NSApp beginSheet:cancelSheet
		   modalForWindow:[self window]
			modalDelegate:self 
		   didEndSelector:nil
			  contextInfo:nil];
	}
}

- (IBAction)cancel_no:(id)sender
{
	[cancelSheet orderOut:self];
	[NSApp endSheet:cancelSheet];
}

- (IBAction)cancel_yes:(id)sender
{
	[cancelSheet orderOut:self];
	[NSApp endSheet:cancelSheet];
	
	[[self window] close];
}

- (IBAction)createAccount:(id)sender
{
	[regServer release];
	regServer = [[serverField stringValue] copy];
	
	[regUsername release];
	regUsername = [[usernameField stringValue] copy];
	
	id passwordField = [clearPasswordField isHidden] ? shadowPasswordField : clearPasswordField;
	
	[regPassword release];
	regPassword = [[passwordField stringValue] copy];
	
	[limitErrorMessage setHidden:YES];
	[serverErrorMessage setHidden:YES];
	[usernameErrorMessage setHidden:YES];
	[passwordErrorMessage setHidden:YES];
	[connectErrorMessage setHidden:YES];
	
	if([regServer length] == 0)
	{
		NSString *errMsg = NSLocalizedString(@"Select a server", @"Error message in welcome panel");
		
		[serverErrorMessage setStringValue:errMsg];
		[serverErrorMessage setHidden:NO];
	}
	else if([regUsername length] == 0)
	{
		NSString *errMsg = NSLocalizedString(@"Invalid Username!", @"Error message in welcome panel");
		
		[usernameErrorMessage setStringValue:errMsg];
		[usernameErrorMessage setHidden:NO];
	}
	else if([regPassword length] == 0)
	{
		// Display "Invalid Password!" message
		
		[passwordErrorMessage setHidden:NO];
	}
	else
	{
		[registerButton setEnabled:NO];
		
		[progressIndicator startAnimation:self];
		
		isConnecting = YES;
		manualDisconnect = NO;
		
		[xmppStream connectToHost:regServer
						   onPort:5222
				  withVirtualHost:regServer];
	}
}

- (IBAction)done:(id)sender
{
	[[self window] close];
}

- (IBAction)goToForum:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:MOJO_URL_FORUM]];
}

- (IBAction)goToAnswers:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:MOJO_URL_ACCOUNT_GUIDE]];
}

- (IBAction)useExistingAccount:(id)sender
{
	[[self window] close];
	[[[NSApp delegate] preferencesController] showAccountsSection];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Server List Updating
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)updateServerList
{
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(updateServerField:)
												 name:DidUpdateServerListNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateServerField:)
												 name:DidNotUpdateServerListNotification
											   object:nil];
	
	[serverProgressIndicator startAnimation:self];
	[ServerListManager updateServerList];
}

- (void)updateServerField:(NSNotification *)notification
{
	NSXMLDocument *doc = nil;
	
	NSData *data = [[NSData alloc] initWithContentsOfFile:[ServerListManager serverListPath]];
	if(data)
	{
		doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
	}
	
	if(doc)
	{
		NSArray *allServers = [[doc rootElement] children];
		
		if([allServers count] > 0)
		{
			[serverField removeAllItems];
			
			NSMutableArray *primaryServers = [NSMutableArray arrayWithCapacity:10];
			
			NSUInteger i;
			for(i = 0; i < [allServers count]; i++)
			{
				NSXMLElement *server = [allServers objectAtIndex:i];
				
				NSString *serverName = [[server attributeForName:@"name"] stringValue];
				
				[serverField addItemWithObjectValue:serverName];
				
				if([[[server attributeForName:@"primary"] stringValue] isEqualToString:@"yes"])
				{
					[primaryServers addObject:serverName];
				}
			}
			
			// If user hasn't changed the server from it's default value (deusty.com),
			// and there is at least one primary server available,
			// choose a server from the list of primary servers.
			
			NSString *currentServer = [serverField stringValue];
			
			if([currentServer isEqualToString:@"deusty.com"] && [primaryServers count] > 0)
			{
				unsigned ri = arc4random() % [primaryServers count];
				NSString *randomServer = [primaryServers objectAtIndex:ri];
				
				[serverField setStringValue:randomServer];
			}
		}
	}
	[doc release];
	[data release];
	
	[serverProgressIndicator stopAnimation:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPStream Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)xmppStreamDidOpen:(XMPPStream *)xs
{
	DDLogVerbose(@"WelcomeController: xmppStreamDidOpen:");
	
	isConnecting = NO;
	
	if(![xmppStream supportsInBandRegistration])
	{
		NSString *errMsg = NSLocalizedString(@"No Registration!", @"Error message in welcome panel");
		
		[serverErrorMessage setStringValue:errMsg];
		[serverErrorMessage setHidden:NO];
		
		[progressIndicator stopAnimation:self];
		[registerButton setEnabled:YES];
		
		manualDisconnect = YES;
		[xmppStream disconnect];
	}
	else
	{
		[xmppStream registerUser:regUsername withPassword:regPassword];
	}
}

- (void)xmppStreamDidRegister:(XMPPStream *)xs
{
	DDLogVerbose(@"WelcomeController: xmppStreamDidRegister:");
	
	// Stop progress indicator, and close window
	[progressIndicator stopAnimation:self];
	
	// Store server in user defaults system
	[[[NSApp delegate] helperProxy] setXMPPServer:regServer];
	
	// Store username in user defaults system
	NSString *jid = [NSString stringWithFormat:@"%@@%@", regUsername, regServer];
	[[[NSApp delegate] helperProxy] setXMPPUsername:jid];
	
	// Store password in keychain
	[RHKeychain setPasswordForXMPPServer:regPassword];
	
	// Post notification of new account
	[[NSNotificationCenter defaultCenter] postNotificationName:DidCreateXMPPAccountNotification object:self];
	
	// Start the XMPPClient
	[[[NSApp delegate] helperProxy] xmpp_start];
	
	// Switch to view 3
	[mojoIdField setStringValue:jid];
	[contentBox setContentView:view3];
	[[self window] makeFirstResponder:doneButton];
}

- (void)xmppStream:(XMPPStream *)xs didNotRegister:(NSXMLElement *)error
{
	DDLogVerbose(@"WelcomeController: xmppStream:didNotRegister:");
	
	// Some servers limit the number of registrations from a single IP address per time-period.
	// This may crop up if several users behind the same IP try to create an account around the same time.
	// 
	// <iq from='jabbernet.eu' type='error'>
	//   <query xmlns='jabber:iq:register'>
	//     <username>deusty</username>
	//     <password>bigcheese</password>
	//   </query>
	//   <error code='500' type='wait'>
	//     <resource-constraint xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>
	//   </error>
	// </iq>
	
	NSString *errorCode = [[[error elementForName:@"error"] attributeForName:@"code"] stringValue];
	
	if([errorCode isEqualToString:@"500"])
	{
		[limitErrorMessage setHidden:NO];
		
		NSString *errMsg2 = NSLocalizedString(@"Try a different server", @"Error message in welcome panel");
		
		[connectErrorMessage setStringValue:errMsg2];
		[connectErrorMessage setHidden:NO];
	}
	else
	{
		NSString *errMsg = NSLocalizedString(@"Not Available!", @"Error message in welcome panel");
		
		[usernameErrorMessage setStringValue:errMsg];
		[usernameErrorMessage setHidden:NO];
	}
	
	[progressIndicator stopAnimation:self];
	[registerButton setEnabled:YES];
	
	manualDisconnect = YES;
	[xmppStream disconnect];
}

/**
 * This method is called after the stream is closed.
**/
- (void)xmppStreamDidClose:(XMPPStream *)xs
{
	DDLogVerbose(@"WelcomeController: xmppStreamDidClose:");
	
	isConnecting = NO;
	
	if(!manualDisconnect)
	{
		NSString *errMsg = NSLocalizedString(@"Unable to connect to server!", @"Error message in welcome panel");
		
		[connectErrorMessage setStringValue:errMsg];
		[connectErrorMessage setHidden:NO];
		
		[serverErrorMessage setHidden:YES];
		[usernameErrorMessage setHidden:YES];
		[passwordErrorMessage setHidden:YES];
		
		[progressIndicator stopAnimation:self];
		[registerButton setEnabled:YES];
	}
}

@end
