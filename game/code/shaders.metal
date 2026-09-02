#include <metal_stdlib>

using namespace metal;

struct vertex_in
{
	float2 Position [[attribute(0)]];
};

struct vertex_out
{
	float4 Position [[position]];
};

struct fragment_out
{
	half4 Color [[color(0)]];
};

[[vertex]] vertex_out
VertexFunction(vertex_in Vertex [[stage_in]])
{
	vertex_out Result;
	
	Result.Position = float4(Vertex.Position, 0.0f, 1.0f);
    
	return Result;
}

[[fragment]] fragment_out
FragmentFunction(vertex_out Fragment [[stage_in]],
                 texture2d<half, access::read> Texture [[texture(0)]])
{
	fragment_out Result;
    
    uint2 PixelPosition = (uint2)Fragment.Position.xy;
	Result.Color = Texture.read(PixelPosition);
    
	return Result;
}
