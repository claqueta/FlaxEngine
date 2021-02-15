// File generated by Flax Materials Editor
// Version: @0

#define MATERIAL 1
@3
#include "./Flax/Common.hlsl"
#include "./Flax/MaterialCommon.hlsl"
#include "./Flax/GBufferCommon.hlsl"
@7
// Primary constant buffer (with additional material parameters)
META_CB_BEGIN(0, Data)
float4x4 ViewProjectionMatrix;
float4x4 WorldMatrix;
float4x4 ViewMatrix;
float4x4 PrevViewProjectionMatrix;
float4x4 PrevWorldMatrix;
float3 ViewPos;
float ViewFar;
float3 ViewDir;
float TimeParam;
float4 ViewInfo;
float4 ScreenSize;
float3 WorldInvScale;
float WorldDeterminantSign;
float2 Dummy0;
float LODDitherFactor;
float PerInstanceRandom;
float4 TemporalAAJitter;
float3 GeometrySize;
float Dummy1;
@1META_CB_END

// Shader resources
@2
// Geometry data passed though the graphics rendering stages up to the pixel shader
struct GeometryData
{
	float3 WorldPosition : TEXCOORD0;
	float2 TexCoord : TEXCOORD1;
	float2 LightmapUV : TEXCOORD2;
#if USE_VERTEX_COLOR
	half4 VertexColor : COLOR;
#endif
	float3 WorldNormal : TEXCOORD3;
	float4 WorldTangent : TEXCOORD4;
	float3 InstanceOrigin : TEXCOORD5;
	float2 InstanceParams : TEXCOORD6; // x-PerInstanceRandom, y-LODDitherFactor
	float3 PrevWorldPosition : TEXCOORD7;
};

// Interpolants passed from the vertex shader
struct VertexOutput
{
	float4 Position : SV_Position;
	GeometryData Geometry;
#if USE_CUSTOM_VERTEX_INTERPOLATORS
	float4 CustomVSToPS[CUSTOM_VERTEX_INTERPOLATORS_COUNT] : TEXCOORD9;
#endif
#if USE_TESSELLATION
    float TessellationMultiplier : TESS;
#endif
};

// Interpolants passed to the pixel shader
struct PixelInput
{
	float4 Position : SV_Position;
	GeometryData Geometry;
#if USE_CUSTOM_VERTEX_INTERPOLATORS
	float4 CustomVSToPS[CUSTOM_VERTEX_INTERPOLATORS_COUNT] : TEXCOORD9;
#endif
	bool IsFrontFace : SV_IsFrontFace;
};

// Material properties generation input
struct MaterialInput
{
	float3 WorldPosition;
	float TwoSidedSign;
	float2 TexCoord;
#if USE_LIGHTMAP
	float2 LightmapUV;
#endif
#if USE_VERTEX_COLOR
	half4 VertexColor;
#endif
	float3x3 TBN;
	float4 SvPosition;
	float3 PreSkinnedPosition;
	float3 PreSkinnedNormal;
	float3 InstanceOrigin;
	float2 InstanceParams;
#if USE_INSTANCING
	float3 InstanceTransform1;
	float3 InstanceTransform2;
	float3 InstanceTransform3;
#endif
#if USE_CUSTOM_VERTEX_INTERPOLATORS
	float4 CustomVSToPS[CUSTOM_VERTEX_INTERPOLATORS_COUNT];
#endif
};

// Extracts geometry data to the material input
MaterialInput GetGeometryMaterialInput(GeometryData geometry)
{
	MaterialInput output = (MaterialInput)0;
	output.WorldPosition = geometry.WorldPosition;
	output.TexCoord = geometry.TexCoord;
#if USE_LIGHTMAP
	output.LightmapUV = geometry.LightmapUV;
#endif
#if USE_VERTEX_COLOR
	output.VertexColor = geometry.VertexColor;
#endif
	output.TBN = CalcTangentBasis(geometry.WorldNormal, geometry.WorldTangent);
	output.InstanceOrigin = geometry.InstanceOrigin;
	output.InstanceParams = geometry.InstanceParams;
	return output;
}

#if USE_TESSELLATION

