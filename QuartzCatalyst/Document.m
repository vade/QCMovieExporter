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
//#import "Shader.h"

@interface Document ()
{
    // Due to lack of Multisample texture samplers
    // and due to the lack of IOSurface supporting
    // Depth Component texture backing
    // We have to resort to:
    // 1) Rendering QC into a multisample storage FBO
    // 2) Blitting said FBO to FBO attached with single sample textures for MSAA resolve
    // 3) Rendering those textures through a shader pass to get linearized depth
    // to our IOSurface
    
    // Maybe its better to blit to depth and do PBO readback and forget IOSurface
    // In totality?
    
    // Multisampled FBO
    GLuint msaaFBO;

    // Multisample Storage Buffers
    GLuint msaaFBODepthAttachment;
    GLuint msaaFBOColorAttachment;
    
    // Blit target from MSAA
    GLuint blitFBO;
    GLuint blitFBODepthAttachment;
    GLuint blitFBOColorAttachment;
    
    // Backed by IOSurfaces
    GLuint fbo;
    GLuint fboColorAttachment;
    GLuint fboDepthAttachment;

    // Shader converts depth samples to linear color samples
    GLuint shaderProgram;
    
    BOOL createdGLResources;
}

// Rendering
@property (readwrite, strong) NSOpenGLContext* context;
@property (readwrite, strong) QCRenderer* renderer;
@property (readwrite, strong) QCComposition* composition;
@property (readwrite, assign) BOOL renderDepth;

// Movie Writing
@property (readwrite, assign) NSInteger durationH, durationM, durationS, duration;
@property (readwrite, strong) AVAssetWriter* assetWriter;
@property (readwrite, strong) AVAssetWriterInput* assetWriterVideoInput;
@property (readwrite, strong) AVAssetWriterInputPixelBufferAdaptor* assetWriterPixelBufferAdaptor;
@property (readwrite, strong) AVAssetWriter* assetWriterDepth;
@property (readwrite, strong) AVAssetWriterInput* assetWriterVideoInputDepth;
@property (readwrite, strong) AVAssetWriterInputPixelBufferAdaptor* assetWriterPixelBufferAdaptorDepth;
@property (atomic, readwrite, assign) BOOL shouldCanel;

@property (readwrite, assign) CMTime frameInterval;
@property (readwrite, assign) NSSize videoResolution;
@property (readwrite, strong) NSString* codecString;
@property (readwrite, assign) int antialiasFactor;

// Interface
@property (readwrite, strong) IBOutlet NSButton* renderButton;
@property (readwrite, strong) IBOutlet NSProgressIndicator* renderProgress;
@property (readwrite, strong) IBOutlet NSPopUpButton* frameRateMenu;
@property (readwrite, strong) IBOutlet NSPopUpButton* resolutionMenu;
@property (readwrite, strong) IBOutlet NSPopUpButton* codecMenu;
@property (readwrite, strong) IBOutlet NSPopUpButton* antialiasMenu;
@property (readwrite, strong) IBOutlet NSButton* codecOptionsButton;
@property (readwrite, strong) IBOutlet NSButton* enablePreviewButton;
@property (readwrite, strong) IBOutlet NSWindow* codecOptionsWindow;

// Codec Options interface
@property (readwrite, strong) IBOutlet NSSlider* jpegQualitySlider;
@property (readwrite, strong) NSNumber* jpegQuality;

