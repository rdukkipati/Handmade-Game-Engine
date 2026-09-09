#include "handmade.h"

internal void
GameOutputSound(game_state *GameState, game_sound_output_buffer *Sound, i32 ToneHz)
{
    i16               ToneVolume = 3000;
    i32               WavePeriod = Sound->SampleFramesPerSecond / ToneHz;
    i16              *Memory     = Sound->Memory;
    
    for(i32 SampleFrame = 0; SampleFrame < Sound->SampleFramesToWrite;
        ++SampleFrame)
    {
        f32 SineValue    = sinf(GameState->tSine);
        i16 SampleValue  = (i16)(SineValue * ToneVolume);
        *Memory++        = SampleValue;
        *Memory++        = SampleValue;
        
        GameState->tSine            += (PI_2 * 1.0f / (f32)WavePeriod);
        if(GameState->tSine >= PI_2)
        {
            GameState->tSine = 0;
        }
    }
}

internal void
RenderWeirdGradient(game_offscreen_buffer *Bitmap, i32 BlueOffset,
                    i32 GreenOffset)
{
    u8 *Row = (u8 *)Bitmap->Memory;
    for(i32 Y = 0; Y < Bitmap->Height; ++Y)
    {
        u32 *Pixel = (u32 *)Row;
        for(i32 X = 0; X < Bitmap->Width; ++X)
        {
            u8 Blue  = (u8)(X + BlueOffset);
            u8 Green = (u8)(Y + GreenOffset);
            *Pixel++ = ((u32)Blue << 0) | ((u32)Green << 8) | ((u32)255 << 24);
            
        }
        Row += Bitmap->Pitch;
    }
}

extern "C" GAME_UPDATE_AND_RENDER(GameUpdateAndRender)
{
    
    Assert((&Input->Controllers[0].Terminator -
            &Input->Controllers[0].Buttons[0]) ==
           (ArrayCount(Input->Controllers[0].Buttons)));
    Assert(sizeof(game_state) <= Memory->PermanentStorageSize);
    
    game_state *GameState = (game_state *)Memory->PermanentStorage;
    
    if(!Memory->IsInitialized)
    {
        char            *Filename = __FILE__;
        debug_read_file_result File     = Memory->DEBUGPlatformReadEntireFile(Filename);
        if(File.Contents)
        {
            Memory->DEBUGPlatformWriteEntireFile("test.out", File.ContentsSize,
                                                 File.Contents);
            Memory->DEBUGPlatformFreeFileMemory(File.Contents);
        }
        GameState->ToneHz     = 256;
        GameState->tSine = 0.0f;
        Memory->IsInitialized = true;
    }
    
    for(i32 ControllerIndex = 0;
        ControllerIndex < ArrayCount(Input->Controllers); ++ControllerIndex)
    {
        game_controller_input *Controller = GetController(Input,
                                                          ControllerIndex);
        
        if(Controller->IsConnected)
        {
            if(Controller->IsAnalog)
            {
                
                GameState->BlueOffset += (i32)(4.0f * Controller->StickAverageX);
                GameState->ToneHz = 256 + (i32)(128.0f * Controller->StickAverageY);
                
            }
            else
            {
                GameState->ToneHz = 256 + (i32)(128.0f * Controller->StickAverageY);
                if(Controller->MoveLeft.EndedDown)
                {
                    GameState->BlueOffset -= 1;
                }
                
                if(Controller->MoveUp.EndedDown)
                {
                    GameState->BlueOffset -= 10;
                }
                
                if(Controller->MoveRight.EndedDown)
                {
                    GameState->BlueOffset += 1;
                }
            }
            
            if(Controller->ActionDown.EndedDown)
            {
                GameState->GreenOffset += 1;
            }
        }
        
    }
    
    RenderWeirdGradient(Bitmap, GameState->BlueOffset, GameState->GreenOffset);
}

extern "C" GAME_GET_SOUND_SAMPLES(GameGetSoundSamples)
{
    
    game_state *GameState = (game_state *)Memory->PermanentStorage;
    GameOutputSound(GameState, Sound, GameState->ToneHz);
}
