Shader "Unlit/StandardToon"
{
    Properties
    {
        [Header(Sample Map)]
		[Space(15)]
        _BaseMap ("Base Map", 2D) = "white" {}
        _NormalMap ("Normal Map", 2D) = "white" {}
        _AOMap("AO Map", 2D) = "white" {}
        _DiffuseRamp("Ramp", 2D) = "white" {}
        _RampTex("Color Ramp", 2D) = "white" {}
        _SpecMap("Specular Map", 2D) = "white" {}
        [MaterialToggle(_NORMALMAP_ON)] _Toggle("HasNormal?", Float) = 0

        [Header(Shadow)]
		[Space(15)]
        _TintLayer1_Offset("TintLayer1_Offset",float)=0.5
        _TintLayer2_Offset("TintLayer2_Offset",float)=0.5
        
        _TintLayer1_Softness("TintLayer1_Softness",Range(0,1))=0.5
        _TintLayer2_Softness("TintLayer2_Softness",Range(0,1))=0.3

        _RimMin("Rim Min",float)=0.5
        _RimMax("Rim Max",float)=0.5
        
        _ShadowTint1("Shadow Tint 1",Color)=(1,1,1,1)
        _ShadowTint2("Shadow Tint 2",Color)=(1,1,1,1)

        [Header(Specular)]
		[Space(15)]
        _SpecSmoothness("Spec Smothness",float)=0.5
        _SpecIntensity("Spec Intensity",float)=0.5
        _SpecColor("Spec Color",Color)=(1,1,1,1)

        [Header(Specular)]
		[Space(15)]
        _FresnelMin("Fresnel Min",float)=0.5
        _FresnelMax("Fresnel Max",float)=0.5
        
        [Header(Ambient)]
		[Space(15)]
        _Roughness("Roughness",Range(0,1))=0.5
        _EnvMap("Evn Map",Cube)="white"{}
        _EnvIntensity("Env Intensity",float)=0.5
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "LightMode"="UniversalForward"}
        LOD 100
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag			

            //支持多个平行光，只支持一个平行光的阴影，主光源阴影，屏幕空间阴影，级联阴影
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            //软阴影，感觉会在身上留下不明痕迹
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            //抗锯齿
            #pragma multi_compile _ Anti_Aliasing_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float2 texcoord1:TEXCOORD1;
                float3 normal:NORMAL;
                float4 tangent:TANGENT;
                float4 color:COLOR;
                
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;

                float3 normalDir:TEXCOORD1;
                float3 tangentDir:TEXCOORD2;
                float3 binormalDir: TEXCOORD3;
                float3 pos_world:TEXCOORD4;
                float4 vertexColor:TEXCOORD5;

            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);
            TEXTURE2D(_AOMap);
            SAMPLER(sampler_AOMap);
            TEXTURE2D(_DiffuseRamp);
            SAMPLER(sampler_DiffuseRamp);
            TEXTURE2D(_SpecMap);
            SAMPLER(sampler_SpecMap);
            TEXTURE2D(_RampTex);
            SAMPLER(sampler_RampTex);
            
            float _TintLayer1_Offset;
            float _TintLayer2_Offset;
            float4 _ShadowTint1;
            float4 _ShadowTint2;
            float _RimMax;
            float _RimMin;
            float _TintLayer1_Softness;
            float _TintLayer2_Softness;
            float _SpecSmoothness;
            float _SpecIntensity;
            float4 _SpecColor;
            float _FresnelMin;
            float _FresnelMax;
            float _Roughness;
            TEXTURECUBE(_EnvMap);
            SAMPLER(sampler_EnvMap);
            float4 _EnvMap_HDR;
            float _EnvIntensity;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.normalDir=TransformObjectToWorldNormal(v.normal);
                o.tangentDir=normalize(mul(unity_ObjectToWorld,float4(v.tangent.xyz,0.0)).xyz);
                o.binormalDir=normalize(cross(o.normalDir,o.tangentDir)*v.tangent.w);
                o.pos_world=mul(unity_ObjectToWorld,v.vertex).xyz;
                o.uv = v.uv;
                return o;
            }

            float GetDistanceFade(float3 positionWS) //阴影淡入淡出
            {
                float4 posVS = mul(GetWorldToViewMatrix(), float4(positionWS, 1));
                //return posVS.z;
                #if UNITY_REVERSED_Z
                    float vz = -posVS.z;
                #else
                    float vz = posVS.z;
                #endif
                // jave.lin : 30.0 : start fade out distance, 40.0 : end fade out distance
                float fade = 1 - smoothstep(30.0, 40.0, vz);
                return fade;
            }

            half4 frag (v2f i) : SV_Target
            {
                //阴影
                float4 SHADOW_COORDS = TransformWorldToShadowCoord(i.pos_world);
				Light mainLight = GetMainLight(SHADOW_COORDS);
				half shadow = MainLightRealtimeShadow(SHADOW_COORDS); 
                
                // 向量计算
                half3 normalDir=normalize(i.normalDir);
                half3 tangentDir=normalize(i.tangentDir);
                half3 binormalDir=normalize(i.binormalDir);
                half3 lightDir=normalize(mainLight.direction);
                half3 viewDir=normalize(_WorldSpaceCameraPos.xyz - i.pos_world);

                //贴图数据
                half3 base_color=SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
                half ao=SAMPLE_TEXTURE2D(_AOMap, sampler_AOMap, i.uv).r;
                half4 spec_map=SAMPLE_TEXTURE2D(_SpecMap, sampler_SpecMap, i.uv);
                half spec_mask=spec_map.b;
                half spec_roughness=spec_map.a;

                //法线贴图
                #ifdef _NORMALMAP_ON
                    float4 normal_map=SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv);
                    float3 normal_data=UnpackNormal(normal_map);
                    float3x3 TBN=float3x3(tangentDir,binormalDir,normalDir);
                    normalDir=normalize(mul(normal_data,TBN));
                #endif

                //漫反射
                half NdotL=dot(normalDir,lightDir);
                half half_lambert=(NdotL+1)*0.5;
                half diffuse_term=half_lambert*ao;
                    //菲涅尔兰伯特计算-硬高光
                // half NdotV=saturate(dot(normalDir,viewDir));
                // half fresnel=1-NdotV;
                // fresnel=step(_RimMin,fresnel);
                // half edgeColor=fresnel;
                            
                half3 final_diffuse=half3(0,0,0);

                //第一层上色
                half2 uv_ramp1=half2(diffuse_term+_TintLayer1_Offset,_TintLayer1_Softness);
                half toon_diffuse1=SAMPLE_TEXTURE2D(_DiffuseRamp,sampler_DiffuseRamp,uv_ramp1).g;
                half3 tint_color1=lerp(half3(1,1,1), _ShadowTint1.rgb,toon_diffuse1*_ShadowTint1.a);
                half3 layer1_diffuse=tint_color1*base_color;
                //二层上色
                half2 uv_ramp2=half2(diffuse_term+_TintLayer2_Offset,_TintLayer2_Softness);
                half toon_diffuse2=SAMPLE_TEXTURE2D(_DiffuseRamp, sampler_DiffuseRamp, uv_ramp2).g;
                half3 tint_color2=lerp(half3(1,1,1), _ShadowTint2.rgb,toon_diffuse2*_ShadowTint2.a);
                final_diffuse=lerp(layer1_diffuse,tint_color2*base_color,toon_diffuse2);
                final_diffuse=min(final_diffuse, shadow*0.5); // 提升阴影的掠射角的质量

                //高光
                half3 H=normalize(lightDir+viewDir);
                half NdotH=dot(normalDir,H);
                half spec_term=max(0.0001,pow(NdotH,_SpecSmoothness*spec_roughness))*ao;
                half3 final_spec=spec_term*_SpecColor*_SpecIntensity*spec_mask;

                //环境反射/边缘光
                half fresnel=1-dot(normalDir,viewDir);
                fresnel=smoothstep(_FresnelMin,_FresnelMax,fresnel);
                half3 reflectDir=reflect(-viewDir,normalDir);
                float roughness=lerp(0.0,0.95,saturate(_Roughness));
                roughness=roughness*(1.7-0.7*roughness);
                float mip_level=roughness*6.0;

                //环境光(天光)
                half3 ambient = half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);

                half4 color_cubemap=SAMPLE_TEXTURECUBE_LOD(_EnvMap, sampler_EnvMap, reflectDir,mip_level);
                half3 env_color=DecodeHDREnvironment(color_cubemap,_EnvMap_HDR); // 在CG中是DecodeHDR
                half3 final_env=env_color*fresnel*_EnvIntensity*spec_mask;

                //阴影补充计算
                half shadowFadeOut = GetDistanceFade(i.pos_world); // 阴影渐入渐出
                shadow = saturate(lerp(1, shadow, shadowFadeOut));     

                //最终颜色
                half3 final_color=(final_diffuse+final_spec) * saturate(ambient * 20) + final_env * base_color * ambient * 5;

                //计算附加光照
                uint pixelLightCount = GetAdditionalLightsCount();
                for (uint lightIndex = 0; lightIndex < pixelLightCount; ++lightIndex)
                {
                    Light light = GetAdditionalLight(lightIndex, i.pos_world);
                    final_color += LightingLambert(light.color, light.direction, normalDir) * light.distanceAttenuation;;
                    //specular += LightingSpecular(light.color, light.direction, normalWS, viewDir, _SpecularColor, _Smoothness);
                }

                return float4(final_color,1);
            }
            ENDHLSL
        }

        Pass // Cast Shadow, Work
        {
            Tags {
                "LightMode"="ShadowCaster"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                half3 normal:NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 pos : SV_POSITION;
                // 生成阴影
                //V2F_SHADOW_CASTER;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {

                //half4 col = tex2D(_MainTex, i.uv);
                return 0;
            }
            ENDHLSL
        }
    }
}
