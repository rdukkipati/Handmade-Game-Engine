#include "handmade.h"

internal void
GameOutputSound(game_sound_output_buffer *Sound, i32 ToneHz)
{
    local_persist f32 Time = 0;
    i16 ToneVolume = 3000;
    i32 WavePeriod = Sound->SampleFramesPerSecond / ToneHz;
    i16 *Memory = Sound->Memory;
    
    for(i32 SampleFrame = 0; SampleFrame < Sound->SampleFramesToWrite; ++SampleFrame)
    {
        f32 SineValue = sinf(Time);
        i16 SampleValue = (i16)(SineValue * ToneVolume);
        *Memory++ = SampleValue;
        *Memory++ = SampleValue;
        
        Time += (PI_2 * 1.0f / (f32)WavePeriod);
        if(Time >= PI_2)
        {
            Time = 0;
        }
    }
}

internal void
RenderWeirdGradient(game_offscreen_buffer *Bitmap, i32 BlueOffset, i32 GreenOffset)
{
    u8 *Row = (u8 *)Bitmap->Memory;
    for(i32 Y = 0; Y < Bitmap->Height; ++Y)
    {
        u32 *Pixel = (u32 *)Row;
        for(i32 X = 0; X < Bitmap->Width; ++X)
        {
            u8 Blue = (u8)(X + BlueOffset);
            u8 Green = (u8)(Y + GreenOffset);
            *Pixel++ = ((u32)Blue << 0) | ((u32)Green << 8) | ((u32)255 << 24);
        }
        Row += Bitmap->Pitch;
    }
}

internal void
GameUpdateAndRender(game_memory *Memory, game_input *Input, game_offscreen_buffer *Bitmap, game_sound_output_buffer *Sound)
{
    
    Assert(sizeof(game_state) <= Memory->PermanentStorageSize);
    
    game_state *GameState = (game_state *)Memory->PermanentStorage;
    
    if(!Memory->IsInitialized)
    {
        const char *Filename = __FILE__;
        debug_read_file_result File = DEBUGPlatformReadEntireFile(Filename);
        if(File.Contents)
        {
            DEBUGPlatformWriteEntireFile("test.out", File.ContentsSize, File.Contents);
            DEBUGPlatformFreeFileMemory(File.Contents);
        }
        GameState->ToneHz = 256;
        Memory->IsInitialized = true;
    }
    
    game_controller_input *Input0 = &Input->Controllers[0];
    
    if(Input0->IsAnalog)
    {
        GameState->BlueOffset += (i32)(4.0f*(Input0->EndX));
        GameState->ToneHz = 256 + (int)(128.0f*(Input0->EndY));
    }
    
    else
    {
        // Digital movement tuning
    }
    
    if(Input0->Down.EndedDown)
    {
        GameState->GreenOffset += 1;
    }
    
    GameOutputSound(Sound, GameState->ToneHz);
    RenderWeirdGradient(Bitmap, GameState->BlueOffset, GameState->GreenOffset);
    
}
