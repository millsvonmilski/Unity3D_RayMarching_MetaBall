using System.Collections;
using System.Collections.Generic;
using UnityEngine;


public class RayMarchCtrl_ComputeShader : MonoBehaviour {

    // global variables 
    // -
    private RenderTexture mTexPattern;

    [Header("Interaction Ctrl")]
    public bool isCenterAttracted;
    public bool isInsideCube;
    public bool triggerScaleJump;

    public bool triggerBgExposure;
    private float mBgExposure = 0f;
    private float mBgExposure_target = 0f;

    public bool triggerTexMode;
    public bool triggerUvMode;

    [Header("scene")]
    public Camera mCam;
    public GameObject mLight;
    public bool isCamMoving;
    private Vector3 mCamLoc = new Vector3(0f, 0f, 70f);
    private Vector3 mCamLoc_target = new Vector3(0f, 0f, 70f);

    [Range (0.0f, 1.0f)]
    public float mTimeDelta;

    private bool isInit = false;
    private int curFrame = 0;
    // -

    // cs_particle variables
    // -
    [Header("cs particle behaviours")]
    public ComputeShader mCsParticleCtrl;

    [Range(0.01f, 1.0f)]
    public float mBlobScaleFactor;

    private int bufSizeSqrt = 7;
    private int numCsThread = 7; // need to be matched with [numthreads(numCsThread, numCsThread, 1)] in compute shader
    private int numCsThreadGroup;
    private RenderTexture[] mCsBuf_posLife;
    private RenderTexture[] mCsBuf_velScale;
    // -

    // metaball variables
    // -
    [Header("rayMarch metaball")]
    public ComputeShader mCsRayMarchCtrl;

    public Cubemap mCubemap_radiance;
    public Cubemap mCubemap_irradiance;

    private RenderTexture mCsBuf_rayMarch;
    private RenderTexture mCsBuf_normal;
    private RenderTexture mCsBuf_surface;
    private float mCsBuf_w = 1920f;
    private float mCsBuf_h = 1080f;
    // -

    public RenderTexture posLifeBuf
    {
        get { return mCsBuf_posLife[curFrame]; }
    }

    public RenderTexture velScaleBuf
    {
        get { return mCsBuf_velScale[curFrame]; }
    }

    public RenderTexture rayMarchingBuf
    {
        get { return mCsBuf_rayMarch; }
    }

    public RenderTexture blobNormalBuf
    {
        get { return mCsBuf_normal; }
    }

    public RenderTexture blobSurfaceBuf
    {
        get { return mCsBuf_surface; }
    }

    public float bgExposure
    {
        get { return mBgExposure; }
    }

    // MonoBehaviour Funtions
    // -
    private void Start()
    {
        initResources();
        ShuffleEvent();
    }

    private void Update()
    {
        // just in case resources are initialized
        if (!isInit)
            initResources();

        // update camera motion
        if (isCamMoving)
            update_camera();

        // get pattern
        mTexPattern = GetComponent<TextureBendingMachine>().getTexture();

        // get key event
        KeyEvent();

        // shuffle event
        ShuffleEvent();

        // update bg exposure
        updateBgExp();

        // update cs-particle textures
        updateCsParticleCtrl();

        // update metalball
        updateCsRayMarchCtrl();

        // swap index for pingponging buffer
        curFrame ^= 1;
    }

    public RenderTexture getRayMarchBuffer()
    {
        return mCsBuf_rayMarch;
    }

    private void OnDestroy()
    {
        destroyResources();
    }
    // -

    private void updateBgExp()
    {
        if (triggerBgExposure)
        {
            while (Mathf.Abs(mBgExposure - mBgExposure_target) < 0.2f)
                mBgExposure_target = Random.Range(0f, 1f);

            triggerBgExposure = false;
        }

        if (Mathf.Abs(mBgExposure - mBgExposure_target) > 0.01f)
        {
            mBgExposure += (mBgExposure_target - mBgExposure) * .02f;

            //Debug.Log(mBgExposure + ", " + mBgExposure_target);
        }
        else
            return;
    }

    private void KeyEvent()
    {
        if (Input.GetKeyUp(KeyCode.Alpha1))
            isCenterAttracted = !isCenterAttracted;

        if (Input.GetKeyUp(KeyCode.Alpha2))
            isInsideCube = !isInsideCube;

        if (Input.GetKeyUp(KeyCode.Alpha3))
            triggerScaleJump = true;

        if (Input.GetKeyUp(KeyCode.Alpha4))
            triggerTexMode = !triggerTexMode;
    }

