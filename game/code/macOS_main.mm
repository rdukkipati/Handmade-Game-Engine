#include <Cocoa/Cocoa.h>
#include <Metal/Metal.h>

#include <limits.h>
#include <mach-o/dyld.h>

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>

#define internal        static
#define local_persist   static
#define global_variable static

typedef int8_t  i8;
typedef int16_t i16;
typedef int32_t i32;
typedef int64_t i64;
typedef i32     b32;

typedef uint8_t     u8;
typedef uint16_t    u16;
typedef uint32_t    u32;
typedef uint64_t    u64;

typedef float       f32;
typedef double      f64;

global_variable b32 GLOBAL_RUNNING = true;
global_variable void *BitmapMemory = NULL;
global_variable id<MTLTexture> Texture = nil;
global_variable MTLTextureDescriptor *TextureDescriptor;
global_variable id<MTLDevice> Device;
global_variable NSUInteger BytesPerPixel = 4;
global_variable NSUInteger TextureWidth;
global_variable NSUInteger TextureHeight;

// clang-format off
@interface HandmadeApplicationDelegate :
NSObject<NSApplicationDelegate, NSWindowDelegate>
@end
// clang-format on
@implementation HandmadeApplicationDelegate

- (NSSize)windowWillResize:(NSWindow *)Window toSize:(NSSize)FrameSize
{

    NSRect WindowRect  = [Window frame];
    NSRect ContentRect = [Window contentRectForFrameRect:WindowRect];

    f32    WindowMinusContentWidth  = (WindowRect.size.width -
                                       ContentRect.size.width);
    f32    WindowMinusContentHeight = (WindowRect.size.height -
                                       ContentRect.size.height);

    f32    NewContentHeight = (10.0f *
                               (FrameSize.width - WindowMinusContentWidth)) /
                              16.0f;

    FrameSize.height        = NewContentHeight + WindowMinusContentHeight;

    return FrameSize;
}

// Note: Will render into fixed size texture and then sample that texture into drawable texture
- (void)ResizeBitmapAndTexturesForWindow:(NSWindow *)Window
{
    NSView *ContentView = [Window contentView];
    CAMetalLayer *MetalLayer = [ContentView layer];
    NSRect BackingBounds = [ContentView convertRectToBacking:[ContentView bounds]];
    [MetalLayer setDrawableSize:BackingBounds.size];
    
    TextureWidth = (NSUInteger)BackingBounds.size.width;
    TextureHeight = (NSUInteger)BackingBounds.size.height;
    
    [Texture release];
    [TextureDescriptor setWidth:TextureWidth];
    [TextureDescriptor setHeight:TextureHeight];
    Texture = [Device newTextureWithDescriptor:TextureDescriptor];
    if(!Texture)
    {
        NSLog(@"Texture allocation failed");
        exit(1);
    }
    
    BitmapMemory = realloc(BitmapMemory, TextureWidth * TextureHeight * BytesPerPixel);
    if(!BitmapMemory)
    {
        NSLog(@"BitmapMemory allocation failed");
        exit(1);
    }
    
}

- (void)windowDidResize:(NSNotification *)notification
{
    NSWindow *Window = [Notification object];
    [self ResizeMetalLayerForWindow:Window];
}

- (void)windowWillClose:(NSNotification *)Notification
{
    GLOBAL_RUNNING = false;
}

@end

struct exe_state
{
    char ExecutablePath[PATH_MAX];
    char *ExecutableDirectory;
};

// TODO: Might want to handle paths that exceed MAX_PATH
internal void
GetExecutablePath(exe_state *State)
{
    char *ExecutablePath = State->ExecutablePath;
    char *ExecutableDirectory = State->ExecutableDirectory;
    u32 Size = sizeof(State->ExecutablePath);
    
    _NSGetExecutablePath(ExecutablePath, &Size);
    ExecutableDirectory = ExecutablePath;
    
    for(char *Scan = ExecutableDirectory; *Scan; ++Scan)
    {
        if(*Scan == '/')
        {
            ExecutableDirectory = Scan + 1;
        }
    }
    
    State->ExecutableDirectory = ExecutableDirectory;
}

// TODO: Might want to handle case where ExecutablePath Length + Filename Length exceeds bounds of FullPath
internal void
BuildFullPath(exe_state *State, char *Filename, size_t FilenameSize, char *FullPath)
{
    char *ExecutablePath = State->ExecutablePath;
    char *ExecutableDirectory = State->ExecutableDirectory;
    i32 DirectoryLength = ExecutableDirectory - ExecutablePath;
    for(int Index = 0; Index < DirectoryLength; ++Index)
    {
        *FullPath++ = *ExecutablePath++;
    }
    for(int Index = 0; Index < FilenameSize - 1; ++Index)
    {
        *FullPath++ = *Filename++;
    }
    *FullPath = 0;
}

