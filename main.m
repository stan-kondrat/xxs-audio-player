// XXS-Audio-Player — Native macOS audio player
// Zero dependencies, privacy-first, offline-only

#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "ID3Metadata.h"
#import "TrackListView.h"
#import "GlassButton.h"

// ──────────────────────────────────────────────
// Style Constants — all visual/dimensional values on 8px grid
// ──────────────────────────────────────────────

// --- Window ---
static const CGFloat WINDOW_INITIAL_WIDTH  = 520; // 65×8
static const CGFloat WINDOW_INITIAL_HEIGHT = 440; // 55×8
static const CGFloat WINDOW_MIN_WIDTH      = 416; // 52×8
static const CGFloat WINDOW_MIN_HEIGHT     = 384; // 48×8

// --- Layout (all 8px multiples) ---
static const CGFloat LAYOUT_PADDING     = 16; // 2×8
static const CGFloat LAYOUT_PADDING_TOP = 32; // 4×8
static const CGFloat LAYOUT_GAP         = 8;  // 1×8
static const CGFloat CTRL_PANEL_HEIGHT  = 152; // 19×8
static const CGFloat CTRL_TOP_MARGIN    = 16; // 2×8
static const CGFloat TITLE_LABEL_H      = 16; // 2×8
static const CGFloat ARTIST_LABEL_H     = 16; // 2×8
static const CGFloat ARTIST_LABEL_Y     = 32; // 4×8
static const CGFloat SEEK_SECTION_Y     = 48; // 6×8
static const CGFloat TIME_LABEL_W       = 48; // 6×8
static const CGFloat SEEK_SLIDER_H      = 24; // 3×8
static const CGFloat TRANSPORT_SECTION_Y = 32; // 4×8

// --- Transport buttons (all 8px multiples) ---
static const CGFloat BTN_GAP         = 8;  // 1×8

// --- Volume (all 8px multiples) ---

// --- Volume (all 8px multiples) ---
static const CGFloat VOL_SECTION_W      = 128; // 16×8
static const CGFloat VOL_ICON_W         = 24;  // 3×8
static const CGFloat VOL_SLIDER_X_OFF   = 32;  // 4×8
static const CGFloat VOL_SLIDER_W_INSET = 32;  // 4×8
static const CGFloat VOL_SLIDER_H       = 24;  // 3×8

// --- Slider ---
static const CGFloat SLIDER_KNOB_SIZE  = 16;  // 2×8
static const CGFloat SLIDER_BAR_HEIGHT = 6.0; // visual thickness, kept

// --- Scroll view (all 8px multiples) ---
static const CGFloat SCROLL_INSET_BOTTOM = 16; // 2×8

// --- Panels ---
static const CGFloat PANEL_CORNER_RADIUS = 12; // kept, visual radius
static const CGFloat PANEL_BORDER_WIDTH  = 0.5;

// --- Separator ---
static const CGFloat SEPARATOR_H = 1;

// --- Progress timer ---
static const NSTimeInterval PROGRESS_TIMER_INTERVAL = 0.1;

// --- App identity ---
static NSString *const APP_NAME    = @"XXS-Audio-Player";
static NSString *const APP_VERSION = @"1.0";

// --- Defaults (all 8px multiples) ---
static const float  DEFAULT_VOLUME        = 0.5f;

// --- Key / behaviour ---
static const NSTimeInterval SEEK_STEP          = 5.0;
static const float          VOLUME_STEP        = 0.05f;
static const NSTimeInterval PREV_TRACK_THRESH  = 3.0;

// --- Glass alpha values (inline NSColor helpers) ---
#define ALPHA_GLASS_INACTIVE_BD   0.12
#define ALPHA_GLASS_KNOB_NORMAL  0.9
#define ALPHA_GLASS_TRACK_BG     0.15

// Track model is now in Track.h / Track.m

// ──────────────────────────────────────────────
// Formatting helpers
// ──────────────────────────────────────────────
static NSString *FormatTime(NSTimeInterval t) {
    if (isnan(t) || isinf(t) || t < 0) return @"0:00";
    int total = (int)round(t);
    return [NSString stringWithFormat:@"%d:%02d", total / 60, total % 60];
}

// ──────────────────────────────────────────────
// Liquid Glass UI Components
// ──────────────────────────────────────────────

// ── GlassSliderCell: thin modern slider appearance ──
@interface GlassSliderCell : NSSliderCell
@end

@implementation GlassSliderCell

// Return the bar track rect — full width, thin, vertically centered
- (NSRect)barRectFlipped:(BOOL)flipped {
    NSRect bounds = [self.controlView bounds];
    CGFloat inset = 4.0;
    CGFloat barH = SLIDER_BAR_HEIGHT;
    return NSMakeRect(bounds.origin.x + inset,
                      NSMidY(bounds) - barH / 2.0,
                      bounds.size.width - inset * 2,
                      barH);
}

// Return the knob rect — square, positioned on the bar at the current value
- (NSRect)knobRectFlipped:(BOOL)flipped {
    NSRect barRect = [self barRectFlipped:flipped];
    double ratio = (self.maxValue > self.minValue) ?
        (self.doubleValue - self.minValue) / (self.maxValue - self.minValue) : 0;
    CGFloat knobS = SLIDER_KNOB_SIZE;
    CGFloat knobX = NSMinX(barRect) + ratio * NSWidth(barRect) - knobS / 2.0;
    CGFloat knobY = NSMidY(barRect) - knobS / 2.0;
    return NSMakeRect(knobX, knobY, knobS, knobS);
}