@property (readwrite, strong) IBOutlet NSSlider* h264QualitySlider;
@property (readwrite, strong) NSNumber* h264Quality;
@property (readwrite, strong) IBOutlet NSTextField* h264Bitrate;


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
        self.frameInterval = CMTimeMake(1, 60);
        self.videoResolution = NSMakeSize(1920, 1080);
        self.codecString = AVVideoCodecAppleProRes4444;
        self.antialiasFactor = 8;
        self.renderDepth = NO;
        
        self.jpegQuality = @(0.8);
        self.h264Quality = @(0.8);
        
        const NSOpenGLPixelFormatAttribute attributes[] = {
            NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersionLegacy,
            NSOpenGLPFAAllowOfflineRenderers,
            NSOpenGLPFAAccelerated,
            NSOpenGLPFAColorSize, 32,
            NSOpenGLPFADepthSize, 24,
            NSOpenGLPFAAcceleratedCompute,
            NSOpenGLPFANoRecovery,
            (NSOpenGLPixelFormatAttribute)0,
        };

        NSOpenGLPixelFormat* pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
        if(pixelFormat)
        {
            self.context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
            
            if(self.context)
            {
                NSLog(@"loaded context");
            }
            else
            {
                return nil;
            }
        }
        else
        {
            NSLog(@"Unable to init GL Pixel Format - falling back");
        }
		
        // Default duration (30 seconds)
        self.durationH = 0;
        self.durationM = 0;
        self.durationS = 30;
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
    self.renderButton.enabled = YES;
    self.codecMenu.enabled = YES;
    self.resolutionMenu.enabled = YES;
    self.frameRateMenu.enabled = YES;
    self.codecOptionsButton.enabled = YES;
    self.antialiasMenu.enabled = YES;

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
    
    [self.resolutionMenu removeAllItems];
    [self makeMenu:self.resolutionMenu representedObjects:resolutions titles:resolutionNames selector:@selector(setResolution:)];

    NSArray* tripleHeadResolutions = @[ [NSValue valueWithSize:NSMakeSize(640 * 3, 480)],
                                        [NSValue valueWithSize:NSMakeSize(1280 * 3, 720)],
                                        [NSValue valueWithSize:NSMakeSize(1920 * 3, 1080)],
                                        [NSValue valueWithSize:NSMakeSize(2048 * 3, 1080)],
                                        [NSValue valueWithSize:NSMakeSize(3840 * 3, 2160)],
                                        [NSValue valueWithSize:NSMakeSize(4096 * 3, 2160)],
                                        ];
    
    NSArray* tripleHeadResolutionNames = @[ @"TripleHead 480P",
                                  @"TripleHead 720P",
                                  @"TripleHead 1080P",
                                  @"TripleHead 2K",
                                  @"TripleHead UHD",
                                  @"TripleHead 4K",
                                  ];
    
    [self.resolutionMenu.menu addItem:[NSMenuItem separatorItem]];

    [self makeMenu:self.resolutionMenu representedObjects:tripleHeadResolutions titles:tripleHeadResolutionNames selector:@selector(setResolution:)];

    // select defaults
    [self.resolutionMenu selectItem:self.resolutionMenu.menu.itemArray[2]];
    
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
    
    [self.frameRateMenu removeAllItems];
    [self makeMenu:self.frameRateMenu representedObjects:frameRates titles:frameRateNames selector:@selector(setFrameRate:)];
    
    // select defaults
    [self.frameRateMenu selectItem:self.frameRateMenu.menu.itemArray[4]];

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
    
    [self.codecMenu removeAllItems];
    [self makeMenu:self.codecMenu representedObjects:codecs titles:codecNames selector:@selector(setCodec:)];

    // select defaults
    [self.codecMenu selectItem:self.codecMenu.menu.itemArray[0]];
    
    NSArray* aaName = @[@"None",
                        @"4x",
                        @"8x",
                        ];
    
    NSArray* aaAmount = @[@(1),
                          @(4),
                          @(8),
                          ];
    
    [self.antialiasMenu removeAllItems];
    [self makeMenu:self.antialiasMenu representedObjects:aaAmount titles:aaName selector:@selector(setAntialiasAmount:)];
    
    // select defaults
    [self.antialiasMenu selectItem:self.antialiasMenu.menu.itemArray[2]];
}

- (void) makeMenu:(NSPopUpButton*)popUp representedObjects:(NSArray*)objects titles:(NSArray*)titles selector:(SEL)selector
{
    for(int i = 0; i < objects.count; i++)
    {
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:titles[i] action:selector keyEquivalent:@""];
        [item setRepresentedObject:objects[i]];
        [popUp.menu addItem:item];
    }
}

