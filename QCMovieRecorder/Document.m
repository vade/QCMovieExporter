//
//  Document.m
//  QCMovieRecorder
//
//  Created by vade on 1/15/17.
//  Copyright © 2017 v002. All rights reserved.
//

#import "Document.h"

#import <AVFoundation/AVFoundation.h>
#import <OpenGL/OpenGL.h>
#import <CoreMedia/CoreMedia.h>
#import <Quartz/Quartz.h>
#import <VideoToolbox/VideoToolbox.h>
#import <Accelerate/Accelerate.h>
#import "SampleLayerView.h"

@interface Document ()
{
    // Multisampled FBO
    GLuint msaaFBO;
    GLuint msaaFBODepthAttachment;
    GLuint msaaFBOColorAttachment;
    
    // Blit target from MSAA
    GLuint fbo;
    // Backed by IOSurface
    GLuint fboColorAttachment;
    
    BOOL createdGLResources;
}

// Rendering
@property (readwrite, strong) NSOpenGLContext* context;
@property (readwrite, strong) QCRenderer* renderer;
@property (readwrite, strong) QCComposition* composition;

// Movie Writing
@property (readwrite, assign) NSInteger durationH, durationM, durationS, duration;
@property (readwrite, strong) AVAssetWriter* assetWriter;
@property (readwrite, strong) AVAssetWriterInput* assetWriterVideoInput;
@property (readwrite, strong) AVAssetWriterInputPixelBufferAdaptor* assetWriterPixelBufferAdaptor;
@property (atomic, readwrite, assign) BOOL shouldCanel;

@property (readwrite, assign) CMTime frameInterval;
@property (readwrite, assign) NSSize videoResolution;
@property (readwrite, strong) NSString* codecString;
@property (readwrite, assign) int antialiasFactor;

// Interface
@property (readwrite, strong) IBOutlet NSButton* renderButton;
@property (readwrite, strong) IBOutlet NSButton* destinationButton;
@property (readwrite, strong) IBOutlet NSTextField* destinationLabel;
@property (readwrite, strong) IBOutlet NSProgressIndicator* renderProgress;
@property (readwrite, strong) IBOutlet NSPopUpButton* frameRateMenu;
@property (readwrite, strong) IBOutlet NSPopUpButton* resolutionMenu;
@property (readwrite, strong) IBOutlet NSPopUpButton* codecMenu;
@property (readwrite, strong) IBOutlet NSPopUpButton* antialiasMenu;
@property (readwrite, strong) IBOutlet NSButton* codecOptionsButton;
@property (readwrite, strong) IBOutlet NSButton* enablePreviewButton;
@property (readwrite, strong) IBOutlet NSWindow* codecOptionsWindow;

@property (readwrite, strong) IBOutlet SampleLayerView* preview;


@end

@implementation Document

- (instancetype)init {
    self = [super init];
    if (self) {
        // Add your subclass-specific initialization here.
        
        createdGLResources = NO;

        self.renderer = nil;
        
        self.shouldCanel = NO;
        self.frameInterval = CMTimeMake(1, 24);
        self.videoResolution = NSMakeSize(640, 480);
        self.codecString = AVVideoCodecAppleProRes4444;
        
        NSOpenGLPixelFormatAttribute attributes[] = {
            NSOpenGLPFAAllowOfflineRenderers,
            NSOpenGLPFAAccelerated,
            NSOpenGLPFAColorSize, 32,
            NSOpenGLPFADepthSize, 24,
            NSOpenGLPFANoRecovery,
            NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersionLegacy
        };

        NSOpenGLPixelFormat* pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
        if(pixelFormat)
        {
            self.context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
            
            if(self.context)
            {
                NSLog(@"loaded context");
            }
            
        }
		
			// Default duration (30 seconds)
		_durationH = 0; _durationM = 0; _durationS = 30;
		[self updateDuration];
    }
    
    return self;
}

+ (BOOL)autosavesInPlace {
    return YES;
}


- (NSString *)windowNibName {
    return @"Document";
}


- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    return nil;
}


- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
    return YES;
}