// Interpolates the geometry positions data only (used by the tessallation when generating vertices)
#define InterpolateGeometryPositions(output, p0, w0, p1, w1, p2, w2, offset) output.WorldPosition = p0.WorldPosition * w0 + p1.WorldPosition * w1 + p2.WorldPosition * w2 + offset; output.PrevWorldPosition = p0.PrevWorldPosition * w0 + p1.PrevWorldPosition * w1 + p2.PrevWorldPosition * w2 + offset

// Offsets the geometry positions data only (used by the tessallation when generating vertices)
#define OffsetGeometryPositions(geometry, offset) geometry.WorldPosition += offset; geometry.PrevWorldPosition += offset

// Applies the Phong tessallation to the geometry positions (used by the tessallation when doing Phong tess)
#define ApplyGeometryPositionsPhongTess(geometry, p0, p1, p2, U, V, W) \
	float3 posProjectedU = TessalationProjectOntoPlane(p0.WorldNormal, p0.WorldPosition, geometry.WorldPosition); \
	float3 posProjectedV = TessalationProjectOntoPlane(p1.WorldNormal, p1.WorldPosition, geometry.WorldPosition); \
	float3 posProjectedW = TessalationProjectOntoPlane(p2.WorldNormal, p2.WorldPosition, geometry.WorldPosition); \
	geometry.WorldPosition = U * posProjectedU + V * posProjectedV + W * posProjectedW; \
	posProjectedU = TessalationProjectOntoPlane(p0.WorldNormal, p0.PrevWorldPosition, geometry.PrevWorldPosition); \
	posProjectedV = TessalationProjectOntoPlane(p1.WorldNormal, p1.PrevWorldPosition, geometry.PrevWorldPosition); \
	posProjectedW = TessalationProjectOntoPlane(p2.WorldNormal, p2.PrevWorldPosition, geometry.PrevWorldPosition); \
	geometry.PrevWorldPosition = U * posProjectedU + V * posProjectedV + W * posProjectedW

// Interpolates the geometry data except positions (used by the tessallation when generating vertices)
GeometryData InterpolateGeometry(GeometryData p0, float w0, GeometryData p1, float w1, GeometryData p2, float w2)
{
	GeometryData output = (GeometryData)0;
	output.TexCoord = p0.TexCoord * w0 + p1.TexCoord * w1 + p2.TexCoord * w2;
#if USE_LIGHTMAP
	output.LightmapUV = p0.LightmapUV * w0 + p1.LightmapUV * w1 + p2.LightmapUV * w2;
#endif
#if USE_VERTEX_COLOR
	output.VertexColor = p0.VertexColor * w0 + p1.VertexColor * w1 + p2.VertexColor * w2;
#endif
	output.WorldNormal = p0.WorldNormal * w0 + p1.WorldNormal * w1 + p2.WorldNormal * w2;
	output.WorldNormal = normalize(output.WorldNormal);
	output.WorldTangent = p0.WorldTangent * w0 + p1.WorldTangent * w1 + p2.WorldTangent * w2;
	output.WorldTangent.xyz = normalize(output.WorldTangent.xyz);
	output.InstanceOrigin = p0.InstanceOrigin;
	output.InstanceParams = p0.InstanceParams;
	return output;
}

#endif

MaterialInput GetMaterialInput(PixelInput input)
{
	MaterialInput output = GetGeometryMaterialInput(input.Geometry);
	output.TwoSidedSign = WorldDeterminantSign * (input.IsFrontFace ? 1.0 : -1.0);
	output.SvPosition = input.Position;
#if USE_CUSTOM_VERTEX_INTERPOLATORS
	output.CustomVSToPS = input.CustomVSToPS;
#endif
	return output;
}

// Gets the local to world transform matrix (supports instancing)
#if USE_INSTANCING
#define GetInstanceTransform(input) float4x4(float4(input.InstanceTransform1.xyz, 0.0f), float4(input.InstanceTransform2.xyz, 0.0f), float4(input.InstanceTransform3.xyz, 0.0f), float4(input.InstanceOrigin.xyz, 1.0f))
#else
#define GetInstanceTransform(input) WorldMatrix;
#endif