- (IBAction) chooseRenderDestination:(NSButton *)sender
{
    if(sender.tag == 0)
    {
        NSSavePanel* savePanel = [NSSavePanel savePanel];
        
        savePanel.allowedFileTypes = @[@"mov"];
        savePanel.nameFieldStringValue = [[self.displayName stringByDeletingPathExtension] stringByAppendingPathExtension:@"mov"];
        [savePanel beginSheetModalForWindow:self.windowControllers[0].window completionHandler:^(NSInteger result) {
            
            if(result == NSFileHandlingPanelOKButton)
            {
                self.assetWriter = [[AVAssetWriter alloc] initWithURL:savePanel.URL fileType:AVFileTypeQuickTimeMovie error:nil];

                if(self.renderDepth)
                {
                    // Modify URL to contain depth
                    NSString* depthURLPath = [savePanel.URL path];
                    depthURLPath = [depthURLPath stringByDeletingPathExtension];
                    depthURLPath = [depthURLPath stringByAppendingString:@"_depth"];
                    depthURLPath = [depthURLPath stringByAppendingPathExtension:@"mov"];
                    self.assetWriterDepth = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:depthURLPath] fileType:AVFileTypeQuickTimeMovie error:nil];

                }
                self.codecMenu.enabled = YES;
                self.antialiasMenu.enabled = YES;
                self.resolutionMenu.enabled = YES;
                self.frameRateMenu.enabled = YES;
                self.codecOptionsButton.enabled = NO;
                
                [self render:sender];
                
                sender.tag = sender.tag == 0 ? 1 : 0;
            }
        }];
    }
    else
    {
        // Note we want to bail cleanly, so we dont call
        // cancel on our asset reader (only if we have an error)
        self.shouldCanel = YES;
    }
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
        
        if([self.codecString isEqualToString:AVVideoCodecJPEG])
        {
            videoOutputSettings = [videoOutputSettings mutableCopy];
            NSDictionary* jpegSettings = @{AVVideoQualityKey : self.jpegQuality};
            [(NSMutableDictionary*)videoOutputSettings addEntriesFromDictionary:@{AVVideoCompressionPropertiesKey : jpegSettings}];
        }

        if([self.codecString isEqualToString:AVVideoCodecH264])
        {
            videoOutputSettings = [videoOutputSettings mutableCopy];
            NSDictionary* h264Settings =  @{AVVideoAverageBitRateKey : self.h264Bitrate};
            [(NSMutableDictionary*)videoOutputSettings addEntriesFromDictionary:@{AVVideoCompressionPropertiesKey : h264Settings}];
        }
        
        NSDictionary* pixelBufferAttributes = @{ (NSString*) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                                 (NSString*) kCVPixelBufferWidthKey : @(self.videoResolution.width),
                                                 (NSString*) kCVPixelBufferHeightKey : @(self.videoResolution.height),
                                                 (NSString*) kCVPixelBufferOpenGLCompatibilityKey : @(YES),
                                                 (NSString*) kCVPixelBufferIOSurfacePropertiesKey : @{ },
                                                 (NSString*) kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey : @(YES),
                                                 (NSString*) kCVPixelBufferIOSurfaceOpenGLFBOCompatibilityKey : @(YES),
                                                 };
        self.assetWriterVideoInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                                                    outputSettings:videoOutputSettings];
        
        self.assetWriterPixelBufferAdaptor = [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:self.assetWriterVideoInput sourcePixelBufferAttributes:pixelBufferAttributes];
        
        if([self.assetWriter canAddInput:self.assetWriterVideoInput])
        {
            [self.assetWriter addInput:self.assetWriterVideoInput];
        }
        
        if(self.renderDepth)
        {
            self.assetWriterVideoInputDepth = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                                                             outputSettings:videoOutputSettings];
            
            self.assetWriterPixelBufferAdaptorDepth = [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:self.assetWriterVideoInputDepth sourcePixelBufferAttributes:pixelBufferAttributes];
            
            if([self.assetWriterDepth canAddInput:self.assetWriterVideoInputDepth])
            {
                [self.assetWriterDepth addInput:self.assetWriterVideoInputDepth];
            }
        }
        
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
			
            // Syncronous activity - effectively disables AppNap / re-enables AppNap on completion
			[NSProcessInfo.processInfo performActivityWithOptions:NSActivityUserInitiated reason:@"Render" usingBlock:^{
				[self.assetWriter startWriting];
				[self.assetWriter startSessionAtSourceTime:kCMTimeZero];
                
                if(self.renderDepth)
                {
                    [self.assetWriterDepth startWriting];
                    [self.assetWriterDepth startSessionAtSourceTime:kCMTimeZero];
                }
                
				[self renderAndWrite];
			}];
		});
	}
}