- (nullable instancetype)initWithContentsOfURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError
{
    self = [super initWithContentsOfURL:url ofType:typeName error:outError];
    if(self)
    {
        VTRegisterProfessionalVideoWorkflowVideoDecoders();
        VTRegisterProfessionalVideoWorkflowVideoEncoders();
        self.composition = [QCComposition compositionWithFile:url.path];
    }
    
    return self;
}

- (void)windowControllerDidLoadNib:(NSWindowController *)windowController;
{
    // disable certain UI items until choices have been made
    self.destinationButton.enabled = YES;
    
    self.renderButton.enabled = NO;
    self.codecMenu.enabled = NO;
    self.resolutionMenu.enabled = NO;
    self.frameRateMenu.enabled = NO;
    self.codecOptionsButton.enabled = NO;
    self.antialiasMenu.enabled = NO;

    [self buildMenus];
}

- (void) buildMenus
{
    NSArray* resolutions = @[ [NSValue valueWithSize:NSMakeSize(640, 480)],
                              [NSValue valueWithSize:NSMakeSize(1280, 720)],
                              [NSValue valueWithSize:NSMakeSize(1920, 1080)],
                              [NSValue valueWithSize:NSMakeSize(2048, 1080)],
                              [NSValue valueWithSize:NSMakeSize(3840, 2160)],
                              [NSValue valueWithSize:NSMakeSize(4096, 2160)],
                              [NSValue valueWithSize:NSMakeSize(7680, 4320)],
                              [NSValue valueWithSize:NSMakeSize(8192, 4320)],
                              ];
    
    NSArray* resolutionNames = @[ @"480P",
                                  @"720P",
                                  @"1080P",
                                  @"2K",
                                  @"UHD",
                                  @"4K",
                                  @"8K UHD",
                                  @"8K",
                                  ];
    
    [self makeMenu:self.resolutionMenu representedObjects:resolutions titles:resolutionNames selector:@selector(setResolution:)];
    
    NSArray* frameRates = @[ [NSValue valueWithCMTime:CMTimeMake(1, 24)],
                             [NSValue valueWithCMTime:CMTimeMake(1, 25)],
                             [NSValue valueWithCMTime:CMTimeMake(1, 30)],
                             [NSValue valueWithCMTime:CMTimeMake(1, 50)],
                             [NSValue valueWithCMTime:CMTimeMake(1, 60)],
                             [NSValue valueWithCMTime:CMTimeMake(1, 120)],
                             ];
    
    NSArray* frameRateNames = @[ @"24",
                                 @"25",
                                 @"30",
                                 @"50",
                                 @"60",
                                 @"120",
                                 ];
    
    [self makeMenu:self.frameRateMenu representedObjects:frameRates titles:frameRateNames selector:@selector(setFrameRate:)];
    
    NSArray* codecs = @[AVVideoCodecAppleProRes4444,
                        AVVideoCodecAppleProRes422,
                        AVVideoCodecJPEG,
                        AVVideoCodecH264,
                        ];
    
    NSArray* codecNames = @[ @"ProRes 4444",
                             @"ProRes 422",
                             @"Motion Jpeg",
                             @"H.264"
                             ];
    
    [self makeMenu:self.codecMenu representedObjects:codecs titles:codecNames selector:@selector(setCodec:)];

    
    NSArray* aaName = @[@"None",
                        @"4x",
                        @"8x",
                        ];
    
    NSArray* aaAmount = @[ @(1),
                            @(4),
                            @(8),
                             ];
    
    [self makeMenu:self.antialiasMenu representedObjects:aaAmount titles:aaName selector:@selector(setAntialiasAmount:)];
}

- (void) makeMenu:(NSPopUpButton*)popUp representedObjects:(NSArray*)objects titles:(NSArray*)titles selector:(SEL)selector
{
    [popUp removeAllItems];

    for(int i = 0; i < objects.count; i++)
    {
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:titles[i] action:selector keyEquivalent:@""];
        [item setRepresentedObject:objects[i]];
        [popUp.menu addItem:item];
    }
}

