using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;

public class OutlineRendererFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class OutlineSettings
    {
        public LayerMask outlineLayerMask = -1;                 // 需要描边的物体所在Layer，-1表示所有层
        public RenderPassEvent insertEvent = RenderPassEvent.AfterRenderingOpaques;
        public string outlinePassTag = "Outline";               // Shader中描边Pass的LightMode标签名
        public string[] additionalTags = new string[0];         // 额外的标签（备选）
    }

    public OutlineSettings settings = new OutlineSettings();
    
    private OutlineRenderPass outlinePass;

    public override void Create()
    {
        outlinePass = new OutlineRenderPass(settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (outlinePass != null)
        {
            renderer.EnqueuePass(outlinePass);
        }
    }
    
    // ==================== RenderPass 实现 ====================
    
    private class OutlineRenderPass : ScriptableRenderPass
    {
        private OutlineSettings settings;
        private List<ShaderTagId> shaderTagIdList;
        private FilteringSettings filteringSettings;
        private RenderStateBlock renderStateBlock;
        
        public OutlineRenderPass(OutlineSettings settings)
        {
            this.settings = settings;
            renderPassEvent = settings.insertEvent;
            
            // 构建ShaderTag列表：从主标签和额外标签
            shaderTagIdList = new List<ShaderTagId>();
            shaderTagIdList.Add(new ShaderTagId(settings.outlinePassTag));
            
            if (settings.additionalTags != null)
            {
                foreach (string tag in settings.additionalTags)
                {
                    if (!string.IsNullOrEmpty(tag))
                    {
                        shaderTagIdList.Add(new ShaderTagId(tag));
                    }
                }
            }
            
            // 按Layer筛选
            filteringSettings = new FilteringSettings(RenderQueueRange.all, settings.outlineLayerMask);
            
            // 渲染状态块（可根据需要开启）
            renderStateBlock = new RenderStateBlock(RenderStateMask.Nothing);
        }
        
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            // 如果没有要渲染的物体，直接返回
            if (shaderTagIdList.Count == 0) return;
            
            // 创建 DrawingSettings，不过滤材质（保留物体自己的材质）
            SortingCriteria sortingCriteria = SortingCriteria.CommonOpaque;
            DrawingSettings drawingSettings = CreateDrawingSettings(shaderTagIdList, ref renderingData, sortingCriteria);
            
            // 重要：不覆盖材质，让每个物体使用自己的材质和描边Pass
            // drawingSettings.overrideMaterial = null; // 默认就是null
            
            // 执行渲染
            context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings, ref renderStateBlock);
        }
        
        // 可选：在每帧开始时执行一些初始化
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 可以在这里设置全局Shader变量，供所有描边Shader使用
            // cmd.SetGlobalInt("_OutlineStencilRef", 2);
        }
    }
}