// Removes the scale vector from the local to world transformation matrix (supports instancing)
float3x3 RemoveScaleFromLocalToWorld(float3x3 localToWorld)
{
#if USE_INSTANCING
	// Extract per axis scales from localToWorld transform
	float scaleX = length(localToWorld[0]);
	float scaleY = length(localToWorld[1]);
	float scaleZ = length(localToWorld[2]);
	float3 invScale = float3(
		scaleX > 0.00001f ? 1.0f / scaleX : 0.0f,
		scaleY > 0.00001f ? 1.0f / scaleY : 0.0f,
		scaleZ > 0.00001f ? 1.0f / scaleZ : 0.0f);
#else
	float3 invScale = WorldInvScale;
#endif
	localToWorld[0] *= invScale.x;
	localToWorld[1] *= invScale.y;
	localToWorld[2] *= invScale.z;
	return localToWorld;
}

// Transforms a vector from tangent space to world space
float3 TransformTangentVectorToWorld(MaterialInput input, float3 tangentVector)
{
	return mul(tangentVector, input.TBN);
}

// Transforms a vector from world space to tangent space
float3 TransformWorldVectorToTangent(MaterialInput input, float3 worldVector)
{
	return mul(input.TBN, worldVector);
}

// Transforms a vector from world space to view space
float3 TransformWorldVectorToView(MaterialInput input, float3 worldVector)
{
	return mul(worldVector, (float3x3)ViewMatrix);
}

// Transforms a vector from view space to world space
float3 TransformViewVectorToWorld(MaterialInput input, float3 viewVector)
{
	return mul((float3x3)ViewMatrix, viewVector);
}

// Transforms a vector from local space to world space
float3 TransformLocalVectorToWorld(MaterialInput input, float3 localVector)
{
	float3x3 localToWorld = (float3x3)GetInstanceTransform(input);
	//localToWorld = RemoveScaleFromLocalToWorld(localToWorld);
	return mul(localVector, localToWorld);
}

// Transforms a vector from local space to world space
float3 TransformWorldVectorToLocal(MaterialInput input, float3 worldVector)
{
	float3x3 localToWorld = (float3x3)GetInstanceTransform(input);
	//localToWorld = RemoveScaleFromLocalToWorld(localToWorld);
	return mul(localToWorld, worldVector);
}

// Gets the current object position (supports instancing)
float3 GetObjectPosition(MaterialInput input)
{
	return input.InstanceOrigin.xyz;
}

// Gets the current object size (supports instancing)
float3 GetObjectSize(MaterialInput input)
{
	float4x4 world = GetInstanceTransform(input);
	return GeometrySize * float3(world._m00, world._m11, world._m22);
}

// Get the current object random value (supports instancing)
float GetPerInstanceRandom(MaterialInput input)
{
	return input.InstanceParams.x;
}

// Get the current object LOD transition dither factor (supports instancing)
float GetLODDitherFactor(MaterialInput input)
{
#if USE_DITHERED_LOD_TRANSITION
	return input.InstanceParams.y;
#else
	return 0;
#endif
}

// Gets the interpolated vertex color (in linear space)
float4 GetVertexColor(MaterialInput input)
{
#if USE_VERTEX_COLOR
	return input.VertexColor;
#else
	return 1;
#endif
}

@8

// Get material properties function (for vertex shader)
Material GetMaterialVS(MaterialInput input)
{
@5
}

// Get material properties function (for domain shader)
Material GetMaterialDS(MaterialInput input)
{
@6
}

// Get material properties function (for pixel shader)
Material GetMaterialPS(MaterialInput input)
{
@4
}

// Calculates the transform matrix from mesh tangent space to local space
float3x3 CalcTangentToLocal(ModelInput input)
{
	float bitangentSign = input.Tangent.w ? -1.0f : +1.0f;
	float3 normal = input.Normal.xyz * 2.0 - 1.0;
	float3 tangent = input.Tangent.xyz * 2.0 - 1.0;
	float3 bitangent = cross(normal, tangent) * bitangentSign;
	return float3x3(tangent, bitangent, normal);
}

