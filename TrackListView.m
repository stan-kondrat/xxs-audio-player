// TrackListView.m — Scrollable track list container

#import "TrackListView.h"

static const CGFloat ROW_HEIGHT = 24;

@interface TrackListView ()
@property (strong) NSMutableArray<TrackRowView *> *rowViews;
@property (assign) NSInteger hoveredRow;
@property (assign) NSInteger anchorIndex;
@end

@implementation TrackListView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _tracks = [[NSMutableArray alloc] init];
        _rowViews = [[NSMutableArray alloc] init];
        _currentIndex = -1;
        _selectedIndexes = [[NSIndexSet alloc] init];
        _hoveredRow = -1;
        _anchorIndex = -1;
    }
    return self;
}


// ── Flipped coordinate system (top-to-bottom layout) ──
- (BOOL)isFlipped {
    return YES;
}


// ── Refresh tracking areas on scroll ──
- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSViewBoundsDidChangeNotification
                                                  object:nil];
    NSClipView *clip = [self.enclosingScrollView contentView];
    if (clip) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(scrollDidChange:)
                                                     name:NSViewBoundsDidChangeNotification
                                                   object:clip];
    }
}

- (void)scrollDidChange:(NSNotification *)note {
    NSWindow *win = self.window;
    if (!win) return;
    NSPoint mouseInWin = [win mouseLocationOutsideOfEventStream];
    NSRect visibleRect = [self visibleRect];
    for (TrackRowView *rv in self.rowViews) {
        [rv updateTrackingAreas];
        // Clear hover if row is scrolled out of view or mouse isn't over it
        if (!NSIntersectsRect(rv.frame, visibleRect)) {
            rv.hovered = NO;
        } else {
            NSPoint mouseInRow = [rv convertPoint:mouseInWin fromView:nil];
            if (!NSPointInRect(mouseInRow, rv.bounds)) {
                rv.hovered = NO;
            }
        }
    }
}


// ── Reload: rebuild all TrackRowView subviews ──
- (void)reloadData {
    // Remove existing row views
    for (TrackRowView *rv in self.rowViews) {
        [rv removeFromSuperview];
    }
    [self.rowViews removeAllObjects];

    // Build new rows
    CGFloat y = 0;
    for (NSUInteger i = 0; i < [self.tracks count]; i++) {
        Track *track = self.tracks[i];
        TrackRowView *row = [[TrackRowView alloc] initWithFrame:NSMakeRect(0, y, NSWidth(self.bounds), ROW_HEIGHT)];
        row.track = track;
        row.nowPlaying = ((NSInteger)i == self.currentIndex);
        row.selected = [self.selectedIndexes containsIndex:i];
        row.target = self;
        row.action = @selector(rowClicked:);
        [self addSubview:row];
        [self.rowViews addObject:row];
        [row release];
        y += ROW_HEIGHT;
    }

    // Update intrinsic content size
    CGFloat totalHeight = MAX(y, NSHeight(self.enclosingScrollView.bounds));
    [self setFrameSize:NSMakeSize(NSWidth(self.bounds), totalHeight)];

    [self setNeedsDisplay:YES];
}

// ── Layout — reposition rows on resize ──
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutRows];
}

- (void)layoutRows {
    CGFloat y = 0;
    CGFloat w = NSWidth(self.bounds);
    for (TrackRowView *rv in self.rowViews) {
        rv.frame = NSMakeRect(0, y, w, ROW_HEIGHT);
        y += ROW_HEIGHT;
    }
    // Keep content tall enough
    CGFloat totalHeight = MAX(y, NSHeight(self.enclosingScrollView.bounds));
    [self setFrameSize:NSMakeSize(w, totalHeight)];
}

// ── Row click handler (multi-select: plain, Shift, Cmd) ──
- (void)rowClicked:(TrackRowView *)sender {
    NSInteger idx = [self.rowViews indexOfObject:sender];
    if (idx == NSNotFound) return;

    NSUInteger mod = sender.modifierFlags;
    BOOL shift = (mod & NSEventModifierFlagShift) != 0;
    BOOL cmd   = (mod & NSEventModifierFlagCommand) != 0;

    if (shift && self.anchorIndex >= 0) {
        // Shift-click: extend selection from anchor to clicked row
        NSRange range = NSMakeRange(MIN(self.anchorIndex, idx),
                                    labs(self.anchorIndex - idx) + 1);
        self.selectedIndexes = [NSIndexSet indexSetWithIndexesInRange:range];
    } else if (cmd) {
        // Cmd-click: toggle clicked row
        NSMutableIndexSet *mis = [[self.selectedIndexes mutableCopy] autorelease];
        if ([mis containsIndex:idx]) {
            [mis removeIndex:idx];
        } else {
            [mis addIndex:idx];
        }
        self.selectedIndexes = mis;
        self.anchorIndex = idx;
    } else {
        // Plain click: select single
        self.selectedIndexes = [NSIndexSet indexSetWithIndex:idx];
        self.anchorIndex = idx;
    }

    [self updateRowSelectionStates];

    // Forward to target only on double-click (play)
    if (sender.clickCount >= 2 && self.target && self.action) {
        [self.target performSelector:self.action withObject:@(idx)];
    }
}

