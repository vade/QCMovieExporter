//
//  SampleLayerView.h
//  QCMovieRecorder
//
//  Created by vade on 1/16/17.
//  Copyright © 2017 v002. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <CoreVideo/CoreVideo.h>

@interface SampleLayerView : NSView
- (void) displayCVPIxelBuffer:(CVPixelBufferRef)pixelBuffer;

@end
