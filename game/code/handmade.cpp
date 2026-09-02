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
            u8 Blue = X + BlueOffset;
            u8 Green = Y + GreenOffset;
            *Pixel++ = ((u32)Blue << 0) | ((u32)Green << 8) | ((u32)255 << 24);
        }
        Row += Bitmap->Pitch;
    }
}

internal void
GameUpdateAndRender(game_input *Input, game_offscreen_buffer *Bitmap, game_sound_output_buffer *Sound)
{
    local_persist i32 BlueOffset = 0;
    local_persist i32 GreenOffset = 0;
    local_persist i32 ToneHz = 256;
    
    game_controller_input *Input0 = &Input->Controllers[0];
    
    if(Input0->IsAnalog)
    {
        BlueOffset += (i32)4.0f*(Input0->EndX);
        ToneHz = 256 + (int)(128.0f*(Input0->EndY));
    }
    
    else
    {
        
    }
    
    if(Input0->Down.EndedDown)
    {
        GreenOffset += 1;
    }
    
    GameOutputSound(Sound, ToneHz);
    RenderWeirdGradient(Bitmap, BlueOffset, GreenOffset);
    
}
