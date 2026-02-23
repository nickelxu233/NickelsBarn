Shader "Miaomiao/StylizedLit"
{
    Properties //着色器的输入 
    {
        _BaseMap ("Texture", 2D) = "white" {}
        _NoiseMap("NoiseMap", 2D) = "white" {}
        _SDFMap("SDF Map", 2D) = "white" {}
        //_TimeRampMap ("Time Ramp", 2D) = "white" {}

        //Emissive
        [HDR]_Tint("Tint Color", Color) = (1,1,1,1)
 
        //Outline
        _OutlineScale("描边宽度", float) = 0.01
        _OutlineNoiseTiling("描边抖动", float) = 1
        _OutlineShakingSpeed("描边抖动速度", Range(0,1)) = 0.3
        _OutlineNoiseSize("描边中断", float) = 1
        _Mask("Mask", 2D) = "white" {}
        _OutlineAlphaClip("描边AlphaClip", float) = 0.3
        _OutlineColor("Outline Color", Color) = (0,0,0,1)

        //Diffuse
        _DiffuseRamp("DiffuseRamp", 2D) = "white" {}

        //SDF
        _SDFProgress("SDF Test", Range(0,1)) = 0.3

        //Rim
        [Header(Rim)]
        _RimPow("Rim Pow", Range(0,5)) = 0.3
        _RimIntensity("边缘光强度", Range(0,5)) = 1
        _RimColor("边缘光颜色", Color) = (1,1,1,1)

        //Planar Shadow
        _GroundHeight("地面高度", Range(0,5)) = 0
        _ShadowFalloff("阴影衰减", Range(0,1)) = 0.1
        _ShadowColor("阴影颜色", Color) = (0,0,0,1)
        _ShadowAlpha("阴影透明度", Range(0,1)) = 1
    }
    SubShader
    {
        Tags {
            "RenderType"="Opaque"
            "RenderPipeLine"="UniversalRenderPipeline" //用于指明使用URP来渲染
        }

        HLSLINCLUDE 
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl" 

        CBUFFER_START(UnityPerMaterial) //声明变量
            float4 _BaseMap_ST;
            half _OutlineScale;
            half _OutlineNoiseTiling;
            half _OutlineNoiseSize;
            half _OutlineAlphaClip;
            half _OutlineShakingSpeed;
            half _SDFProgress;
            half4 _OutlineColor;
            half4 _Tint;
            uniform half _Timer;

            //Rim
            half _RimPow;
            half _RimIntensity;
            half4 _RimColor;

        CBUFFER_END

        TEXTURE2D(_BaseMap); //贴图采样  
        SAMPLER(sampler_BaseMap);
        TEXTURE2D(_NoiseMap); //贴图采样  
        SAMPLER(sampler_NoiseMap);
        TEXTURE2D(_Mask); //贴图采样  
        SAMPLER(sampler_Mask);

        //时间
        float _Timers;
        TEXTURE2D(_TimeRampMap); 
        SAMPLER(sampler_TimeRampMap);

        struct a2v //顶点着色器
        {
            float4 positionOS: POSITION;
            float3 normal: NORMAL;
            float2 uv : TEXCOORD0;
            half4 vertexColor : COLOR;
        };

        struct v2f //片元着色器
        {
            float4 positionCS: SV_POSITION;
            float2 uv: TEXCOORD0;
            float3 worldNormal:TEXCOORD1;
            float3 worldPos: TEXCOORD2;
            half4 color: TEXCOORD3;
        }; 

        ENDHLSL

        Pass
        {
            Cull Back
            Blend SrcAlpha OneMinusSrcAlpha
            Tags{"LightMode" = "UniversalForward"}
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS //主光源阴影
            //#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE //级联阴影(多张阴影贴图, 近处分辨率高, 远处分辨率低)
            //#pragma multi_compile _ _SHADOWS_SOFT //阴影抗锯齿


            v2f vert (a2v v)
            {
                v2f o;
                o.positionCS = TransformObjectToHClip(v.positionOS);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.worldNormal = TransformObjectToWorldNormal(v.normal);
                o.worldPos = mul(unity_ObjectToWorld, v.positionOS).xyz;
                return o;
            }

            half4 frag (v2f i) : SV_Target  /* 注意在HLSL中，fixed4类型变成了half4类型*/
            {
                //i.uv.y = - i.uv.y;
                //Normalize
                half3 worldNormal=normalize(i.worldNormal);
                half3 viewDir= normalize(_WorldSpaceCameraPos.xyz - i.worldPos);
                Light mainLight = GetMainLight();
                half3 lightDir = mainLight.direction;
                half3 lightColor = mainLight.color;

                // //Sample Texture
                half4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * _Tint;
                half3 time_Ramp = SAMPLE_TEXTURE2D(_TimeRampMap, sampler_TimeRampMap, half2(_Timers, 1));

                //环境光
                half3 ambient_col = SampleSH(worldNormal);

                //Diffuse
                half lambert = saturate(dot(lightDir, worldNormal));
                half cartoon_lambert = step(0.3, lambert);
                half3 diffuse_col = lerp(ambient_col, 1, cartoon_lambert);
                col.xyz *= diffuse_col;

                //边缘光
                half fresnel = dot(viewDir,worldNormal);
                fresnel = 1-saturate(pow(fresnel, _RimPow));
                fresnel = step(0.5,fresnel);
                fresnel *= cartoon_lambert;
                half3 fresnel_Col = saturate(fresnel * col.xyz * _RimColor * _RimIntensity);

                col.xyz += fresnel_Col;
                
                //时间系统
                col.xyz *= time_Ramp;

                //多光源支持
                half3 addCol = half3(0,0,0);
                uint pixelLightCount = GetAdditionalLightsCount();
                for (uint lightIndex = 0; lightIndex < pixelLightCount; ++lightIndex)
                {
                    Light addlight = GetAdditionalLight(lightIndex, i.worldPos);
                    addCol += LightingLambert(addlight.color, addlight.direction, worldNormal) * col * addlight.distanceAttenuation;;
                    //specular += LightingSpecular(light.color, light.direction, normalWS, viewDir, _SpecularColor, _Smoothness);
                }
                col.xyz += addCol;

                return half4(col.xyz,1.0);
            }
            ENDHLSL
        }

        //描边
        Pass
        {
            Cull Front
            Tags {"LightMode" = "SRPDefaultUnlit"}
            Blend SrcAlpha OneMinusSrcAlpha
            //ZWrite Off

            // Stencil {
            //     Ref 1
            //     Comp notEqual
            // }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            //#pragma shader_feature_local _OUTLINE_ON

            half _OutlineOn;

            v2f vert (a2v v)
            {
                //外扩
                v2f o;
                
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                half vertexCol = SAMPLE_TEXTURE2D_LOD(_NoiseMap,sampler_NoiseMap, o.uv * _OutlineNoiseTiling * sin(_Time.y * _OutlineShakingSpeed)  + 20,0).g;
                
                v.positionOS.xyz += v.normal * _OutlineScale * v.vertexColor;
                //v.positionOS.xyz *=_OutlineOn;
                o.positionCS = TransformObjectToHClip(v.positionOS);
                
                o.worldNormal = TransformObjectToWorldNormal(v.normal);
                o.worldPos = mul(unity_ObjectToWorld, v.positionOS).xyz;
                //o.screenPos = ComputeScreenPos(o.positionCS);

                
                return o;
            }
            half4 frag (v2f i) : SV_Target
            {
                half2 yUV = i.worldPos.xz / _OutlineNoiseSize;
                half2 xUV = i.worldPos.zy / _OutlineNoiseSize;
                half2 zUV = i.worldPos.xy / _OutlineNoiseSize;

                half yDiff = SAMPLE_TEXTURE2D(_Mask, sampler_Mask, yUV).b;
                half xDiff = SAMPLE_TEXTURE2D(_Mask, sampler_Mask, xUV).b;
                half zDiff = SAMPLE_TEXTURE2D(_Mask, sampler_Mask, zUV).b;

                half3 blendWeights = abs(i.worldNormal);
                blendWeights = blendWeights / (blendWeights.x + blendWeights.y + blendWeights.z);

                half final_alpha = xDiff * blendWeights.x + yDiff * blendWeights.y + zDiff * blendWeights.z;
               
                if(final_alpha<_OutlineAlphaClip)
                discard;

                //时间系统
                half3 time_Ramp = SAMPLE_TEXTURE2D(_TimeRampMap, sampler_TimeRampMap, half2(_Timers, 1));
                half3 outline_col = _OutlineColor * time_Ramp;
                

                return half4(outline_col, 1);
            }
            ENDHLSL
        }
        
        //阴影
        Pass
        {
            Cull Off
            //Tags {"LightMode" = "PlanarShadow"}
            Blend SrcAlpha OneMinusSrcAlpha
            //ZWrite Off

            Stencil
            {
                Ref 0
                Comp equal
                Pass incrWrap
                Fail keep
                ZFail keep
            }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            //#pragma shader_feature_local _OUTLINE_ON

            //CBUFFER_START(UnityPerMaterial) //声明变量
                half _GroundHeight;
                half _ShadowFalloff;
                half4 _ShadowColor;
                half _ShadowAlpha;
            //CBUFFER_END

            float3 ShadowProjectPos(float4 vertPos)
            {
                float3 shadowPos;

                //得到顶点的世界空间坐标
                float3 worldPos = mul(unity_ObjectToWorld , vertPos).xyz;

                //灯光方向
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);

                //阴影的世界空间坐标（低于地面的部分不做改变）
                shadowPos.y = min(worldPos .y , _GroundHeight);
                shadowPos.xz = worldPos .xz - lightDir.xz * max(0 , worldPos .y - _GroundHeight) / lightDir.y; 

                return shadowPos;
            }

            // float GetAlpha (v2f i) {
            //     float alpha = _BaseColor.a;
            //     alpha *= tex2D(_BaseMap, i.uv.xy).a;
            //     return alpha;
            // }

            v2f vert (a2v v)
            {
                //外扩
                v2f o;

                //得到阴影的世界空间坐标
                float3 shadowPos = ShadowProjectPos(v.positionOS);

                //转换到裁切空间
                // o.vertex = UnityWorldToClipPos(shadowPos);
                o.positionCS = TransformWorldToHClip(shadowPos);

                //计算阴影衰减
                float3 center = float3(unity_ObjectToWorld[0].w , _GroundHeight , unity_ObjectToWorld[2].w); //得到中心点世界坐标
                float falloff = 1-saturate(distance(shadowPos , center) * _ShadowFalloff);  //计算阴影衰减

                //阴影颜色
                o.color = _ShadowColor;
                o.color.a *= falloff * _ShadowAlpha;
                
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                half vertexCol = SAMPLE_TEXTURE2D_LOD(_NoiseMap,sampler_NoiseMap, o.uv * _OutlineNoiseTiling * sin(_Time.y * _OutlineShakingSpeed)  + 20,0).g;
                
                //v.positionOS.xyz += v.normal * _OutlineScale * v.vertexColor;
                
                o.worldNormal = TransformObjectToWorldNormal(v.normal);
                o.worldPos = mul(unity_ObjectToWorld, v.positionOS).xyz;

                return o;
            }
            half4 frag (v2f i) : SV_Target
            {
                return half4(i.color);
            }
            ENDHLSL
        }
        

    }
}
