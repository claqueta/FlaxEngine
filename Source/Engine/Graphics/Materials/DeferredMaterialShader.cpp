// Copyright (c) 2012-2021 Wojciech Figat. All rights reserved.

#include "DeferredMaterialShader.h"
#include "MaterialParams.h"
#include "Engine/Graphics/RenderBuffers.h"
#include "Engine/Graphics/RenderView.h"
#include "Engine/Renderer/DrawCall.h"
#include "Engine/Level/Scene/Lightmap.h"
#include "Engine/Graphics/GPUContext.h"
#include "Engine/Graphics/Shaders/GPUConstantBuffer.h"
#include "Engine/Graphics/Models/SkinnedMeshDrawData.h"
#include "Engine/Graphics/GPUDevice.h"
#include "Engine/Graphics/Shaders/GPUShader.h"
#include "Engine/Graphics/GPULimits.h"
#include "Engine/Engine/Time.h"
#include "Engine/Graphics/RenderTask.h"

PACK_STRUCT(struct DeferredMaterialShaderData {
    Matrix ViewProjectionMatrix;
    Matrix WorldMatrix;
    Matrix ViewMatrix;
    Matrix PrevViewProjectionMatrix;
    Matrix PrevWorldMatrix;
    Vector3 ViewPos;
    float ViewFar;
    Vector3 ViewDir;
    float TimeParam;
    Vector4 ViewInfo;
    Vector4 ScreenSize;
    Rectangle LightmapArea;
    Vector3 WorldInvScale;
    float WorldDeterminantSign;
    Vector2 Dummy0;
    float LODDitherFactor;
    float PerInstanceRandom;
    Vector4 TemporalAAJitter;
    Vector3 GeometrySize;
    float Dummy1;
    });

DrawPass DeferredMaterialShader::GetDrawModes() const
{
    return DrawPass::Depth | DrawPass::GBuffer | DrawPass::MotionVectors;
}

bool DeferredMaterialShader::CanUseLightmap() const
{
    return true;
}

bool DeferredMaterialShader::CanUseInstancing() const
{
    return true;
}