float3x3 CalcTangentToWorld(float4x4 world, float3x3 tangentToLocal)
{
	float3x3 localToWorld = RemoveScaleFromLocalToWorld((float3x3)world);
	return mul(tangentToLocal, localToWorld); 
}

// Vertex Shader function for GBuffer Pass and Depth Pass (with full vertex data)
META_VS(true, FEATURE_LEVEL_ES2)
META_PERMUTATION_1(USE_INSTANCING=0)
META_PERMUTATION_1(USE_INSTANCING=1)
META_VS_IN_ELEMENT(POSITION, 0, R32G32B32_FLOAT,   0, 0,     PER_VERTEX, 0, true)
META_VS_IN_ELEMENT(TEXCOORD, 0, R16G16_FLOAT,      1, 0,     PER_VERTEX, 0, true)
META_VS_IN_ELEMENT(NORMAL,   0, R10G10B10A2_UNORM, 1, ALIGN, PER_VERTEX, 0, true)
META_VS_IN_ELEMENT(TANGENT,  0, R10G10B10A2_UNORM, 1, ALIGN, PER_VERTEX, 0, true)
META_VS_IN_ELEMENT(TEXCOORD, 1, R16G16_FLOAT,      1, ALIGN, PER_VERTEX, 0, true)
META_VS_IN_ELEMENT(COLOR,    0, R8G8B8A8_UNORM,    2, 0,     PER_VERTEX, 0, USE_VERTEX_COLOR)
META_VS_IN_ELEMENT(ATTRIBUTE,0, R32G32B32A32_FLOAT,3, 0,     PER_INSTANCE, 1, USE_INSTANCING)
META_VS_IN_ELEMENT(ATTRIBUTE,1, R32G32B32A32_FLOAT,3, ALIGN, PER_INSTANCE, 1, USE_INSTANCING)
META_VS_IN_ELEMENT(ATTRIBUTE,2, R32G32B32_FLOAT,   3, ALIGN, PER_INSTANCE, 1, USE_INSTANCING)
META_VS_IN_ELEMENT(ATTRIBUTE,3, R32G32B32_FLOAT,   3, ALIGN, PER_INSTANCE, 1, USE_INSTANCING)
META_VS_IN_ELEMENT(ATTRIBUTE,4, R16G16B16A16_FLOAT,3, ALIGN, PER_INSTANCE, 1, USE_INSTANCING)
VertexOutput VS(ModelInput input)
{
	VertexOutput output;

	// Compute world space vertex position
	float4x4 world = GetInstanceTransform(input);
	output.Geometry.WorldPosition = mul(float4(input.Position.xyz, 1), world).xyz;
	output.Geometry.PrevWorldPosition = mul(float4(input.Position.xyz, 1), PrevWorldMatrix).xyz;

	// Compute clip space position
	output.Position = mul(float4(output.Geometry.WorldPosition, 1), ViewProjectionMatrix);

	// Pass vertex attributes
	output.Geometry.TexCoord = input.TexCoord;
#if USE_VERTEX_COLOR
	output.Geometry.VertexColor = input.Color;
#endif
	output.Geometry.InstanceOrigin = world[3].xyz;
#if USE_INSTANCING
	output.Geometry.LightmapUV = input.LightmapUV * input.InstanceLightmapArea.zw + input.InstanceLightmapArea.xy;
	output.Geometry.InstanceParams = float2(input.InstanceOrigin.w, input.InstanceTransform1.w);
#else
#if USE_LIGHTMAP
	output.Geometry.LightmapUV = input.LightmapUV * LightmapArea.zw + LightmapArea.xy;
#else
	output.Geometry.LightmapUV = input.LightmapUV;
#endif
	output.Geometry.InstanceParams = float2(PerInstanceRandom, LODDitherFactor);
#endif

	// Calculate tanget space to world space transformation matrix for unit vectors
	float3x3 tangentToLocal = CalcTangentToLocal(input);
	float3x3 tangentToWorld = CalcTangentToWorld(world, tangentToLocal);
	output.Geometry.WorldNormal = tangentToWorld[2];
	output.Geometry.WorldTangent.xyz = tangentToWorld[0];
	output.Geometry.WorldTangent.w = input.Tangent.w ? -1.0f : +1.0f;

	// Get material input params if need to evaluate any material property
#if USE_POSITION_OFFSET || USE_TESSELLATION || USE_CUSTOM_VERTEX_INTERPOLATORS
	MaterialInput materialInput = GetGeometryMaterialInput(output.Geometry);
	materialInput.TwoSidedSign = WorldDeterminantSign;
	materialInput.SvPosition = output.Position;
	materialInput.PreSkinnedPosition = input.Position.xyz;
	materialInput.PreSkinnedNormal = tangentToLocal[2].xyz;
#if USE_INSTANCING
	materialInput.InstanceTransform1 = input.InstanceTransform1.xyz;
	materialInput.InstanceTransform2 = input.InstanceTransform2.xyz;
	materialInput.InstanceTransform3 = input.InstanceTransform3.xyz;
#endif
	Material material = GetMaterialVS(materialInput);
#endif

	// Apply world position offset per-vertex
#if USE_POSITION_OFFSET
	output.Geometry.WorldPosition += material.PositionOffset;
	output.Position = mul(float4(output.Geometry.WorldPosition, 1), ViewProjectionMatrix);
#endif

	// Get tessalation multiplier (per vertex)
#if USE_TESSELLATION
    output.TessellationMultiplier = material.TessellationMultiplier;
#endif

	// Copy interpolants for other shader stages
#if USE_CUSTOM_VERTEX_INTERPOLATORS
	output.CustomVSToPS = material.CustomVSToPS;
#endif

	return output;
}