- (void) renderAndWrite
{
    CMTime duration = CMTimeMakeWithSeconds(self.duration, 600);
    __block CMTime currentTime = kCMTimeZero;
    __block NSUInteger frameNumber = 0;
    
    dispatch_semaphore_t finishedSignal = dispatch_semaphore_create(0);
    dispatch_queue_t videoRenderQueue = dispatch_queue_create("videoRenderQueue", DISPATCH_QUEUE_SERIAL);

    __weak typeof(self) weakSelf = self;
    
    // For now, we use our Color asset writer to also enqueue our depth.
    // Unclear the best way to handle this
    [self.assetWriterVideoInput requestMediaDataWhenReadyOnQueue:videoRenderQueue usingBlock:^{

        __strong typeof(weakSelf) strongSelf = weakSelf;

        // Are we above our duration, or do we bail nicely?
        if( CMTIME_COMPARE_INLINE(currentTime, >=,  duration) || strongSelf.shouldCanel)
        {
            [strongSelf.assetWriterVideoInput markAsFinished];
            
            if(strongSelf.renderDepth)
                [strongSelf.assetWriterVideoInputDepth markAsFinished];

            strongSelf.shouldCanel = NO;

            dispatch_semaphore_signal(finishedSignal);
        }
        else if (strongSelf.assetWriter.status == AVAssetWriterStatusCancelled || strongSelf.assetWriter.status == AVAssetWriterStatusFailed)
        {
            [strongSelf.assetWriterVideoInput markAsFinished];
            
            if(strongSelf.renderDepth)
                [strongSelf.assetWriterVideoInputDepth markAsFinished];

            dispatch_semaphore_signal(finishedSignal);
        }
        else if (strongSelf.assetWriter.status == AVAssetWriterStatusWriting)
        {
            // assign context
            [strongSelf.context makeCurrentContext];
        
            // create color texture attachment from IOSurface backed CVPixelBuffer
            CVPixelBufferRef ioSurfaceBackedPixelBufferColor = NULL;
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, strongSelf.assetWriterPixelBufferAdaptor.pixelBufferPool, &ioSurfaceBackedPixelBufferColor);

            //create depth texture attachment from IOSurface backed CVPixelBuffer
            CVPixelBufferRef ioSurfaceBackedPixelBufferDepth = NULL;
            if(strongSelf.renderDepth)
            {
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, strongSelf.assetWriterPixelBufferAdaptorDepth.pixelBufferPool, &ioSurfaceBackedPixelBufferDepth);
            }
            
            GLsizei width = (GLsizei) CVPixelBufferGetWidth(ioSurfaceBackedPixelBufferColor);
            GLsizei height = (GLsizei) CVPixelBufferGetHeight(ioSurfaceBackedPixelBufferColor);

            // Need to create Renderer on same thread we use it on, (ugh)
            if(strongSelf.renderer == nil)
            {
                CGColorSpaceRef cspace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
                
                strongSelf.renderer = [[QCRenderer alloc] initWithCGLContext:strongSelf.context.CGLContextObj
                                                                 pixelFormat:strongSelf.context.pixelFormat.CGLPixelFormatObj
                                                                  colorSpace:cspace
                                                                 composition:strongSelf.composition];
                CGColorSpaceRelease(cspace);
            }
            
            // create GL resources if we need it
            [strongSelf createFBOWithCVPixelBufferColorAttachment:ioSurfaceBackedPixelBufferColor depthAttachment:ioSurfaceBackedPixelBufferDepth];
            
#pragma mark - Render MSAA Pass
            
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

#pragma mark - MSAA Resolve Blit Pass
            
            // MSAA Resolve / Blit to IOSurface attachment / FBO
            glBindFramebuffer(GL_READ_FRAMEBUFFER, msaaFBO);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, blitFBO);
            
            // blit the whole extent from read to draw
            glBlitFramebufferEXT(0, 0, width, height, 0, 0, width, height, GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT , GL_NEAREST);

            // GL Syncronize contents of Blit Target
            glFlushRenderAPPLE();

#pragma mark - Color and Depth to IOSurface Pass
            
            glBindFramebuffer(GL_FRAMEBUFFER, fbo);
            
            glViewport(0, 0, width, height);
            glOrtho(0, width, 0, height, -1, 1);

            glMatrixMode(GL_PROJECTION);
            glLoadIdentity();
            
            glMatrixMode(GL_MODELVIEW);
            glLoadIdentity();

            glClear(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT);
            
            // Render Color to color, depth to color 1

            // TODO: Bind Shader to normalize depth and blit to MRT Color 1
            glUseProgram(shaderProgram);
            
            if(strongSelf.renderDepth)
            {
                GLenum drawBuffers[] = { GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1};
                glDrawBuffers(2, drawBuffers);

                glEnable(GL_TEXTURE_RECTANGLE_EXT);
                glActiveTexture(GL_TEXTURE1);
                glBindTexture(GL_TEXTURE_RECTANGLE_EXT, blitFBODepthAttachment);
                glUniform1i(glGetUniformLocation(shaderProgram, "depth"), 1);
            }
            
            glEnable(GL_TEXTURE_RECTANGLE_EXT);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_RECTANGLE_EXT, blitFBOColorAttachment);
            glUniform1i(glGetUniformLocation(shaderProgram, "color"), 0);

            
            glColor4f(1.0, 1.0, 1.0, 1.0);
            
            // move to VA for rendering
            GLfloat tex_coords[] =
            {
                width, height,
                0.0,height,
                0.0,0.0,
                width, 0.0
            };
            
            GLfloat verts[] =
            {
                1.0,1.0,
                -1.0,1.0,
                -1.0,-1.0,
                1.0,-1.0
            };
            
            glEnableClientState( GL_TEXTURE_COORD_ARRAY );
            glTexCoordPointer(2, GL_FLOAT, 0, tex_coords );
            glEnableClientState(GL_VERTEX_ARRAY);
            glVertexPointer(2, GL_FLOAT, 0, verts );
            glDrawArrays( GL_TRIANGLE_FAN, 0, 4 );	// TODO: GL_QUADS or GL_TRIANGLE_FAN?

            glUseProgram(0);

            glPopAttrib();
            
            // GL Syncronize / Readback IOSurface to pixel buffer
            // Note glFlushRenderApple / glFlush should be sufficient as I understand it
            // but we appear to get some flicker with them.
            glFlushRenderAPPLE();
            
            
            // Write color
            CVPixelBufferRef flippedIoSurfaceBackedPixelBuffer = [strongSelf createFlippedPixelBufferIfNecessary:ioSurfaceBackedPixelBufferColor fromPool:strongSelf.assetWriterPixelBufferAdaptor.pixelBufferPool];
            
            // Write pixel buffer to movie
            if(![strongSelf.assetWriterPixelBufferAdaptor appendPixelBuffer:flippedIoSurfaceBackedPixelBuffer withPresentationTime:currentTime])
                NSLog(@"Unable to write color frame at time: %@", CMTimeCopyDescription(kCFAllocatorDefault, currentTime));
            

            CVPixelBufferRef flippedIoSurfaceBackedPixelBufferDepth = NULL;
            
            if(strongSelf.renderDepth)
            {
                flippedIoSurfaceBackedPixelBufferDepth = [strongSelf createFlippedPixelBufferIfNecessary:ioSurfaceBackedPixelBufferDepth fromPool:strongSelf.assetWriterPixelBufferAdaptorDepth.pixelBufferPool];

                if(![strongSelf.assetWriterPixelBufferAdaptorDepth appendPixelBuffer:flippedIoSurfaceBackedPixelBufferDepth withPresentationTime:currentTime])
                    NSLog(@"Unable to write depth frame at time: %@", CMTimeCopyDescription(kCFAllocatorDefault, currentTime));

            }
            
            CVPixelBufferRef previewBuffer = (strongSelf.renderDepth && flippedIoSurfaceBackedPixelBufferDepth) ? flippedIoSurfaceBackedPixelBuffer : flippedIoSurfaceBackedPixelBuffer;
            
            // Update UI on main queue
            CVPixelBufferRetain(previewBuffer);

            dispatch_async(dispatch_get_main_queue(), ^{
                
                if(strongSelf.enablePreviewButton.state == NSOnState)
                    [strongSelf.preview displayCVPIxelBuffer:previewBuffer];
                
                CVPixelBufferRelease(previewBuffer);
                
                strongSelf.renderProgress.doubleValue = CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(duration);
            });
            
            
            // Clean up
            
            CVPixelBufferRelease(flippedIoSurfaceBackedPixelBuffer);
            
            // increment time
            currentTime = CMTimeAdd(currentTime, strongSelf.frameInterval);
            frameNumber++;
        }
    }];
    
    dispatch_semaphore_wait(finishedSignal, DISPATCH_TIME_FOREVER);
    
    [self.assetWriter finishWritingWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[self.assetWriter.outputURL]];
        });
    }];
    
    if(self.renderDepth)
    {
        [self.assetWriterDepth finishWritingWithCompletionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[self.assetWriterDepth.outputURL]];
            });

        }];
    }
}

