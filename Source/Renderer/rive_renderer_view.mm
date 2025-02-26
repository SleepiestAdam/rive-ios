#include "rive_renderer_view.hh"

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#if TARGET_OS_IPHONE || TARGET_VISION_OS || TARGET_OS_TV
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

#import "RivePrivateHeaders.h"
#import <RenderContext.h>
#import <RenderContextManager.h>
// We manually need to provide this as our build-time config isn't shared with
// xcode.
#define WITH_RIVE_AUDIO
#include "rive/audio/audio_engine.hpp"

#if TARGET_OS_VISION
@implementation RiveMTKView
{
    id<CAMetalDrawable> _currentDrawable;
}

@synthesize enableSetNeedsDisplay;

@synthesize paused;

@synthesize sampleCount;

@synthesize depthStencilPixelFormat;

- (instancetype)initWithFrame:(CGRect)frameRect device:(id<MTLDevice>)device
{
    self = [super initWithFrame:frameRect];
    self.device = device;
    return self;
}

+ (Class)layerClass
{
    return [CAMetalLayer class];
}

- (nullable id<MTLDevice>)device
{
    return [self metalLayer].device;
}

- (void)setDevice:(nullable id<MTLDevice>)device
{
    [self metalLayer].device = device;
}

- (CAMetalLayer*)metalLayer
{
    return (CAMetalLayer*)self.layer;
}

- (void)setFramebufferOnly:(BOOL)framebufferOnly
{
    [self metalLayer].framebufferOnly = framebufferOnly;
}

- (BOOL)framebufferOnly
{
    return [self metalLayer].framebufferOnly;
}

- (void)setCurrentDrawable:(id<CAMetalDrawable> _Nullable)currentDrawable
{
    return;
}

- (nullable id<CAMetalDrawable>)currentDrawable
{
    if (_currentDrawable == nil)
    {
        _currentDrawable = [self metalLayer].nextDrawable;
    }
    return _currentDrawable;
}

- (void)setColorPixelFormat:(MTLPixelFormat)colorPixelFormat
{
    [self metalLayer].pixelFormat = colorPixelFormat;
}

- (MTLPixelFormat)colorPixelFormat
{
    return [self metalLayer].pixelFormat;
}

- (void)setDrawableSize:(CGSize)drawableSize
{
    [self metalLayer].drawableSize = drawableSize;
}

- (CGSize)drawableSize
{
    return [self metalLayer].drawableSize;
}

- (void)_updateDrawableSizeFromBounds
{
    CGSize newSize = self.bounds.size;
    newSize.width *= self.traitCollection.displayScale;
    newSize.height *= self.traitCollection.displayScale;
    self.drawableSize = newSize;
}

- (void)setContentScaleFactor:(CGFloat)contentScaleFactor
{
    [super setContentScaleFactor:contentScaleFactor];
    [self _updateDrawableSizeFromBounds];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self _updateDrawableSizeFromBounds];
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];
    [self _updateDrawableSizeFromBounds];
}

- (void)setBounds:(CGRect)bounds
{
    [super setBounds:bounds];
    [self _updateDrawableSizeFromBounds];
}

// For some reason, when setNeedsDisplay is called, drawRect is not called
// But, we get a delegate callback when the layer should be displayed,
// so we'll just piggyback off of that and draw for now.
- (void)displayLayer:(CALayer*)layer
{
    _currentDrawable = [self metalLayer].nextDrawable;
    [self drawRect:self.bounds];
}

@end
#else
@implementation RiveMTKView
@end
#endif

@implementation RiveRendererView
{
    RenderContext* _renderContext;
    rive::Renderer* _renderer;
    dispatch_queue_t _renderQueue;
}

- (void)didEnterBackground:(NSNotification*)notification
{
    auto engine = rive::AudioEngine::RuntimeEngine(false);
    if (engine != nil)
    {
        engine->stop();
    }
}

- (void)didEnterForeground:(NSNotification*)notification
{
    auto engine = rive::AudioEngine::RuntimeEngine(false);
    if (engine != nil)
    {
        engine->start();
    }
}

- (instancetype)initWithCoder:(NSCoder*)decoder
{
#if TARGET_OS_IPHONE || TARGET_OS_VISION || TARGET_OS_TV
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(didEnterBackground:)
               name:UIApplicationDidEnterBackgroundNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(didEnterForeground:)
               name:UIApplicationWillEnterForegroundNotification
             object:nil];
#else
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(didEnterBackground:)
               name:NSApplicationDidResignActiveNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(didEnterForeground:)
               name:NSApplicationWillBecomeActiveNotification
             object:nil];
