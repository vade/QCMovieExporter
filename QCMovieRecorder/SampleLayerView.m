//
//  SampleLayerView.m
//  QCMovieRecorder
//
//  Created by vade on 1/16/17.
//  Copyright © 2017 v002. All rights reserved.
//

#import "SampleLayerView.h"
#import <AVFoundation/AVFoundation.h>


@implementation SampleLayerView

- (id) initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if(self)
    {
        [self commonInit];
    }

    return self;
}

- (void) awakeFromNib
{
    [self commonInit];
}

- (void) commonInit
{
    self.layer.backgroundColor = [NSColor blackColor].CGColor;
}

- (BOOL) wantsLayer
{
    return YES;
}

- (void) displayCVPIxelBuffer:(CVPixelBufferRef)pixelBuffer
{
    self.layer.contents = (__bridge id _Nullable)(pixelBuffer);
    self.layer.contentsGravity = @"resizeAspect";
}


@end
