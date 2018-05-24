using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class TextureBendingMachine : MonoBehaviour {
    public Texture2D mNoise;
    public ComputeShader mShader;

    private RenderTexture mRt;
    private float mCsBuf_w = 1024f;
    private float mCsBuf_h = 1024f;
    private int mPatternId = 0;

    // Use this for initialization
    void Start () {
        mRt = new RenderTexture((int)mCsBuf_w, (int)mCsBuf_h, 0);
        mRt.format = RenderTextureFormat.ARGBFloat;
        mRt.useMipMap = true;
        mRt.autoGenerateMips = true;
        mRt.antiAliasing = 8;
        mRt.filterMode = FilterMode.Trilinear;
        mRt.wrapMode = TextureWrapMode.Mirror;
        mRt.enableRandomWrite = true;
        mRt.Create();

        mShader.SetTexture(mShader.FindKernel("pattern1"), "uTexNoise", mNoise);
    }
	
	// Update is called once per frame
	void Update () {
        updateTexture(mPatternId);
    }

    private void OnDestroy()
    {
        if (mRt)
            mRt.Release();
        mRt = null;
    }

    private void updateTexture(int _id)
    {
        string kernel_name;

        switch (_id)
        {
            case 0:
                kernel_name = "pattern0";
                break;
            case 1:
                kernel_name = "pattern1";
                break;
            case 2:
                kernel_name = "pattern2";
                break;
            default:
                kernel_name = "pattern1";
                break;
        }

        int kernel_id = mShader.FindKernel(kernel_name);

        mShader.SetTexture(kernel_id, "Result", mRt);
        mShader.SetFloat("uTime", Time.frameCount);
        mShader.SetVector("uRes", new Vector2(mCsBuf_w, mCsBuf_h));

        mShader.Dispatch(
            kernel_id, (int)mCsBuf_w / 8, (int)mCsBuf_h / 8, 1);
    }

    public RenderTexture getTexture()
    {
        return mRt;
    }

    public void setPatternId(int _id)
    {
        mPatternId = _id;
    }
}