#endif
    self = [super initWithCoder:decoder];

    if (self) {
        // Create a serial queue for rendering
        _renderQueue = dispatch_queue_create("com.rive.renderQueue", DISPATCH_QUEUE_SERIAL);
        
        // Rest of existing initialization
        _renderContext = [[RenderContextManager shared] getDefaultContext];
        assert(_renderContext);
        self.device = [_renderContext metalDevice];

        [self setDepthStencilPixelFormat:_renderContext.depthStencilPixelFormat];
        [self setColorPixelFormat:MTLPixelFormatBGRA8Unorm];
        [self setFramebufferOnly:_renderContext.framebufferOnly];
        [self setSampleCount:1];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frameRect
{
#if TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(didEnterBackground:)
               name:UIApplicationDidEnterBackgroundNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(didEnterForeground:)
               name:UIApplicationWillEnterForegroundNotification
             object:nil];
#else
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(didEnterBackground:)
               name:NSApplicationDidResignActiveNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(didEnterForeground:)
               name:NSApplicationWillBecomeActiveNotification
             object:nil];
#endif
    _renderQueue = dispatch_queue_create("com.rive.renderQueue", DISPATCH_QUEUE_SERIAL);
    _renderContext = [[RenderContextManager shared] getDefaultContext];
    assert(_renderContext);

    auto value = [super initWithFrame:frameRect
                               device:_renderContext.metalDevice];

    [self setDepthStencilPixelFormat:_renderContext.depthStencilPixelFormat];
    [self setColorPixelFormat:MTLPixelFormatBGRA8Unorm];
    [self setFramebufferOnly:_renderContext.framebufferOnly];
    [self setSampleCount:1];

    return value;
}

- (void)alignWithRect:(CGRect)rect
          contentRect:(CGRect)contentRect
            alignment:(RiveAlignment)alignment
                  fit:(RiveFit)fit
{
    // Uses 1 as the scale factor since that is equivalent to the c++ default
    // parameter.
    [self alignWithRect:rect
            contentRect:contentRect
              alignment:alignment
                    fit:fit
            scaleFactor:1];
}

- (void)alignWithRect:(CGRect)rect
          contentRect:(CGRect)contentRect
            alignment:(RiveAlignment)alignment
                  fit:(RiveFit)fit
          scaleFactor:(CGFloat)scaleFactor
{
    rive::AABB frame(rect.origin.x,
                     rect.origin.y,
                     rect.size.width + rect.origin.x,
                     rect.size.height + rect.origin.y);

    rive::AABB content(contentRect.origin.x,
                       contentRect.origin.y,
                       contentRect.size.width + contentRect.origin.x,
                       contentRect.size.height + contentRect.origin.y);

    auto riveFit = [self riveFit:fit];
    auto riveAlignment = [self riveAlignment:alignment];

    _renderer->align(riveFit, riveAlignment, frame, content, scaleFactor);
}
- (void)save
{
    assert(_renderer != nil);
    _renderer->save();
}

- (void)restore
{
    assert(_renderer != nil);
    _renderer->restore();
}

- (void)transform:(float)xx
               xy:(float)xy
               yx:(float)yx
               yy:(float)yy
               tx:(float)tx
               ty:(float)ty
{
    assert(_renderer != nil);
    _renderer->transform(rive::Mat2D{xx, xy, yx, yy, tx, ty});
}

- (void)drawWithArtboard:(RiveArtboard*)artboard
{
    assert(_renderer != nil);
    [artboard artboardInstance]->draw(_renderer);
}

- (void)drawRive:(CGRect)rect size:(CGSize)size
{
    // Intended to be overridden.
}

- (bool)isPaused
{
    return true;
}

- (void)drawInRect:(CGRect)rect
    withCompletion:(_Nullable MTLCommandBufferHandler)completionHandler
{
    // Capture scale on main thread
    CGFloat scale = -1;
#if TARGET_OS_IPHONE
    CGFloat displayScale = self.traitCollection.displayScale;
    if (displayScale > 0)
    {
        scale = displayScale;
    }
#else
    NSWindow* window = self.window;
    if (self.window != nil)
    {
        scale = window.backingScaleFactor;
    }
#endif

    // If we're on the main thread, dispatch to background
    if ([NSThread isMainThread]) {
        dispatch_async(_renderQueue, ^{
            [self drawInRect:rect withCompletion:completionHandler];
        });
        return;
    }

    // Check if we can draw
    if ([_renderContext canDrawInRect:rect
                        drawableSize:self.drawableSize
                               scale:scale] == NO)
    {
        return;
    }

    // Get drawable (now with retry logic built into currentDrawable)
    id<CAMetalDrawable> drawable = [self currentDrawable];
    if (!drawable.texture)
    {
        // If we couldn't get a drawable, schedule another draw
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setNeedsDisplay:YES];
        });
        return;
    }

    _renderer = [_renderContext beginFrame:self];
    if (_renderer != nil)
    {
        _renderer->save();
        [self drawRive:rect size:self.drawableSize];
        _renderer->restore();
    }
    
    // Complete rendering and present
    [_renderContext endFrame:self withCompletion:^(id<MTLCommandBuffer> _Nonnull buffer) {
        // Handle completion on main thread if needed
        if (completionHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(buffer);
            });
        }
        
        // Update view state on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            bool paused = [self isPaused];
            [self setEnableSetNeedsDisplay:paused];
            [self setPaused:paused];
        });
    }];

    _renderer = nil;
}