void DeferredMaterialShader::Bind(BindParameters& params)
{
    // Prepare
    auto context = params.GPUContext;
    auto& view = params.RenderContext.View;
    auto& drawCall = *params.FirstDrawCall;
    const auto cb0 = _shader->GetCB(0);
    const bool hasCb0 = cb0 && cb0->GetSize() != 0;

    // Setup parameters
    MaterialParameter::BindMeta bindMeta;
    bindMeta.Context = context;
    bindMeta.Buffer0 = hasCb0 ? _cb0Data.Get() + sizeof(DeferredMaterialShaderData) : nullptr;
    bindMeta.Input = nullptr;
    bindMeta.Buffers = nullptr;
    bindMeta.CanSampleDepth = false;
    bindMeta.CanSampleGBuffer = false;
    MaterialParams::Bind(params.ParamsLink, bindMeta);

    // Setup material constants data
    auto materialData = reinterpret_cast<DeferredMaterialShaderData*>(_cb0Data.Get());
    if (hasCb0)
    {
        Matrix::Transpose(view.Frustum.GetMatrix(), materialData->ViewProjectionMatrix);
        Matrix::Transpose(drawCall.World, materialData->WorldMatrix);
        Matrix::Transpose(view.View, materialData->ViewMatrix);
        Matrix::Transpose(drawCall.PrevWorld, materialData->PrevWorldMatrix);
        Matrix::Transpose(view.PrevViewProjection, materialData->PrevViewProjectionMatrix);

        materialData->ViewPos = view.Position;
        materialData->ViewFar = view.Far;
        materialData->ViewDir = view.Direction;
        materialData->TimeParam = Time::Draw.UnscaledTime.GetTotalSeconds();
        materialData->ViewInfo = view.ViewInfo;
        materialData->ScreenSize = view.ScreenSize;

        // Extract per axis scales from LocalToWorld transform
        const float scaleX = Vector3(drawCall.World.M11, drawCall.World.M12, drawCall.World.M13).Length();
        const float scaleY = Vector3(drawCall.World.M21, drawCall.World.M22, drawCall.World.M23).Length();
        const float scaleZ = Vector3(drawCall.World.M31, drawCall.World.M32, drawCall.World.M33).Length();
        const Vector3 worldInvScale = Vector3(
            scaleX > 0.00001f ? 1.0f / scaleX : 0.0f,
            scaleY > 0.00001f ? 1.0f / scaleY : 0.0f,
            scaleZ > 0.00001f ? 1.0f / scaleZ : 0.0f);

        materialData->WorldInvScale = worldInvScale;
        materialData->WorldDeterminantSign = drawCall.WorldDeterminantSign;
        materialData->LODDitherFactor = drawCall.LODDitherFactor;
        materialData->PerInstanceRandom = drawCall.PerInstanceRandom;
        materialData->TemporalAAJitter = view.TemporalAAJitter;
        materialData->GeometrySize = drawCall.GeometrySize;
    }
    const bool useLightmap = view.Flags & ViewFlags::GI
#if USE_EDITOR
            && EnableLightmapsUsage
#endif
            && drawCall.Lightmap != nullptr;
    if (useLightmap)
    {
        // Bind lightmap textures
        GPUTexture *lightmap0, *lightmap1, *lightmap2;
        drawCall.Lightmap->GetTextures(&lightmap0, &lightmap1, &lightmap2);
        context->BindSR(0, lightmap0);
        context->BindSR(1, lightmap1);
        context->BindSR(2, lightmap2);

        // Set lightmap data
        materialData->LightmapArea = drawCall.LightmapUVsArea;
    }

    // Check if is using mesh skinning
    const bool useSkinning = drawCall.Skinning != nullptr;
    bool perBoneMotionBlur = false;
    if (useSkinning)
    {
        // Bind skinning buffer
        ASSERT(drawCall.Skinning->IsReady());
        context->BindSR(0, drawCall.Skinning->BoneMatrices->View());
        if (drawCall.Skinning->PrevBoneMatrices && drawCall.Skinning->PrevBoneMatrices->IsAllocated())
        {
            context->BindSR(1, drawCall.Skinning->PrevBoneMatrices->View());
            perBoneMotionBlur = true;
        }
    }

    // Bind constants
    if (hasCb0)
    {
        context->UpdateCB(cb0, _cb0Data.Get());
        context->BindCB(0, cb0);
    }

    // Select pipeline state based on current pass and render mode
    const bool wireframe = (_info.FeaturesFlags & MaterialFeaturesFlags::Wireframe) != 0 || view.Mode == ViewMode::Wireframe;
    CullMode cullMode = view.Pass == DrawPass::Depth ? CullMode::TwoSided : _info.CullMode;
#if USE_EDITOR
    if (IsRunningRadiancePass)
        cullMode = CullMode::TwoSided;
#endif
    if (cullMode != CullMode::TwoSided && drawCall.IsNegativeScale())
    {
        // Invert culling when scale is negative
        if (cullMode == CullMode::Normal)
            cullMode = CullMode::Inverted;
        else
            cullMode = CullMode::Normal;
    }
    ASSERT_LOW_LAYER(!(useSkinning && params.DrawCallsCount > 1)); // No support for instancing skinned meshes
    const auto cache = params.DrawCallsCount == 1 ? &_cache : &_cacheInstanced;
    PipelineStateCache* psCache = cache->GetPS(view.Pass, useLightmap, useSkinning, perBoneMotionBlur);
    ASSERT(psCache);
    GPUPipelineState* state = psCache->GetPS(cullMode, wireframe);

    // Bind pipeline
    context->SetState(state);
}

void DeferredMaterialShader::Unload()
{
    // Base
    MaterialShader::Unload();

    _cache.Release();
    _cacheInstanced.Release();
}