- (void)drawKnob:(NSRect)knobRect {
    // Draw filled circle inset slightly inside the rect
    NSRect r = NSInsetRect(knobRect, 2, 2);

    NSColor *knobColor = [NSColor colorWithWhite:0.85 alpha:ALPHA_GLASS_KNOB_NORMAL];
    if (self.highlighted || self.isHighlighted) {
        knobColor = [NSColor whiteColor];
    }

    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:r];
    [knobColor setFill];
    [path fill];

    // Subtle outer ring for depth
    [[knobColor colorWithAlphaComponent:0.3] setStroke];
    [path setLineWidth:1.0];
    [path stroke];
}

- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped {
    NSRect barRect = [self barRectFlipped:flipped];
    CGFloat r = SLIDER_BAR_HEIGHT / 2.0;

    // Background track (full bar)
    [[NSColor colorWithWhite:0.5 alpha:ALPHA_GLASS_TRACK_BG] setFill];
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:barRect xRadius:r yRadius:r];
    [track fill];

    // Filled portion
    double ratio = (self.maxValue > self.minValue) ?
        (self.doubleValue - self.minValue) / (self.maxValue - self.minValue) : 0;
    NSRect filledRect = barRect;
    filledRect.size.width = barRect.size.width * MAX(0, MIN(1, ratio));

    [[NSColor controlAccentColor] setFill];
    NSBezierPath *filled = [NSBezierPath bezierPathWithRoundedRect:filledRect xRadius:r yRadius:r];
    [filled fill];
}

- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView {
    return YES;
}

- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint inView:(NSView *)controlView {
    [super continueTracking:lastPoint at:currentPoint inView:controlView];
    [(NSControl *)controlView sendAction:[(NSControl *)controlView action] to:[(NSControl *)controlView target]];
    return YES;
}

- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(NSView *)controlView mouseIsUp:(BOOL)flag {
    [super stopTracking:lastPoint at:stopPoint inView:controlView mouseIsUp:flag];
    [(NSControl *)controlView sendAction:[(NSControl *)controlView action] to:[(NSControl *)controlView target]];
}

- (BOOL)prefersTrackingUntilMouseUp {
    return YES;
}

@end

// ── GlassSlider: convenience wrapper ──
@interface GlassSlider : NSSlider
@end

@implementation GlassSlider
+ (Class)cellClass { return [GlassSliderCell class]; }

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = NO;
    }
    return self;
}
@end

// ── GlassSeparator: thin blur-aware separator line ──
@interface GlassSeparator : NSView
@end

@implementation GlassSeparator
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithWhite:0.5 alpha:ALPHA_GLASS_INACTIVE_BD] setFill];
    NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, SEPARATOR_H));
}
@end

// ── GlassBackgroundView: explicit layout callback + drag support ──
@interface GlassBackgroundView : NSVisualEffectView
@property (copy) void (^onLayout)(void);
@end

@implementation GlassBackgroundView
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    if (self.onLayout) self.onLayout();
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return NSDragOperationCopy;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    id d = [NSApp delegate];
    if ([d respondsToSelector:@selector(acceptDroppedURLs:)]) {
        NSPasteboard *pb = [sender draggingPasteboard];
        NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[[NSURL class]] options:nil];
        if (urls) { [d performSelector:@selector(acceptDroppedURLs:) withObject:urls]; return YES; }
    }
    return NO;
}
@end

static BOOL IsAudioURL(NSURL *url) {
    static NSSet *exts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exts = [[NSSet alloc] initWithObjects:@"mp3", @"m4a", @"wav", @"aiff", @"aac", @"flac", @"alac", @"ogg", nil];
    });
    NSString *ext = [[url pathExtension] lowercaseString];
    return [exts containsObject:ext];
}

static NSArray<Track *> *TracksFromURLs(NSArray<NSURL *> *urls) {
    NSMutableArray *tracks = [NSMutableArray array];
    for (NSURL *url in urls) {
        if (!IsAudioURL(url)) continue;
        Track *t = [[[Track alloc] init] autorelease];
        t.url = url;

        // Use ID3Parser for metadata decoding with encoding detection
        ID3MetadataResult *meta = [ID3Parser parseMetadataFromURL:url];
        if (meta) {
            t.title = meta.title ?: [[url lastPathComponent] stringByDeletingPathExtension];
            t.artist = meta.artist ?: @"Unknown Artist";
            t.duration = meta.duration;
        } else {
            // Fallback
            t.title = [[url lastPathComponent] stringByDeletingPathExtension];
            t.artist = @"Unknown Artist";
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
            t.duration = CMTimeGetSeconds([asset duration]);
        }
        [tracks addObject:t];
    }
    return tracks;
}

// ──────────────────────────────────────────────
// Player Controller — wraps AVAudioPlayer
// ──────────────────────────────────────────────
@interface PlayerController : NSObject <AVAudioPlayerDelegate>
@property (strong) AVAudioPlayer *player;
@property (strong) Track *currentTrack;
@property (assign) BOOL isPlaying;
@property (assign) NSTimeInterval currentTime;
@property (assign) NSTimeInterval duration;
@property (nonatomic, assign) float volume;
@property (copy) void (^onFinish)(BOOL successful);
@property (copy) void (^onTimeUpdate)(NSTimeInterval current, NSTimeInterval duration);
@property (strong) NSTimer *progressTimer;
@end

@implementation PlayerController

- (instancetype)init {
    self = [super init];
    if (self) {
        _volume = DEFAULT_VOLUME;
    }
    return self;
}

- (void)loadTrack:(Track *)track {
    [self stop];
    self.currentTrack = track;
    self.duration = track.duration;
    self.currentTime = 0;

    NSError *error = nil;
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:track.url error:&error];
    if (error) {
        NSLog(@"Failed to load %@: %@", [track.url lastPathComponent], error);
        self.player = nil;
        return;
    }
    self.player.delegate = self;
    self.player.volume = self.volume;
    [self.player prepareToPlay];
}

- (void)play {
    if (!self.player) return;
    if (![self.player play]) {
        NSLog(@"play failed for %@", [self.currentTrack.url lastPathComponent]);
    }
    self.isPlaying = YES;
    [self startProgressTimer];
    [self updateNowPlaying];
}

