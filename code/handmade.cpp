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
        
#if 0
        f32 SineValue    = sinf(GameState->tSine);
        i16 SampleValue  = (i16)(SineValue * ToneVolume);
#else
        i16 SampleValue = 0;
#endif
        *Memory++        = SampleValue;
        *Memory++        = SampleValue;
        
#if 0
        GameState->tSine            += (PI_2 * 1.0f / (f32)WavePeriod);
        if(GameState->tSine >= PI_2)
        {
            GameState->tSine = 0;
        }
#endif
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

internal i32
RoundReal32ToInt32(f32 Value)
{
    i32 Result = (i32)(Value + 0.5f);
    //TODO: Intrinsic?
    return Result;
}

internal void
DrawRectangle(game_offscreen_buffer *Bitmap, f32 RealMinX, f32 RealMinY, f32 RealMaxX, f32 RealMaxY, u32 Color)
{
    
    i32 MinX = RoundReal32ToInt32(RealMinX);
    i32 MinY = RoundReal32ToInt32(RealMinY);
    i32 MaxX = RoundReal32ToInt32(RealMaxX);
    i32 MaxY = RoundReal32ToInt32(RealMaxY);
    
    if(MinX < 0)
    {
        MinX = 0;
    }
    
    if(MinY < 0)
    {
        MinY = 0;
    }
    
    if(MaxX > Bitmap->Width)
    {
        MaxX = Bitmap->Width;
    }
    
    if(MaxY > Bitmap->Height)
    {
        MaxY = Bitmap->Height;
    }
    
    u8 *Row = ((u8 *)Bitmap->Memory + MinX*Bitmap->BytesPerPixel + MinY*Bitmap->Pitch);
    
    for(i32 Y = MinY; Y < MaxY; ++Y)
    {
        
        u32 *Pixel = (u32 *)Row;
        for(i32 X = MinX; X < MaxX; ++X)
        {
            
            *Pixel++ = Color;
        }
        
        Row += Bitmap->Pitch;
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
                
                
            }
            else
            {
                
                
            }
            
        }
        
    }
    
    DrawRectangle(Bitmap, 0.0f, 0.0f, (f32)Bitmap->Width, (f32)Bitmap->Height, 0x00FF00FF);
    DrawRectangle(Bitmap, 10.0f, 10.0f, 40.0f, 40.0f, 0x0000FFFF);
    
}

extern "C" GAME_GET_SOUND_SAMPLES(GameGetSoundSamples)
{
    (void)Thread;
    game_state *GameState = (game_state *)Memory->PermanentStorage;
    GameOutputSound(GameState, Sound, 400);
}


/*
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
*/