- (IBAction) chooseRenderDestination:(id)sender
{
    NSSavePanel* savePanel = [NSSavePanel savePanel];
    
    savePanel.allowedFileTypes = @[@"mov"];
    
    [savePanel beginSheetModalForWindow:self.windowControllers[0].window completionHandler:^(NSInteger result) {
        
        if(result == NSFileHandlingPanelOKButton)
        {
            self.assetWriter = [[AVAssetWriter alloc] initWithURL:savePanel.URL fileType:AVFileTypeQuickTimeMovie error:nil];
        
            self.renderButton.enabled = YES;
            self.destinationLabel.stringValue = savePanel.URL.path;
            self.codecMenu.enabled = YES;
            self.antialiasMenu.enabled = YES;
            self.resolutionMenu.enabled = YES;
            self.frameRateMenu.enabled = YES;
            self.codecOptionsButton.enabled = NO;
        }
    }];
}

- (IBAction) setResolution:(NSMenuItem*)sender
{
    self.videoResolution = [sender.representedObject sizeValue];
}

- (IBAction) setCodec:(NSMenuItem*)sender
{
    self.codecString = sender.representedObject;
    
    if([self.codecString isEqualToString:AVVideoCodecJPEG] || [self.codecString isEqualToString:AVVideoCodecH264])
    {
        self.codecOptionsButton.enabled = YES;
    }
    else
    {
        self.codecOptionsButton.enabled = NO;
    }
}

- (IBAction) setFrameRate:(NSMenuItem*)sender
{
    self.frameInterval = [sender.representedObject CMTimeValue];
}

- (IBAction)setAntialiasAmount:(NSMenuItem*)sender
{
    self.antialiasFactor = [sender.representedObject intValue];
}

- (IBAction)updateH:(NSTextField *)sender
{
	self.durationH = sender.integerValue;
	[self updateDuration];
}

- (IBAction)updateM:(NSTextField *)sender
{
	self.durationM = sender.integerValue;
	[self updateDuration];
}

- (IBAction)updateS:(NSTextField *)sender
{
	self.durationS = sender.integerValue;
	[self updateDuration];
}

- (void) updateDuration
{
	self.duration = (_durationH * 60 * 60) + (_durationM * 60) + _durationS;
}

- (IBAction)revealCodecOptions:(id)sender
{
    [self.windowControllers[0].window beginSheet:self.codecOptionsWindow completionHandler:^(NSModalResponse returnCode) {
        
    }];
}

- (IBAction)commitCodecOptions:(id)sender
{
    [self.windowControllers[0].window endSheet:self.codecOptionsWindow];
}

- (IBAction) render:(NSButton *)sender
{
	if (sender.tag == 0)
    {
        // Start rendering
        // Disable changing options once we render - makes no sense
		self.destinationButton.enabled = NO;
		self.codecMenu.enabled = NO;
		self.resolutionMenu.enabled = NO;
		self.frameRateMenu.enabled = NO;
		self.codecOptionsButton.enabled = NO;
        self.antialiasMenu.enabled = NO;
		self.renderButton.title = @"Cancel";
		
        // Setup outputs absed on chosen framerate, resolution, codec
        
        NSDictionary* videoOutputSettings = @{ AVVideoCodecKey : self.codecString,
                                               AVVideoWidthKey : @(self.videoResolution.width),
                                               AVVideoHeightKey : @(self.videoResolution.height),
                                               
                                               // HD:
                                               AVVideoColorPropertiesKey : @{
                                                       AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                                       AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                                       AVVideoYCbCrMatrixKey : AVVideoYCbCrMatrix_ITU_R_709_2,
                                                       },
                                               };
        
        self.assetWriterVideoInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                                                    outputSettings:videoOutputSettings];
        
        NSDictionary* pixelBufferAttributes = @{ (NSString*) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                                 (NSString*) kCVPixelBufferWidthKey : @(self.videoResolution.width),
                                                 (NSString*) kCVPixelBufferHeightKey : @(self.videoResolution.height),
                                                 (NSString*) kCVPixelBufferIOSurfacePropertiesKey : @{ },
                                                 (NSString*) kCVPixelBufferOpenGLCompatibilityKey : @(YES),
                                                 (NSString*) kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey : @(YES),
                                                 (NSString*) kCVPixelBufferIOSurfaceOpenGLFBOCompatibilityKey : @(YES),
                                                 };
        
        self.assetWriterPixelBufferAdaptor = [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:self.assetWriterVideoInput sourcePixelBufferAttributes:pixelBufferAttributes];
        
        if([self.assetWriter canAddInput:self.assetWriterVideoInput])
        {
            [self.assetWriter addInput:self.assetWriterVideoInput];
        }
        
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
			
            // Syncronous activity - effectively disables AppNap / re-enables AppNap on completion
			[NSProcessInfo.processInfo performActivityWithOptions:NSActivityUserInitiated reason:@"Render" usingBlock:^{
				[self.assetWriter startWriting];
				[self.assetWriter startSessionAtSourceTime:kCMTimeZero];
				[self renderAndWrite];
			}];
		});
	}
    else
    {
        // Note we want to bail cleanly, so we dont call
        // cancel on our asset reader (only if we have an error)
        self.shouldCanel = YES;
    }
	
	sender.tag = sender.tag == 0 ? 1 : 0;
}


