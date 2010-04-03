#import <Foundation/Foundation.h>

@class ITunesData;
@class ITunesForeignData;
@class ITunesForeignInfo;

#define DOWNLOAD_STATUS_NONE         0
#define DOWNLOAD_STATUS_QUEUED       1
#define DOWNLOAD_STATUS_DOWNLOADING  2
#define DOWNLOAD_STATUS_DOWNLOADED   3
#define DOWNLOAD_STATUS_FAILED       4


@interface ITunesTrack : NSObject
{
	NSMutableDictionary *trackRef;
}

+ (NSDictionary *)createTracksForData:(ITunesData *)data;

- (id)initWithTrackID:(int)trackID forData:(ITunesData *)data;

- (NSDictionary *)trackRef;

- (NSString *)persistentID;
- (NSString *)location;
- (NSString *)name;
- (NSString *)artist;
- (NSString *)album;
- (NSString *)genre;
- (NSString *)composer;
- (NSString *)kind;
- (NSString *)type;
- (NSString *)comments;

- (NSDate *)dateAdded;

- (int)trackID;
- (int)fileSize;
- (int)totalTime;
- (int)playCount;
- (int)rating;
- (int)trackNumber;
- (int)trackCount;
- (int)discNumber;
- (int)discCount;
- (int)bitRate;
- (int)year;
- (int)bpm;

- (NSString *)pathExtension;

- (BOOL)isProtected;
- (BOOL)isVideo;

- (BOOL)hasLocalConnection;
- (void)setHasLocalConnection:(BOOL)flag;

- (int)localTrackID;
- (void)setLocalTrackID:(int)localTrackID;

- (int)downloadStatus;
- (void)setDownloadStatus:(int)downloadStatus;

@end
