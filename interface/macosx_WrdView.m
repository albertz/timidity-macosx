#import "macosx_WrdView.h"
#import "wrdt_macosx.h"
#import "macosx_wrdwindow.h"

@implementation WrdView
  
 - (id) initWithFrame : (NSRect) frameRect
 {
     [ super initWithFrame : frameRect ]; // �X�[�p�[�N���X�ŏ�����
    
    //dispImage = [ [NSImage alloc] initWithSize:NSMakeSize( 640, 480 ) ];
    //wrdEnv.dispImage = dispImage;
    wrdEnv.wrdView   = self;

    //[ dispImage lockFocus ]; 
    //[ dispImage unlockFocus ];

    return self;
 }
 
 - (void) drawRect : (NSRect) arBounds
 {
    [wrdEnv.dispWorld32 draw];
    //[dispImage compositeToPoint:arBounds.origin fromRect:arBounds
    //    operation:NSCompositeCopy];
}

- (BOOL)isOpaque {
    return YES;
}

@end

