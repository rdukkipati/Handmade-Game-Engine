/* date = September 4th 2026 3:28 pm */

#ifndef HANDMADE_H

// TODO: Implement sine ourselves
#include <math.h>
#include <stdint.h>

#define internal        static
#define local_persist   static
#define global_variable static

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

#if HANDMADE_SLOW
#define Assert(Expression)                                                     \
if(!(Expression))                                                          \
{                                                                          \
__builtin_trap();                                                      \
}
#else
#define Assert(Expression)
#endif

#define Kilobytes(Value)  ((u64)(Value) * 1024)
#define Megabytes(Value)  (Kilobytes(Value) * 1024)
#define Gigabytes(Value)  (Megabytes(Value) * 1024)
#define Terabytes(Value)  (Gigabytes(Value) * 1024)

#define ArrayCount(Array) ((i32)(sizeof(Array) / sizeof((Array)[0])))

inline u32
SafeTruncate_u64(u64 Value)
{
    Assert(Value <= 0xFFFFFFFF);
    u32 Result = (u32)Value;
    return Result;
}

struct thread_context
{
    i32 Placeholder;
};

#if HANDMADE_INTERNAL

struct debug_read_file_result
{
    u32   ContentsSize;
    void *Contents;
};

#define DEBUG_PLATFORM_FREE_FILE_MEMORY(name) void name(void *Memory)
typedef DEBUG_PLATFORM_FREE_FILE_MEMORY(debug_platform_free_file_memory);

#define DEBUG_PLATFORM_READ_ENTIRE_FILE(name)                                  \
debug_read_file_result name(char *Filename)
typedef DEBUG_PLATFORM_READ_ENTIRE_FILE(debug_platform_read_entire_file);

#define DEBUG_PLATFORM_WRITE_ENTIRE_FILE(name)                                 \
b32 name(char *Filename, u32 MemorySize, void *Memory)
typedef DEBUG_PLATFORM_WRITE_ENTIRE_FILE(debug_platform_write_entire_file);

#endif

struct game_offscreen_buffer
{
    void *Memory;
    i32   Width;
    i32   Height;
    i32   Pitch;
    i32 BytesPerPixel;
};

struct game_sound_output_buffer
{
    i32  SampleFramesPerSecond;
    i32  SampleFramesToWrite;
    i16 *Memory;
};

struct game_button_state
{
    i32 HalfTransitionCount;
    b32 EndedDown;
};

struct game_controller_input
{
    b32 IsConnected;
    b32 IsAnalog;
    f32 StickAverageX;
    f32 StickAverageY;
    
    union
    {
        game_button_state Buttons[12];
        struct
        {
            game_button_state MoveUp;
            game_button_state MoveDown;
            game_button_state MoveLeft;
            game_button_state MoveRight;
            
            game_button_state ActionUp;
            game_button_state ActionDown;
            game_button_state ActionLeft;
            game_button_state ActionRight;
            
            game_button_state LeftShoulder;
            game_button_state RightShoulder;
            
            game_button_state Back;
            game_button_state Start;
            
            // NOTE(casey): All buttons must be added above this line
            
            game_button_state Terminator;
        };
    };
};

struct game_input
{
    game_button_state MouseButtons[5];
    i32 MouseX;
    i32 MouseY;
    i32 MouseZ;
    
    f32 dtForFrame;
    
    game_controller_input Controllers[5];
};

inline game_controller_input *
GetController(game_input *Input, i32 ControllerIndex)
{
    Assert(ControllerIndex < ArrayCount(Input->Controllers));
    game_controller_input *Result = &Input->Controllers[ControllerIndex];
    return Result;
}

struct game_memory
{
    b32                               IsInitialized;
    
    u64                               PermanentStorageSize;
    void                             *PermanentStorage;
    
    u64                               TransientStorageSize;
    void                             *TransientStorage;
    
    debug_platform_free_file_memory  *DEBUGPlatformFreeFileMemory;
    debug_platform_read_entire_file  *DEBUGPlatformReadEntireFile;
    debug_platform_write_entire_file *DEBUGPlatformWriteEntireFile;
};

struct game_state
{
    
    f32 PlayerX;
    f32 PlayerY;
};

#define GAME_UPDATE_AND_RENDER(name) void name(thread_context *Thread, game_memory *Memory, game_input *Input, game_offscreen_buffer *Bitmap)
typedef GAME_UPDATE_AND_RENDER(game_update_and_render);
GAME_UPDATE_AND_RENDER(GameUpdateAndRenderStub)
{
    (void)Thread;
    (void)Memory;
    (void)Input;
    (void)Bitmap;
}

#define GAME_GET_SOUND_SAMPLES(name) void name(thread_context *Thread, game_memory *Memory, game_sound_output_buffer *Sound)
typedef GAME_GET_SOUND_SAMPLES(game_get_sound_samples);
GAME_GET_SOUND_SAMPLES(GameGetSoundSamplesStub)
{
    (void)Thread;
    (void)Memory;
    (void)Sound;
}

#define HANDMADE_H
#endif