bool DeferredMaterialShader::Load()
{
    auto psDesc = GPUPipelineState::Description::Default;
    psDesc.DepthTestEnable = (_info.FeaturesFlags & MaterialFeaturesFlags::DisableDepthTest) == 0;
    psDesc.DepthWriteEnable = (_info.FeaturesFlags & MaterialFeaturesFlags::DisableDepthWrite) == 0;

    // Check if use tessellation (both material and runtime supports it)
    const bool useTess = _info.TessellationMode != TessellationMethod::None && GPUDevice::Instance->Limits.HasTessellation;
    if (useTess)
    {
        psDesc.HS = _shader->GetHS("HS");
        psDesc.DS = _shader->GetDS("DS");
    }

    // GBuffer Pass
    psDesc.VS = _shader->GetVS("VS");
    psDesc.PS = _shader->GetPS("PS_GBuffer");
    _cache.Default.Init(psDesc);
    psDesc.VS = _shader->GetVS("VS", 1);
    _cacheInstanced.Default.Init(psDesc);

    // GBuffer Pass with lightmap (use pixel shader permutation for USE_LIGHTMAP=1)
    psDesc.VS = _shader->GetVS("VS");
    psDesc.PS = _shader->GetPS("PS_GBuffer", 1);
    _cache.DefaultLightmap.Init(psDesc);
    psDesc.VS = _shader->GetVS("VS", 1);
    _cacheInstanced.DefaultLightmap.Init(psDesc);

    // GBuffer Pass with skinning
    psDesc.VS = _shader->GetVS("VS_Skinned");
    psDesc.PS = _shader->GetPS("PS_GBuffer");
    _cache.DefaultSkinned.Init(psDesc);

    // Motion Vectors pass
    psDesc.DepthWriteEnable = false;
    psDesc.DepthTestEnable = true;
    psDesc.DepthFunc = ComparisonFunc::LessEqual;
    if (useTess)
    {
        psDesc.HS = _shader->GetHS("HS", 1);
        psDesc.DS = _shader->GetDS("DS", 1);
    }
    psDesc.VS = _shader->GetVS("VS", 2);
    psDesc.PS = _shader->GetPS("PS_MotionVectors");
    _cache.MotionVectors.Init(psDesc);

    // Motion Vectors pass with skinning
    psDesc.VS = _shader->GetVS("VS_Skinned", 1);
    _cache.MotionVectorsSkinned.Init(psDesc);

    // Motion Vectors pass with skinning (with per-bone motion blur)
    psDesc.VS = _shader->GetVS("VS_Skinned", 2);
    _cache.MotionVectorsSkinnedPerBone.Init(psDesc);

    // Depth Pass
    psDesc.CullMode = CullMode::TwoSided;
    psDesc.DepthClipEnable = false;
    psDesc.DepthWriteEnable = true;
    psDesc.DepthTestEnable = true;
    psDesc.DepthFunc = ComparisonFunc::Less;
    psDesc.HS = nullptr;
    psDesc.DS = nullptr;
    GPUShaderProgramVS* instancedDepthPassVS;
    if ((_info.UsageFlags & (MaterialUsageFlags::UseMask | MaterialUsageFlags::UsePositionOffset)) != 0)
    {
        // Materials with masking need full vertex buffer to get texcoord used to sample textures for per pixel masking.
        // Materials with world pos offset need full VB to apply offset using texcoord etc.
        psDesc.VS = _shader->GetVS("VS");
        instancedDepthPassVS = _shader->GetVS("VS", 1);
        psDesc.PS = _shader->GetPS("PS_Depth");
    }
    else
    {
        psDesc.VS = _shader->GetVS("VS_Depth");
        instancedDepthPassVS = _shader->GetVS("VS_Depth", 1);
        psDesc.PS = nullptr;
    }
    _cache.Depth.Init(psDesc);
    psDesc.VS = instancedDepthPassVS;
    _cacheInstanced.Depth.Init(psDesc);

    // Depth Pass with skinning
    psDesc.VS = _shader->GetVS("VS_Skinned");
    _cache.DepthSkinned.Init(psDesc);

    return false;
}
