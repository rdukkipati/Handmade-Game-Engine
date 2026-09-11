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

#include <unistd.h>

#include "macOS_keyboard.h"

// vm_allocate
// Getting screen size

// Reducing c runtime
//

#include <sys/stat.h>

#include <copyfile.h>
#include <dlfcn.h>

#include "handmade.h"


struct macOS_replay_buffer
{
    
    i32 FileDescriptor;
    char *Filename;
    void *MemoryBlock;
};

struct macOS_state
{
    
    u64 MemorySize;
    void *GameMemoryBlock;
    macOS_replay_buffer ReplayBuffers[4];
    char InputReplayFilenames[4][PATH_MAX];
    
    i32 RecordingFileDescriptor;
    i32 InputRecordingIndex;
    
    i32 PlaybackFileDescriptor;
    i32 InputPlayingIndex;
    
    
};


global_variable b32 GLOBAL_RUNNING            = true;

global_variable id<MTLTexture>        Texture = nil;
global_variable MTLTextureDescriptor *TextureDescriptor;
global_variable id<MTLDevice> Device        = nil;

#define BITMAP_WIDTH 960
#define BITMAP_HEIGHT 540
#define SCREEN_TEXTURE_WIDTH (BITMAP_WIDTH * 2)
#define SCREEN_TEXTURE_HEIGHT (BITMAP_HEIGHT * 2)
#define BYTES_PER_PIXEL 4
#define BITMAP_PITCH (BITMAP_WIDTH * BYTES_PER_PIXEL)

#define SAMPLE_FRAMES_PER_SECOND 48000
#define BYTES_PER_SAMPLE_FRAME ((i32)(sizeof(i16) * 2))

#define SOUND_LATENCY 3200
#define GAME_SOUND_SIZE_IN_BYTES (SOUND_LATENCY * BYTES_PER_SAMPLE_FRAME)
#define RING_BUFFER_SIZE_IN_BYTES (SAMPLE_FRAMES_PER_SECOND * BYTES_PER_SAMPLE_FRAME * 2)


global_variable u8            OldKeyboardState[128] = {};

global_variable CGFloat ScreenTextureWidthInPoints = 0;
global_variable CGFloat ScreenTextureHeightInPoints = 0;



DEBUG_PLATFORM_FREE_FILE_MEMORY(DEBUGPlatformFreeFileMemory)
{
    if(Memory)
    {
        free(Memory);
    }
}


DEBUG_PLATFORM_READ_ENTIRE_FILE(DEBUGPlatformReadEntireFile)
{
    debug_read_file_result Result         = {};
    i32                    FileDescriptor = open(Filename, O_RDONLY);
    if(FileDescriptor != -1)
    {
        struct stat FileStat;
        if(fstat(FileDescriptor, &FileStat) == 0)
        {
            u32 FileSize32  = (u32)FileStat.st_size;
            i32 result      = -1;
            
            Result.Contents = (char *)malloc(FileSize32);
            if(Result.Contents)
            {
                result = 0;
            }
            if(result == 0)
            {
                ssize_t BytesRead;
                BytesRead = read(FileDescriptor, Result.Contents, FileSize32);
                if(BytesRead == FileSize32)
                {
                    Result.ContentsSize = FileSize32;
                }
                else
                {
                    DEBUGPlatformFreeFileMemory(Result.Contents);
                    Result.Contents = 0;
                }
            }
            else
            {
                NSLog(@"DEBUGPlatformReadEntireFile %s: vm_allocate error: %d: "
                      @"%s\n",
                      Filename, errno, strerror(errno));
            }
        }
        else
        {
            NSLog(@"DEBUGPlatformReadEntireFile %s: fstat error: %d: %s\n",
                  Filename, errno, strerror(errno));
        }
        
        close(FileDescriptor);
    }
    else
    {
        NSLog(@"DEBUGPlatformReadEntireFile %s: open error: %d: %s\n", Filename,
              errno, strerror(errno));
    }
    
    return Result;
}