- (void)pause {
    if (!self.player) return;
    [self.player pause];
    self.isPlaying = NO;
    [self stopProgressTimer];
}

- (void)togglePlayPause {
    if (self.isPlaying) [self pause]; else [self play];
}

- (void)stop {
    [self stopProgressTimer];
    if (self.player) {
        [self.player stop];
        self.player = nil;
    }
    self.isPlaying = NO;
    self.currentTrack = nil;
    self.currentTime = 0;
    self.duration = 0;
}

- (void)seekTo:(NSTimeInterval)time {
    if (!self.player) return;
    time = MAX(0, MIN(time, self.duration));
    self.player.currentTime = time;
    self.currentTime = time;
    if (self.onTimeUpdate) self.onTimeUpdate(time, self.duration);
}

- (void)setVolume:(float)volume {
    _volume = volume;
    if (self.player) self.player.volume = volume;
}

// ── Timer ──
- (void)startProgressTimer {
    [self stopProgressTimer];
    self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:PROGRESS_TIMER_INTERVAL
                                                          target:self
                                                        selector:@selector(timerFired:)
                                                        userInfo:nil
                                                         repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.progressTimer forMode:NSRunLoopCommonModes];
}

- (void)stopProgressTimer {
    [self.progressTimer invalidate];
    self.progressTimer = nil;
}

- (void)timerFired:(NSTimer *)timer {
    if (!self.player) return;
    self.currentTime = self.player.currentTime;
    if (self.onTimeUpdate) self.onTimeUpdate(self.currentTime, self.duration);
}

// ── AVAudioPlayerDelegate ──
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    self.isPlaying = NO;
    [self stopProgressTimer];
    if (self.onFinish) self.onFinish(flag);
}

// ── Now Playing (Media Key support) ──
- (void)updateNowPlaying {
    if (!self.currentTrack) return;
    MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];
    center.nowPlayingInfo = @{
        MPMediaItemPropertyTitle: self.currentTrack.title ?: @"",
        MPMediaItemPropertyArtist: self.currentTrack.artist ?: @"",
        MPMediaItemPropertyPlaybackDuration: @(self.duration),
        MPNowPlayingInfoPropertyElapsedPlaybackTime: @(self.currentTime),
        MPNowPlayingInfoPropertyPlaybackRate: @(self.isPlaying ? 1.0 : 0.0),
    };
}

- (void)dealloc {
    [self stop];
    [_onFinish release];
    [_onTimeUpdate release];
    [super dealloc];
}

@end

// ──────────────────────────────────────────────
// App Delegate — UI, playlist, controls
// ──────────────────────────────────────────────
@interface AppDelegate : NSObject <NSApplicationDelegate>

// Window
@property (strong) NSWindow *window;

// Playlist
@property (strong) NSMutableArray<Track *> *tracks;

// Player
@property (strong) PlayerController *playerController;

// Controls (GlassButton)
@property (strong) GlassButton *playPauseButton;
@property (strong) GlassButton *prevButton;
@property (strong) GlassButton *nextButton;
@property (strong) GlassButton *shuffleButton;
@property (strong) GlassButton *repeatButton;

@property (strong) NSSlider *seekSlider;
@property (strong) NSTextField *timeLabel;
@property (strong) NSTextField *durationLabel;

@property (strong) NSSlider *volumeSlider;
@property (strong) NSTextField *volIconLabel;

@property (strong) NSTextField *titleLabel;
@property (strong) NSTextField *artistLabel;

// Glass panels for explicit layout
@property (strong) NSVisualEffectView *controlPanel;
@property (strong) NSVisualEffectView *trackListPanel;
@property (strong) TrackListView *trackListView;
@property (strong) NSScrollView *trackListScrollView;

// State
@property (assign) NSInteger currentIndex;
@property (assign) BOOL shuffle;
@property (assign) NSInteger repeatMode; // 0=off, 1=all, 2=one
@property (strong) NSMutableArray *playHistory; // for previous-track
@property (assign) BOOL isUpdatingSeek;
@property (strong) NSArray *shuffledOrder;

@end

@implementation AppDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _tracks = [[NSMutableArray alloc] init];
        _currentIndex = -1;
        _shuffle = NO;
        _repeatMode = 0;
        _playHistory = [[NSMutableArray alloc] init];
        _shuffledOrder = [[NSArray alloc] init];
        _playerController = [[PlayerController alloc] init];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self setupMenu];
    [self setupMediaKeys];
    [self setupWindow];
}

// ── Menu Bar ──
- (void)setupMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    // App menu
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appMenuItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenuItem setSubmenu:appMenu];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];

    // File menu
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    [mainMenu addItem:fileMenuItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenuItem setSubmenu:fileMenu];
    NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"Open Audio File(s)..." action:@selector(openFiles:) keyEquivalent:@"o"];
    [openItem setTarget:self];
    [fileMenu addItem:openItem];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];

    // Controls menu
    NSMenuItem *ctrlMenuItem = [[NSMenuItem alloc] initWithTitle:@"Controls" action:nil keyEquivalent:@""];
    [mainMenu addItem:ctrlMenuItem];
    NSMenu *ctrlMenu = [[NSMenu alloc] initWithTitle:@"Controls"];
    [ctrlMenuItem setSubmenu:ctrlMenu];

    NSMenuItem *playItem = [ctrlMenu addItemWithTitle:@"Play/Pause" action:@selector(togglePlayPause:) keyEquivalent:@" "];
    [playItem setTarget:self];

    NSMenuItem *nextItem = [ctrlMenu addItemWithTitle:@"Next Track" action:@selector(nextTrack:) keyEquivalent:@""];
    [nextItem setTarget:self];

    NSMenuItem *prevItem = [ctrlMenu addItemWithTitle:@"Previous Track" action:@selector(previousTrack:) keyEquivalent:@""];
    [prevItem setTarget:self];

    [ctrlMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *shufItem = [ctrlMenu addItemWithTitle:@"Toggle Shuffle" action:@selector(toggleShuffle:) keyEquivalent:@"s"];
    [shufItem setTarget:self];

    NSMenuItem *repItem = [ctrlMenu addItemWithTitle:@"Cycle Repeat" action:@selector(cycleRepeatMode:) keyEquivalent:@"r"];
    [repItem setTarget:self];

    // Edit menu (for copy/paste)
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    [mainMenu addItem:editMenuItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenuItem setSubmenu:editMenu];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];

    [NSApp setMainMenu:mainMenu];
}

