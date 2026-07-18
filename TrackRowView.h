// TrackRowView.h — Custom view for a single playlist row

#import <Cocoa/Cocoa.h>
#import "Track.h"

@interface TrackRowView : NSView

@property (strong) Track *track;
@property (nonatomic, assign, getter=isSelected) BOOL selected;
@property (nonatomic, assign, getter=isNowPlaying) BOOL nowPlaying;
@property (nonatomic, assign, getter=isHovered) BOOL hovered;

// Target-action for click / play
@property (assign) id target;
@property (assign) SEL action;

// Click count from last mouse event (1 = single, 2 = double)
@property (assign) NSInteger clickCount;

// Modifier flags from last mouse event
@property (assign) NSUInteger modifierFlags;

@end