internal void
RenderWeirdGradient(i32 BlueOffset, i32 GreenOffset)
{
    
    i32 Pitch = TextureWidth * BytesPerPixel;
    u8 *Row = (u8 *)BitmapMemory;
    for(i32 Y = 0; Y < TextureHeight; ++Y)
    {
        u32 *Pixel = (u32 *)Row;
        for(i32 X = 0; X < TextureWidth; ++X)
        {
            u8 Blue = X + BlueOffset;
            u8 Green = Y + GreenOffset;
            
            *Pixel++ = ((u32)Blue << 0) | ((u32)Green << 8);
        }
        Row += Pitch;
    }
}

i32
main(i32 argc, const char *argv[])
{

    @autoreleasepool
    {
        
        // Note: Set window size, and then determine render texture size
        // later, we'll have a fixed render texture size that's fullscreen
        // Then, we'll sample it into the metal layer drawable texture
        NSString      *ApplicationName = @"Handmade Game";
        NSUInteger     WindowWidth     = 960;
        NSUInteger     WindowHeight    = 600;

        NSApplication *application     = [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        HandmadeApplicationDelegate *ApplicationDelegate;

        ApplicationDelegate = [[HandmadeApplicationDelegate alloc] init];
        if(!ApplicationDelegate)
        {
            NSLog(@"ApplicationDelegate allocation failed");
            return 1;
        }
        [application setDelegate:ApplicationDelegate];

        [NSApp finishLaunching];

        NSRect ScreenRect   = [[NSScreen mainScreen] frame];

        NSRect InitialFrame = NSMakeRect(
            (ScreenRect.size.width - WindowWidth) * 0.5f,
            (ScreenRect.size.height - WindowHeight) * 0.5f, WindowWidth,
            WindowHeight);

        NSWindow *Window = [[NSWindow alloc]
            initWithContentRect:InitialFrame
                      styleMask:NSWindowStyleMaskTitled |
                                NSWindowStyleMaskClosable |
                                NSWindowStyleMaskMiniaturizable |
                                NSWindowStyleMaskResizable
                        backing:NSBackingStoreBuffered
                          defer:NO];
        if(!Window)
        {
            NSLog(@"Window allocation failed");
            return 1;
        }

        [Window setBackgroundColor:[NSColor windowBackgroundColor]];
        [Window setDelegate:ApplicationDelegate];
        [Window setMinSize:NSMakeSize(480, 300)];
        [Window setTitle:ApplicationName];
        [Window makeKeyAndOrderFront:nil];

        exe_state State;
        GetExecutablePath(&State);
        char MetalLibraryFilename[] = "shaders.metallib";
        char MetalLibraryFullPath[PATH_MAX];
        BuildFullPath(&State, MetalLibraryFilename, sizeof(MetalLibraryFilename), MetalLibraryFullPath);
        NSString *NSString_MetalLibraryFullPath = [NSString stringWithUTF8String:MetalLibraryFullPath];
        NSURL *NSURL_MetalLibraryFullPath = [NSURL fileURLWithPath:NSString_MetalLibraryFullPath];
        
        id<MTLDevice> Device = MTLCreateSystemDefaultDevice();
        NSError *Errors = nil;
        id<MTLLibrary> MetalLibrary = [Device newLibraryWithURL:NSURL_MetalLibraryFullPath error:&Errors];
        if(!MetalLibrary)
        {
            NSLog(@"Library load failed: %@", [Errors localizedDescription]);
            return 1;
        }
        id<MTLFunction> VertexFunction = [MetalLibrary newFunctionWithName:@"VertexFunction"];
        id<MTLFunction FragmentFunction = [MetalLibrary newFunctionWithName:@"FragmentFunction"];
        
        CAMetalLayer *MetalLayer = [[CAMetalLayer alloc] init];
        if(!MetalLayer)
        {
            NSLog(@"MetalLayer allocation failed");
            return 1;
        }
        [MetalLayer setDevice:Device];
        [MetalLayer setPixelFormat:MTLPixelFormatBGRA8Unorm];
        // NOTE: drawable size is set later using application delegate
        [MetalLayer setFramebufferOnly:YES];
        [MetalLayer setPresentsWithTransaction:NO];
        
        NSView *ContentView = [Window contentView];
        [ContentView setAutoresizingMask:NSViewWidthSizable |
                                         NSViewHeightSizable];
        [ContentView setWantsLayer:YES];
        [ContentView setLayer:MetalLayer];
        
        id<MTLCommandQueue> CommandQueue = [Device newCommandQueueWithMaxCommandBufferCount:64];
        if(!CommandQueue)
        {
            NSLog(@"CommandQueue allocation failed");
            return 1;
        }
        
        MTLTextureDescriptor *TextureDescriptor = [MTLTextureDescriptor                  texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1 height:1 mipmapped:NO];

        [ApplicationDelegate ResizeBitmapAndTexturesForWindow:Window];
        
        float                      VerticesAndUVs[]    = {
            -1.0f, -1.0f, 0.0f, 1.0f, -1.0f, 1.0f,  0.0f, 0.0f,
            1.0f,  -1.0f, 1.0f, 1.0f, 1.0f,  -1.0f, 1.0f, 1.0f,
            -1.0f, 1.0f,  0.0f, 0.0f, 1.0f,  1.0f,  1.0f, 0.0f,
        };
        
        // Note: Buffers expensive to create
        id<MTLBuffer> VertexBuffer = [Device
                                      newBufferWithBytes:VerticesAndUVs
                                      length:sizeof(VerticesAndUVs)
                                      options:0];
        if(!VertexBuffer)
        {
            NSLog(@"VertexBuffer failed");
            return 1;
        }
        
        MTLRenderPipelineDescriptor *RenderPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        if(!RenderPipelineDescriptor)
        {
            NSLog(@"RenderPipelineDescriptor failed");
            return 1;
        }
        
        RenderPipelineDescriptor.vertexFunction = VertexFunction;
        RenderPipelineDescriptor.fragmentFunction = FragmentFunction;
        RenderPipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        
        MTLVertexDescriptor *VertexDescriptor = [[MTLVertexDescriptor alloc] init];
        if(!VertexDescriptor)
        {
            NSLog(@"VertexDescriptor failed");
            return 1;
        }
        
        VertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
        VertexDescriptor.attributes[0].bufferIndex = 0;
        VertexDescriptor.attributes[0].offset      = 0;
        VertexDescriptor.attributes[1].format      = MTLVertexFormatFloat2;
        VertexDescriptor.attributes[1].bufferIndex = 0;
        VertexDescriptor.attributes[1].offset      = 2 * sizeof(float);
        VertexDescriptor.layouts[0].stride         = 4 * sizeof(float);
        VertexDescriptor.layouts[0].stepFunction =
            MTLVertexStepFunctionPerVertex;
        
        RenderPipelineDescriptor.vertexDescriptor = VertexDescriptor;
        
        Errors = nil;
        id<MTLRenderPipelineState> RenderPipelineState = [Device newRenderPipelineStateWithDescriptor:RenderPipelineDescriptor error:&Errors];
        if(!RenderPipelineState)
        {
            NSLog(@"RenderPipelineState failed: %@", [Errors localizedDescription]);
            return 1;
        }
        
        MTLSamplerDescriptor *SamplerDescriptor = [[MTLSamplerDescriptor alloc] init];
        if(!SamplerDescriptor)
        {
            NSLog(@"SamplerDescriptor failed");
            return 1;
        }
        id<MTLSamplerState> Sampler = [device newSamplerStateWithDescriptor:SamplerDescriptor];
        
        NSEvent *Event;
        i32 XOffset = 0;
        i32 YOffset = 0;
        while(GLOBAL_RUNNING)
        {
            @autoreleasepool
            {

                do
                {
                    Event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                               untilDate:nil
                                                  inMode:NSDefaultRunLoopMode
                                                 dequeue:YES];

                    [NSApp sendEvent:Event];

                } while(Event != nil);
                
                RenderWeirdGradient(XOffset, YOffset);
                
                [Texture replaceRegion:MTLRegionMake2D(0, 0, TextureWidth, TextureHeight) mipmapLevel:0 withBytes:BitmapMemory bytesPerRow:BytesPerPixel*TextureWidth];
                
                id<MTLCommandBuffer> CommandBuffer = [CommandQueue commandBuffer];
                
                MTLRenderPassDescriptor *RenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
                
                id<CAMetalDrawable> Drawable = [MetalLayer nextDrawable];
                if(!Drawable)
                {
                    NSLog(@"Drawables ran out");
                    return 1;
                }
                RenderPassDescriptor.colorAttachments[0].texture = [Drawable texture];
                RenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
                RenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
                
                id<MTLRenderCommandEncoder> RenderCommandEncoder = [CommandBuffer renderCommandEncoderWithDescriptor:RenderPassDescriptor];
                
                [RenderCommandEncoder setRenderPipelinestate:RenderPipelineState];
                
                [RenderCommandEncoder setVertexBuffer:VertexBuffer offset:0 atIndex:0];
                [RenderCommandEncoder setFragmentTexture:Texture atIndex:0];
                [RenderCommandEncoder setFragmentSamplerState:Sampler atIndex:0];

                [RenderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
                
                [RenderCommandEncoder endEncoding];
                [CommandBuffer commit];
                
                ++XOffset;
                YOffset += 2;
            }
        }

        printf("Handmade Game finished running\n");
    }
}














