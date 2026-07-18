// TrackListView.h — Scrollable container for TrackRowView items
// Used as the documentView of an NSScrollView.

#import <Cocoa/Cocoa.h>
#import "Track.h"
#import "TrackRowView.h"

@interface TrackListView : NSView

@property (strong) NSMutableArray<Track *> *tracks;
@property (nonatomic, assign) NSInteger currentIndex;
@property (strong) NSIndexSet *selectedIndexes;

// Target-action for row click / play
@property (assign) id target;
@property (assign) SEL action;

// Target-action for placeholder click (open files)
@property (assign) SEL placeholderAction;

// Reload all rows from the tracks array
- (void)reloadData;

// Scroll to make a specific row visible
- (void)scrollToRow:(NSInteger)row;

// Remove selected tracks (returns YES if any were removed)
- (BOOL)removeSelectedTracks;

// Select all tracks
- (void)selectAll;

@end