- (void) renderAndWrite
{
    CMTime duration = CMTimeMakeWithSeconds(self.duration, 600);
    __block CMTime currentTime = kCMTimeZero;
    __block NSUInteger frameNumber = 0;
    
    dispatch_semaphore_t finishedSignal = dispatch_semaphore_create(0);
    dispatch_queue_t videoRenderQueue = dispatch_queue_create("videoRenderQueue", DISPATCH_QUEUE_SERIAL);

    [self.assetWriterVideoInput requestMediaDataWhenReadyOnQueue:videoRenderQueue usingBlock:^{
       
        // Are we above our duration, or do we bail nicely?
        if( CMTIME_COMPARE_INLINE(currentTime, >=,  duration) || self.shouldCanel)
        {
            [self.assetWriterVideoInput markAsFinished];
            
            self.shouldCanel = NO;

            dispatch_semaphore_signal(finishedSignal);
        }
        else if (self.assetWriter.status == AVAssetWriterStatusCancelled || self.assetWriter.status == AVAssetWriterStatusFailed)
        {
            [self.assetWriterVideoInput markAsFinished];
            
            dispatch_semaphore_signal(finishedSignal);
        }
        else if (self.assetWriter.status == AVAssetWriterStatusWriting)
        {
            // assign context
            [self.context makeCurrentContext];
        
            // create texture attachment from IOSurfaceBacked PixelBuffer
            CVPixelBufferRef ioSurfaceBackedPixelBuffer;
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, self.assetWriterPixelBufferAdaptor.pixelBufferPool, &ioSurfaceBackedPixelBuffer);
            GLsizei width = (GLsizei) CVPixelBufferGetWidth(ioSurfaceBackedPixelBuffer);
            GLsizei height = (GLsizei) CVPixelBufferGetHeight(ioSurfaceBackedPixelBuffer);

            // Need to create Renderer on same thread we use it on, (ugh)
            if(self.renderer == nil)
            {
                CGColorSpaceRef cspace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
                
                self.renderer = [[QCRenderer alloc] initWithCGLContext:self.context.CGLContextObj
                                                           pixelFormat:self.context.pixelFormat.CGLPixelFormatObj
                                                            colorSpace:cspace
                                                           composition:self.composition];
                CGColorSpaceRelease(cspace);
            }
            
            // create GL resources if we need it
            [self createFBOWithCVPixelBuffer:ioSurfaceBackedPixelBuffer];
            
            // bind FBO
            glBindFramebuffer(GL_FRAMEBUFFER, msaaFBO);

            // Setup default GL state
            glPushAttrib(GL_ALL_ATTRIB_BITS);

            glViewport(0, 0, width, height);
            glOrtho(0, width, 0, height, -1, 1);

            glMatrixMode(GL_PROJECTION);
            glLoadIdentity();
            
            glMatrixMode(GL_MODELVIEW);
            glLoadIdentity();

            // render into FBO
            CFStringRef timeString = CMTimeCopyDescription(kCFAllocatorDefault, currentTime);
            NSLog(@"Rendering frame:%lu time: %@", (unsigned long)frameNumber,  timeString);
            CFRelease(timeString);
            
            [self.renderer renderAtTime:CMTimeGetSeconds(currentTime) arguments:nil];

            // GL Syncronize contents of MSAA
            glFlushRenderAPPLE();

            // MSAA Resolve / Blit to IOSurface attachment / FBO
            glBindFramebuffer(GL_READ_FRAMEBUFFER, msaaFBO);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbo);
            
            // blit the whole extent from read to draw
            glBlitFramebufferEXT(0, 0, width, height, 0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_NEAREST);
            
            // GL Syncronize / Readback IOSurface to pixel buffer
            // Note glFlushRenderApple / glFlush should be sufficient as I understand it
            // but we appear to get some flicker with them.
            glFlushRenderAPPLE();
            
            // restore viewport, matrix
            glPopAttrib();
            
            
            // Use VImage to flip vertically if we need to
            if(CVImageBufferIsFlipped(ioSurfaceBackedPixelBuffer))
            {
                // Create a new destination pixel buffer from our pool,
                
                CVPixelBufferRef flippedIoSurfaceBackedPixelBuffer;
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, self.assetWriterPixelBufferAdaptor.pixelBufferPool, &flippedIoSurfaceBackedPixelBuffer);

                
                // Lock base addresses for reading / writing
                CVPixelBufferLockBaseAddress(ioSurfaceBackedPixelBuffer, kCVPixelBufferLock_ReadOnly);
                CVPixelBufferLockBaseAddress(flippedIoSurfaceBackedPixelBuffer, 0);
                
                // make vImage buffers
                
                vImage_Buffer source;
                source.data = CVPixelBufferGetBaseAddress(ioSurfaceBackedPixelBuffer);
                source.rowBytes = CVPixelBufferGetBytesPerRow(ioSurfaceBackedPixelBuffer);
                source.width = CVPixelBufferGetWidth(ioSurfaceBackedPixelBuffer);
                source.height = CVPixelBufferGetHeight(ioSurfaceBackedPixelBuffer);
                
                vImage_Buffer dest;
                dest.data = CVPixelBufferGetBaseAddress(flippedIoSurfaceBackedPixelBuffer);
                dest.rowBytes = CVPixelBufferGetBytesPerRow(flippedIoSurfaceBackedPixelBuffer);
                dest.width = CVPixelBufferGetWidth(flippedIoSurfaceBackedPixelBuffer);
                dest.height = CVPixelBufferGetHeight(flippedIoSurfaceBackedPixelBuffer);
                
                vImageVerticalReflect_ARGB8888(&source, &dest, kvImageNoFlags);
                
                CVPixelBufferUnlockBaseAddress(ioSurfaceBackedPixelBuffer, kCVPixelBufferLock_ReadOnly);
                CVPixelBufferUnlockBaseAddress(flippedIoSurfaceBackedPixelBuffer, 0);
                
                // Clean Up
                CVPixelBufferRelease(ioSurfaceBackedPixelBuffer);

                // Write pixel buffer to movie
                if(![self.assetWriterPixelBufferAdaptor appendPixelBuffer:flippedIoSurfaceBackedPixelBuffer withPresentationTime:currentTime])
                    NSLog(@"Unable to write frame at time: %@", CMTimeCopyDescription(kCFAllocatorDefault, currentTime));
                
                // Update UI on main queue
                CVPixelBufferRetain(flippedIoSurfaceBackedPixelBuffer);
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    if(self.enablePreviewButton.state == NSOnState)
                        [self.preview displayCVPIxelBuffer:flippedIoSurfaceBackedPixelBuffer];
                    
                    CVPixelBufferRelease(flippedIoSurfaceBackedPixelBuffer);
                    
                    self.renderProgress.doubleValue = CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(duration);
                });

                // Cleanup
                CVPixelBufferRelease(flippedIoSurfaceBackedPixelBuffer);
                
            }
            else
            {
                // Write pixel buffer to movie
                if(![self.assetWriterPixelBufferAdaptor appendPixelBuffer:ioSurfaceBackedPixelBuffer withPresentationTime:currentTime])
                    NSLog(@"Unable to write frame at time: %@", CMTimeCopyDescription(kCFAllocatorDefault, currentTime));
                
                // Update UI on main queue
                CVPixelBufferRetain(ioSurfaceBackedPixelBuffer);
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    if(self.enablePreviewButton.state == NSOnState)
                        [self.preview displayCVPIxelBuffer:ioSurfaceBackedPixelBuffer];
                    
                    CVPixelBufferRelease(ioSurfaceBackedPixelBuffer);
                    
                    self.renderProgress.doubleValue = CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(duration);
                });

                // Cleanup
                CVPixelBufferRelease(ioSurfaceBackedPixelBuffer);
            }
            
            
            // increment time
            currentTime = CMTimeAdd(currentTime, self.frameInterval);
            frameNumber++;
        }
    }];
    
    dispatch_semaphore_wait(finishedSignal, DISPATCH_TIME_FOREVER);
    
    [self.assetWriter finishWritingWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[self.assetWriter.outputURL]];
        });
    }];
}

