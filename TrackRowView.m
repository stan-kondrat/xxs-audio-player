// TrackRowView.m — Custom playlist row rendering

#import "TrackRowView.h"

// ── Layout constants (8px grid) ──
static const CGFloat TEXT_LEFT_MARGIN  = 20;
static const CGFloat TEXT_TOP_OFFSET   = 4;
static const CGFloat ROW_CORNER_RADIUS = 6;
static const CGFloat ROW_INSET_H       = 4;
static const CGFloat ROW_INSET_V       = 1;
static const CGFloat SEPARATOR_ALPHA   = 0.08;

@interface TrackRowView ()
@property (strong) NSTrackingArea *trackingArea;
@end

@implementation TrackRowView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _selected = NO;
        _nowPlaying = NO;
        _hovered = NO;
        self.wantsLayer = YES;
    }
    return self;
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    [self setNeedsDisplay:YES];
}

- (void)setNowPlaying:(BOOL)nowPlaying {
    _nowPlaying = nowPlaying;
    [self setNeedsDisplay:YES];
}

- (void)setHovered:(BOOL)hovered {
    _hovered = hovered;
    [self setNeedsDisplay:YES];
}

// ── Drawing ──
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;

    // Background
    if (self.isSelected) {
        // Selection highlight
        NSRect selRect = NSInsetRect(bounds, ROW_INSET_H, ROW_INSET_V);
        selRect.size.height -= 1;
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:selRect
                                                             xRadius:ROW_CORNER_RADIUS
                                                             yRadius:ROW_CORNER_RADIUS];
        [[NSColor controlAccentColor] setFill];
        [path fill];
    } else if (self.isHovered) {
        // Hover highlight (subtle glass)
        NSRect hoverRect = NSInsetRect(bounds, ROW_INSET_H, ROW_INSET_V);
        hoverRect.size.height -= 1;
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:hoverRect
                                                             xRadius:ROW_CORNER_RADIUS
                                                             yRadius:ROW_CORNER_RADIUS];
        [[NSColor colorWithWhite:0.5 alpha:0.10] setFill];
        [path fill];
    }

    if (!self.track) return;

    // ── Sizing ──
    CGFloat textX = TEXT_LEFT_MARGIN;
    CGFloat rightMargin = 8;
    CGFloat rowW = NSWidth(bounds);

    // Meta text (artist + time) — max 50% of row width
    NSString *artist = self.track.artist ?: @"";
    NSString *timeStr = [self formatTime:self.track.duration];
    NSString *meta = [NSString stringWithFormat:@"%@  [%@]", artist, timeStr];

    NSDictionary *metaAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: self.isSelected
            ? [NSColor selectedControlTextColor]
            : [NSColor secondaryLabelColor]
    };

    CGFloat maxMetaW = floor(rowW * 0.5);
    NSSize metaSize = [meta sizeWithAttributes:metaAttrs];
    CGFloat metaW = MIN(metaSize.width, maxMetaW);
    CGFloat metaX = rowW - metaW - rightMargin;

    // Title — fills remaining space between textX and meta
    NSColor *textColor;
    if (self.isSelected) {
        textColor = [NSColor selectedControlTextColor];
    } else if (self.isNowPlaying) {
        textColor = [NSColor controlAccentColor];
    } else {
        textColor = [NSColor labelColor];
    }

    NSDictionary *titleAttrs = @{
        NSFontAttributeName: self.isNowPlaying ? [NSFont boldSystemFontOfSize:13]
                                               : [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: textColor
    };

    CGFloat titleMaxW = MAX(20, metaX - textX - 4);
    NSString *titleStr = self.track.title ?: @"";

    // Draw title (truncated)
    NSRect titleRect = NSMakeRect(textX, TEXT_TOP_OFFSET, titleMaxW, 18);
    NSMutableParagraphStyle *titleP = [[[NSMutableParagraphStyle alloc] init] autorelease];
    titleP.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableDictionary *titleDrawAttrs = [[titleAttrs mutableCopy] autorelease];
    [titleDrawAttrs setObject:titleP forKey:NSParagraphStyleAttributeName];
    [titleStr drawInRect:titleRect withAttributes:titleDrawAttrs];

    // Draw meta (truncated)
    NSRect metaRect = NSMakeRect(metaX, TEXT_TOP_OFFSET + 2, metaW, 16);
    NSMutableParagraphStyle *metaP = [[[NSMutableParagraphStyle alloc] init] autorelease];
    metaP.lineBreakMode = NSLineBreakByTruncatingTail;
    metaP.alignment = NSTextAlignmentRight;
    NSMutableDictionary *metaDrawAttrs = [[metaAttrs mutableCopy] autorelease];
    [metaDrawAttrs setObject:metaP forKey:NSParagraphStyleAttributeName];
    [meta drawInRect:metaRect withAttributes:metaDrawAttrs];

    // ── Subtle bottom separator ──
    [[NSColor colorWithWhite:0.5 alpha:SEPARATOR_ALPHA] setFill];
    NSRectFill(NSMakeRect(0, 0, NSWidth(bounds), 1));
}

// ── Mouse events ──
- (void)mouseDown:(NSEvent *)event {
    self.clickCount = event.clickCount;
    self.modifierFlags = event.modifierFlags;
    // Forward click to the enclosing track list via action message
    [self sendActionToTarget];
}

- (void)mouseEntered:(NSEvent *)event {
    [super mouseEntered:event];
    self.hovered = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    [super mouseExited:event];
    self.hovered = NO;
    [self setNeedsDisplay:YES];
}

// ── Keyboard events ──
- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 49) {         // Space — play/pause
        [self sendActionToTarget];
    } else if (event.keyCode == 51) {  // Delete — remove track
        if ([self.target respondsToSelector:self.action]) {
            // Wrap in a custom action if needed, or use NSApp
        }
    } else {
        [super keyDown:event];
    }
}

// ── Target-action pattern (like NSControl) ──
- (void)sendActionToTarget {
    if (self.target && self.action) {
        [self.target performSelector:self.action withObject:self];
    }
}

// ── Tracking areas for hover ──
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.trackingArea) {
        [self removeTrackingArea:self.trackingArea];
    }
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                      options:NSTrackingMouseEnteredAndExited |
                                                              NSTrackingActiveInActiveApp
                                                        owner:self
                                                     userInfo:nil];
    [self addTrackingArea:self.trackingArea];
}

// ── Helpers ──
- (NSString *)formatTime:(NSTimeInterval)t {
    if (isnan(t) || isinf(t) || t < 0) return @"0:00";
    int total = (int)round(t);
    return [NSString stringWithFormat:@"%d:%02d", total / 60, total % 60];
}

- (void)dealloc {
    [_track release];
    [_trackingArea release];
    [super dealloc];
}

@end