- (void)updateRowSelectionStates {
    for (NSUInteger i = 0; i < [self.rowViews count]; i++) {
        self.rowViews[i].selected = [self.selectedIndexes containsIndex:i];
    }
}

// ── Now playing highlight ──
- (void)setCurrentIndex:(NSInteger)currentIndex {
    if (_currentIndex == currentIndex) return;
    // Clear old
    if (_currentIndex >= 0 && _currentIndex < (NSInteger)[self.rowViews count]) {
        self.rowViews[_currentIndex].nowPlaying = NO;
    }
    _currentIndex = currentIndex;
    // Set new
    if (currentIndex >= 0 && currentIndex < (NSInteger)[self.rowViews count]) {
        self.rowViews[currentIndex].nowPlaying = YES;
    }
}

// ── Scroll to row ──
- (void)scrollToRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)[self.rowViews count]) return;
    TrackRowView *rv = self.rowViews[row];
    [self.enclosingScrollView.contentView scrollToPoint:NSMakePoint(0, NSMinY(rv.frame))];
    [self.enclosingScrollView reflectScrolledClipView:self.enclosingScrollView.contentView];
}

// ── Remove selected ──
- (BOOL)removeSelectedTracks {
    if ([self.selectedIndexes count] == 0) return NO;

    // Remove in reverse order
    NSMutableArray *toRemove = [NSMutableArray array];
    [self.selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [toRemove addObject:@(idx)];
    }];
    [toRemove sortUsingSelector:@selector(compare:)];
    for (NSNumber *n in [toRemove reverseObjectEnumerator]) {
        [self.tracks removeObjectAtIndex:[n unsignedIntegerValue]];
    }

    // Reset selection
    self.selectedIndexes = [NSIndexSet indexSet];
    [self reloadData];
    return YES;
}

// ── Select all ──
- (void)selectAll {
    if ([self.tracks count] == 0) return;
    self.selectedIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self.tracks count])];
    [self updateRowSelectionStates];
}

// ── Placeholder click → open files ──
- (void)mouseDown:(NSEvent *)event {
    if ([self.tracks count] == 0 && self.target && self.placeholderAction) {
        [self.target performSelector:self.placeholderAction withObject:self];
        return;
    }
    [super mouseDown:event];
}


// ── Keyboard ──
- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    unsigned short keyCode = [event keyCode];
    NSEventModifierFlags mod = [event modifierFlags];

    // Cmd+A — Select All
    if (keyCode == 0 && (mod & NSEventModifierFlagCommand)) {
        [self selectAll];
        return;
    }

    // Delete (51) — Remove selected
    if (keyCode == 51) {
        if ([self removeSelectedTracks]) {
            // Notify controller to sync state
            if (self.target && [self.target respondsToSelector:@selector(trackListDidChange)]) {
                [self.target performSelector:@selector(trackListDidChange)];
            }
        }
        return;
    }

    [super keyDown:event];
}

// ── Placeholder when empty ──
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if ([self.tracks count] > 0) return;

    NSString *msg = @"Drop audio files here";
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };
    NSSize size = [msg sizeWithAttributes:attrs];
    CGFloat x = (NSWidth(self.bounds) - size.width) / 2.0;
    CGFloat y = (NSHeight(self.bounds) - size.height) / 2.0;
    [msg drawAtPoint:NSMakePoint(x, y) withAttributes:attrs];
}

// ── Drag & Drop support ──
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = [sender draggingPasteboard];
    NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[[NSURL class]] options:nil];
    if ([urls count] == 0) return NO;

    // Forward to delegate / target
    if (self.target && [self.target respondsToSelector:@selector(acceptDroppedURLs:)]) {
        [self.target performSelector:@selector(acceptDroppedURLs:) withObject:urls];
        return YES;
    }
    return NO;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_tracks release];
    [_rowViews release];
    [_selectedIndexes release];
    [super dealloc];
}

@end
