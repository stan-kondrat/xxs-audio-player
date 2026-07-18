#import "GlassButton.h"

@implementation GlassButton
{
    BOOL _pressed;
    NSTrackingArea *_trackingArea;
}


- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];

    if (self) {

        self.enabled = YES;
        self.wantsLayer = YES;
        _active = NO;

        self.layer.cornerRadius = 10;
        self.layer.masksToBounds = YES;
    }

    return self;
}


#pragma mark -
#pragma mark State setters


- (void)setActive:(BOOL)active
{
    _active = active;
    [self setNeedsDisplay:YES];
}


- (void)setHover:(BOOL)hover
{
    _hover = hover;
    [self setNeedsDisplay:YES];
}


- (void)setEmoji:(NSString *)emoji
{
    [_emoji release];
    _emoji = [emoji copy];
    [self setNeedsDisplay:YES];
}


- (void)setEnabled:(BOOL)enabled
{
    [super setEnabled:enabled];
    [self setNeedsDisplay:YES];
}



#pragma mark -
#pragma mark Drawing


- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = self.bounds;


    NSColor *background;


    if (!self.enabled) {

        background =
        [NSColor colorWithWhite:0.5 alpha:0.08];

    }
    else if (_pressed) {

        background =
        [NSColor systemBlueColor];

    }
    else if (self.active) {

        background =
        [[NSColor systemBlueColor]
         colorWithAlphaComponent:0.45];

    }
    else if (self.hover) {

        background =
        [NSColor colorWithWhite:1 alpha:0.12];

    }
    else {

        background =
        [NSColor colorWithWhite:1 alpha:0.06];

    }


    NSBezierPath *path =
    [NSBezierPath bezierPathWithRoundedRect:bounds
                                   xRadius:10
                                   yRadius:10];


    [background setFill];
    [path fill];



    NSString *text = self.emoji ?: @"";


    NSColor *textColor =
    self.enabled ?
    NSColor.labelColor :
    [NSColor.secondaryLabelColor
     colorWithAlphaComponent:.4];


    NSDictionary *attributes =
    @{
      NSFontAttributeName:
          [NSFont systemFontOfSize:14 weight:NSFontWeightMedium],

      NSForegroundColorAttributeName:
          textColor
    };


    NSSize size =
    [text sizeWithAttributes:attributes];


    NSPoint p =
    NSMakePoint(
        NSMidX(bounds)-size.width/2,
        NSMidY(bounds)-size.height/2
    );


    [text drawAtPoint:p
       withAttributes:attributes];
}



#pragma mark -
#pragma mark Hover


- (void)updateTrackingAreas
{
    [super updateTrackingAreas];


    if (_trackingArea) {

        [self removeTrackingArea:_trackingArea];
        [_trackingArea release];
    }


    _trackingArea =
    [[NSTrackingArea alloc]
     initWithRect:self.bounds
     options:
        NSTrackingMouseEnteredAndExited |
        NSTrackingActiveAlways
     owner:self
     userInfo:nil];


    [self addTrackingArea:_trackingArea];
}



- (void)mouseEntered:(NSEvent *)event
{
    self.hover = YES;

    if (self.enabled)
        [[NSCursor pointingHandCursor] set];
}



- (void)mouseExited:(NSEvent *)event
{
    self.hover = NO;

    [[NSCursor arrowCursor] set];
}



#pragma mark -
#pragma mark Mouse


- (void)mouseDown:(NSEvent *)event
{
    if (!self.enabled)
        return;

    _pressed = YES;
    [self setNeedsDisplay:YES];

    NSEvent *up =
    [[self window]
     nextEventMatchingMask:NSEventMaskLeftMouseUp];

    _pressed = NO;
    [self setNeedsDisplay:YES];

    NSPoint point =
    [self convertPoint:up.locationInWindow fromView:nil];

    if (NSPointInRect(point, self.bounds)) {
        [self sendAction:self.action to:self.target];
    }
}



#pragma mark -
#pragma mark Keyboard


- (BOOL)acceptsFirstResponder
{
    return YES;
}


- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    return YES;
}


- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36) {
        [self sendAction:self.action to:self.target];
    }
}



#pragma mark -
#pragma mark Cleanup


- (void)dealloc
{
    if (_trackingArea)
        [_trackingArea release];

    [_emoji release];

    [super dealloc];
}

@end