- (void) createFBOWithCVPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    if(!createdGLResources)
    {
        GLsizei width = (GLsizei) CVPixelBufferGetWidth(pixelBuffer);
        GLsizei height = (GLsizei) CVPixelBufferGetHeight(pixelBuffer);
        
        // Final MSAA FBO resolve target
        glGenFramebuffers(1, &fbo);
        
        // MSAA Resolve buffers
        glGenFramebuffers(1, &msaaFBO);
        glBindFramebuffer(GL_FRAMEBUFFER, msaaFBO);
        
        // depth storage
        glGenRenderbuffers(1, &msaaFBODepthAttachment);
        glBindRenderbuffer(GL_RENDERBUFFER_EXT, msaaFBODepthAttachment);
        glRenderbufferStorageMultisample(GL_RENDERBUFFER, self.antialiasFactor, GL_DEPTH_COMPONENT, width, height);
        glBindRenderbuffer(GL_RENDERBUFFER, 0);
        
        // color MSAA storage
        glGenRenderbuffers(1, &msaaFBOColorAttachment);
        glBindRenderbuffer(GL_RENDERBUFFER, msaaFBOColorAttachment);
        glRenderbufferStorageMultisample(GL_RENDERBUFFER, self.antialiasFactor, GL_RGBA, width, height);
        glBindRenderbuffer(GL_RENDERBUFFER, 0);

        // attach our MSAA render storage and depth storage  to our msaaFrameBuffer
        glFramebufferRenderbufferEXT(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, msaaFBOColorAttachment);
        glFramebufferRenderbufferEXT(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, msaaFBODepthAttachment);
        
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if(status != GL_FRAMEBUFFER_COMPLETE)
        {
            NSLog(@"could not create FBO - bailing");
        }

        createdGLResources = YES;
    }
    
    // Re-assign our MSAA resolve color attachment to our current IOSurfaceID
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    
    if(fboColorAttachment)
        glDeleteTextures(1, &fboColorAttachment);
    
    // color storage
    glGenTextures(1, &fboColorAttachment);
    glBindTexture(GL_TEXTURE_RECTANGLE_EXT, fboColorAttachment);
    
    // Back bound texture with IOSurface
    CGLTexImageIOSurface2D(self.context.CGLContextObj,
                           GL_TEXTURE_RECTANGLE_EXT,
                           GL_RGBA,
                           (GLsizei) CVPixelBufferGetWidth(pixelBuffer),
                           (GLsizei) CVPixelBufferGetHeight(pixelBuffer),
                           GL_BGRA,
                           GL_UNSIGNED_INT_8_8_8_8_REV,
                           CVPixelBufferGetIOSurface(pixelBuffer),
                           0);
    
    // attach texture to framebuffer
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_RECTANGLE_EXT, fboColorAttachment, 0);
    
    // things go according to plan?
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if(status != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"could not create FBO - bailing");
    }
    
//    glBindTexture(GL_TEXTURE_RECTANGLE_EXT, 0);
//    glBindFramebuffer(GL_FRAMEBUFFER, 0);

}

@end
