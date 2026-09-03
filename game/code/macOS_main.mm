#include <Cocoa/Cocoa.h>
#include <Metal/Metal.h>
#include <QuartzCore/CAMetalLayer.h>
#include <GameController/GameController.h>
#include <AudioUnit/AudioUnit.h>

#include <mach/mach_time.h>

#include <limits.h>
#include <mach-o/dyld.h>

#include <mach/mach.h>
#include <mach/mach_error.h>

#include <stdint.h>

// TODO: Implement sine ourselves
#include <math.h>

#include "macOS_keyboard.h"

#define internal        static
#define local_persist   static
#define global_variable static

// vm_allocate
// Getting screen size

// Reducing c runtime
//



typedef int8_t   i8;
typedef int16_t  i16;
typedef int32_t  i32;
typedef int64_t  i64;
typedef i32      b32;

typedef uint8_t  u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

typedef float    f32;
typedef double   f64;

#define PI   3.14159265359f
#define PI_2 6.28318530718f

#include "handmade.cpp"

global_variable b32   GLOBAL_RUNNING          = true;

global_variable id<MTLTexture>        Texture = nil;
global_variable MTLTextureDescriptor *TextureDescriptor;
global_variable id<MTLDevice> Device        = nil;
global_variable NSUInteger    BytesPerPixel = 4;
global_variable NSUInteger    TextureWidth;
global_variable NSUInteger    TextureHeight;
global_variable NSUInteger    BitmapPitch;

global_variable u8            OldKeyboardState[128] = {};

global_variable i32           SampleFramesPerSecond = 48000;
global_variable i32           BytesPerSampleFrame = sizeof(i16) * 2;

global_variable i32 Latency = 3200;
global_variable i32 GameSoundSizeInBytes = Latency * BytesPerSampleFrame;
global_variable i32 RingBufferSizeInBytes = SampleFramesPerSecond * BytesPerSampleFrame * 2;

struct macOS_sound_output
{
    i32 *RingBuffer;
    i32 SizeInSampleFrames;
    i32 ReadIndex;
    i32 WriteIndex;
};

OSStatus
AudioUnitCallback(void *InRefCon, AudioUnitRenderActionFlags *IOActionFlags,
                  const AudioTimeStamp *InTimeStamp, UInt32 InBusNumber,
                  UInt32 InNumberFrames, AudioBufferList *IOData)
{
    // Unused parameters
    (void)IOActionFlags;
    (void)InTimeStamp;
    (void)InBusNumber;
    
    macOS_sound_output *macOS_Sound = (macOS_sound_output *)InRefCon;
    i32 WriteIndex = macOS_Sound->WriteIndex;
    
    
    i16 *OutputBuffer = (i16 *)IOData->mBuffers[0].mData;
    
    UInt32 SampleFrame = 0;
    while(macOS_Sound->ReadIndex != WriteIndex && SampleFrame < InNumberFrames)
    {
        i16 *RingSample = (i16 *)&macOS_Sound->RingBuffer[macOS_Sound->ReadIndex++];
        *OutputBuffer++ = *RingSample++;
        *OutputBuffer++ = *RingSample;
        if(macOS_Sound->ReadIndex >= macOS_Sound->SizeInSampleFrames)
        {
            macOS_Sound->ReadIndex = 0;
        }
        ++SampleFrame;
    }
    while(SampleFrame < InNumberFrames)
    {
        *OutputBuffer++ = 0;
        *OutputBuffer++ = 0;
        ++SampleFrame;
    }
    
    return noErr;
}

internal void
ProcessButton(GCControllerButtonInput *Button, game_button_state *OldState, game_button_state *NewState)
{
    
    NewState->EndedDown = [Button isPressed];
    NewState->HalfTransitionCount = (OldState->EndedDown != NewState->EndedDown) ? 1 : 0;
    
}

@interface HandmadeApplicationDelegate
: NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

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
    BitmapPitch   = TextureWidth * BytesPerPixel;
    
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