// ── Media Keys (via MPRemoteCommandCenter) ──
- (void)setupMediaKeys {
    MPRemoteCommandCenter *cmd = [MPRemoteCommandCenter sharedCommandCenter];

    [cmd.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self.playerController play];
        [self updatePlayPauseButton];
        [self updateNowPlayingInfo];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [cmd.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self.playerController pause];
        [self updatePlayPauseButton];
        [self updateNowPlayingInfo];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [cmd.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self.playerController togglePlayPause];
        [self updatePlayPauseButton];
        [self updateNowPlayingInfo];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [cmd.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self nextTrack:nil];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [cmd.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self previousTrack:nil];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [cmd.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        MPChangePlaybackPositionCommandEvent *posEvent = (MPChangePlaybackPositionCommandEvent *)event;
        [self.playerController seekTo:posEvent.positionTime];
        [self updateSeekUI];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
}

// ── Window Setup ──
// ── Convenience: vibrancy-safe label ──
- (NSTextField *)makeLabel:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *tf = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    [tf setStringValue:text];
    [tf setBordered:NO];
    [tf setDrawsBackground:NO];
    [tf setEditable:NO];
    [tf setSelectable:NO];
    [tf setBackgroundColor:[NSColor clearColor]];
    [tf setFont:font];
    [tf setTextColor:color];
    [tf setAlignment:NSTextAlignmentCenter];
    return tf;
}

// ── Explicit two-panel layout: playlist (top) + controls (bottom) ──
- (void)layoutViews {
    NSView *bg = [[self.window contentView] subviews].firstObject;
    if (!bg) return;
    CGFloat W = bg.bounds.size.width;
    CGFloat H = bg.bounds.size.height;
    CGFloat pad = LAYOUT_PADDING, gap = LAYOUT_GAP;
    CGFloat ctrlH = CTRL_PANEL_HEIGHT; // fixed control panel height

    // ── Control panel at bottom ──
    self.controlPanel.frame = NSMakeRect(pad, pad, W - 2*pad, ctrlH);
    CGFloat cw = self.controlPanel.bounds.size.width;

    // Now playing (top of control panel)
    CGFloat y = ctrlH - CTRL_TOP_MARGIN;
    self.titleLabel.frame = NSMakeRect(pad, y - TITLE_LABEL_H, cw - 2*pad, TITLE_LABEL_H);
    self.artistLabel.frame = NSMakeRect(pad, y - ARTIST_LABEL_Y, cw - 2*pad, ARTIST_LABEL_H);

    // Seek bar
    y -= SEEK_SECTION_Y;
    self.timeLabel.frame = NSMakeRect(pad, y + (SEEK_SLIDER_H - 16) / 2, TIME_LABEL_W, 16);
    self.durationLabel.frame = NSMakeRect(cw - pad - TIME_LABEL_W, y + (SEEK_SLIDER_H - 16) / 2, TIME_LABEL_W, 16);
    self.seekSlider.frame = NSMakeRect(pad + TIME_LABEL_W + 6, y, cw - 2*pad - TIME_LABEL_W*2 - 12, SEEK_SLIDER_H);

    // Transport buttons (uniform GlassButton row)
    y -= TRANSPORT_SECTION_Y;
    const CGFloat BTN_W = 36;
    const CGFloat BTN_H = 36;
    const CGFloat BTN_COUNT = 5;
    CGFloat totalW = BTN_COUNT * BTN_W + (BTN_COUNT - 1) * BTN_GAP;
    CGFloat btnY = y;

    // Volume on the right of the transport row
    CGFloat volSectionW = VOL_SECTION_W;
    CGFloat volRightX = cw - pad - volSectionW;
    self.volIconLabel.frame = NSMakeRect(volRightX, btnY + (VOL_SLIDER_H - 20) / 2, VOL_ICON_W, 20);
    self.volumeSlider.frame = NSMakeRect(volRightX + VOL_SLIDER_X_OFF, btnY, volSectionW - VOL_SLIDER_W_INSET, VOL_SLIDER_H);

    // Re-center transport buttons to account for volume section
    CGFloat btnAreaW = volRightX - pad - 8;
    CGFloat btnX = pad + (btnAreaW - totalW) / 2.0;
    self.shuffleButton.frame    = NSMakeRect(btnX, btnY, BTN_W, BTN_H); btnX += BTN_W + BTN_GAP;
    self.prevButton.frame       = NSMakeRect(btnX, btnY, BTN_W, BTN_H); btnX += BTN_W + BTN_GAP;
    self.playPauseButton.frame  = NSMakeRect(btnX, btnY, BTN_W, BTN_H); btnX += BTN_W + BTN_GAP;
    self.nextButton.frame       = NSMakeRect(btnX, btnY, BTN_W, BTN_H); btnX += BTN_W + BTN_GAP;
    self.repeatButton.frame     = NSMakeRect(btnX, btnY, BTN_W, BTN_H);

    // ── Playlist area (top) — single full-width panel ──
    CGFloat plTop = pad + ctrlH + gap;
    CGFloat plH = H - plTop - LAYOUT_PADDING_TOP;

    self.trackListPanel.frame = NSMakeRect(pad, plTop, W - 2*pad, plH);
    self.trackListScrollView.frame = self.trackListPanel.bounds;
    self.trackListView.frame = NSMakeRect(0, 0, NSWidth(self.trackListScrollView.bounds),
                                           MAX(NSHeight(self.trackListView.frame),
                                               NSHeight(self.trackListScrollView.bounds)));
}

