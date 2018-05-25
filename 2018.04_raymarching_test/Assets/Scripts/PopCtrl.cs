using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class PopCtrl : MonoBehaviour {
    public Camera mCam;
    public ComputeShader mCs;
    private RenderTexture[] mCsBuf_posLife;
    private RenderTexture[] mCsBuf_velScale;
    private RenderTexture[] mCsBuf_collision;

    private int bufSizeSqrt = 80;

    public Mesh mMesh;
    public Shader mShdr;
    private Material mMat;
    private ComputeBuffer mCsBuf_args;
    private uint[] mArgs = new uint[5] { 0, 0, 0, 0, 0 };

    private int curFrame = 0;
    private bool isInit = false;

    public RenderTexture posLifeBuf
    {
        get { return mCsBuf_posLife[curFrame]; }
    }

    public RenderTexture collisionBuf
    {
        get { return mCsBuf_collision[curFrame]; }
    }

    void Start () {
        initResources();
	}
	
	void Update () {
        updateInstance();
        drawInstance();

        AudioEvent();

        curFrame ^= 1;
    }

    void OnDestroy()
    {
        destroyResources();
    }

    private void AudioEvent()
    {
        AudioAnalyzer aa = GetComponent<AudioAnalyzer>();
        float bass = aa.bass;
        float treb = aa.treb;
        bool bassHit = aa.bassHit;
        bool trebHit = aa.trebHit;

        mCs.SetFloat("uBass", bass);
        mCs.SetFloat("uTreb", treb);

        mMat.SetFloat("uBass", bass);
        mMat.SetFloat("uTreb", treb);
    }

    private void updateInstance()
    {
        int kernel_id = mCs.FindKernel("CsPopUpdate");

        mCs.SetTexture(kernel_id, "out_posLife", mCsBuf_posLife[curFrame]);
        mCs.SetTexture(kernel_id, "out_velScale", mCsBuf_velScale[curFrame]);
        mCs.SetTexture(kernel_id, "out_collision", mCsBuf_collision[curFrame]);

        mCs.SetTexture(kernel_id, "pPosLife", mCsBuf_posLife[curFrame^1]);
        mCs.SetTexture(kernel_id, "pVelScale", mCsBuf_velScale[curFrame^1]);
        mCs.SetTexture(kernel_id, "pCollision", mCsBuf_collision[curFrame^1]);

        mCs.SetTexture(kernel_id, "uBlobNormal", GetComponent<RayMarchCtrl_ComputeShader>().blobNormalBuf);
        mCs.SetTexture(kernel_id, "uBlobSurface", GetComponent<RayMarchCtrl_ComputeShader>().blobSurfaceBuf);

        mCs.SetVector("uTranslate", transform.position);
        mCs.SetVector("_WorldSpaceCameraPos", mCam.transform.position);

        mCs.SetFloat("uExposure", 1.0f - GetComponent<RayMarchCtrl_ComputeShader>().bgExposure);

        if (isInit)
        {
            mCs.SetTexture(kernel_id, "uPosLifeData",
                 GetComponent<RayMarchCtrl_ComputeShader>().posLifeBuf);
            mCs.SetTexture(kernel_id, "uVelScaleData",
                GetComponent<RayMarchCtrl_ComputeShader>().velScaleBuf);
        }

        mCs.SetBool("isInit", isInit);

        mCs.Dispatch(
            kernel_id, bufSizeSqrt/8, bufSizeSqrt/8, 1);
    }

    private void drawInstance()
    {
        // draw mesh
        mMat.SetTexture("uCsBufPosLife", mCsBuf_posLife[curFrame^1]);
        mMat.SetTexture("uCsBufVelScale", mCsBuf_velScale[curFrame^1]);
        mMat.SetTexture("uCsBufCollision", mCsBuf_collision[curFrame^1]);

        mMat.SetTexture("uCube", GetComponent<RayMarchCtrl_ComputeShader>().mCubemap_radiance);
        mMat.SetTexture("uRayMarchingDepth", GetComponent<RayMarchCtrl_ComputeShader>().rayMarchingBuf);
        mMat.SetFloat("u_time", Time.fixedTime);
        mMat.SetFloat("uBgExposure", 1.0f-GetComponent<RayMarchCtrl_ComputeShader>().bgExposure);

        Graphics.DrawMeshInstancedIndirect(
            mMesh, 0, mMat,
            new Bounds(Vector3.zero, new Vector3(500.0f, 500.0f, 500.0f)),
            mCsBuf_args);
    }

    private void initResources()
    {
        // material
        mMat = new Material(mShdr);

        // buffer for instance mesh
        mCsBuf_args = new ComputeBuffer(
            1, mArgs.Length * sizeof(uint), ComputeBufferType.IndirectArguments);

        uint numIndices = mMesh != null ? (uint)mMesh.GetIndexCount(0) : 0;
        mArgs[0] = numIndices;
        mArgs[1] = (uint)(bufSizeSqrt * bufSizeSqrt); // <- num particles

        mCsBuf_args.SetData(mArgs);

        // render textures for compute shader
        mCsBuf_posLife = new RenderTexture[2];
        mCsBuf_velScale = new RenderTexture[2];
        mCsBuf_collision = new RenderTexture[2];
        for (int i = 0; i < 2; i++)
        {
            mCsBuf_posLife[i] = initCsBuffer(bufSizeSqrt, bufSizeSqrt);
            mCsBuf_velScale[i] = initCsBuffer(bufSizeSqrt, bufSizeSqrt);
            mCsBuf_collision[i] = initCsBuffer(bufSizeSqrt, bufSizeSqrt);
        }

        // init buffers
        updateInstance();

        isInit = true;
    }

    private void destroyResources()
    {
        if (mMat)
            Destroy(mMat);

        for (int i = 0; i < 2; i++)
        {
            if (mCsBuf_posLife[i])
                mCsBuf_posLife[i].Release();
            mCsBuf_posLife[i] = null;

            if (mCsBuf_velScale[i])
                mCsBuf_velScale[i].Release();
            mCsBuf_velScale[i] = null;

            if (mCsBuf_collision[i])
                mCsBuf_collision[i].Release();
            mCsBuf_collision[i] = null;
        }

        if (mCsBuf_args != null)
            mCsBuf_args.Release();
        mCsBuf_args = null;
    }

    private RenderTexture initCsBuffer(int _w, int _h)
    {
        RenderTexture _out = new RenderTexture(_w, _h, 0);
        _out.format = RenderTextureFormat.ARGBFloat; 
        _out.filterMode = FilterMode.Point;
        _out.wrapMode = TextureWrapMode.Clamp;
        _out.enableRandomWrite = true;
        _out.Create();

        return _out;
    }
}
