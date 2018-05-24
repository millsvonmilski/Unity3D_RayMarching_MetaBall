using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class BgGridLayer : MonoBehaviour
{
    public ComputeShader mCs;
    private RenderTexture mCsBuf_particle;

    private int bufSizeSqrt = 80;

    public Mesh mMesh;
    public Shader mShdr;
    private Material mMat;
    private ComputeBuffer mCsBuf_args;
    private uint[] mArgs = new uint[5] { 0, 0, 0, 0, 0 };

    private bool isInit = false;

    void Start()
    {
        initResources();
    }

    void Update()
    {
        updateInstance();
        drawInstance();
    }

    void OnDestroy()
    {
        destroyResources();
    }

    private void updateInstance()
    {
        int kernel_id = mCs.FindKernel("CsBgGrid");

        mCs.SetTexture(kernel_id, "out_particle", mCsBuf_particle);
        mCs.SetFloat("uTime", Time.fixedTime);
        mCs.SetBool("isInit", isInit);

        mCs.Dispatch(
            kernel_id, bufSizeSqrt / 8, bufSizeSqrt / 8, 1);
    }

    private void drawInstance()
    {
        // draw mesh
        mMat.SetTexture("uCsBufParticle", mCsBuf_particle);

        mMat.SetTexture("uRayMarchingDepth", GetComponent<RayMarchCtrl_ComputeShader>().rayMarchingBuf);
        mMat.SetFloat("uTime", Time.fixedTime);
        mMat.SetFloat("uBgExposure", 1.0f - GetComponent<RayMarchCtrl_ComputeShader>().bgExposure);

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
        mCsBuf_particle = initCsBuffer(bufSizeSqrt, bufSizeSqrt);

        // init buffers
        updateInstance();

        isInit = true;
    }

    private void destroyResources()
    {
        if (mMat)
            Destroy(mMat);

        if (mCsBuf_particle)
            mCsBuf_particle.Release();
        mCsBuf_particle = null;

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

