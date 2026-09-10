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

internal void
RenderPlayer(game_offscreen_buffer *Bitmap, i32 PlayerX, i32 PlayerY)
{
    
    u8 *EndOfBuffer = (u8 *)Bitmap->Memory + Bitmap->Pitch * Bitmap->Height;
    u32 Color = 0xFFFFFFFF;
    i32 Top = PlayerY;
    i32 Bottom = PlayerY + 10;
    for(i32 X = PlayerX; X < PlayerX + 10; ++X)
    {
        
        u8 *Pixel = ((u8 *)Bitmap->Memory + X * Bitmap->BytesPerPixel + Top * Bitmap->Pitch);
        
        for(int Y = Top; Y < Bottom; ++Y)
        {
            
            if((Pixel >= Bitmap->Memory) && ((Pixel + 4) <= EndOfBuffer))
            {
                
                *(u32 *)Pixel = Color;
            }
            
            Pixel += Bitmap->Pitch;
        }
    }
}

extern "C" GAME_UPDATE_AND_RENDER(GameUpdateAndRender)
{
    (void)Thread;
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
        
        GameState->PlayerX = 100;
        GameState->PlayerY = 100;
        
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
                
                if(Controller->MoveLeft.EndedDown)
                {
                    GameState->BlueOffset -= 1;
                }
                
                if(Controller->MoveRight.EndedDown)
                {
                    GameState->BlueOffset += 1;
                }
            }
            
            GameState->PlayerX += (i32)(4.0f * Controller->StickAverageX);
            GameState->PlayerY -= (i32)(4.0f * Controller->StickAverageY);
            if(GameState->tJump > 0)
            {
                
                GameState->PlayerY += (i32)(5.0f * sinf(0.5f * PI * GameState->tJump));
            }
            
            if(Controller->ActionDown.EndedDown)
            {
                
                GameState->tJump = 4.0f;
            }
            
            GameState->tJump -= 0.033f;
            
        }
        
    }
    
    RenderWeirdGradient(Bitmap, GameState->BlueOffset, GameState->GreenOffset);
    RenderPlayer(Bitmap, GameState->PlayerX, GameState->PlayerY);
    RenderPlayer(Bitmap, Input->MouseX, Input->MouseY);
    
    if(Input->MouseButtons[0].EndedDown)
    {
        RenderPlayer(Bitmap, 10 + 20*0, 10);
    }
}

extern "C" GAME_GET_SOUND_SAMPLES(GameGetSoundSamples)
{
    (void)Thread;
    game_state *GameState = (game_state *)Memory->PermanentStorage;
    GameOutputSound(GameState, Sound, GameState->ToneHz);
}
