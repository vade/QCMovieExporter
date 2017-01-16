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
@property (readwrite, assign) NSUInteger videoWidth;
@property (readwrite, assign) NSUInteger videoHeight;
@property (readwrite, strong) AVAssetWriter* assetWriter;
@property (readwrite, strong) AVAssetWriterInput* assetWriterVideoInput;
@property (readwrite, strong) AVAssetWriterInputPixelBufferAdaptor* assetWriterPixelBufferAdaptor;

// Interface
@property (readwrite, strong) IBOutlet NSButton* renderButton;
@property (readwrite, strong) IBOutlet NSButton* destinationButton;
@property (readwrite, strong) IBOutlet NSTextField* destinationLabel;
@property (readwrite, strong) IBOutlet NSProgressIndicator* renderProgress;
@property (readwrite, strong) IBOutlet NSPopUpButton* frameRateMenu;
@property (readwrite, strong) IBOutlet NSPopUpButton* resolutionMenu;
@property (readwrite, strong) IBOutlet NSPopUpButton* codecMenu;
@property (readwrite, strong) IBOutlet NSButton* codecOptionsButton;
@property (readwrite, strong) IBOutlet NSButton* enablePreviewButton;

@property (readwrite, strong) IBOutlet SampleLayerView* preview;


@end

@implementation Document

- (instancetype)init {
    self = [super init];
    if (self) {
        // Add your subclass-specific initialization here.
        
        createdGLResources = NO;

        self.renderer = nil;
        
        
        NSOpenGLPixelFormatAttribute attributes[] = {
            NSOpenGLPFAAllowOfflineRenderers,
            NSOpenGLPFAAccelerated,
            NSOpenGLPFAColorSize, 32,
            NSOpenGLPFADepthSize, 24,
//            NSOpenGLPFAMultisample, 1,
//            NSOpenGLPFASampleBuffers, 1,
//            NSOpenGLPFASamples, 4,
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
}

- (IBAction) chooseRenderDestination:(id)sender
{
    NSSavePanel* savePanel = [NSSavePanel savePanel];
    
    savePanel.allowedFileTypes = @[@"mov"];
    
    [savePanel beginSheetModalForWindow:self.windowControllers[0].window completionHandler:^(NSInteger result) {
        
        if(result == NSFileHandlingPanelOKButton)
        {
            self.assetWriter = [[AVAssetWriter alloc] initWithURL:savePanel.URL fileType:AVFileTypeQuickTimeMovie error:nil];
            
            self.videoWidth = 1920;
            self.videoHeight = 1080;
            //                self.videoWidth = 4096;
            //                self.videoHeight = 2160;
            
            NSDictionary* videoOutputSettings = @{ AVVideoCodecKey : AVVideoCodecAppleProRes4444,
                                                   AVVideoWidthKey : @(self.videoWidth),
                                                   AVVideoHeightKey : @(self.videoHeight),
                                                   
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
                                                     (NSString*) kCVPixelBufferWidthKey : @(self.videoWidth),
                                                     (NSString*) kCVPixelBufferHeightKey : @(self.videoHeight),
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
            
            self.renderButton.enabled = YES;
            self.destinationLabel.stringValue = savePanel.URL.path;
            self.codecMenu.enabled = YES;
            self.resolutionMenu.enabled = YES;
            self.frameRateMenu.enabled = YES;
            self.codecOptionsButton.enabled = NO;
        }
    }];
}

- (IBAction) render:(id)sender
{
    // Disable changing options once we render - makes no sense
    self.destinationButton.enabled = NO;
    self.codecMenu.enabled = NO;
    self.resolutionMenu.enabled = NO;
    self.frameRateMenu.enabled = NO;
    self.codecOptionsButton.enabled = NO;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{

        // Syncronous activity - effectively disables AppNap / re-enables AppNap on completion
        [NSProcessInfo.processInfo performActivityWithOptions:NSActivityUserInitiated reason:@"Render" usingBlock:^{
            [self.assetWriter startWriting];
            [self.assetWriter startSessionAtSourceTime:kCMTimeZero];
            [self renderAndWrite];
        }];
    });
}


- (void) renderAndWrite
{
    CMTime frameInterval = CMTimeMake(1, 60);
    CMTime duration = CMTimeMakeWithSeconds(10, 600);
    __block CMTime currentTime = kCMTimeZero;
    __block NSUInteger frameNumber = 0;
    
    dispatch_queue_t videoRenderQueue = dispatch_queue_create("videoRenderQueue", DISPATCH_QUEUE_SERIAL);
    
    dispatch_semaphore_t finishedSignal = dispatch_semaphore_create(0);
    
    [self.assetWriterVideoInput requestMediaDataWhenReadyOnQueue:videoRenderQueue usingBlock:^{
       
        // Are we above our duration?
        if( CMTIME_COMPARE_INLINE(currentTime, >=,  duration))
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

            // TODO: flipping projection matrix fucks up depth buffer
            // flip if we need to
//            if(CVImageBufferIsFlipped(ioSurfaceBackedPixelBuffer))
//                glScaled(1, -1, 1);            
            
            glMatrixMode(GL_MODELVIEW);
            glLoadIdentity();

            // render into FBO
            CFStringRef timeString = CMTimeCopyDescription(kCFAllocatorDefault, currentTime);
            NSLog(@"Rendering frame:%lu time: %@", (unsigned long)frameNumber,  timeString);
            CFRelease(timeString);
            
            [self.renderer renderAtTime:CMTimeGetSeconds(currentTime) arguments:nil];

            // GL Syncronize contents of MSAA FBO
            glFinish();

            // MSAA Resolve / Blit to IOSurface attachment / FBO
            glBindFramebuffer(GL_READ_FRAMEBUFFER, msaaFBO);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbo);
            
            // blit the whole extent from read to draw
            glBlitFramebufferEXT(0, 0, width, height, 0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_NEAREST);
            
            // GL Syncronize / Readback IOSurface to pixel buffer
            glFinish();
            
            // restore viewport, matrix
            glPopAttrib();
            
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
            
            // increment time
            currentTime = CMTimeAdd(currentTime, frameInterval);
            frameNumber++;

            
            // Cleanup
            CVPixelBufferRelease(ioSurfaceBackedPixelBuffer);
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
        glRenderbufferStorageMultisample(GL_RENDERBUFFER, 8, GL_DEPTH_COMPONENT, width, height);
        glBindRenderbuffer(GL_RENDERBUFFER, 0);
        
        // color MSAA storage
        glGenRenderbuffers(1, &msaaFBOColorAttachment);
        glBindRenderbuffer(GL_RENDERBUFFER, msaaFBOColorAttachment);
        glRenderbufferStorageMultisample(GL_RENDERBUFFER, 8, GL_RGBA, width, height);
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