// Vertex Shader function for Depth Pass
META_VS(true, FEATURE_LEVEL_ES2)
META_PERMUTATION_1(USE_INSTANCING=0)
META_PERMUTATION_1(USE_INSTANCING=1)
META_VS_IN_ELEMENT(POSITION, 0, R32G32B32_FLOAT,   0, 0,     PER_VERTEX, 0, true)
META_VS_IN_ELEMENT(ATTRIBUTE,0, R32G32B32A32_FLOAT,3, 0,     PER_INSTANCE, 1, USE_INSTANCING)
META_VS_IN_ELEMENT(ATTRIBUTE,1, R32G32B32A32_FLOAT,3, ALIGN, PER_INSTANCE, 1, USE_INSTANCING)
META_VS_IN_ELEMENT(ATTRIBUTE,2, R32G32B32_FLOAT,   3, ALIGN, PER_INSTANCE, 1, USE_INSTANCING)
META_VS_IN_ELEMENT(ATTRIBUTE,3, R32G32B32_FLOAT,   3, ALIGN, PER_INSTANCE, 1, USE_INSTANCING)
META_VS_IN_ELEMENT(ATTRIBUTE,4, R16G16B16A16_FLOAT,3, ALIGN, PER_INSTANCE, 1, USE_INSTANCING)
float4 VS_Depth(ModelInput_PosOnly input) : SV_Position
{
	float4x4 world = GetInstanceTransform(input);
	float3 worldPosition = mul(float4(input.Position.xyz, 1), world).xyz;
	float4 position = mul(float4(worldPosition, 1), ViewProjectionMatrix);
	return position;
}

#if USE_SKINNING

// The skeletal bones matrix buffer (stored as 4x3, 3 float4 behind each other)
Buffer<float4> BoneMatrices : register(t0);

#if PER_BONE_MOTION_BLUR

// The skeletal bones matrix buffer from the previous frame
Buffer<float4> PrevBoneMatrices : register(t1);

float3x4 GetPrevBoneMatrix(int index)
{
	float4 a = PrevBoneMatrices[index * 3];
	float4 b = PrevBoneMatrices[index * 3 + 1];
	float4 c = PrevBoneMatrices[index * 3 + 2];
	return float3x4(a, b, c);
}

