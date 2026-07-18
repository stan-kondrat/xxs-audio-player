#import <Cocoa/Cocoa.h>

@interface GlassButton : NSControl

@property (nonatomic, copy) NSString *emoji;

@property (nonatomic, assign, getter=isActive) BOOL active;
@property (nonatomic, assign, getter=isHovered) BOOL hover;

@end
