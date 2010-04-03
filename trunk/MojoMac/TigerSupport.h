// 
// Define various things for pre Leopard systems
// 
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
  
  #import <CoreFoundation/CFBase.h>
  
  #ifndef NSINTEGER_DEFINED
    #if __LP64__ || NS_BUILD_32_LIKE_64
      typedef long NSInteger;
      typedef unsigned long NSUInteger;
    #else
      typedef int NSInteger;
      typedef unsigned int NSUInteger;
    #endif
    #define NSIntegerMax    LONG_MAX
    #define NSIntegerMin    LONG_MIN
    #define NSUIntegerMax   ULONG_MAX
    #define NSINTEGER_DEFINED 1
  #endif
  
  #if !defined(NS_INLINE)
    #if defined(__GNUC__)
      #define NS_INLINE static __inline__ __attribute__((always_inline))
    #elif defined(__MWERKS__) || defined(__cplusplus)
      #define NS_INLINE static inline
    #elif defined(_MSC_VER)
      #define NS_INLINE static __inline
    #elif defined(__WIN32__)
      #define NS_INLINE static __inline__
    #endif
  #endif
  
  #ifndef NSRunLoopCommonModes
    #define NSRunLoopCommonModes ((NSString *)kCFRunLoopCommonModes)
  #endif
  
  NS_INLINE id NSMakeCollectable(CFTypeRef cf) {
	return cf ? (id)cf : nil;
  }

#endif