- (void)drawRect:(CGRect)rect
{
    [super drawRect:rect];
    
    // If we're on the main thread, dispatch to background
    if ([NSThread isMainThread]) {
        dispatch_async(_renderQueue, ^{
            [self drawInRect:rect withCompletion:NULL];
        });
        return;
    }
    
    [self drawInRect:rect withCompletion:NULL];
}

- (rive::Fit)riveFit:(RiveFit)fit
{
    rive::Fit riveFit;

    switch (fit)
    {
        case fill:
            riveFit = rive::Fit::fill;
            break;
        case contain:
            riveFit = rive::Fit::contain;
            break;
        case cover:
            riveFit = rive::Fit::cover;
            break;
        case fitHeight:
            riveFit = rive::Fit::fitHeight;
            break;
        case fitWidth:
            riveFit = rive::Fit::fitWidth;
            break;
        case scaleDown:
            riveFit = rive::Fit::scaleDown;
            break;
        case layout:
            riveFit = rive::Fit::layout;
            break;
        case noFit:
            riveFit = rive::Fit::none;
            break;
    }

    return riveFit;
}

- (rive::Alignment)riveAlignment:(RiveAlignment)alignment
{
    rive::Alignment riveAlignment = rive::Alignment::center;

    switch (alignment)
    {
        case topLeft:
            riveAlignment = rive::Alignment::topLeft;
            break;
        case topCenter:
            riveAlignment = rive::Alignment::topCenter;
            break;
        case topRight:
            riveAlignment = rive::Alignment::topRight;
            break;
        case centerLeft:
            riveAlignment = rive::Alignment::centerLeft;
            break;
        case center:
            riveAlignment = rive::Alignment::center;
            break;
        case centerRight:
            riveAlignment = rive::Alignment::centerRight;
            break;
        case bottomLeft:
            riveAlignment = rive::Alignment::bottomLeft;
            break;
        case bottomCenter:
            riveAlignment = rive::Alignment::bottomCenter;
            break;
        case bottomRight:
            riveAlignment = rive::Alignment::bottomRight;
            break;
    }

    return riveAlignment;
}

- (CGPoint)artboardLocationFromTouchLocation:(CGPoint)touchLocation
                                  inArtboard:(CGRect)artboardRect
                                         fit:(RiveFit)fit
                                   alignment:(RiveAlignment)alignment
{
    // Note, we've offset the frame by the frame.origin before
    // but in testing our touch location seems to already take this into account
    rive::AABB frame(0, 0, self.frame.size.width, self.frame.size.height);

    rive::AABB content(artboardRect.origin.x,
                       artboardRect.origin.y,
                       artboardRect.size.width + artboardRect.origin.x,
                       artboardRect.size.height + artboardRect.origin.y);

    auto riveFit = [self riveFit:fit];
    auto riveAlignment = [self riveAlignment:alignment];
    auto sf = 1.0;
    if (riveFit == rive::Fit::layout)
    {
        sf = frame.width() / artboardRect.size.width;
    }
    rive::Mat2D forward =
        rive::computeAlignment(riveFit, riveAlignment, frame, content, sf);

    rive::Mat2D inverse = forward.invertOrIdentity();

    rive::Vec2D frameLocation(touchLocation.x, touchLocation.y);
    rive::Vec2D convertedLocation = inverse * frameLocation;

    return CGPointMake(convertedLocation.x, convertedLocation.y);
}

// Update currentDrawable implementation to avoid blocking main thread
- (nullable id<CAMetalDrawable>)currentDrawable
{
    // If we're on the main thread, return immediately to avoid blocking
    if ([NSThread isMainThread]) {
        return [self metalLayer].nextDrawable;
    }
    
    // If we're already on a background thread, we can try a few times with shorter timeouts
    for (int attempt = 0; attempt < 3; attempt++) {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block id<CAMetalDrawable> drawable = nil;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            drawable = [self metalLayer].nextDrawable;
            dispatch_semaphore_signal(semaphore);
        });
        
        // Use a shorter timeout (16ms = roughly one frame)
        if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 16 * NSEC_PER_MSEC)) == 0) {
            if (drawable) {
                return drawable;
            }
        }
    }
    
    return nil;
}

@end