- (void)setupWindow {
    NSRect sf = [[NSScreen mainScreen] visibleFrame];
    CGFloat w = WINDOW_INITIAL_WIDTH, h = WINDOW_INITIAL_HEIGHT;
    NSRect wr = NSMakeRect(NSMidX(sf)-w/2, NSMidY(sf)-h/2, w, h);

    self.window = [[NSWindow alloc] initWithContentRect:wr
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                  NSWindowStyleMaskFullSizeContentView
        backing:NSBackingStoreBuffered defer:NO];

    [self.window setTitle:[NSString stringWithFormat:@"%@ v%@", APP_NAME, APP_VERSION]];
    [self.window setTitlebarAppearsTransparent:YES];
    [self.window setTitleVisibility:NSWindowTitleHidden];
    [self.window setMinSize:NSMakeSize(WINDOW_MIN_WIDTH, WINDOW_MIN_HEIGHT)];
    [self.window setBackgroundColor:[NSColor clearColor]];
    [self.window setOpaque:NO];
    [self.window setMovableByWindowBackground:YES];
    [self.window setHasShadow:YES];
    [self.window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
    [self.window center];

    NSView *content = [self.window contentView];

    // ── Global glass foundation (fills entire window, handles drops) ──
    GlassBackgroundView *bg = [[GlassBackgroundView alloc] initWithFrame:[content bounds]];
    [bg setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [bg setMaterial:NSVisualEffectMaterialDark];
    [bg setState:NSVisualEffectStateActive];
    [bg setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
    [bg setWantsLayer:YES];
    [content addSubview:bg];
    [bg registerForDraggedTypes:@[NSPasteboardTypeFileURL]];

    // ────────────────────────────────────────────
    // CONTROL PANEL (bottom — fixed height, all controls inside)
    // ────────────────────────────────────────────
    self.controlPanel = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    [self.controlPanel setMaterial:NSVisualEffectMaterialHUDWindow];
    [self.controlPanel setState:NSVisualEffectStateActive];
    [self.controlPanel setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
    [self.controlPanel setWantsLayer:YES];
    self.controlPanel.layer.cornerRadius = PANEL_CORNER_RADIUS;
    self.controlPanel.layer.masksToBounds = YES;
    self.controlPanel.layer.borderWidth = PANEL_BORDER_WIDTH;
    self.controlPanel.layer.borderColor = [[NSColor colorWithWhite:0.5 alpha:ALPHA_GLASS_INACTIVE_BD] CGColor];
    [bg addSubview:self.controlPanel];

    // Now playing
    self.titleLabel = [self makeLabel:@"No track selected" font:[NSFont boldSystemFontOfSize:15] color:[NSColor labelColor]];
    [self.controlPanel addSubview:self.titleLabel];
    self.artistLabel = [self makeLabel:@"" font:[NSFont systemFontOfSize:11] color:[NSColor secondaryLabelColor]];
    [self.controlPanel addSubview:self.artistLabel];

    // Seek bar
    self.timeLabel = [self makeLabel:@"0:00" font:[NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular] color:[NSColor secondaryLabelColor]];
    [self.timeLabel setAlignment:NSTextAlignmentRight];
    [self.controlPanel addSubview:self.timeLabel];

    self.seekSlider = [[GlassSlider alloc] initWithFrame:NSZeroRect];
    [self.seekSlider setMinValue:0]; [self.seekSlider setMaxValue:1];
    [self.seekSlider setTarget:self]; [self.seekSlider setAction:@selector(seekSliderChanged:)];
    [self.seekSlider setContinuous:YES];
    [self.controlPanel addSubview:self.seekSlider];

    self.durationLabel = [self makeLabel:@"0:00" font:[NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular] color:[NSColor secondaryLabelColor]];
    [self.durationLabel setAlignment:NSTextAlignmentLeft];
    [self.controlPanel addSubview:self.durationLabel];

    // Transport buttons (GlassButton)
    self.shuffleButton = [[[GlassButton alloc] initWithFrame:NSZeroRect] autorelease];
    self.shuffleButton.emoji = @"🔀";
    self.shuffleButton.toolTip = @"Shuffle";
    self.shuffleButton.target = self;
    self.shuffleButton.action = @selector(toggleShuffle:);
    [self.controlPanel addSubview:self.shuffleButton];

    self.prevButton = [[[GlassButton alloc] initWithFrame:NSZeroRect] autorelease];
    self.prevButton.emoji = @"⏮";
    self.prevButton.toolTip = @"Previous track";
    self.prevButton.target = self;
    self.prevButton.action = @selector(previousTrack:);
    [self.controlPanel addSubview:self.prevButton];

    self.playPauseButton = [[[GlassButton alloc] initWithFrame:NSZeroRect] autorelease];
    self.playPauseButton.emoji = @"▶";
    self.playPauseButton.toolTip = @"Play / Pause";
    self.playPauseButton.target = self;
    self.playPauseButton.action = @selector(togglePlayPause:);
    self.playPauseButton.active = YES;
    [self.controlPanel addSubview:self.playPauseButton];

    self.nextButton = [[[GlassButton alloc] initWithFrame:NSZeroRect] autorelease];
    self.nextButton.emoji = @"⏭";
    self.nextButton.toolTip = @"Next track";
    self.nextButton.target = self;
    self.nextButton.action = @selector(nextTrack:);
    [self.controlPanel addSubview:self.nextButton];

    self.repeatButton = [[[GlassButton alloc] initWithFrame:NSZeroRect] autorelease];
    self.repeatButton.emoji = @"🔁";
    self.repeatButton.toolTip = @"Repeat";
    self.repeatButton.target = self;
    self.repeatButton.action = @selector(cycleRepeatMode:);
    [self.controlPanel addSubview:self.repeatButton];

    // Volume (icon + slider)
    NSTextField *volIcon = [self makeLabel:@"🔊" font:[NSFont systemFontOfSize:12] color:[NSColor secondaryLabelColor]];
    self.volIconLabel = volIcon;
    [self.controlPanel addSubview:volIcon];

    self.volumeSlider = [[GlassSlider alloc] initWithFrame:NSZeroRect];
    [self.volumeSlider setMinValue:0]; [self.volumeSlider setMaxValue:1];
    [self.volumeSlider setFloatValue:0.5];
    [self.volumeSlider setTarget:self]; [self.volumeSlider setAction:@selector(volumeSliderChanged:)];
    [self.volumeSlider setContinuous:YES];
    [self.controlPanel addSubview:self.volumeSlider];

    // ────────────────────────────────────────────
    // TRACK LIST PANEL (top — fills remaining space)
    // ────────────────────────────────────────────
    self.trackListPanel = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    [self.trackListPanel setMaterial:NSVisualEffectMaterialMenu];
    [self.trackListPanel setState:NSVisualEffectStateActive];
    [self.trackListPanel setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
    [self.trackListPanel setWantsLayer:YES];
    self.trackListPanel.layer.cornerRadius = PANEL_CORNER_RADIUS;
    self.trackListPanel.layer.masksToBounds = YES;
    [bg addSubview:self.trackListPanel];

    self.trackListScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [self.trackListScrollView setHasVerticalScroller:YES];
    [self.trackListScrollView setAutohidesScrollers:YES];
    [self.trackListScrollView setScrollerStyle:NSScrollerStyleOverlay];
    [self.trackListScrollView setDrawsBackground:NO];
    [self.trackListScrollView setBorderType:NSNoBorder];
    [[self.trackListScrollView contentView] setDrawsBackground:NO];
    [[self.trackListScrollView contentView] setBackgroundColor:[NSColor clearColor]];
    [self.trackListPanel addSubview:self.trackListScrollView];
    [self.trackListScrollView setAutomaticallyAdjustsContentInsets:NO];
    [self.trackListScrollView setContentInsets:NSEdgeInsetsMake(0, 0, SCROLL_INSET_BOTTOM, 0)];

    self.trackListView = [[TrackListView alloc] initWithFrame:NSZeroRect];
    self.trackListView.tracks = self.tracks;
    self.trackListView.target = self;
    self.trackListView.action = @selector(trackListClicked:);
    self.trackListView.placeholderAction = @selector(openFiles:);
    [self.trackListScrollView setDocumentView:self.trackListView];
    [self.trackListView reloadData];

    // ── Explicit layout callback — fires on every resize ──
    __unsafe_unretained typeof(self) weakSelf = self;
    bg.onLayout = ^{
        [weakSelf layoutViews];
    };
    [self layoutViews]; // initial layout

    // ── Key monitor ──
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *ev) {
        if ([weakSelf handleKeyEvent:ev]) return nil;
        return ev;
    }];

    [self updateShuffleRepeatUI];
    [self updateControlsEnabled];
    [self.window makeKeyAndOrderFront:nil];
}

// ── Key Event Handling ──
- (BOOL)handleKeyEvent:(NSEvent *)event {
    if ([event type] != NSEventTypeKeyDown) return NO;
    unsigned short keyCode = [event keyCode];

    // Space (49) — Play/Pause
    if (keyCode == 49) {
        [self togglePlayPause:nil];
        return YES;
    }
    // Left arrow (123) — Seek back 5s
    if (keyCode == 123 && !([event modifierFlags] & NSEventModifierFlagCommand)) {
        NSTimeInterval t = self.playerController.currentTime - SEEK_STEP;
        [self.playerController seekTo:t];
        [self updateSeekUI];
        return YES;
    }
    // Right arrow (124) — Seek forward 5s
    if (keyCode == 124 && !([event modifierFlags] & NSEventModifierFlagCommand)) {
        NSTimeInterval t = self.playerController.currentTime + SEEK_STEP;
        [self.playerController seekTo:t];
        [self updateSeekUI];
        return YES;
    }
    // Up arrow (126) — Volume +5%
    if (keyCode == 126) {
        float v = MIN(1, self.volumeSlider.floatValue + VOLUME_STEP);
        [self.volumeSlider setFloatValue:v];
        [self volumeSliderChanged:nil];
        return YES;
    }
    // Down arrow (125) — Volume -5%
    if (keyCode == 125) {
        float v = MAX(0, self.volumeSlider.floatValue - VOLUME_STEP);
        [self.volumeSlider setFloatValue:v];
        [self volumeSliderChanged:nil];
        return YES;
    }
    // Cmd+A (0) — Select All in playlist
    if (keyCode == 0 && ([event modifierFlags] & NSEventModifierFlagCommand)) {
        [self.trackListView selectAll];
        return YES;
    }
    // Delete (51) — Remove selected tracks
    if (keyCode == 51) {
        if ([self.trackListView removeSelectedTracks]) {
            [self trackListDidChange];
        }
        return YES;
    }
    return NO;
}


// ── TrackListView change callback ──
- (void)trackListDidChange {
    BOOL hadTrackRemoved = (self.currentIndex >= (NSInteger)[self.tracks count]);

    if (hadTrackRemoved) {
        self.currentIndex = [self.tracks count] > 0 ? (NSInteger)[self.tracks count] - 1 : -1;
    }

    [self.trackListView setCurrentIndex:self.currentIndex];

    // Stop player if current track was removed or list is empty
    if (self.currentIndex < 0 || hadTrackRemoved) {
        [self.playerController stop];
    }

    [self updateControlsEnabled];
    [self updateNowPlayingUI];
    [self updatePlayPauseButton];
}


// ── Drag & Drop acceptance helper ──
- (void)acceptDroppedURLs:(NSArray<NSURL *> *)urls {
    if ([urls count] == 0) return;
    // Expand directories
    NSMutableArray *audioURLs = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSNumber *isDir;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if ([isDir boolValue]) {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSDirectoryEnumerator *en = [fm enumeratorAtURL:url
                                 includingPropertiesForKeys:nil
                                                    options:NSDirectoryEnumerationSkipsHiddenFiles
                                               errorHandler:nil];
            for (NSURL *child in en) {
                if (IsAudioURL(child)) [audioURLs addObject:child];
            }
        } else if (IsAudioURL(url)) {
            [audioURLs addObject:url];
        }
    }
    if ([audioURLs count] > 0) {
        [self addTracksFromURLs:audioURLs atIndex:(NSInteger)[self.tracks count]];
    }
}

// ── Track Management ──
- (void)addTracksFromURLs:(NSArray<NSURL *> *)urls atIndex:(NSInteger)index {
    NSArray *newTracks = TracksFromURLs(urls);
    if ([newTracks count] == 0) return;

    NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, [newTracks count])];
    [self.tracks insertObjects:newTracks atIndexes:indexes];

    // Update shuffled order
    if (self.shuffle) [self rebuildShuffleOrder];

    [self.trackListView reloadData];
    [self.trackListView setCurrentIndex:self.currentIndex];
    [self updateControlsEnabled];

    // Auto-play if nothing is playing
    if (self.currentIndex < 0 && [self.tracks count] > 0) {
        [self playTrackAtIndex:index];
    }
}

