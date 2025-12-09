Shader "Custom/URPUnlitTemplate_Full"
{
    Properties
    {
        // 基础属性
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _BaseMap ("Base Texture", 2D) = "white" {}
        
        // 金属度/光滑度
        _Metallic ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        
        // 法线贴图
        [Normal] _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Float) = 1.0
        
        // 自发光
        [HDR] _EmissionColor ("Emission Color", Color) = (0,0,0)
        _EmissionMap ("Emission Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag


            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 3.0

            // 着色器变体
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE
            #pragma multi_compile_fog

            // 包含URP核心库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 顶点输入结构
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            // 顶点输出结构
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 tangentWS : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
                float fogCoord : TEXCOORD5;
            };

            // 声明属性变量
            TEXTURE2D(_BaseMap);        SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap);        SAMPLER(sampler_BumpMap);
            TEXTURE2D(_EmissionMap);    SAMPLER(sampler_EmissionMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half _Metallic;
                half _Smoothness;
                half _BumpScale;
                half4 _EmissionColor;
            CBUFFER_END

            // 顶点着色器
            Varyings vert(Attributes input)
            {
                Varyings output;
                
                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                
                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalInputs.normalWS;
                output.tangentWS = normalInputs.tangentWS;
                output.bitangentWS = normalInputs.bitangentWS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.fogCoord = ComputeFogFactor(positionInputs.positionCS.z);
                
                return output;
            }

            // 片段着色器
            half4 frag(Varyings input) : SV_Target
            {
                // 采样纹理
                half4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
                
                // 采样法线贴图
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv), _BumpScale);
                half3 normalWS = TransformTangentToWorld(normalTS, half3x3(input.tangentWS, input.bitangentWS, input.normalWS));
                normalWS = NormalizeNormalPerPixel(normalWS);
                
                // 光照计算
                InputData lightingInput = (InputData)0;
                lightingInput.positionWS = input.positionWS;
                lightingInput.normalWS = normalWS;
                lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                
                SurfaceData surfaceInput = (SurfaceData)0;
                surfaceInput.albedo = baseColor.rgb;
                surfaceInput.normalTS = normalTS;
                surfaceInput.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, input.uv).rgb * _EmissionColor.rgb;
                surfaceInput.metallic = _Metallic;
                surfaceInput.smoothness = _Smoothness;
                surfaceInput.alpha = baseColor.a;
                
                // 应用URP光照模型
                half4 color = UniversalFragmentPBR(lightingInput, surfaceInput);
                
                // 应用雾效
                color.rgb = MixFog(color.rgb, input.fogCoord);
                
                return color;
            }

            ENDHLSL
        }

        // 阴影Pass（可选）
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            
            HLSLPROGRAM
            // 阴影投射代码...
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Lit"
}