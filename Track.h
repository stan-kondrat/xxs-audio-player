// Track.h — Audio track model
// Zero dependencies, lightweight data object

#import <Foundation/Foundation.h>

@interface Track : NSObject

@property (strong) NSURL *url;
@property (strong) NSString *title;
@property (strong) NSString *artist;
@property (assign) NSTimeInterval duration;

@end