- (void) createFBOWithCVPixelBufferColorAttachment:(CVPixelBufferRef)colorPixelBuffer depthAttachment:(CVPixelBufferRef)depthPixelBuffer
{
    if(!createdGLResources)
    {
        
        // TODO: Create Shader to normalize depth and blit to MRT Color 1
//        self.shader = [[Shader alloc] initWithShadersInAppBundle:@"colorAndDepth" forContext:self.context.CGLContextObj];
        
        [self loadShader];
        
        GLsizei width = (GLsizei) CVPixelBufferGetWidth(colorPixelBuffer);
        GLsizei height = (GLsizei) CVPixelBufferGetHeight(colorPixelBuffer);
        
        // MSAA Render
        glGenFramebuffers(1, &msaaFBO);
        glBindFramebuffer(GL_FRAMEBUFFER, msaaFBO);
        
        // MSAA depth storage
        glGenRenderbuffers(1, &msaaFBODepthAttachment);
        glBindRenderbuffer(GL_RENDERBUFFER_EXT, msaaFBODepthAttachment);
        glRenderbufferStorageMultisample(GL_RENDERBUFFER, self.antialiasFactor, GL_DEPTH_COMPONENT, width, height);
        glBindRenderbuffer(GL_RENDERBUFFER, 0);
        
        // MSAA color  storage
        glGenRenderbuffers(1, &msaaFBOColorAttachment);
        glBindRenderbuffer(GL_RENDERBUFFER, msaaFBOColorAttachment);
        glRenderbufferStorageMultisample(GL_RENDERBUFFER, self.antialiasFactor, GL_RGBA, width, height);
        glBindRenderbuffer(GL_RENDERBUFFER, 0);

        // attach our MSAA render storage and depth storage  to our msaaFrameBuffer
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, msaaFBOColorAttachment);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, msaaFBODepthAttachment);
        
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if(status != GL_FRAMEBUFFER_COMPLETE)
        {
            NSLog(@"could not create MSAA FBO - bailing");
        }

        // MSAA Resolve buffers
        glGenFramebuffers(1, &blitFBO);
        glBindFramebuffer(GL_FRAMEBUFFER, blitFBO);
        
        // MSAA depth storage
        glGenTextures(1, &blitFBODepthAttachment);
        glBindTexture(GL_TEXTURE_RECTANGLE_EXT, blitFBODepthAttachment);
        glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_DEPTH_COMPONENT, width, height, 0, GL_DEPTH_COMPONENT, GL_UNSIGNED_BYTE, NULL);

        glGenTextures(1, &blitFBOColorAttachment);
        glBindTexture(GL_TEXTURE_RECTANGLE_EXT, blitFBOColorAttachment);
        glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGBA, width, height, 0, GL_BGRA , GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
        
        // attach our MSAA render storage and depth storage  to our msaaFrameBuffer
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_RECTANGLE_EXT, blitFBOColorAttachment, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_RECTANGLE_EXT, blitFBODepthAttachment, 0);
        
        glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if(status != GL_FRAMEBUFFER_COMPLETE)
        {
            NSLog(@"could not create blit FBO - bailing");
        }
        
        // final FBO target for IOSurface
        glGenFramebuffers(1, &fbo);
        
        createdGLResources = YES;
    }
    
    // Re-assign our MSAA resolve color/depth attachments to our current IOSurfaceID
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
                           (GLsizei) CVPixelBufferGetWidth(colorPixelBuffer),
                           (GLsizei) CVPixelBufferGetHeight(colorPixelBuffer),
                           GL_BGRA,
                           GL_UNSIGNED_INT_8_8_8_8_REV,
                           CVPixelBufferGetIOSurface(colorPixelBuffer),
                           0);
    
    // attach texture to framebuffer
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_RECTANGLE_EXT, fboColorAttachment, 0);
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if(status != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"could not Attach Color to FBO - bailing %i", status);
    }
    
    if(self.renderDepth)
    {
        // Depth Storage - since IOSurface does not support
        if(fboDepthAttachment)
            glDeleteTextures(1, &fboDepthAttachment);
        
        glGenTextures(1, &fboDepthAttachment);
        glBindTexture(GL_TEXTURE_RECTANGLE_EXT, fboDepthAttachment);
        CGLTexImageIOSurface2D(self.context.CGLContextObj,
                               GL_TEXTURE_RECTANGLE_EXT,
                               GL_RGBA,
                               (GLsizei) CVPixelBufferGetWidth(depthPixelBuffer),
                               (GLsizei) CVPixelBufferGetHeight(depthPixelBuffer),
                               GL_BGRA,
                               GL_UNSIGNED_INT_8_8_8_8_REV,
                               CVPixelBufferGetIOSurface(depthPixelBuffer),
                               0);
        
        // attach texture to framebuffer
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_RECTANGLE_EXT, fboDepthAttachment, 0);
        status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if(status != GL_FRAMEBUFFER_COMPLETE)
        {
            NSLog(@"could not Attach Color 2 to FBO - bailing %i", status);
        }
    }
}

