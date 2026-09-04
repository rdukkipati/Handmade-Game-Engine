/* date = September 4th 2026 3:28 pm */

#ifndef HANDMADE_H

#if HANDMADE_SLOW
#define Assert(Expression) if(!(Expression)) { __builtin_trap();}
#else
#define Assert(Expression)
#endif

#define Kilobytes(Value) ((u64)(Value)*1024)
#define Megabytes(Value) (Kilobytes(Value)*1024)
#define Gigabytes(Value) (Megabytes(Value)*1024)
#define Terabytes(Value) (Gigabytes(Value)*1024)

inline u32
SafeTruncate_u64(u64 Value)
{
    Assert(Value <= 0xFFFFFFFF);
    u32 Result = (u32)Value);
    return Result;
}

#if HANDMADE_INTERNAL

struct debug_read_file_result
{
    u32 ContentsSize;
    void *Contents;
};

internal debug_read_file_result DEBUGPlatformReadEntireFile(char *Filename);
internal void DEBUGPlatformFreeFileMemory(void *Memory);
internal b32 DEBUGPlatformWriteEntireFile(char *Filename, u32 MemorySize, void *Memory);

#endif

struct game_offscreen_buffer
{
    void *Memory;
    i32 Width;
    i32 Height;
    i32 Pitch;
};

struct game_sound_output_buffer
{
    i32 SampleFramesPerSecond;
    i32 SampleFramesToWrite;
    i16 *Memory;
};

struct game_button_state
{
    i32 HalfTransitionCount;
    b32 EndedDown;
};

struct game_controller_input
{
    b32 IsAnalog;
    
    f32 StartX;
    f32 StartY;
    
    f32 MinX;
    f32 MinY;
    
    f32 MaxX;
    f32 MaxY;
    
    f32 EndX;
    f32 EndY;
    
    union
    {
        game_button_state Buttons[6];
        struct
        {
            game_button_state Up;
            game_button_state Down;
            game_button_state Left;
            game_button_state Right;
            game_button_state LeftShoulder;
            game_button_state RightShoulder;
        };
    };
};

struct game_input
{
    game_controller_input Controllers[4];
};

struct game_memory
{
    b32 IsInitialized;
    
    u64 PermanentStorageSize;
    void *PermanentStorage;
    
    u64 TransientStorageSize;
    void *TransientStorage;
};

struct game_state
{
    i32 ToneHz;
    i32 GreenOffset;
    i32 BlueOffset;
};


internal void GameUpdateAndRender(game_memory *Memory, game_input *Input, game_offscreen_buffer *Bitmap, game_sound_output_buffer *Sound);
























#define HANDMADE_H
#endif
