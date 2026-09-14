#import "NativeMediaHelper.h"
#import <dlfcn.h>
#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>

@implementation ConstellationNativeMediaHelper
+ (NSDictionary *)nowPlayingInfo {
    // Keep the framework loaded for the lifetime of any outstanding callback.
    static void *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    });
    if (!framework) return nil;
    typedef void (*GetInfo)(dispatch_queue_t, void (^)(NSDictionary *));
    GetInfo getInfo = (GetInfo)dlsym(framework, "MRMediaRemoteGetNowPlayingInfo");
    if (!getInfo) return nil;
    dispatch_semaphore_t ready = dispatch_semaphore_create(0);
    __block NSDictionary *snapshot;
    getInfo(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(NSDictionary *info) {
        snapshot = [info copy] ?: @{};
        dispatch_semaphore_signal(ready);
    });
    // The caller also bounds the helper process. A late callback owns its captured
    // state until completion, even when we return on timeout.
    if (dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 800 * NSEC_PER_MSEC))) return nil;
    return snapshot;
}
@end

// Entry point for the system Perl host. Exits rather than returning through Perl's
// XSUB ABI; all work stays in this short-lived subprocess.
void constellation_media_snapshot(void) {
    @autoreleasepool {
        NSDictionary *info = [ConstellationNativeMediaHelper nowPlayingInfo];
        if (!info) exit(1);
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        NSDictionary *keys = @{@"Title": @"title", @"Artist": @"artist", @"Album": @"album",
                               @"PlaybackRate": @"rate", @"Duration": @"duration", @"ElapsedTime": @"position"};
        for (NSString *key in keys) {
            id value = info[[@"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:key]];
            if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) result[keys[key]] = value;
        }
        NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        if ([timestamp isKindOfClass:NSDate.class] && [result[@"rate"] doubleValue] > 0) {
            result[@"position"] = @([result[@"position"] doubleValue] + MAX(0, -timestamp.timeIntervalSinceNow) * [result[@"rate"] doubleValue]);
        }
        id identifier = info[@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] ?: info[@"kMRMediaRemoteNowPlayingInfoUniqueIdentifier"];
        if (identifier) result[@"identifier"] = [identifier description];
        NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        // Keep base64 output under the runner's 1 MiB bound without discarding
        // high-resolution covers supplied by some players.
        if ([art isKindOfClass:NSData.class] && art.length >= 700000) {
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)art, NULL);
            if (source) {
                CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
                    (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                    (id)kCGImageSourceThumbnailMaxPixelSize: @600,
                    (id)kCGImageSourceCreateThumbnailWithTransform: @YES
                });
                if (thumbnail) {
                    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:thumbnail];
                    art = [bitmap representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @0.85}];
                    CGImageRelease(thumbnail);
                }
                CFRelease(source);
            }
        }
        if ([art isKindOfClass:NSData.class] && art.length < 700000) result[@"artwork"] = [art base64EncodedStringWithOptions:0];
        void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        typedef void (*GetPID)(dispatch_queue_t, void (^)(int));
        GetPID getPID = framework ? (GetPID)dlsym(framework, "MRMediaRemoteGetNowPlayingApplicationPID") : NULL;
        if (getPID) {
            dispatch_semaphore_t ready = dispatch_semaphore_create(0);
            __block int playerPID = 0;
            getPID(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(int pid) { playerPID = pid; dispatch_semaphore_signal(ready); });
            if (!dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC))) {
                result[@"source"] = [NSRunningApplication runningApplicationWithProcessIdentifier:playerPID].localizedName ?: @"macOS";
            }
        }
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        if (!json) exit(1);
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        exit(0);
    }
}
