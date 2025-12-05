Shader "Custom/MyCustomURPSimple"
{
    Properties //着色器的输入 
    {
        _BaseMap ("Texture", 2D) = "white" {}
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
        CBUFFER_END

        TEXTURE2D(_BaseMap); //贴图采样  
        SAMPLER(sampler_BaseMap);

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
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag


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

                half4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                return half4(col.xyz,1.0);
            }
            ENDHLSL
        }
    }
}
