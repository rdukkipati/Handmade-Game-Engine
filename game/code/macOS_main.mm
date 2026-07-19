#include <Cocoa/Cocoa.h>
#include <Metal/Metal.h>
#include <QuartzCore/CAMetalLayer.h>

#include <limits.h>
#include <mach-o/dyld.h>

#include <mach/mach.h>
#include <mach/mach_error.h>

#include <stdint.h>

#include <string.h>

#include "macOS_keyboard.h"

#define internal        static
#define local_persist   static
#define global_variable static

// vm_allocate
// Getting screen size

// Reducing c runtime
//

typedef int8_t        i8;
typedef int16_t       i16;
typedef int32_t       i32;
typedef int64_t       i64;
typedef i32           b32;

typedef uint8_t       u8;
typedef uint16_t      u16;
typedef uint32_t      u32;
typedef uint64_t      u64;

typedef float         f32;
typedef double        f64;

global_variable b32   GLOBAL_RUNNING          = true;
global_variable void *BitmapMemory            = NULL;
global_variable id<MTLTexture>        Texture = nil;
global_variable MTLTextureDescriptor *TextureDescriptor;
global_variable id<MTLDevice> Device        = nil;
global_variable NSUInteger    BytesPerPixel = 4;
global_variable NSUInteger    TextureWidth;
global_variable NSUInteger    TextureHeight;
global_variable NSUInteger BitmapPitch;

global_variable u8 OldKeyboardState[128] = {};

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

// Note: Will render into fixed size texture and then sample that texture into
// drawable texture
- (void)ResizeBitmapAndTexturesForWindow:(NSWindow *)Window
{
    NSView       *ContentView   = [Window contentView];
    CAMetalLayer *MetalLayer    = (CAMetalLayer *)[ContentView layer];
    NSRect        BackingBounds = [ContentView
                                   convertRectToBacking:[ContentView bounds]];
    [MetalLayer setDrawableSize:BackingBounds.size];
    
    TextureWidth  = (NSUInteger)BackingBounds.size.width;
    TextureHeight = (NSUInteger)BackingBounds.size.height;
    BitmapPitch = TextureWidth * BytesPerPixel;
    
    // Maybe allocate texture only once and bitmap only once
    // Then only use however much of it you need
}

- (void)windowDidResize:(NSNotification *)Notification
{
    NSWindow *Window = [Notification object];
    [self ResizeBitmapAndTexturesForWindow:Window];
}

- (void)windowWillClose:(NSNotification *)Notification
{
    GLOBAL_RUNNING = false;
}

- (void)controllerDidConnect:(NSNotification *)Notification
{
    // Do something when a controller connects
}

- (void)controllerDidDisconnect:(NSNotification *)Notification
{
    // Do something when a controller disconnects
}

@end

struct exe_state
{
    char  ExecutablePath[PATH_MAX];
    char *ExecutableDirectory;
};