- (CVPixelBufferRef) createFlippedPixelBufferIfNecessary:(CVPixelBufferRef)input fromPool:(CVPixelBufferPoolRef)pool
{
    if(CVImageBufferIsFlipped(input))
    {
        // Create a new destination pixel buffer from our pool,
        CVPixelBufferRef flipped;
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &flipped);
        
        // Lock base addresses for reading / writing
        CVPixelBufferLockBaseAddress(input, kCVPixelBufferLock_ReadOnly);
        CVPixelBufferLockBaseAddress(flipped, 0);
        
        // make vImage buffers
        vImage_Buffer source;
        source.data = CVPixelBufferGetBaseAddress(input);
        source.rowBytes = CVPixelBufferGetBytesPerRow(input);
        source.width = CVPixelBufferGetWidth(input);
        source.height = CVPixelBufferGetHeight(input);
        
        vImage_Buffer dest;
        dest.data = CVPixelBufferGetBaseAddress(flipped);
        dest.rowBytes = CVPixelBufferGetBytesPerRow(flipped);
        dest.width = CVPixelBufferGetWidth(flipped);
        dest.height = CVPixelBufferGetHeight(flipped);
        
        vImageVerticalReflect_ARGB8888(&source, &dest, kvImageNoFlags);
        
        // Clean Up
        CVPixelBufferUnlockBaseAddress(input, kCVPixelBufferLock_ReadOnly);
        CVPixelBufferUnlockBaseAddress(flipped, 0);

        // Cleanup our input, we no longer need it
        CVPixelBufferRelease(input);
        
        return flipped;
    }
    
    return input;
}