- (void)playTrackAtIndex:(NSInteger)index {
    [self playTrackAtIndex:index skippingHistory:NO];
}

- (void)playTrackAtIndex:(NSInteger)index skippingHistory:(BOOL)skipHistory {
    if (index < 0 || index >= (NSInteger)[self.tracks count]) return;

    if (!skipHistory && self.currentIndex >= 0 && self.currentIndex != index) {
        [self.playHistory addObject:@(self.currentIndex)];
    }

    self.currentIndex = index;
    Track *track = self.tracks[index];

    __unsafe_unretained typeof(self) weakSelf = self;
    self.playerController.onFinish = ^(BOOL successful) {
        [weakSelf trackDidFinish];
    };
    self.playerController.onTimeUpdate = ^(NSTimeInterval current, NSTimeInterval duration) {
        [weakSelf updateSeekUI];
    };

    [self.playerController loadTrack:track];
    [self.playerController play];

    [self updateNowPlayingUI];
    [self updateSeekUI];
    [self updatePlayPauseButton];
    [self updateNowPlayingInfo];
    [self.trackListView reloadData];
    [self.trackListView setCurrentIndex:self.currentIndex];
}

- (void)trackDidFinish {
    if (self.repeatMode == 2) {
        // Repeat one
        [self.playerController seekTo:0];
        [self.playerController play];
        [self updatePlayPauseButton];
        return;
    }
    [self nextTrackImpl];
}