    private void ShuffleEvent()
    {
        if (Time.frameCount % 140 == (Mathf.Floor(Random.Range(0f, 1f) * 140.0f)))
        {
            // jump scale
            triggerScaleJump = true;

            // update pattern id
            int patternId = (int)Random.Range(0f, 3f);
            GetComponent<TextureBendingMachine>().setPatternId(patternId);

            triggerUvMode = patternId == 0 ? true : false;

            // dice to trigger texture mode
            if (Random.Range(0f, 1f) > 0.5f)
                triggerTexMode = !triggerTexMode;

            // 
            ShuffleCam();

            //
            triggerBgExposure = true;

            //
            if (Random.Range(0f, 1f) > 0.5f)
                isCenterAttracted = !isCenterAttracted;
        }                        
    }

    private void ShuffleCam()
    {
        //
        mCamLoc_target.x = (Random.Range(0f, 1f) * 120f + 10f);// * (Random.Range(0f, 1f) > 0.5f ? 1f : -1f);
        mCamLoc_target.y = (Random.Range(0f, 1f) * 60f + 10f);// * (Random.Range(0f, 1f) > 0.5f ? 1f : -1f);
        mCamLoc_target.z = (Random.Range(0f, 1f) * 120f + 10f);// * (Random.Range(0f, 1f) > 0.5f ? 1f : -1f);
    }


    // Custom Functions
    // 
    private RenderTexture create_cs_out_texture(int _w, int _h)
    {
        RenderTexture _out = new RenderTexture(_w, _h, 0);
        _out.format = RenderTextureFormat.ARGBFloat; // 32bit to encode pos/vel data
        _out.filterMode = FilterMode.Point;
        _out.wrapMode = TextureWrapMode.Clamp;
        _out.enableRandomWrite = true;
        _out.Create();

        return _out;
    }

    private void initResources()
    {
        //mCsBuf_w = Screen.width;
        //mCsBuf_h = Screen.height;

        // ref - how numthreads works in compute shader
        // https://msdn.microsoft.com/en-us/library/windows/desktop/ff471442(v=vs.85).aspx
        numCsThreadGroup = (int)((float)bufSizeSqrt / numCsThread);

        // 
        mCsBuf_rayMarch = new RenderTexture((int)mCsBuf_w, (int)mCsBuf_h, 0);
        mCsBuf_rayMarch.format = RenderTextureFormat.ARGBFloat;
        //mCsBuf_rayMarch.useMipMap = true;
        //mCsBuf_rayMarch.autoGenerateMips = true;
        //mCsBuf_rayMarch.antiAliasing = 8;
        mCsBuf_rayMarch.filterMode = FilterMode.Bilinear;
        mCsBuf_rayMarch.wrapMode = TextureWrapMode.Clamp;
        mCsBuf_rayMarch.enableRandomWrite = true;
        mCsBuf_rayMarch.Create();

        mCsBuf_normal = create_cs_out_texture((int)mCsBuf_w, (int)mCsBuf_h);
        mCsBuf_surface = create_cs_out_texture((int)mCsBuf_w, (int)mCsBuf_h);

        // init render textures 
        mCsBuf_posLife = new RenderTexture[2];
        mCsBuf_velScale = new RenderTexture[2];

        for (int i = 0; i < 2; i++)
        {
            mCsBuf_posLife[i] = create_cs_out_texture(bufSizeSqrt, bufSizeSqrt);
            mCsBuf_velScale[i] = create_cs_out_texture(bufSizeSqrt, bufSizeSqrt);
        }
        init_cs_buffers();

        isInit = true;
    }

    private void destroyResources()
    {
        for (int i = 0; i < 2; i++)
        {
            if (mCsBuf_posLife[i])
                mCsBuf_posLife[i].Release();
            mCsBuf_posLife[i] = null;

            if (mCsBuf_velScale[i])
                mCsBuf_velScale[i].Release();
            mCsBuf_velScale[i] = null;
        }

        if (mCsBuf_rayMarch != null)
            mCsBuf_rayMarch.Release();
        mCsBuf_rayMarch = null;
    }

    private void init_cs_buffers()
    {
        int kernel_id = mCsParticleCtrl.FindKernel("cs_init_buffers");

        mCsParticleCtrl.SetTexture(kernel_id, "out_pos_and_life", mCsBuf_posLife[curFrame^1]);
        mCsParticleCtrl.SetTexture(kernel_id, "out_vel_and_scale", mCsBuf_velScale[curFrame^1]);
        
        mCsParticleCtrl.Dispatch(
            kernel_id, numCsThreadGroup, numCsThreadGroup, 1);
    }