- (void)loadShader
{
    GLuint vertexShader;
    GLuint fragmentShader;
    
    vertexShader   = [self compileShaderOfType:GL_VERTEX_SHADER   file:[[NSBundle mainBundle] pathForResource:@"colorAndDepth" ofType:@"vert"]];
    fragmentShader = [self compileShaderOfType:GL_FRAGMENT_SHADER file:[[NSBundle mainBundle] pathForResource:@"colorAndDepth" ofType:@"frag"]];
    
    if (0 != vertexShader && 0 != fragmentShader)
    {
        shaderProgram = glCreateProgram();
//        GetError();
        
        glAttachShader(shaderProgram, vertexShader  );
//        GetError();
        glAttachShader(shaderProgram, fragmentShader);
//        GetError();
        
        [self linkProgram:shaderProgram];
        
//        positionUniform = glGetUniformLocation(shaderProgram, "p");
//        GetError();
//        if (positionUniform < 0)
//        {
//            [NSException raise:kFailedToInitialiseGLException format:@"Shader did not contain the 'p' uniform."];
//        }
//        colourAttribute = glGetAttribLocation(shaderProgram, "colour");
//        GetError();
//        if (colourAttribute < 0)
//        {
//            [NSException raise:kFailedToInitialiseGLException format:@"Shader did not contain the 'colour' attribute."];
//        }
//        positionAttribute = glGetAttribLocation(shaderProgram, "position");
//        GetError();
//        if (positionAttribute < 0)
//        {
//            [NSException raise:kFailedToInitialiseGLException format:@"Shader did not contain the 'position' attribute."];
//        }
        
        glDeleteShader(vertexShader);
//        GetError();
        glDeleteShader(fragmentShader);
//        GetError();
    }
//    else
//    {
//        [NSException raise:kFailedToInitialiseGLException format:@"Shader compilation failed."];
//    }
}

