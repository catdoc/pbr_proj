/**
* piexl.hlsl: frag funtion
*/

#ifndef UNITY_PIEXL
#define UNITY_PIEXL

#include "UnityPBSLighting.cginc"
#include "UnityStandardBRDF.cginc"
#include "stdlib.hlsl"
#include "debug.hlsl"
#include "material.hlsl"

float4 fragPBRForwardBase(VertexPBROutput i) : SV_Target {
    i.normalDir = normalize(i.normalDir);
    float3x3 tangentTransform = float3x3(i.tangentDir, i.bitangentDir, i.normalDir);
    float3 viewDirection = normalize(_WorldSpaceCameraPos.xyz - i.posWorld.xyz);
    float3 _NormalMap_var = UnpackNormal(tex2D(_NormalMap,TRANSFORM_TEX(i.uv0, _NormalMap)));
    float3 normalLocal = _NormalMap_var.rgb;
    float3 normalDirection = normalize(mul( normalLocal, tangentTransform )); // Perturbed normals
    float3 viewReflectDirection = reflect( -viewDirection, normalDirection );
    float3 lightDirection = normalize(_WorldSpaceLightPos0.xyz);
    float3 lightColor = _LightColor0.rgb;
    float3 halfDirection = normalize(viewDirection+lightDirection);
////// Lighting:
    float attenuation = LIGHT_ATTENUATION(i);
    float3 attenColor = attenuation * _LightColor0.xyz;
///////// Gloss:
    float gloss = _Gloss;
    float perceptualRoughness = 1.0 - _Gloss;
    float roughness = perceptualRoughness * perceptualRoughness;
/////// GI Data:
    UnityLight light;
    #ifdef LIGHTMAP_OFF
        light.color = lightColor;
        light.dir = lightDirection;
        light.ndotl = LambertTerm (normalDirection, light.dir);
    #else
        light.color = half3(0.f, 0.f, 0.f);
        light.ndotl = 0.0f;
        light.dir = half3(0.f, 0.f, 0.f);
    #endif
    UnityGIInput d;
    d.light = light;
    d.worldPos = i.posWorld.xyz;
    d.worldViewDir = viewDirection;
    d.atten = attenuation;
    #if defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
        d.ambient = 0;
        d.lightmapUV = i.ambientOrLightmapUV;
    #else
        d.ambient = i.ambientOrLightmapUV;
    #endif
    #if UNITY_SPECCUBE_BLENDING || UNITY_SPECCUBE_BOX_PROJECTION
        d.boxMin[0] = unity_SpecCube0_BoxMin;
        d.boxMin[1] = unity_SpecCube1_BoxMin;
    #endif
    #if UNITY_SPECCUBE_BOX_PROJECTION
        d.boxMax[0] = unity_SpecCube0_BoxMax;
        d.boxMax[1] = unity_SpecCube1_BoxMax;
        d.probePosition[0] = unity_SpecCube0_ProbePosition;
        d.probePosition[1] = unity_SpecCube1_ProbePosition;
    #endif
    d.probeHDR[0] = unity_SpecCube0_HDR;
    d.probeHDR[1] = unity_SpecCube1_HDR;
    Unity_GlossyEnvironmentData ugls_en_data;
    ugls_en_data.roughness = 1.0 - gloss;
    ugls_en_data.reflUVW = viewReflectDirection;
    UnityGI gi = UnityGlobalIllumination(d, 1, normalDirection, ugls_en_data );
    lightDirection = gi.light.dir;
    lightColor = gi.light.color;
////// Specular:
    float NdotL = saturate(dot(normalDirection, lightDirection));
    float LdotH = saturate(dot(lightDirection, halfDirection));
    float3 specularColor = _Metallic;
    float specularMonochrome;
    float4 _MainTex_var = tex2D(_MainTex,TRANSFORM_TEX(i.uv0, _MainTex));
    float3 diffuseColor = (_MainTex_var.rgb*_Color.rgb); // Need this for specular when using metallic
    diffuseColor = DiffuseAndSpecularFromMetallic(diffuseColor, specularColor, specularColor, specularMonochrome);
    specularMonochrome = 1.0-specularMonochrome;
    float NdotV = abs(dot(normalDirection, viewDirection));
    float NdotH = saturate(dot(normalDirection, halfDirection));
    float VdotH = saturate(dot(viewDirection, halfDirection));
    float visTerm = SmithJointGGXVisibilityTerm(NdotL, NdotV, roughness);
    float normTerm = GGXTerm(NdotH, roughness);
    float specularPBL = (visTerm*normTerm) * PI;
    #ifdef UNITY_COLORSPACE_GAMMA
        specularPBL = sqrt(max(1e-4h, specularPBL));
    #endif
    specularPBL = max(0, specularPBL * NdotL);
    #if defined(_SPECULARHIGHLIGHTS_OFF)
        specularPBL = 0.0;
    #endif
    half surfaceReduction;
    #ifdef UNITY_COLORSPACE_GAMMA
        surfaceReduction = 1.0-0.28*roughness*perceptualRoughness;
    #else
        surfaceReduction = 1.0/(roughness*roughness + 1.0);
    #endif
    specularPBL *= any(specularColor) ? 1.0 : 0.0;
    float3 directSpecular = attenColor*specularPBL*FresnelTerm(specularColor, LdotH);
    half grazingTerm = saturate( gloss + specularMonochrome );
    float3 indirectSpecular = (gi.indirect.specular);
    indirectSpecular *= FresnelLerp (specularColor, grazingTerm, NdotV);
    indirectSpecular *= surfaceReduction;
    float3 specular = (directSpecular + indirectSpecular);
/////// Diffuse:
    NdotL = max(0.0,dot( normalDirection, lightDirection ));
    half fd90 = 0.5 + 2 * LdotH * LdotH * (1-gloss);
    float nlPow5 = Pow5(1-NdotL);
    float nvPow5 = Pow5(1-NdotV);
    float3 directDiffuse = ((1 +(fd90 - 1)*nlPow5) * (1 + (fd90 - 1)*nvPow5) * NdotL) * attenColor;
    float3 indirectDiffuse = float3(0,0,0);
    indirectDiffuse += gi.indirect.diffuse;
    float3 diffuse = (directDiffuse + indirectDiffuse) * diffuseColor;
/// Final Color:
    float3 finalColor = diffuse + specular;
    fixed4 finalRGBA = fixed4(finalColor,1);
    UNITY_APPLY_FOG(i.fogCoord, finalRGBA);
    #if OPEN_SHADER_DEBUG
    DEBUG_PBS_COLOR(diffuse,specular,normalDirection);
    #endif
    return finalRGBA;
}

#endif //UNITY_PIEXL