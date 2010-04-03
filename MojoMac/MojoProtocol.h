@protocol MojoProtocol

/**
 * Note that the following method is NOT oneway.
 * Proxy notifications must act just as regular notifications do.
**/
- (void)postNotificationWithName:(in bycopy NSString *)name;

@end