- (void)nextTrackImpl {
    NSInteger count = (NSInteger)[self.tracks count];
    if (count == 0) return;

    NSInteger next;
    if (self.shuffle) {
        [self rebuildShuffleOrder];
        NSInteger pos = -1;
        for (NSInteger i = 0; i < (NSInteger)[self.shuffledOrder count]; i++) {
            if ([self.shuffledOrder[i] integerValue] == self.currentIndex) {
                pos = i;
                break;
            }
        }
        NSInteger nextPos = (pos + 1) % (NSInteger)[self.shuffledOrder count];
        next = [self.shuffledOrder[nextPos] integerValue];
    } else {
        next = self.currentIndex + 1;
        if (next >= count) {
            if (self.repeatMode == 1) {
                next = 0;
            } else {
                self.currentIndex = -1;
                [self.playerController stop];
                [self updateNowPlayingUI];
                [self updatePlayPauseButton];
                [self.trackListView reloadData];
                [self.trackListView setCurrentIndex:-1];
                return;
            }
        }
    }

    if (next >= 0 && next < count) {
        [self playTrackAtIndex:next];
    }
}

// ── Actions ──
- (void)openFiles:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:YES];
    [panel setAllowsOtherFileTypes:YES];

    if (@available(macOS 11.0, *)) {
        // Use UTIs for modern macOS
        [panel setAllowedContentTypes:@[
            [UTType typeWithFilenameExtension:@"mp3"],
            [UTType typeWithFilenameExtension:@"m4a"],
            [UTType typeWithFilenameExtension:@"wav"],
            [UTType typeWithFilenameExtension:@"aiff"],
            [UTType typeWithFilenameExtension:@"aac"],
            [UTType typeWithFilenameExtension:@"flac"],
            [UTType typeWithFilenameExtension:@"alac"],
            [UTType typeWithFilenameExtension:@"ogg"],
            [UTType typeWithFilenameExtension:@"wma"],
        ]];
    } else {
        [panel setAllowedFileTypes:@[@"mp3", @"m4a", @"wav", @"aiff", @"aac", @"flac", @"alac", @"ogg", @"wma"]];
    }

    if ([panel runModal] != NSModalResponseOK) return;

    NSMutableArray *urls = [NSMutableArray array];
    for (NSURL *url in [panel URLs]) {
        NSNumber *isDir;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if ([isDir boolValue]) {
            // Expand directory
            NSFileManager *fm = [NSFileManager defaultManager];
            NSDirectoryEnumerator *en = [fm enumeratorAtURL:url
                                 includingPropertiesForKeys:nil
                                                    options:NSDirectoryEnumerationSkipsHiddenFiles
                                               errorHandler:nil];
            for (NSURL *child in en) {
                if (IsAudioURL(child)) [urls addObject:child];
            }
        } else {
            if (IsAudioURL(url)) [urls addObject:url];
        }
    }
    if ([urls count] > 0) {
        [self addTracksFromURLs:urls atIndex:(NSInteger)[self.tracks count]];
    }
}

