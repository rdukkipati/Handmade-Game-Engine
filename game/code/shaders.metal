#include <metal_stdlib>

using namespace metal;

struct vertex_in
{
	float2 Position [[attribute(0)]];
	float2 UV [[attribute(1)]];
};

struct vertex_out
{
	float4 Position [[position]];
	float2 UV;
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
	Result.UV = Vertex.UV;

	return Result;
}

[[fragment]] fragment_out
FragmentFunction(vertex_out Fragment [[stage_in]],
			   texture2d<half> Texture [[texture(0)]],
			   sampler Sampler [[sampler(0)]])
{
	fragment_out Result;

	Result.Color = Texture.sample(Sampler, Fragment.UV);

	return Result;
}