// TODO: Might want to handle paths that exceed MAX_PATH
internal void
GetExecutablePath(exe_state *State)
{
    char *ExecutablePath      = State->ExecutablePath;
    char *ExecutableDirectory = State->ExecutableDirectory;
    u32   Size                = sizeof(State->ExecutablePath);
    
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

// TODO: Might want to handle case where ExecutablePath Length + Filename Length
// exceeds bounds of FullPath
internal void
BuildFullPath(exe_state *State, char *Filename, size_t FilenameSize,
              char *FullPath)
{
    char *ExecutablePath      = State->ExecutablePath;
    char *ExecutableDirectory = State->ExecutableDirectory;
    i32   DirectoryLength     = ExecutableDirectory - ExecutablePath;
    for(i32 Index = 0; Index < DirectoryLength; ++Index)
    {
        *FullPath++ = *ExecutablePath++;
    }
    for(i32 Index = 0; Index < (i32)FilenameSize - 1; ++Index)
    {
        *FullPath++ = *Filename++;
    }
    *FullPath = 0;
}

internal void
RenderWeirdGradient(i32 BlueOffset, i32 GreenOffset)
{
    
    u8 *Row   = (u8 *)BitmapMemory;
    for(i32 Y = 0; Y < (i32)TextureHeight; ++Y)
    {
        u32 *Pixel = (u32 *)Row;
        for(i32 X = 0; X < (i32)TextureWidth; ++X)
        {
            u8 Blue  = X + BlueOffset;
            u8 Green = Y + GreenOffset;
            
            *Pixel++ = ((u32)Blue << 0) | ((u32)Green << 8) | ((u32)255 << 24);
        }
        Row += BitmapPitch;
    }
}

i32
main()
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
        BuildFullPath(&State, MetalLibraryFilename,
                      sizeof(MetalLibraryFilename), MetalLibraryFullPath);
        NSString *NSString_MetalLibraryFullPath = [NSString
                                                   stringWithUTF8String:MetalLibraryFullPath];
        NSURL    *NSURL_MetalLibraryFullPath    = [NSURL
                                                   fileURLWithPath:NSString_MetalLibraryFullPath];
        
        Device = MTLCreateSystemDefaultDevice();
        if(!Device)
        {
            NSLog(@"No Metal device available");
            return 1;
        }
        
        NSError       *Errors       = nil;
        id<MTLLibrary> MetalLibrary = [Device
                                       newLibraryWithURL:NSURL_MetalLibraryFullPath
                                       error:&Errors];
        if(!MetalLibrary)
        {
            NSLog(@"Library load failed: %@", [Errors localizedDescription]);
            return 1;
        }
        id<MTLFunction> VertexFunction   = [MetalLibrary
                                            newFunctionWithName:@"VertexFunction"];
        id<MTLFunction> FragmentFunction = [MetalLibrary
                                            newFunctionWithName:@"FragmentFunction"];
        
        CAMetalLayer   *MetalLayer       = [[CAMetalLayer alloc] init];
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
        [ContentView
         setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [ContentView setWantsLayer:YES];
        [ContentView setLayer:MetalLayer];
        
        id<MTLCommandQueue> CommandQueue = [Device
                                            newCommandQueueWithMaxCommandBufferCount:64];
        if(!CommandQueue)
        {
            NSLog(@"CommandQueue allocation failed");
            return 1;
        }
        
        TextureDescriptor = [MTLTextureDescriptor
                             texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                             width:3456
                             height:2234
                             mipmapped:NO];
        
        Texture = [Device newTextureWithDescriptor:TextureDescriptor];
        if(!Texture)
        {
            NSLog(@"Texture allocation failed");
            return 1;
        }
        
        kern_return_t Result = vm_allocate(mach_task_self(), (vm_address_t *)&BitmapMemory, 3456 * 2234 * BytesPerPixel, VM_FLAGS_ANYWHERE);
        if(Result != KERN_SUCCESS)
        {
            NSLog(@"vm_allocate for BitmapMemory failed: %s", mach_error_string(Result));
            return 1;
        }
        
        
        [ApplicationDelegate ResizeBitmapAndTexturesForWindow:Window];
        
        float VerticesAndUVs[] = {
            -1.0f, -1.0f, -1.0f, 1.0f,
            1.0f,  -1.0f, 1.0f,  -1.0f,
            -1.0f, 1.0f,  1.0f,  1.0f,
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
        
        MTLRenderPipelineDescriptor *RenderPipelineDescriptor =
            [[MTLRenderPipelineDescriptor alloc] init];
        if(!RenderPipelineDescriptor)
        {
            NSLog(@"RenderPipelineDescriptor failed");
            return 1;
        }
        
        RenderPipelineDescriptor.vertexFunction   = VertexFunction;
        RenderPipelineDescriptor.fragmentFunction = FragmentFunction;
        RenderPipelineDescriptor.colorAttachments[0].pixelFormat =
            MTLPixelFormatBGRA8Unorm;
        
        MTLVertexDescriptor *VertexDescriptor = [[MTLVertexDescriptor alloc]
                                                 init];
        if(!VertexDescriptor)
        {
            NSLog(@"VertexDescriptor failed");
            return 1;
        }
        
        VertexDescriptor.attributes[0].format      = MTLVertexFormatFloat2;
        VertexDescriptor.attributes[0].bufferIndex = 0;
        VertexDescriptor.attributes[0].offset      = 0;
        VertexDescriptor.layouts[0].stride         = 2 * sizeof(float);
        VertexDescriptor.layouts[0].stepFunction =
            MTLVertexStepFunctionPerVertex;
        
        RenderPipelineDescriptor.vertexDescriptor      = VertexDescriptor;
        
        Errors                                         = nil;
        id<MTLRenderPipelineState> RenderPipelineState = [Device
                                                          newRenderPipelineStateWithDescriptor:RenderPipelineDescriptor
                                                          error:&Errors];
        if(!RenderPipelineState)
        {
            NSLog(@"RenderPipelineState failed: %@",
                  [Errors localizedDescription]);
            return 1;
        }
        
        NSEvent            *Event;
        i32                 XOffset = 0;
        i32                 YOffset = 0;
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
                    
                    NSEventType EventType = [Event type];
                    switch(EventType)
                    {
                        case NSKeyDown:
                        case NSKeyUp:
                        {
                            u16 KeyCode = [Event keyCode];
                            if(KeyCode >= sizeof(OldKeyboardState))
                            {
                                NSLog(@"KeyCode too large: %hu (0x%02hX)", KeyCode, KeyCode);
                                return 1;
                                
                            }
                            
                            /*NSEventModifierFlags ModifierFlags = [Event modifierFlags];
                            i32 CommandKeyFlag = (ModifierFlags & NSCommandKeyMask);
                            i32 ControlKeyFlag = (ModifierFlags & NSControlKeyMask);
                            i32 AlternateKeyFlag = (ModifierFlags & NSAlternateKeyMask);
                            i32 ShiftKeyFlag = (ModifierFlags & NSShiftKeyMask);*/
                            
                            b32 IsDown = ((EventType == NSKeyDown) ? 1 : 0);
                            b32 WasDown = OldKeyboardState[KeyCode];
                            
                            if(IsDown != WasDown)
                            {
                                switch(KeyCode)
                                {
                                    case kVK_Escape:
                                    {
                                        NSLog(@"ESCAPE: ");
                                        if(IsDown)
                                        {
                                            NSLog(@"IsDown");
                                        }
                                        if(WasDown)
                                        {
                                            NSLog(@"WasDown");
                                        }
                                        NSLog(@"\n");
                                        
                                    } break;
                                }
                                
                            }
                            
                            OldKeyboardState[KeyCode] = IsDown;
                            
                        } break;
                        
                        default:
                        [NSApp sendEvent:Event];
                    }
                    
                } while(Event != nil);
                
                NSArray<GCController *> *Controllers = [GCController controllers];
                for(NSUInteger ControllerIndex = 0; ControllerIndex < [Controllers count]; ++ControllerIndex)
                {
                    GCController *Controller = [Controllers objectAtIndex:0];
                    GCExtendedGamepad *Gamepad = [Controller extendedGamepad];
                    if(Gamepad)
                    {
                        BOOL A_Button = [[Gamepad buttonA] isPressed];
                        BOOL B_Button = [[Gamepad buttonB] isPressed];
                        BOOL X_Button = [[Gamepad buttonX] isPressed];
                        BOOL Y_Button = [[Gamepad buttonY] isPressed];
                        
                        f32 LeftStick_X = [[[Gamepad leftThumbstick] xAxis] value];
                        f32 LeftStick_Y = [[[Gamepad leftThumbstick] yAxis] value];
                        f32 RightStick_X = [[[Gamepad rightThumbstick] xAxis] value];
                        f32 RightStick_Y = [[[Gamepad rightThumbstick] yAxis] value];
                        
                        XOffset += (i32)(LeftStick_X * 8.0f);
                        YOffset += (i32)(LeftStick_Y * 8.0f);
                        
                    }
                }
                
                RenderWeirdGradient(XOffset, YOffset);
                
                [Texture replaceRegion:MTLRegionMake2D(0, 0, TextureWidth,
                                                       TextureHeight)
                 mipmapLevel:0
                 withBytes:BitmapMemory
                 bytesPerRow:BitmapPitch];
                
                id<MTLCommandBuffer> CommandBuffer =
                    [CommandQueue commandBuffer];
                
                MTLRenderPassDescriptor *RenderPassDescriptor =
                    [MTLRenderPassDescriptor renderPassDescriptor];
                
                id<CAMetalDrawable> Drawable = [MetalLayer nextDrawable];
                if(!Drawable)
                {
                    NSLog(@"Drawables ran out");
                    return 1;
                }
                RenderPassDescriptor.colorAttachments[0].texture =
                    [Drawable texture];
                RenderPassDescriptor.colorAttachments[0].loadAction =
                    MTLLoadActionDontCare;
                RenderPassDescriptor.colorAttachments[0].storeAction =
                    MTLStoreActionStore;
                
                id<MTLRenderCommandEncoder> RenderCommandEncoder =
                    [CommandBuffer renderCommandEncoderWithDescriptor:
                     RenderPassDescriptor];
                
                [RenderCommandEncoder
                 setRenderPipelineState:RenderPipelineState];
                
                [RenderCommandEncoder setVertexBuffer:VertexBuffer
                 offset:0
                 atIndex:0];
                [RenderCommandEncoder setFragmentTexture:Texture atIndex:0];
                
                [RenderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                 vertexStart:0
                 vertexCount:6];
                
                [RenderCommandEncoder endEncoding];
                [CommandBuffer presentDrawable:Drawable];
                [CommandBuffer commit];
                [CommandBuffer waitUntilCompleted];
                
                ++XOffset;
                YOffset += 2;
            }
        }
        
        NSLog(@"Handmade Game finished running\n");
    }
}
/*
[[NSNotificationCenter defaultCenter] addObserver:ApplicationDelegate selector:@selector(controllerDidConnect:) name:GCControllerDidConnectNotification object:nil];

[[NSNotificationCenter defaultCenter] addObserver:ApplicationDelegate selector:@selector(controllerDidDisconnect:) name:GCControllerDidDisconnectNotification object:nil];

*/