- (void)togglePlayPause:(id)sender {
    if (self.currentIndex < 0) {
        if ([self.tracks count] > 0) {
            [self playTrackAtIndex:0];
        }
        return;
    }
    if (!self.playerController.player) {
        // Track was loaded but player failed — reload
        [self playTrackAtIndex:self.currentIndex];
        return;
    }
    [self.playerController togglePlayPause];
    [self updatePlayPauseButton];
    [self updateNowPlayingInfo];
}

- (void)nextTrack:(id)sender {
    [self nextTrackImpl];
}

- (void)previousTrack:(id)sender {
    if ([self.tracks count] == 0) return;

    // If more than 3 seconds in, restart current track
    if (self.playerController.currentTime > PREV_TRACK_THRESH) {
        [self.playerController seekTo:0];
        [self updateSeekUI];
        return;
    }

    // Go back in history, or previous sequential
    if ([self.playHistory count] > 0) {
        NSInteger prev = [[self.playHistory lastObject] integerValue];
        [self.playHistory removeLastObject];
        if (prev >= 0 && prev < (NSInteger)[self.tracks count]) {
            // Don't push current onto history when using history (avoid cycles)
            [self playTrackAtIndex:prev skippingHistory:YES];
            return;
        }
    }

    NSInteger prevIdx = self.currentIndex - 1;
    if (prevIdx < 0) {
        if (self.repeatMode == 1) {
            prevIdx = (NSInteger)[self.tracks count] - 1;
        } else {
            prevIdx = 0;
        }
    }
    [self playTrackAtIndex:prevIdx];
}

- (void)toggleShuffle:(id)sender {
    self.shuffle = !self.shuffle;
    if (self.shuffle) {
        [self rebuildShuffleOrder];
    } else {
        self.shuffledOrder = @[];
    }
    [self updateShuffleRepeatUI];
}

- (void)cycleRepeatMode:(id)sender {
    self.repeatMode = (self.repeatMode + 1) % 3;
    [self updateShuffleRepeatUI];
}

- (void)seekSliderChanged:(id)sender {
    self.isUpdatingSeek = YES;
    double ratio = [self.seekSlider doubleValue];
    NSTimeInterval t = ratio * self.playerController.duration;
    [self.playerController seekTo:t];
    self.isUpdatingSeek = NO;
}

- (void)volumeSliderChanged:(id)sender {
    float vol = [self.volumeSlider floatValue];
    [self.playerController setVolume:vol];
}

// ── TrackListView row click ──
- (void)trackListClicked:(NSNumber *)rowObj {
    NSInteger row = [rowObj integerValue];
    if (row >= 0 && row < (NSInteger)[self.tracks count]) {
        [self playTrackAtIndex:row];
    }
}

// ── UI Updates ──
- (void)updatePlayPauseButton {
    if (self.playerController.isPlaying) {
        self.playPauseButton.emoji = @"⏸";
    } else {
        self.playPauseButton.emoji = @"▶";
    }
}

- (void)updateNowPlayingUI {
    if (self.currentIndex >= 0 && self.currentIndex < (NSInteger)[self.tracks count]) {
        Track *t = self.tracks[self.currentIndex];
        [self.titleLabel setStringValue:t.title];
        [self.artistLabel setStringValue:t.artist];
    } else if ([self.tracks count] == 0) {
        [self.titleLabel setStringValue:@"No tracks loaded"];
        [self.artistLabel setStringValue:@"Drop audio files to begin"];
    } else {
        [self.titleLabel setStringValue:@"Select a track"];
        [self.artistLabel setStringValue:@""];
    }
}

- (void)updateSeekUI {
    NSTimeInterval current = self.playerController.currentTime;
    NSTimeInterval duration = self.playerController.duration;
    double ratio = (duration > 0) ? (current / duration) : 0;

    if (!self.isUpdatingSeek) {
        [self.seekSlider setDoubleValue:ratio];
    }
    [self.timeLabel setStringValue:FormatTime(current)];
    [self.durationLabel setStringValue:FormatTime(duration)];
}

- (void)updateShuffleRepeatUI {
    self.shuffleButton.active = self.shuffle;
    self.shuffleButton.emoji = @"🔀";

    NSString *repEmoji = self.repeatMode == 0 ? @"🔁" : (self.repeatMode == 1 ? @"🔁" : @"🔂");
    self.repeatButton.active = (self.repeatMode > 0);
    self.repeatButton.emoji = repEmoji;
}

- (void)updateControlsEnabled {
    BOOL hasTracks = [self.tracks count] > 0;
    [self.playPauseButton setEnabled:hasTracks];
    [self.prevButton setEnabled:hasTracks];
    [self.nextButton setEnabled:hasTracks];
}

- (void)updateNowPlayingInfo {
    [self.playerController updateNowPlaying];
}

- (void)rebuildShuffleOrder {
    NSInteger count = (NSInteger)[self.tracks count];
    NSMutableArray *indices = [NSMutableArray arrayWithCapacity:count];
    for (NSInteger i = 0; i < count; i++) [indices addObject:@(i)];
    // Fisher-Yates
    for (NSInteger i = count - 1; i > 0; i--) {
        NSInteger j = arc4random_uniform((uint32_t)(i + 1));
        [indices exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    self.shuffledOrder = indices;
}

// ── Application Delegate ──
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end

// ──────────────────────────────────────────────
// Entry Point
// ──────────────────────────────────────────────
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