float3 SkinPrevPosition(ModelInput_Skinned input)
{
	float4 position = float4(input.Position.xyz, 1);
	float3x4 boneMatrix = input.BlendWeights.x * GetPrevBoneMatrix(input.BlendIndices.x);
	boneMatrix += input.BlendWeights.y * GetPrevBoneMatrix(input.BlendIndices.y);
	boneMatrix += input.BlendWeights.z * GetPrevBoneMatrix(input.BlendIndices.z);
	boneMatrix += input.BlendWeights.w * GetPrevBoneMatrix(input.BlendIndices.w);
	return mul(boneMatrix, position);
}

#endif

// Cached skinning data to avoid multiple calculation 
struct SkinningData
{
	float3x4 BlendMatrix;
};

// Calculates the transposed transform matrix for the given bone index
float3x4 GetBoneMatrix(int index)
{
	float4 a = BoneMatrices[index * 3];
	float4 b = BoneMatrices[index * 3 + 1];
	float4 c = BoneMatrices[index * 3 + 2];
	return float3x4(a, b, c);
}

// Calculates the transposed transform matrix for the given vertex (uses blending)
float3x4 GetBoneMatrix(ModelInput_Skinned input)
{
	float3x4 boneMatrix = input.BlendWeights.x * GetBoneMatrix(input.BlendIndices.x);
	boneMatrix += input.BlendWeights.y * GetBoneMatrix(input.BlendIndices.y);
	boneMatrix += input.BlendWeights.z * GetBoneMatrix(input.BlendIndices.z);
	boneMatrix += input.BlendWeights.w * GetBoneMatrix(input.BlendIndices.w);
	return boneMatrix;
}

// Transforms the vertex position by weighted sum of the skinning matrices
float3 SkinPosition(ModelInput_Skinned input, SkinningData data)
{
	return mul(data.BlendMatrix, float4(input.Position.xyz, 1));
}

// Transforms the vertex position by weighted sum of the skinning matrices
float3x3 SkinTangents(ModelInput_Skinned input, SkinningData data)
{
	// Unpack vertex tangent frame
	float bitangentSign = input.Tangent.w ? -1.0f : +1.0f;
	float3 normal = input.Normal.xyz * 2.0 - 1.0;
	float3 tangent = input.Tangent.xyz * 2.0 - 1.0;

	// Apply skinning
	tangent = mul(data.BlendMatrix, float4(tangent, 0));
	normal = mul(data.BlendMatrix, float4(normal, 0));

	float3 bitangent = cross(normal, tangent) * bitangentSign;
	return float3x3(tangent, bitangent, normal);
}