- (GLuint)compileShaderOfType:(GLenum)type file:(NSString *)file
{
    GLuint shader;
    const GLchar *source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSASCIIStringEncoding error:nil] cStringUsingEncoding:NSASCIIStringEncoding];
    
    if (nil == source)
    {
        NSLog(@"No Source");
//        [NSException raise:kFailedToInitialiseGLException format:@"Failed to read shader file %@", file];
    }
    
    shader = glCreateShader(type);
//    GetError();
    glShaderSource(shader, 1, &source, NULL);
//    GetError();
    glCompileShader(shader);
//    GetError();
    
#if defined(DEBUG)
    GLint logLength;
    
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
//    GetError();
    if (logLength > 0)
    {
        GLchar *log = malloc((size_t)logLength);
        glGetShaderInfoLog(shader, logLength, &logLength, log);
//        GetError();
        NSLog(@"Shader compilation failed with error:\n%s", log);
        free(log);
    }
#endif
    
    GLint status;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
//    GetError();
    if (0 == status)
    {
        glDeleteShader(shader);
//        GetError();
        NSLog(@"Failed to compile shader");

//        [NSException raise:kFailedToInitialiseGLException format:@"Shader compilation failed for file %@", file];
    }
    
    return shader;
}

- (void)linkProgram:(GLuint)program
{
    glLinkProgram(program);
//    GetError();
    
#if defined(DEBUG)
    GLint logLength;
    
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
//    GetError();
    if (logLength > 0)
    {
        GLchar *log = malloc((size_t)logLength);
        glGetProgramInfoLog(program, logLength, &logLength, log);
//        GetError();
        NSLog(@"Shader program linking failed with error:\n%s", log);
        free(log);
    }
#endif
    
    GLint status;
    glGetProgramiv(program, GL_LINK_STATUS, &status);
//    GetError();
    if (0 == status)
    {
        NSLog(@"Failed to link shader program");

//        [NSException raise:kFailedToInitialiseGLException format:@"Failed to link shader program"];
    }
}

- (void)validateProgram:(GLuint)program
{
    GLint logLength;
    
    glValidateProgram(program);
//    GetError();
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
//    GetError();
    if (logLength > 0)
    {
        GLchar *log = malloc((size_t)logLength);
        glGetProgramInfoLog(program, logLength, &logLength, log);
//        GetError();
        NSLog(@"Program validation produced errors:\n%s", log);
        free(log);
    }
    
    GLint status;
    glGetProgramiv(program, GL_VALIDATE_STATUS, &status);
//    GetError();
    if (0 == status)
    {
        NSLog(@"Failed to link shader program");

//        [NSException raise:kFailedToInitialiseGLException format:@"Failed to link shader program"];
    }
}

@end
