using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SimpleScreenPP : ScriptableRendererFeature
{
    //public Material TestM;
    [System.Serializable]       // 类的序列化：方便传输、存储、读取该类
    public class Settings       // RenderFeature面板中P  ass参数设置----新建个类，方便管理
    {        
        public RenderPassEvent my_RenderPassEvent;      // 设置Pass渲染的位置-初始值

        //材质
        public Material Mat;

    }

    public Settings settings = new Settings();      //新建设置

    class CustomTVPass : ScriptableRenderPass
    {
        //基本变量
        public Material m_Mat;
        //RenderTargetHandle m_Destination;//临时渲染的结果(临时RT) !!!注意RenderTargetHandle已经过时，现支持RTHandle
        RTHandle m_Destination;
        //临时RT名称
        private const string k_TempRTHandleName = "_TemporaryColorTexture_RTHandle";

        //着色器属性ID
        private static readonly int mainTexID = Shader.PropertyToID("_BaseMap");
        private static readonly string cmdName = "ScreenEffectRTHandle";

        public CustomTVPass(RenderPassEvent evt){
            //设置渲染事件位置
            this.renderPassEvent = evt;
            //设置过滤渲染目标(Opaque Or Transparent?)，先不设置了
            //......
        }

        // public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor){
        //     //直接配置渲染通道使用临时RTHandle作为渲染目标，也可以直接写在OnCameraSetup里
        //     ConfigureTarget(m_Destination);
        //     this.ConfigureClear( ClearFlag.All, Color.clear );
        // }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var cameraTextureDescriptor = renderingData.cameraData.cameraTargetDescriptor; //cameraTextureDescriptor 包含了当前相机的所有渲染设置
            cameraTextureDescriptor.colorFormat = RenderTextureFormat.DefaultHDR; //之前的ARGBHalf说太大了，改成这个
            cameraTextureDescriptor.depthBufferBits = 0;

            //升级为RTHandle之后，renderTargetHandle.Init + commandBuffer.GetTemporaryRT一并替换为RenderingUtils.ReallocateIfNeeded 或 RTHandles.Alloc
            //如果为ShadowMap则使用ShadowUtils.ShadowRTReAllocateIfNeeded
            RenderingUtils.ReAllocateIfNeeded(ref m_Destination, cameraTextureDescriptor, //使用相机的宽高，MSAA采样数和其他一些渲染信息
                                           FilterMode.Bilinear, 
                                           TextureWrapMode.Clamp, 
                                           name: k_TempRTHandleName);
            //简单一些使用RTHandles.Alloc("_ShaderProperty", name: "_ShaderProperty"); 一次性手动管理分配

            //以下的configure可以写在这里也可以写在Configure()里
            ConfigureTarget(m_Destination);
            this.ConfigureClear( ClearFlag.All, Color.clear );
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {   
            if (m_Mat == null)
            {
                Debug.LogError("ScreenEffect Material is null!");
                return;
            }

            if (m_Destination == null)
            {
                Debug.LogError("Destination RTHandle is null!");
                return;
            }
            //掏出cmd池
            CommandBuffer cmd = CommandBufferPool.Get(cmdName);
            RTHandle Source = renderingData.cameraData.renderer.cameraColorTargetHandle;
            //设置全局的_MainTex
            cmd.SetGlobalTexture(mainTexID, Source);

            try
            {
            cmd.Blit(Source, m_Destination, m_Mat, 0);
            cmd.Blit(m_Destination, Source);

            context.ExecuteCommandBuffer(cmd);
            }finally
            {
                CommandBufferPool.Release(cmd);
            }
        }
        
        //不需要的话可以不写，虽然也省不了多少
        // public override void OnCameraCleanup(CommandBuffer cmd)
        // {
        //     //如果使用ReAllocateIfNeeded分配RTHandle，一般不需要在此手动释放，但如有需要立即释放，使用m_TempRTHandle?.Release();
        // }
    }

    CustomTVPass m_TVPass;

    /// <inheritdoc/>
    public override void Create()
    {
        m_TVPass = new CustomTVPass(settings.my_RenderPassEvent);
        m_TVPass.m_Mat = settings.Mat;

    }


    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if(renderingData.cameraData.cameraType == CameraType.Game){
            renderer.EnqueuePass(m_TVPass);
        }
        
    }
}