DEBUG_PLATFORM_WRITE_ENTIRE_FILE(DEBUGPlatformWriteEntireFile)
{
    b32 Result         = false;
    i32 FileDescriptor = open(Filename, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if(FileDescriptor != -1)
    {
        ssize_t BytesWritten = write(FileDescriptor, Memory, MemorySize);
        Result               = (BytesWritten == MemorySize);
        if(!Result)
        {
        }
        
        close(FileDescriptor);
    }
    else
    {
    }
    
    return Result;
}

struct macOS_sound_output
{
    i32 *RingBuffer;
    i32  SizeInSampleFrames;
    i32  ReadIndex;
    i32  WriteIndex;
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
    
    macOS_sound_output *macOS_Sound  = (macOS_sound_output *)InRefCon;
    i32                 WriteIndex   = macOS_Sound->WriteIndex;
    
    i16                *OutputBuffer = (i16 *)IOData->mBuffers[0].mData;
    
    UInt32              SampleFrame  = 0;
    while(macOS_Sound->ReadIndex != WriteIndex && SampleFrame < InNumberFrames)
    {
        i16 *RingSample =
            (i16 *)&macOS_Sound->RingBuffer[macOS_Sound->ReadIndex++];
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

@interface HandmadeApplicationDelegate
: NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@implementation HandmadeApplicationDelegate

- (NSSize)windowWillResize:(NSWindow *)Window toSize:(NSSize)FrameSize
{
    
    NSRect  WindowRect  = [Window frame];
    NSRect  ContentRect = [Window contentRectForFrameRect:WindowRect];
    
    CGFloat WindowMinusContentWidth  = (WindowRect.size.width -
                                        ContentRect.size.width);
    CGFloat WindowMinusContentHeight = (WindowRect.size.height -
                                        ContentRect.size.height);
    
    CGFloat NewContentHeight = (9.0 *
                                (FrameSize.width - WindowMinusContentWidth)) /
        16.0;
    
    FrameSize.height         = NewContentHeight + WindowMinusContentHeight;
    
    return FrameSize;
}

- (void)windowDidResize:(NSNotification *)Notification
{
    NSWindow *Window = [Notification object];
    NSView *ContentView = [Window contentView];
    CAMetalLayer *MetalLayer = (CAMetalLayer *)[ContentView layer];
    
    NSRect Bounds = [ContentView bounds];
    
    [MetalLayer setFrame:NSMakeRect((Bounds.size.width - ScreenTextureWidthInPoints) / 2, (Bounds.size.height - ScreenTextureHeightInPoints) / 2, ScreenTextureWidthInPoints, ScreenTextureHeightInPoints)];
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
    i32   DirectoryLength     = (i32)(ExecutableDirectory - ExecutablePath);
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

struct macOS_game_code
{
    void *GameCodeDLL;
    timespec LastWrite;
    
    game_update_and_render *UpdateAndRender;
    game_get_sound_samples *GetSoundSamples;
    
    b32 IsValid;
};

internal timespec 
macOS_GetLastWriteTime(char *Filename)
{
    struct stat FileData = {};
    
    timespec Result = {};
    
    if(stat(Filename, &FileData) == 0)
    {
        Result = FileData.st_mtimespec;
    }
    
    return Result;
}

internal void
macOS_LoadGameCode(macOS_game_code *GameCode, char *GameFullPath, char *CopyFullPath)
{
    
    copyfile(GameFullPath, CopyFullPath, NULL, COPYFILE_ALL);
    
    GameCode->GameCodeDLL = dlopen(CopyFullPath, RTLD_NOW);
    if(GameCode->GameCodeDLL)
    {
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpedantic"
        
        GameCode->UpdateAndRender = (game_update_and_render *)dlsym(GameCode->GameCodeDLL, "GameUpdateAndRender");
        
        GameCode->GetSoundSamples = (game_get_sound_samples *)dlsym(GameCode->GameCodeDLL, "GameGetSoundSamples");
        
#pragma clang diagnostic pop
        
        GameCode->IsValid = (GameCode->UpdateAndRender && GameCode->GetSoundSamples);
        
        
    }
    
    if(!GameCode->IsValid)
    {
        
        GameCode->UpdateAndRender = GameUpdateAndRenderStub;
        GameCode->GetSoundSamples = GameGetSoundSamplesStub;
    }
    
    
}

internal void
macOS_UnloadGameCode(macOS_game_code *GameCode)
{
    
    if(GameCode->GameCodeDLL)
    {
        
        dlclose(GameCode->GameCodeDLL);
        GameCode->GameCodeDLL = 0;
    }
    
    GameCode->IsValid = false;
    GameCode->UpdateAndRender = GameUpdateAndRenderStub;
    GameCode->GetSoundSamples = GameGetSoundSamplesStub;
}


internal void
macOS_ProcessKeyboardMessage(game_button_state *ButtonState, b32 IsDown)
{
    
    Assert(ButtonState->EndedDown != IsDown);
    ButtonState->EndedDown = IsDown;
    ++ButtonState->HalfTransitionCount;
}

internal void
macOS_ProcessButton(b32 Pressed, game_button_state *ButtonState)
{
    
    ButtonState->HalfTransitionCount = (ButtonState->EndedDown != Pressed) ? 1
        : 0;
    ButtonState->EndedDown           = Pressed;
}

inline f64
GetMillisecondsElapsed(u64 EndCounter, u64 StartCounter,
                       mach_timebase_info_data_t Timebase)
{
    u64 Elapsed      = EndCounter - StartCounter;
    u64 NanoSeconds  = Elapsed * Timebase.numer / Timebase.denom;
    f64 Milliseconds = NanoSeconds / 1e6;
    return Milliseconds;
}

internal macOS_replay_buffer *
macOS_GetReplayBuffer(macOS_state *State, i32 Index)
{
    
    Assert(Index < ArrayCount(State->ReplayBuffers));
    macOS_replay_buffer *Result = &State->ReplayBuffers[Index];
    return Result;
}

internal void
macOS_BeginRecordingInput(macOS_state *State, i32 InputRecordingIndex)
{
    
    macOS_replay_buffer *ReplayBuffer = macOS_GetReplayBuffer(State, InputRecordingIndex);
    if(ReplayBuffer->MemoryBlock)
    {
        
        State->InputRecordingIndex = InputRecordingIndex;
        
        char *Filename = State->InputReplayFilenames[InputRecordingIndex];
        State->RecordingFileDescriptor = open(Filename, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        
        memcpy(ReplayBuffer->MemoryBlock, State->GameMemoryBlock, State->MemorySize);
        
        
    }
}

internal void
macOS_EndRecordingInput(macOS_state *State)
{
    close(State->RecordingFileDescriptor);
    State->InputRecordingIndex = -1;
}

internal void
macOS_BeginInputPlayback(macOS_state *State, i32 InputPlayingIndex)
{
    
    macOS_replay_buffer *ReplayBuffer = macOS_GetReplayBuffer(State, InputPlayingIndex);
    if(ReplayBuffer->MemoryBlock)
    {
        
        State->InputPlayingIndex = InputPlayingIndex;
        
        char *Filename = State->InputReplayFilenames[InputPlayingIndex];
        State->PlaybackFileDescriptor = open(Filename, O_RDONLY);
        
        memcpy(State->GameMemoryBlock, ReplayBuffer->MemoryBlock, State->MemorySize);
    }
}

internal void
macOS_EndInputPlayback(macOS_state *State)
{
    
    close(State->PlaybackFileDescriptor);
    State->InputPlayingIndex = -1;
}

internal void
macOS_RecordInput(macOS_state *State, game_input *NewInput)
{
    
    write(State->RecordingFileDescriptor, NewInput, sizeof(*NewInput));
}

internal void
macOS_PlaybackInput(macOS_state *State, game_input *NewInput)
{
    
    ssize_t BytesRead = read(
                             State->PlaybackFileDescriptor,
                             NewInput,
                             sizeof(*NewInput));
    
    if(BytesRead > 0)
    {
        
        // Successfully read input
    }
    else if(BytesRead == 0)
    {
        
        // EOF — restart playback
        i32 PlayingIndex = State->InputPlayingIndex;
        macOS_EndInputPlayback(State);
        macOS_BeginInputPlayback(State, PlayingIndex);
        read(State->PlaybackFileDescriptor, NewInput, sizeof(*NewInput));
        
    }
    else
    {
        
        // Error
    }
}

i32
main()
{
    
    exe_state EXEState;
    GetExecutablePath(&EXEState);
    
    macOS_state State = {};
    State.InputRecordingIndex = -1;
    State.InputPlayingIndex = -1;
    
    char GameFilename[] = "handmade.dylib";
    char CopyFilename[] = "handmade_temp.dylib";
    char GameFullPath[PATH_MAX];
    char CopyFullPath[PATH_MAX];
    BuildFullPath(&EXEState, GameFilename, sizeof(GameFilename), GameFullPath);
    BuildFullPath(&EXEState, CopyFilename, sizeof(CopyFilename), CopyFullPath);
    
    char ReplayFilename1[] = "replay1.hmi";
    char ReplayFilename2[] = "replay2.hmi";
    char ReplayFilename3[] = "replay3.hmi";
    char ReplayFilename4[] = "replay4.hmi";
    char ReplayFullPaths[4][PATH_MAX];
    BuildFullPath(&EXEState, ReplayFilename1, sizeof(ReplayFilename1), ReplayFullPaths[0]);
    BuildFullPath(&EXEState, ReplayFilename2, sizeof(ReplayFilename2), ReplayFullPaths[1]);
    BuildFullPath(&EXEState, ReplayFilename3, sizeof(ReplayFilename3), ReplayFullPaths[2]);
    BuildFullPath(&EXEState, ReplayFilename4, sizeof(ReplayFilename4), ReplayFullPaths[3]);
    
    
    char InputFilename1[] = "input1.hmi";
    char InputFilename2[] = "input2.hmi";
    char InputFilename3[] = "input3.hmi";
    char InputFilename4[] = "input4.hmi";
    BuildFullPath(&EXEState, InputFilename1, sizeof(InputFilename1), State.InputReplayFilenames[0]);
    BuildFullPath(&EXEState, InputFilename2, sizeof(InputFilename2), State.InputReplayFilenames[1]);
    BuildFullPath(&EXEState, InputFilename3, sizeof(InputFilename3), State.InputReplayFilenames[2]);
    BuildFullPath(&EXEState, InputFilename4, sizeof(InputFilename4), State.InputReplayFilenames[3]);
    
    i32 MonitorRefreshHz           = 60;
    i32 GameUpdateHz               = MonitorRefreshHz / 2;
    f64 TargetMillisecondsPerFrame = 1000.0 / (f64)GameUpdateHz;
    f64 TargetSecondsPerFrame = 1.0 / (f64)GameUpdateHz;
    
    
    
    @autoreleasepool
    {
        
#if HANDMADE_INTERNAL
        vm_address_t BaseAddress = (vm_address_t)Terabytes(2);
        int          Flags       = VM_FLAGS_FIXED;
#else
        vm_address_t BaseAddress = 0;
        int          Flags       = VM_FLAGS_ANYWHERE;
#endif
        
        game_memory GameMemory          = {};
        GameMemory.PermanentStorageSize = Megabytes(64);
        GameMemory.TransientStorageSize = Gigabytes(1);
        GameMemory.DEBUGPlatformFreeFileMemory = DEBUGPlatformFreeFileMemory;
        GameMemory.DEBUGPlatformReadEntireFile = DEBUGPlatformReadEntireFile;
        GameMemory.DEBUGPlatformWriteEntireFile = DEBUGPlatformWriteEntireFile;
        
        State.MemorySize = GameMemory.PermanentStorageSize +
            GameMemory.TransientStorageSize;
        
        kern_return_t Result;
        Result = vm_allocate(mach_task_self(), &BaseAddress, State.MemorySize, Flags);
        if(Result != KERN_SUCCESS)
        {
            NSLog(@"vm_allocate for game memory failed: %s",
                  mach_error_string(Result));
            return 1;
        }
        
        State.GameMemoryBlock = (void *)BaseAddress;
        
        GameMemory.PermanentStorage = State.GameMemoryBlock;
        GameMemory.TransientStorage = ((u8 *)GameMemory.PermanentStorage +
                                       GameMemory.PermanentStorageSize);
        
        
        for(i32 ReplayIndex = 0; ReplayIndex < ArrayCount(State.ReplayBuffers); ++ReplayIndex)
        {
            
            macOS_replay_buffer *ReplayBuffer = &State.ReplayBuffers[ReplayIndex];
            
            ReplayBuffer->Filename = ReplayFullPaths[ReplayIndex];
            
            ReplayBuffer->FileDescriptor = open(ReplayBuffer->Filename, O_RDWR | O_CREAT | O_TRUNC, 0666);
            
            if(ftruncate(ReplayBuffer->FileDescriptor, (off_t)State.MemorySize) == 0)
            {
                
                ReplayBuffer->MemoryBlock = mmap(0, State.MemorySize, PROT_READ | PROT_WRITE, MAP_SHARED, ReplayBuffer->FileDescriptor, 0);
                
                if(ReplayBuffer->MemoryBlock != MAP_FAILED)
                {
                    
                }
                else
                {
                    
                }
            }
            
            
        }
        
        
        mach_timebase_info_data_t Timebase;
        mach_timebase_info(&Timebase);
        
        macOS_sound_output macOS_Sound     = {};
        macOS_Sound.SizeInSampleFrames     = SAMPLE_FRAMES_PER_SECOND * 2;
        
        game_sound_output_buffer GameSound = {};
        GameSound.SampleFramesPerSecond    = SAMPLE_FRAMES_PER_SECOND;
        
        game_offscreen_buffer GameBitmap   = {};
        GameBitmap.BytesPerPixel = BYTES_PER_PIXEL;
        
        // Allocate macOS_Sound
        Result                             = vm_allocate(
                                                         mach_task_self(), (vm_address_t *)&macOS_Sound.RingBuffer,
                                                         (vm_size_t)RING_BUFFER_SIZE_IN_BYTES, VM_FLAGS_ANYWHERE);
        
        if(Result != KERN_SUCCESS)
        {
            NSLog(@"vm_allocate for macOS_Sound failed: %s",
                  mach_error_string(Result));
            return 1;
        }
        
        // Allocate GameSound
        Result = vm_allocate(
                             mach_task_self(), (vm_address_t *)&GameSound.Memory,
                             (vm_size_t)GAME_SOUND_SIZE_IN_BYTES, VM_FLAGS_ANYWHERE);
        
        if(Result != KERN_SUCCESS)
        {
            NSLog(@"vm_allocate for RingBuffer failed: %s",
                  mach_error_string(Result));
            return 1;
        }
        
        // Allocate GameBitmap
        Result = vm_allocate(mach_task_self(),
                             (vm_address_t *)&GameBitmap.Memory,
                             BITMAP_WIDTH * BITMAP_HEIGHT * BYTES_PER_PIXEL, VM_FLAGS_ANYWHERE);
        
        if(Result != KERN_SUCCESS)
        {
            NSLog(@"vm_allocate for BitmapMemory failed: %s",
                  mach_error_string(Result));
            return 1;
        }
        
        NSString      *ApplicationName = @"Handmade Game";
        
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
        
        NSRect InitialFrame = NSMakeRect(0, 0, 0, 0);
        
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
        
        // Resize window so it's based off our texture's width and height
        CGFloat Scale = [Window backingScaleFactor];
        CGFloat ScreenTextureWidthInPoints = SCREEN_TEXTURE_WIDTH / Scale; 
        CGFloat ScreenTextureHeightInPoints = SCREEN_TEXTURE_HEIGHT / Scale;
        
        NSRect NewFrame = NSMakeRect(
                                     (ScreenRect.size.width - ScreenTextureWidthInPoints) * 0.5f,
                                     (ScreenRect.size.height - ScreenTextureHeightInPoints) * 0.5f, ScreenTextureWidthInPoints,
                                     ScreenTextureHeightInPoints);
        
        [Window setFrame:NewFrame display:YES];
        
        
        [Window setBackgroundColor:[NSColor windowBackgroundColor]];
        [Window setDelegate:ApplicationDelegate];
        [Window setMinSize:NSMakeSize(ScreenTextureWidthInPoints, ScreenTextureHeightInPoints)];
        [Window setTitle:ApplicationName];
        [Window makeKeyAndOrderFront:nil];
        
        char MetalLibraryFilename[] = "shaders.metallib";
        char MetalLibraryFullPath[PATH_MAX];
        BuildFullPath(&EXEState, MetalLibraryFilename,
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
        [MetalLayer setDrawableSize:CGSizeMake(SCREEN_TEXTURE_WIDTH, SCREEN_TEXTURE_HEIGHT)];
        [MetalLayer setFramebufferOnly:YES];
        [MetalLayer setPresentsWithTransaction:NO];
        
        NSView *ContentView = [Window contentView];
        
        NSRect Bounds = [ContentView bounds];
        
        [MetalLayer setFrame:NSMakeRect((Bounds.size.width - ScreenTextureWidthInPoints) / 2, (Bounds.size.height - ScreenTextureHeightInPoints) / 2, ScreenTextureWidthInPoints, ScreenTextureHeightInPoints)];
        
        
        
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
                             width:BITMAP_WIDTH
                             height:BITMAP_HEIGHT
                             mipmapped:NO];
        
        Texture           = [Device newTextureWithDescriptor:TextureDescriptor];
        if(!Texture)
        {
            NSLog(@"Texture allocation failed");
            return 1;
        }
        
        MTLSamplerDescriptor *SamplerDescriptor = [[MTLSamplerDescriptor alloc] init];
        
        SamplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
        SamplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
        
        id<MTLSamplerState> Sampler = [Device newSamplerStateWithDescriptor:SamplerDescriptor];
        if(!Sampler)
        {
            NSLog(@"Sampler allocation failed");
            return 1;
        }
        
        float VerticesAndUVs[]    = {
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
        VertexDescriptor.attributes[1].format      = MTLVertexFormatFloat2;
        VertexDescriptor.attributes[1].bufferIndex = 0;
        VertexDescriptor.attributes[1].offset      = 2 * sizeof(float);
        VertexDescriptor.layouts[0].stride         = 4 * sizeof(float);
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
        StreamFormat.mSampleRate                 = SAMPLE_FRAMES_PER_SECOND;
        StreamFormat.mFormatID                   = kAudioFormatLinearPCM;
        StreamFormat.mFormatFlags       = kAudioFormatFlagIsSignedInteger |
            kAudioFormatFlagIsPacked;
        StreamFormat.mBytesPerPacket    = 4;
        StreamFormat.mFramesPerPacket   = 1;
        StreamFormat.mBytesPerFrame     = (u32)BYTES_PER_SAMPLE_FRAME;
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
        
        // game_input Input[2] = {};
        // game_input *NewInput = &Input[0];
        // game_input *OldInput = &Input[1];
        
        macOS_game_code Game = {};
        Game.LastWrite = macOS_GetLastWriteTime(GameFullPath);
        macOS_LoadGameCode(&Game, GameFullPath, CopyFullPath);
        
        game_input             Input              = {};
        Input.SecondsToAdvanceOverUpdate = (f32)TargetSecondsPerFrame;
        game_controller_input *KeyboardController = GetController(&Input, 0);
        KeyboardController->IsConnected           = true;
        
        Error = AudioUnitInitialize(OutputUnit);
        Error = AudioOutputUnitStart(OutputUnit);
        
        NSEvent *Event;
        
        u64      StartCounter = mach_absolute_time();
        
        while(GLOBAL_RUNNING)
        {
            timespec NewLastWrite = macOS_GetLastWriteTime(GameFullPath);
            if(NewLastWrite.tv_sec != Game.LastWrite.tv_sec || NewLastWrite.tv_nsec != Game.LastWrite.tv_nsec)
            {
                Game.LastWrite = NewLastWrite;
                macOS_UnloadGameCode(&Game);
                macOS_LoadGameCode(&Game, GameFullPath, CopyFullPath);
            }
            
            for(i32 ButtonIndex = 0;
                ButtonIndex < ArrayCount(KeyboardController->Buttons);
                ++ButtonIndex)
            {
                KeyboardController->Buttons[ButtonIndex].HalfTransitionCount =
                    0;
            }
            
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
                                    
                                    case kVK_ANSI_W:
                                    {
                                        
                                        macOS_ProcessKeyboardMessage(
                                                                     &KeyboardController->MoveUp,
                                                                     IsDown);
                                    }
                                    break;
                                    
                                    case kVK_ANSI_A:
                                    {
                                        
                                        macOS_ProcessKeyboardMessage(
                                                                     &KeyboardController->MoveLeft,
                                                                     IsDown);
                                    }
                                    break;
                                    
                                    case kVK_ANSI_S:
                                    {
                                        
                                        macOS_ProcessKeyboardMessage(
                                                                     &KeyboardController->MoveDown,
                                                                     IsDown);
                                    }
                                    break;
                                    
                                    case kVK_ANSI_D:
                                    {
                                        
                                        macOS_ProcessKeyboardMessage(
                                                                     &KeyboardController->MoveRight,
                                                                     IsDown);
                                    }
                                    break;
                                    
                                    case kVK_ANSI_Q:
                                    {
                                        
                                        macOS_ProcessKeyboardMessage(
                                                                     &KeyboardController->LeftShoulder,
                                                                     IsDown);
                                    }
                                    break;
                                    
                                    case kVK_ANSI_E:
                                    {
                                        
                                        macOS_ProcessKeyboardMessage(
                                                                     &KeyboardController->RightShoulder,
                                                                     IsDown);
                                    }
                                    break;
                                    
                                    case kVK_UpArrow:
                                    {
                                        
                                        macOS_ProcessKeyboardMessage(
                                                                     &KeyboardController->ActionUp,
                                                                     IsDown);
                                    }
                                    break;
                                    
                                    case kVK_LeftArrow:
                                    {
                                        
                                        macOS_ProcessKeyboardMessage(
                                                                     &KeyboardController->ActionLeft,
                                                                     IsDown);
                                    }
                                    break;
                                    
                                    case kVK_DownArrow:
                                    {
                                        
                                        macOS_ProcessKeyboardMessage(
                                                                     &KeyboardController->ActionDown,
                                                                     IsDown);
                                    }
                                    break;
                                    
                                    case kVK_RightArrow:
                                    {
                                        
                                        macOS_ProcessKeyboardMessage(
                                                                     &KeyboardController->ActionRight,
                                                                     IsDown);
                                    }
                                    break;
                                    
                                    case kVK_Escape:
                                    {
                                        
                                        macOS_ProcessKeyboardMessage(
                                                                     &KeyboardController->Start, IsDown);
                                    }
                                    break;
                                    
                                    case kVK_Space:
                                    {
                                        
                                        macOS_ProcessKeyboardMessage(
                                                                     &KeyboardController->Back, IsDown);
                                    }
                                    break;
                                    
#if HANDMADE_INTERNAL
                                    
                                    case kVK_ANSI_L:
                                    {
                                        
                                        if(IsDown)
                                        {
                                            if(State.InputPlayingIndex == -1)
                                            {
                                                if(State.InputRecordingIndex == -1)
                                                {
                                                    
                                                    macOS_BeginRecordingInput(&State, 0);
                                                }
                                                
                                                else
                                                {
                                                    
                                                    macOS_EndRecordingInput(&State);
                                                    macOS_BeginInputPlayback(&State, 0);
                                                }
                                            }
                                            else
                                            {
                                                macOS_EndInputPlayback(&State);
                                            }
                                            
                                        }
                                    }
                                    break;
                                    
#endif
                                }
                            }
                            
                            OldKeyboardState[KeyCode] = (u8)IsDown;
                        }
                        break;
                        
                        default:
                        {
                            
                            [NSApp sendEvent:Event];
                        }
                        break;
                    }
                    
                } while(Event != nil);
                
                
                NSPoint screenPoint = [NSEvent mouseLocation];
                
                NSPoint windowPoint = [Window convertPointFromScreen:screenPoint];
                
                NSView *contentView = Window.contentView;
                NSPoint viewPoint = [contentView convertPoint:windowPoint fromView:nil];
                
                NSPoint pixelPoint = [contentView convertPointToBacking:viewPoint];
                
                i32 MouseX = (i32)pixelPoint.x;
                i32 MouseY = (i32)(contentView.bounds.size.height * contentView.window.backingScaleFactor
                                   - pixelPoint.y);
                
                i32 Width = (i32)(contentView.bounds.size.width * contentView.window.backingScaleFactor);
                i32 Height = (i32)(contentView.bounds.size.height * contentView.window.backingScaleFactor);
                
                
                if(MouseX < 0) MouseX = 0;
                if(MouseX > Width) MouseX = Width;
                
                if(MouseY < 0) MouseY = 0;
                if(MouseY > Height) MouseY = Height;
                
                Input.MouseX = MouseX / 2;
                Input.MouseY = MouseY / 2;
                Input.MouseZ = 0;
                
                
                b32 MouseDown = ([NSEvent pressedMouseButtons] & (1 << 0)) != 0;
                
                macOS_ProcessButton(MouseDown, &Input.MouseButtons[0]);
                
                NSArray<GCController *> *Controllers =
                    [GCController controllers];
                
                i32 ControllerIndex = 1;
                for(GCController *Controller in Controllers)
                {
                    
                    if(ControllerIndex >= 5)
                    {
                        break;
                    }
                    
                    game_controller_input *GameController =
                        &Input.Controllers[ControllerIndex];
                    
                    GCExtendedGamepad *Gamepad = [Controller extendedGamepad];
                    if(Gamepad)
                    {
                        
                        GameController->IsConnected = true;
                        GameController->IsAnalog = true;
                        
                        GameController->StickAverageX =
                            [[[Gamepad leftThumbstick] xAxis] value];
                        GameController->StickAverageY =
                            [[[Gamepad leftThumbstick] yAxis] value];
                        
                        /*
                        if((GameController->StickAverageX != 0.0f) ||
                           (GameController->StickAverageY != 0.0f))
                        {
                            
                            GameController->IsAnalog = true;
                        }
*/
                        
                        GCControllerDirectionPad *DPad = [Gamepad dpad];
                        
                        if([[DPad up] isPressed])
                        {
                            GameController->StickAverageY = 1.0f;
                            GameController->IsAnalog      = false;
                            
                        }
                        
                        if([[DPad down] isPressed])
                        {
                            GameController->StickAverageY = -1.0f;
                            GameController->IsAnalog      = false;
                        }
                        
                        if([[DPad left] isPressed])
                        {
                            GameController->StickAverageX = -1.0f;
                            GameController->IsAnalog      = false;
                        }
                        
                        if([[DPad right] isPressed])
                        {
                            GameController->StickAverageX = 1.0f;
                            GameController->IsAnalog      = false;
                        }
                        
                        f32 Threshold = 0.5f;
                        
                        macOS_ProcessButton(
                                            (GameController->StickAverageX < -Threshold) ? 1
                                            : 0,
                                            &GameController->MoveLeft);
                        
                        macOS_ProcessButton(
                                            (GameController->StickAverageX > Threshold) ? 1 : 0,
                                            &GameController->MoveRight);
                        
                        macOS_ProcessButton(
                                            (GameController->StickAverageY < -Threshold) ? 1
                                            : 0,
                                            &GameController->MoveDown);
                        
                        macOS_ProcessButton(
                                            (GameController->StickAverageY > Threshold) ? 1 : 0,
                                            &GameController->MoveUp);
                        
                        /*
                        f32  RightStick_X  = [[[Gamepad rightThumbstick]
                        xAxis] value]; f32  RightStick_Y  = [[[Gamepad
                        rightThumbstick] yAxis] value];
*/
                        
                        macOS_ProcessButton([[Gamepad buttonA] isPressed],
                                            &GameController->ActionDown);
                        
                        macOS_ProcessButton([[Gamepad buttonB] isPressed],
                                            &GameController->ActionRight);
                        
                        macOS_ProcessButton([[Gamepad buttonX] isPressed],
                                            &GameController->ActionLeft);
                        
                        macOS_ProcessButton([[Gamepad buttonY] isPressed],
                                            &GameController->ActionUp);
                        
                        macOS_ProcessButton([[Gamepad leftShoulder] isPressed],
                                            &GameController->LeftShoulder);
                        
                        macOS_ProcessButton([[Gamepad rightShoulder] isPressed],
                                            &GameController->RightShoulder);
                        
                        macOS_ProcessButton([[Gamepad buttonMenu] isPressed],
                                            &GameController->Start);
                        
                        macOS_ProcessButton([[Gamepad buttonOptions] isPressed],
                                            &GameController->Back);
                    }
                    else
                    {
                        
                        GameController->IsConnected = false;
                    }
                    
                    ++ControllerIndex;
                }
                
                while(ControllerIndex < 5)
                {
                    
                    Input.Controllers[ControllerIndex].IsConnected = false;
                    ++ControllerIndex;
                }
                
                thread_context Thread = {};
                
                GameBitmap.Width  = BITMAP_WIDTH;
                GameBitmap.Height = BITMAP_HEIGHT;
                GameBitmap.Pitch  = BITMAP_PITCH;
                
                if(State.InputRecordingIndex >= 0)
                {
                    
                    macOS_RecordInput(&State, &Input);
                }
                
                if(State.InputPlayingIndex >= 0)
                {
                    
                    macOS_PlaybackInput(&State, &Input);
                }
                
                Game.UpdateAndRender(&Thread, &GameMemory, &Input, &GameBitmap);
                
                // ReadWriteDiff is in SampleFrames
                i32 ReadWriteDiff = 0;
                i32 ReadIndex     = macOS_Sound.ReadIndex;
                
                if(macOS_Sound.WriteIndex >= ReadIndex)
                {
                    ReadWriteDiff = macOS_Sound.WriteIndex - ReadIndex;
                }
                
                else
                {
                    ReadWriteDiff = (macOS_Sound.SizeInSampleFrames -
                                     ReadIndex) +
                        (macOS_Sound.WriteIndex);
                }
                
                
                GameSound.SampleFramesToWrite = SOUND_LATENCY - ReadWriteDiff;
                Assert(GameSound.SampleFramesToWrite >= 0);
                
                
                Game.GetSoundSamples(&Thread, &GameMemory, &GameSound);
                
                // Copy game sound into ring buffer
                i16 *Memory = GameSound.Memory;
                
                for(int Sample = 0; Sample < GameSound.SampleFramesToWrite;
                    ++Sample)
                {
                    i16 *RingSample = (i16 *)&macOS_Sound
                        .RingBuffer[macOS_Sound.WriteIndex++];
                    *RingSample++   = *Memory++;
                    *RingSample     = *Memory++;
                    if(macOS_Sound.WriteIndex >= macOS_Sound.SizeInSampleFrames)
                    {
                        macOS_Sound.WriteIndex = 0;
                    }
                }
                
                [Texture replaceRegion:MTLRegionMake2D(0, 0, BITMAP_WIDTH,
                                                       BITMAP_HEIGHT)
                 mipmapLevel:0
                 withBytes:GameBitmap.Memory
                 bytesPerRow:BITMAP_PITCH];
                
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
                [RenderCommandEncoder setFragmentSamplerState:Sampler atIndex:0];
                
                [RenderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                 vertexStart:0
                 vertexCount:6];
                
                [RenderCommandEncoder endEncoding];
                [CommandBuffer presentDrawable:Drawable];
                [CommandBuffer commit];
                //[CommandBuffer waitUntilCompleted];
            }
            
            u64 EndCounter          = mach_absolute_time();
            f64 MillisecondsElapsed = GetMillisecondsElapsed(
                                                             EndCounter, StartCounter, Timebase);
            
            if(MillisecondsElapsed < TargetMillisecondsPerFrame)
            {
                f64 SleepMS = TargetMillisecondsPerFrame - MillisecondsElapsed;
                if(SleepMS > 2.0)
                {
                    u64 SleepUS = (u64)((SleepMS - 2.0) * 1000.0);
                    usleep((useconds_t)(SleepUS));
                }
                
                f64 TestMillisecondsElapsedForFrame = GetMillisecondsElapsed(
                                                                             mach_absolute_time(), StartCounter, Timebase);
                Assert(TestMillisecondsElapsedForFrame <
                       TargetMillisecondsPerFrame);
                
                while(TestMillisecondsElapsedForFrame <
                      TargetMillisecondsPerFrame)
                {
                    TestMillisecondsElapsedForFrame = GetMillisecondsElapsed(
                                                                             mach_absolute_time(), StartCounter, Timebase);
                }
            }
            else
            {
                // TODO: Missed frame rate
            }
            
            EndCounter       = mach_absolute_time();
            f64 Milliseconds = GetMillisecondsElapsed(EndCounter, StartCounter,
                                                      Timebase);
            StartCounter     = EndCounter;
            NSLog(@"%.3f seconds\n", Milliseconds);
        }
        
        
        NSLog(@"Handmade Game finished running\n");
    }
}
