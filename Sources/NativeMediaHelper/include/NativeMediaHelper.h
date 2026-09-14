#import <Foundation/Foundation.h>

/// Loaded only by the system scripting host, not linked into the bar.
@interface ConstellationNativeMediaHelper : NSObject
+ (NSDictionary *)nowPlayingInfo;
@end