    private void update_camera()
    {
        Vector3 dir = mCamLoc_target - mCamLoc;
        float dist = dir.magnitude;
        dir.Normalize();

        if (dist < .25f)
        {
            mCamLoc = mCamLoc_target;

            ShuffleCam();
        }
        else
        {
            mCamLoc += dir * .25f;
        }

        mCam.transform.position = mCamLoc;
        mCam.transform.LookAt(transform.position, Vector3.up);
    }

    private void updateCsParticleCtrl()
    {
        int kernel_id = mCsParticleCtrl.FindKernel("cs_update_buffers");

        mCsParticleCtrl.SetTexture(kernel_id, "u_p_pos_and_life", mCsBuf_posLife[curFrame^1]);
        mCsParticleCtrl.SetTexture(kernel_id, "u_p_vel_and_scale", mCsBuf_velScale[curFrame^1]);

        mCsParticleCtrl.SetTexture(kernel_id, "out_pos_and_life", mCsBuf_posLife[curFrame]);
        mCsParticleCtrl.SetTexture(kernel_id, "out_vel_and_scale", mCsBuf_velScale[curFrame]);

        mCsParticleCtrl.SetFloat("u_time_delta", mTimeDelta);
        mCsParticleCtrl.SetFloat("u_time", Time.fixedTime);
        mCsParticleCtrl.SetFloat("u_blob_scale_factor", mBlobScaleFactor);

        mCsParticleCtrl.SetBool("uIsCentered", isCenterAttracted);
        mCsParticleCtrl.SetBool("uIsInsideCube", isInsideCube);
        mCsParticleCtrl.SetBool("uTriggerScaleJump", triggerScaleJump);
        triggerScaleJump = false;

        mCsParticleCtrl.SetVector("u_stay_in_cube_range", 
            new Vector3(transform.localScale.x, transform.localScale.y, transform.localScale.z));

        mCsParticleCtrl.Dispatch(
            kernel_id, numCsThreadGroup, numCsThreadGroup, 1);
    }

    private void updateCsRayMarchCtrl()
    {
        int kernel_id = mCsRayMarchCtrl.FindKernel("CSRayMarching");

        mCsRayMarchCtrl.SetBool("uTriggerTexMode", triggerTexMode);
        mCsRayMarchCtrl.SetBool("uTriggerUvMode", triggerUvMode);

        mCsRayMarchCtrl.SetFloat("uTime", Time.fixedTime);
        float _uBgExposure = mBgExposure * mBgExposure;
        mCsRayMarchCtrl.SetFloat("uBgExposure", _uBgExposure);

        mCsRayMarchCtrl.SetVector("_ScreenParams", new Vector2(mCsBuf_w, mCsBuf_h));
        mCsRayMarchCtrl.SetVector("u_translate", transform.position);
        mCsRayMarchCtrl.SetVector("_WorldSpaceCameraPos", mCam.transform.position);
        mCsRayMarchCtrl.SetVector("_WorldSpaceLightPos0", mLight.transform.position);

        mCsRayMarchCtrl.SetTexture(kernel_id, "uTexPattern", mTexPattern);

        mCsRayMarchCtrl.SetTexture(kernel_id, "uCube_radiance", mCubemap_radiance);
        mCsRayMarchCtrl.SetTexture(kernel_id, "uCube_irradiance", mCubemap_irradiance);

        mCsRayMarchCtrl.SetTexture(kernel_id, "u_cs_buf_pos_and_life", mCsBuf_posLife[curFrame^1]);
        mCsRayMarchCtrl.SetTexture(kernel_id, "u_cs_buf_vel_and_scale", mCsBuf_velScale[curFrame^1]);

        mCsRayMarchCtrl.SetTexture(kernel_id, "uPopPosLife", GetComponent<PopCtrl>().posLifeBuf);
        mCsRayMarchCtrl.SetTexture(kernel_id, "uPopCollision", GetComponent<PopCtrl>().collisionBuf);

        mCsRayMarchCtrl.SetMatrix("uProjInv", mCam.projectionMatrix.inverse);
        mCsRayMarchCtrl.SetMatrix("uViewInv", mCam.cameraToWorldMatrix);

        mCsRayMarchCtrl.SetTexture(kernel_id, "Result", mCsBuf_rayMarch);
        mCsRayMarchCtrl.SetTexture(kernel_id, "out_CsBuf_normal", mCsBuf_normal);
        mCsRayMarchCtrl.SetTexture(kernel_id, "out_CsBuf_surface", mCsBuf_surface);

        mCsRayMarchCtrl.Dispatch(kernel_id, (int)mCsBuf_w / 8, (int)mCsBuf_h / 8, 1);
    }
    // -
}
