// Track.m — Audio track model implementation

#import "Track.h"

@implementation Track

- (NSString *)description {
    return self.title;
}

- (void)dealloc {
    [_url release];
    [_title release];
    [_artist release];
    [super dealloc];
}

@end