i32
main()
{
    
    @autoreleasepool
    {
        
#if HANDMADE_INTERNAL
        vm_address_t BaseAddress = (vm_address_t)Terabytes(2);
        int Flags = VM_FLAGS_FIXED;
#else
        vm_address_t BaseAddress = 0;
        int Flags = VM_FLAGS_ANYWHERE;
#endif
        
        game_memory GameMemory = {};
        GameMemory.PermanentStorageSize = Megabytes(64);
        GameMemory.TransientStorageSize = Gigabytes(4);
        
        u64 TotalSize = GameMemory.PermanentStorageSize + GameMemory.TransientStorageSize;
        
        kern_return_t Result;
        Result = vm_allocate(mach_task_self(), &BaseAddress, TotalSize, Flags);
        if(Result != KERN_SUCCESS)
        {
            NSLog(@"vm_allocate for game memory failed: %s", mach_error_string(Result));
            return 1;
        }
        
        GameMemory.PermanentStorage = (void *)BaseAddress;
        GameMemory.TransientStorage = ((u8 *)GameMemory.PermanentStorage + GameMemory.PermanentStorageSize);
        
        mach_timebase_info_data_t Timebase;
        mach_timebase_info(&Timebase);
        
        macOS_sound_output macOS_Sound = {};
        macOS_Sound.SizeInSampleFrames = SampleFramesPerSecond * 2;
        
        game_sound_output_buffer GameSound = {};
        GameSound.SampleFramesPerSecond = SampleFramesPerSecond;
        
        game_offscreen_buffer GameBitmap = {};
        
        
        // Allocate macOS_Sound
        Result = vm_allocate(mach_task_self(), (vm_address_t *)&macOS_Sound.RingBuffer, RingBufferSizeInBytes, VM_FLAGS_ANYWHERE);
        
        if(Result != KERN_SUCCESS)
        {
            NSLog(@"vm_allocate for macOS_Sound failed: %s", mach_error_string(Result));
            return 1;
        }
        
        // Allocate GameSound
        Result = vm_allocate(mach_task_self(), (vm_address_t *)&GameSound.Memory, GameSoundSizeInBytes, VM_FLAGS_ANYWHERE);
        
        if(Result != KERN_SUCCESS)
        {
            NSLog(@"vm_allocate for RingBuffer failed: %s", mach_error_string(Result));
            return 1;
            
        }
        
        // Allocate GameBitmap
        Result = vm_allocate(
                             mach_task_self(), (vm_address_t *)&GameBitmap.Memory,
                             3456 * 2234 * BytesPerPixel, VM_FLAGS_ANYWHERE);
        
        if(Result != KERN_SUCCESS)
        {
            NSLog(@"vm_allocate for BitmapMemory failed: %s",
                  mach_error_string(Result));
            return 1;
        }
        
        
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
        
        Texture           = [Device newTextureWithDescriptor:TextureDescriptor];
        if(!Texture)
        {
            NSLog(@"Texture allocation failed");
            return 1;
        }
        
        [ApplicationDelegate ResizeBitmapAndTexturesForWindow:Window];
        
        float VerticesAndUVs[] = {
            -1.0f, -1.0f, -1.0f, 1.0f, 1.0f, -1.0f,
            1.0f,  -1.0f, -1.0f, 1.0f, 1.0f, 1.0f,
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
        
        AudioComponentDescription OutputUnitDescription = {};
        OutputUnitDescription.componentType             = kAudioUnitType_Output;
        OutputUnitDescription.componentSubType =
            kAudioUnitSubType_DefaultOutput;
        OutputUnitDescription.componentManufacturer =
            kAudioUnitManufacturer_Apple;
        
        AudioComponent OutputUnitComponent = AudioComponentFindNext(
                                                                    NULL, &OutputUnitDescription);
        if(!OutputUnitComponent)
        {
            NSLog(@"No Default Audio Component");
            return 1;
        }
        
        AudioUnit OutputUnit;
        OSStatus  Error = AudioComponentInstanceNew(OutputUnitComponent,
                                                    &OutputUnit);
        if(Error)
        {
            NSLog(@"Audio Unit Creation Failed");
            return 1;
        }
        
        AudioStreamBasicDescription StreamFormat = {};
        StreamFormat.mSampleRate                 = SampleFramesPerSecond;
        StreamFormat.mFormatID                   = kAudioFormatLinearPCM;
        StreamFormat.mFormatFlags       = kAudioFormatFlagIsSignedInteger |
            kAudioFormatFlagIsPacked;
        StreamFormat.mBytesPerPacket    = 4;
        StreamFormat.mFramesPerPacket   = 1;
        StreamFormat.mBytesPerFrame     = BytesPerSampleFrame;
        StreamFormat.mChannelsPerFrame  = 2;
        StreamFormat.mBitsPerChannel    = 16;
        
        AURenderCallbackStruct Callback = {};
        Callback.inputProc              = AudioUnitCallback;
        Callback.inputProcRefCon        = &macOS_Sound;
        
        Error                           = AudioUnitSetProperty(
                                                               OutputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
                                                               0, &StreamFormat, sizeof(StreamFormat));
        if(Error)
        {
            NSLog(@"AudioUnit set stream format failed");
            return 1;
        }
        
        Error = AudioUnitSetProperty(
                                     OutputUnit, kAudioUnitProperty_SetRenderCallback,
                                     kAudioUnitScope_Input, 0, &Callback, sizeof(Callback));
        if(Error)
        {
            NSLog(@"AudioUnit set callback failed");
            return 1;
        }
        
        game_input Input[2] = {};
        game_input *NewInput = &Input[0];
        game_input *OldInput = &Input[1];
        
        Error = AudioUnitInitialize(OutputUnit);
        Error = AudioOutputUnitStart(OutputUnit);
        
        NSEvent *Event;
        
        u64      StartCounter = mach_absolute_time();
        
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
                                NSLog(@"KeyCode too large: %hu (0x%02hX)",
                                      KeyCode, KeyCode);
                                return 1;
                            }
                            
                            /*NSEventModifierFlags ModifierFlags = [Event
                            modifierFlags]; i32 CommandKeyFlag = (ModifierFlags
                            & NSCommandKeyMask); i32 ControlKeyFlag =
                            (ModifierFlags & NSControlKeyMask); i32
                            AlternateKeyFlag = (ModifierFlags &
                            NSAlternateKeyMask); i32 ShiftKeyFlag =
                            (ModifierFlags & NSShiftKeyMask);*/
                            
                            b32 IsDown  = ((EventType == NSKeyDown) ? 1 : 0);
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
                                    }
                                    break;
                                }
                            }
                            
                            OldKeyboardState[KeyCode] = IsDown;
                            
                        }
                        break;
                        
                        default:
                        {
                            [NSApp sendEvent:Event];
                            
                        }
                        break;
                        
                    }
                    
                } while(Event != nil);
                
                NSArray<GCController *> *Controllers =
                    [GCController controllers];
                
                i32 ControllerIndex = 0;
                for(GCController *Controller in Controllers)
                {
                    
                    if(ControllerIndex >= 4)
                    {
                        break;
                    }
                    
                    game_controller_input *OldController = &OldInput->Controllers[ControllerIndex];
                    game_controller_input *NewController = &NewInput->Controllers[ControllerIndex];
                    
                    GCExtendedGamepad *Gamepad = [Controller extendedGamepad];
                    if(Gamepad)
                    {
                        
                        NewController->IsAnalog = true;
                        NewController->StartX = OldController->EndX;
                        NewController->StartY = OldController->EndY;
                        
                        f32 LeftStick_X  = [[[Gamepad leftThumbstick] xAxis]
                                            value];
                        f32 LeftStick_Y  = [[[Gamepad leftThumbstick] yAxis]
                                            value];
                        
                        NewController->MinX = NewController->MaxX = NewController->EndX = LeftStick_X;
                        NewController->MinY = NewController->MaxY = NewController->EndY = LeftStick_Y;
                        
                        /*
                        f32  RightStick_X  = [[[Gamepad rightThumbstick]
                        xAxis] value]; f32  RightStick_Y  = [[[Gamepad
                        rightThumbstick] yAxis] value];
*/
                        
                        ProcessButton([Gamepad buttonA], &OldController->Down, &NewController->Down);
                        ProcessButton([Gamepad buttonB], &OldController->Right, &NewController->Right);
                        ProcessButton([Gamepad buttonX], &OldController->Left, &NewController->Left);
                        ProcessButton([Gamepad buttonY], &OldController->Up,
                                      &NewController->Up);
                        ProcessButton([Gamepad leftShoulder], &OldController->LeftShoulder, &NewController->LeftShoulder);
                        ProcessButton([Gamepad rightShoulder], &OldController->RightShoulder, &NewController->RightShoulder);
                        
                        
                    }
                }
                
                // ReadWriteDiff is in SampleFrames
                i32 ReadWriteDiff = 0;
                i32 ReadIndex = macOS_Sound.ReadIndex;
                
                if(macOS_Sound.WriteIndex >= ReadIndex)
                {
                    ReadWriteDiff = macOS_Sound.WriteIndex - ReadIndex;
                }
                
                else
                {
                    ReadWriteDiff = (macOS_Sound.SizeInSampleFrames - ReadIndex) + (macOS_Sound.WriteIndex); 
                }
                
                GameSound.SampleFramesToWrite = Latency - ReadWriteDiff;
                if(GameSound.SampleFramesToWrite < 0)
                {
                    NSLog(@"WREEEEE");
                    return 1;
                }
                
                GameBitmap.Width = TextureWidth;
                GameBitmap.Height = TextureHeight;
                GameBitmap.Pitch = BitmapPitch;
                
                GameUpdateAndRender(&GameMemory, NewInput, &GameBitmap, &GameSound);
                
                //Copy game sound into ring buffer
                i16 *Memory = GameSound.Memory;
                
                for(int Sample = 0; Sample < GameSound.SampleFramesToWrite; ++Sample)
                {
                    i16 *RingSample = (i16 *)&macOS_Sound.RingBuffer[macOS_Sound.WriteIndex++];
                    *RingSample++ = *Memory++;
                    *RingSample = *Memory++;
                    if(macOS_Sound.WriteIndex >= macOS_Sound.SizeInSampleFrames)
                    {
                        macOS_Sound.WriteIndex = 0;
                    }
                    
                }
                
                
                [Texture replaceRegion:MTLRegionMake2D(0, 0, TextureWidth,
                                                       TextureHeight)
                 mipmapLevel:0
                 withBytes:GameBitmap.Memory
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
                
            }
            
            game_input *Temp = NewInput;
            NewInput = OldInput;
            OldInput = Temp;
            
            u64 EndCounter  = mach_absolute_time();
            u64 Elapsed     = EndCounter - StartCounter;
            u64 NanoSeconds = Elapsed * Timebase.numer / Timebase.denom;
            f64 Milliseconds     = NanoSeconds / 1e6;
            NSLog(@"%.3f seconds\n", Milliseconds);
            
            StartCounter = EndCounter;
        }
        
        AudioOutputUnitStop(OutputUnit);
        
        NSLog(@"Handmade Game finished running\n");
    }
}
