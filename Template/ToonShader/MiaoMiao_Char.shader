Shader "Nainiu"
{
    Properties //着色器的输入 
    {
        _BaseMap ("Texture", 2D) = "white" {}
        _NoiseMap("NoiseMap", 2D) = "white" {}
        _SDFMap("SDF Map", 2D) = "white" {}
        _EmissiveMap("Emissive Color", 2D) = "Black" {}
        
        //Outline
        _OutlineScale("描边宽度", float) = 0.01
        _OutlineNoiseTiling("描边抖动", float) = 1
        _OutlineShakingSpeed("描边抖动速度", Range(0,1)) = 0.3
        _OutlineNoiseSize("描边中断", float) = 1
        _Mask("Mask", 2D) = "white" {}
        _OutlineAlphaClip("描边AlphaClip", float) = 0.3

        //Diffuse
        _DiffuseRamp("DiffuseRamp", 2D) = "white" {}
        _DiffuseIntensity("DiffuseIntensity", float) = 1

        //SDF
        _SDFProgress("SDF Test", Range(0,1)) = 0.3
        
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
            half _DiffuseIntensity;
        CBUFFER_END

        TEXTURE2D(_BaseMap); //贴图采样  
        SAMPLER(sampler_BaseMap);
        TEXTURE2D(_NoiseMap); //贴图采样  
        SAMPLER(sampler_NoiseMap);
        TEXTURE2D(_Mask); //贴图采样  
        SAMPLER(sampler_Mask);
        TEXTURE2D(_DiffuseRamp); 
        SAMPLER(sampler_DiffuseRamp);
        TEXTURE2D(_SDFMap); 
        SAMPLER(sampler_SDFMap);
        TEXTURE2D(_EmissiveMap); 
        SAMPLER(sampler_EmissiveMap);

        struct a2v //顶点着色器
        {
            float4 positionOS: POSITION;
            float3 normal: NORMAL;
            float2 uv : TEXCOORD0;
        };

        struct v2f //片元着色器
        {
            float4 positionCS: SV_POSITION;
            float2 uv: TEXCOORD0;
            float3 worldNormal:TEXCOORD1;
            float3 worldPos: TEXCOORD2;
        }; 

        ENDHLSL

        Pass
        {
            Cull Off
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
                //Normalize
                half3 worldNormal=normalize(i.worldNormal);
                half3 viewDir= normalize(_WorldSpaceCameraPos.xyz - i.worldPos);

                float4 SHADOW_COORDS = TransformWorldToShadowCoord(i.worldPos); // 获取阴影坐标
                Light mainLight = GetMainLight(SHADOW_COORDS);
                half3 lightDir = mainLight.direction; 

                //Sample Texture
                half4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                half4 diffuseRamp = SAMPLE_TEXTURE2D(_DiffuseRamp, sampler_DiffuseRamp, i.uv);
                half4 sdfMap = SAMPLE_TEXTURE2D(_SDFMap, sampler_SDFMap, i.uv);

                //Lambert Diffuse
                half lambert = saturate(dot(worldNormal, lightDir));
                half cartoon_diffuse = saturate(step(0.5, lambert));
                //half3 diffuse_col = lerp(diffuseRamp.rgb, 1, cartoon_diffuse);

                //SDF
                // half3 leftDir = mul(unity_ObjectToWorld, float4(-1,0,0,0));
                // half3 frontDir = mul(unity_ObjectToWorld, float4(0,0,1,0));
                // half signLdotL = dot(normalize(leftDir.xz), normalize(lightDirWS.xz))>=0?1:-1;
                // half faseSDFMap = SAMPLE_TEXTURE2D(_FaceSDFMap, sampler_FaceSDFMap, float2(uv.x*signLdotL,uv.y)).r;
                // half FdotL = dot(normalize(frontDir.xz), normalize(lightDir.xz));
                // faseSDFMap = step(0.5-FdotL*0.5,pow(faseSDFMap,_ShadowFacePow));
                // half4 color = lerp(_ShadowFaceColor * albedo, albedo,faseSDFMap);
    
                // half sdfTest = step(_SDFProgress, sdfMap.r);
                // half final_Diffuse = lerp( cartoon_diffuse, sdfTest, diffuseRamp.a);
                // half3 final_DiffuseCol = lerp(diffuseRamp.xyz, 1, final_Diffuse);

                //********************面部SDF********************************************************************************
                half sdf = 1;
                half3 sdf_col = half3(1,1,1);
                half bias = 0; 

                float isSahdow = 0;
                //这张阈值图代表的是阴影在灯光从正前方移动到左后方的变化
                //half4 ilmTex = SAMPLE_TEXTURE2D(_SDFMap, sampler_SDFMap, float2(1 - i.uv.x, i.uv.y));
                //这张阈值图代表的是阴影在灯光从正前方移动到右后方的变化
                half r_ilmTex = SAMPLE_TEXTURE2D(_SDFMap, sampler_SDFMap, i.uv);
                half l_ilmTex = SAMPLE_TEXTURE2D(_SDFMap, sampler_SDFMap, half2(-i.uv.x, i.uv.y));
                float2 Left = normalize(TransformObjectToWorldDir(float3(-1, 0, 0)).xz);	    //世界空间角色正左侧方向向量
                float2 FrontDir = normalize(TransformObjectToWorldDir(float3(0, 0, 1)).xz);	//世界空间角色正前方向向量
                float2 LightDir = normalize(lightDir.xz);
                float ctrl = 1 - clamp(0, 1, dot(FrontDir, LightDir) * 0.5 + 0.5);//计算前向与灯光的角度差（0-1），0代表重合
                float ilm = dot(LightDir, Left) > 0 ?  r_ilmTex.r : l_ilmTex ;//确定采样的贴图
                //ctrl值越大代表越远离灯光，所以阴影面积会更大，光亮的部分会减少-阈值要大一点，所以ctrl=阈值
                //ctrl大于采样，说明是阴影点
                isSahdow = step(saturate(ilm), ctrl);
                bias = smoothstep(0, 0.1, abs(ctrl - ilm));//平滑边界，smoothstep的原理和用法可以参考我上一篇文章
                if (ctrl > 0.99 || isSahdow == 1)
                    sdf = lerp( 1, 0 , saturate(isSahdow));

                // col.xyz *= sdf_col;
                //********************面部SDF End********************************************************************************
                half final_Diffuse = lerp( cartoon_diffuse, sdf, diffuseRamp.a);
                half3 final_DiffuseCol = lerp(diffuseRamp.xyz * _DiffuseIntensity, 1, final_Diffuse);
                col.xyz *= final_DiffuseCol;

                half3 emissive_col = saturate (SAMPLE_TEXTURE2D(_EmissiveMap, sampler_EmissiveMap, i.uv));
                return half4(col.xyz + emissive_col*3,1.0);
            }
            ENDHLSL
        }

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
                
                v.positionOS.xyz += v.normal * _OutlineScale * vertexCol;
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

                return half4(0,0,0,1);
            }
            ENDHLSL
        }
        
        
        

    }
}
