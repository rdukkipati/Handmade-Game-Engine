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

internal i32
RoundReal32ToInt32(f32 Real32)
{
    i32 Result = (i32)(Real32 + 0.5f);
    //TODO: Intrinsic?
    return Result;
}

internal u32
RoundReal32ToUInt32(f32 Real32)
{
    
    u32 Result = (u32)(Real32 + 0.5f);
    return Result;
}

internal void
DrawRectangle(game_offscreen_buffer *Bitmap, f32 RealMinX, f32 RealMinY, f32 RealMaxX, f32 RealMaxY, f32 R, f32 G, f32 B)
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
    
    u32 Color = ((RoundReal32ToUInt32(R * 255.0f) << 16) | (RoundReal32ToUInt32(G * 255.0f) << 8) | (RoundReal32ToUInt32(B * 255.0f) << 0));
    
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
                
                f32 dPlayerX = 0.0f;
                f32 dPlayerY = 0.0f;
                
                if(Controller->MoveUp.EndedDown)
                {
                    
                    dPlayerY = -1.0f;
                }
                if(Controller->MoveDown.EndedDown)
                {
                    
                    dPlayerY = 1.0f;
                }
                if(Controller->MoveLeft.EndedDown)
                {
                    
                    dPlayerX = -1.0f;
                }
                if(Controller->MoveRight.EndedDown)
                {
                    dPlayerX = 1.0f;
                }
                dPlayerX *= 64.0f;
                dPlayerY *= 64.0f;
                
                GameState->PlayerX += Input->dtForFrame * dPlayerX;
                GameState->PlayerY += Input->dtForFrame * dPlayerY;
                
            }
            
        }
        
    }
    
    u32 TileMap[9][17] =
    {
        {1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1},
        {1, 1, 0, 0,  0, 1, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1},
        {1, 1, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0, 1},
        {1, 0, 0, 0,  0, 0, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 1},
        {0, 0, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 0, 0, 0},
        {1, 1, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  0, 1, 0, 0, 1},
        {1, 0, 0, 0,  0, 1, 0, 0,  1, 0, 0, 0,  1, 0, 0, 0, 1},
        {1, 1, 1, 1,  1, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0, 1},
        {1, 1, 1, 1,  1, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1, 1},
    };
    
    f32 UpperLeftX = -30;
    f32 UpperLeftY = 0;
    f32 TileWidth = 60;
    f32 TileHeight = 60;
    
    DrawRectangle(Bitmap, 0.0f, 0.0f, (f32)Bitmap->Width, (f32)Bitmap->Height, 1.0f, 0.0f, 0.1f);
    
    for(i32 Row = 0; Row < 9; ++Row)
    {
        for(i32 Column = 0; Column < 17; ++Column)
        {
            u32 TileID = TileMap[Row][Column];
            f32 Gray = 0.5f;
            if(TileID == 1)
            {
                Gray = 1.0f;
            }
            
            f32 MinX = UpperLeftX + ((f32)Column) * TileWidth;
            f32 MinY = UpperLeftY + ((f32)Row) * TileHeight;
            f32 MaxX = MinX + TileWidth;
            f32 MaxY = MinY + TileHeight;
            DrawRectangle(Bitmap, MinX, MinY, MaxX, MaxY, Gray, Gray, Gray);
        }
    }
    
    f32 PlayerR = 1.0f;
    f32 PlayerG = 1.0f;
    f32 PlayerB = 0.0f;
    f32 PlayerWidth = 0.75f * TileWidth;
    f32 PlayerHeight = TileHeight;
    f32 PlayerLeft = GameState->PlayerX - 0.5f * PlayerWidth;
    f32 PlayerTop = GameState->PlayerY - PlayerHeight;
    DrawRectangle(Bitmap, PlayerLeft, PlayerTop, PlayerLeft + PlayerWidth, PlayerTop + PlayerHeight, PlayerR, PlayerG, PlayerB);
    
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