// Vertex Shader function for GBuffers/Depth Pass (skinned mesh rendering)
META_VS(true, FEATURE_LEVEL_ES2)
META_PERMUTATION_1(USE_SKINNING=1)
META_PERMUTATION_2(USE_SKINNING=1, PER_BONE_MOTION_BLUR=1)
META_VS_IN_ELEMENT(POSITION,     0, R32G32B32_FLOAT,   0, 0,     PER_VERTEX, 0, true)
META_VS_IN_ELEMENT(TEXCOORD,     0, R16G16_FLOAT,      0, ALIGN, PER_VERTEX, 0, true)
META_VS_IN_ELEMENT(NORMAL,       0, R10G10B10A2_UNORM, 0, ALIGN, PER_VERTEX, 0, true)
META_VS_IN_ELEMENT(TANGENT,      0, R10G10B10A2_UNORM, 0, ALIGN, PER_VERTEX, 0, true)
META_VS_IN_ELEMENT(BLENDINDICES, 0, R8G8B8A8_UINT,     0, ALIGN, PER_VERTEX, 0, true)
META_VS_IN_ELEMENT(BLENDWEIGHT,  0, R16G16B16A16_FLOAT,0, ALIGN, PER_VERTEX, 0, true)
VertexOutput VS_Skinned(ModelInput_Skinned input)
{
	VertexOutput output;
	
	// Perform skinning
	SkinningData data;
	data.BlendMatrix = GetBoneMatrix(input);
	float3 position = SkinPosition(input, data);
	float3x3 tangentToLocal = SkinTangents(input, data);
	
	// Compute world space vertex position
	float4x4 world = GetInstanceTransform(input);
	output.Geometry.WorldPosition = mul(float4(position, 1), world).xyz;
#if PER_BONE_MOTION_BLUR
	float3 prevPosition = SkinPrevPosition(input);
	output.Geometry.PrevWorldPosition = mul(float4(prevPosition, 1), PrevWorldMatrix).xyz;
#else
	output.Geometry.PrevWorldPosition = mul(float4(position, 1), PrevWorldMatrix).xyz;
#endif

	// Compute clip space position
	output.Position = mul(float4(output.Geometry.WorldPosition, 1), ViewProjectionMatrix);

	// Pass vertex attributes
	output.Geometry.TexCoord = input.TexCoord;
#if USE_VERTEX_COLOR
	output.Geometry.VertexColor = float4(0, 0, 0, 1);
#endif
	output.Geometry.LightmapUV = float2(0, 0);
	output.Geometry.InstanceOrigin = world[3].xyz;
#if USE_INSTANCING
	output.Geometry.InstanceParams = float2(input.InstanceOrigin.w, input.InstanceTransform1.w);
#else
	output.Geometry.InstanceParams = float2(PerInstanceRandom, LODDitherFactor);
#endif

	// Calculate tanget space to world space transformation matrix for unit vectors
	float3x3 tangentToWorld = CalcTangentToWorld(world, tangentToLocal);
	output.Geometry.WorldNormal = tangentToWorld[2];
	output.Geometry.WorldTangent.xyz = tangentToWorld[0];
	output.Geometry.WorldTangent.w = input.Tangent.w ? -1.0f : +1.0f;

	// Get material input params if need to evaluate any material property
#if USE_POSITION_OFFSET || USE_TESSELLATION || USE_CUSTOM_VERTEX_INTERPOLATORS
	MaterialInput materialInput = GetGeometryMaterialInput(output.Geometry);
	materialInput.TwoSidedSign = WorldDeterminantSign;
	materialInput.SvPosition = output.Position;
	materialInput.PreSkinnedPosition = input.Position.xyz;
	materialInput.PreSkinnedNormal = tangentToLocal[2].xyz;
	Material material = GetMaterialVS(materialInput);
#endif

	// Apply world position offset per-vertex
#if USE_POSITION_OFFSET
	output.Geometry.WorldPosition += material.PositionOffset;
	output.Position = mul(float4(output.Geometry.WorldPosition, 1), ViewProjectionMatrix);
#endif

	// Get tessalation multiplier (per vertex)
#if USE_TESSELLATION
    output.TessellationMultiplier = material.TessellationMultiplier;
#endif
	
	// Copy interpolants for other shader stages
#if USE_CUSTOM_VERTEX_INTERPOLATORS
	output.CustomVSToPS = material.CustomVSToPS;
#endif

	return output;
}

#endif

#if USE_DITHERED_LOD_TRANSITION

void ClipLODTransition(PixelInput input)
{
	float ditherFactor = input.InstanceParams.y;
	if (abs(ditherFactor) > 0.001)
	{
		float randGrid = cos(dot(floor(input.Position.xy), float2(347.83452793, 3343.28371863)));
		float randGridFrac = frac(randGrid * 1000.0);
		half mask = (ditherFactor < 0.0) ? (ditherFactor + 1.0 > randGridFrac) : (ditherFactor < randGridFrac);
		clip(mask - 0.001);
	}
}

#endif

// Pixel Shader function for Depth Pass
META_PS(true, FEATURE_LEVEL_ES2)
void PS_Depth(PixelInput input)
{	
#if USE_DITHERED_LOD_TRANSITION
	// LOD masking
	ClipLODTransition(input);
#endif

#if MATERIAL_MASKED || MATERIAL_BLEND != MATERIAL_BLEND_OPAQUE 
	// Get material parameters
	MaterialInput materialInput = GetMaterialInput(input);
	Material material = GetMaterialPS(materialInput);

	// Perform per pixel clipping
#if MATERIAL_MASKED
	clip(material.Mask - MATERIAL_MASK_THRESHOLD);
#endif
#if MATERIAL_BLEND != MATERIAL_BLEND_OPAQUE
	clip(material.Opacity - MATERIAL_OPACITY_THRESHOLD);
#endif
#endif
}

@9