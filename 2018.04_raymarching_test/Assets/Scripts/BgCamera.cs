using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class BgCamera : MonoBehaviour {
    public Shader mShader;
    private Material mMat;
    private RenderTexture mRT;

	void Start ()
    {
        // mat
        mMat = new Material(mShader);
        // render texture
        mRT = new RenderTexture(Screen.width, Screen.height, 0);
        mRT.format = RenderTextureFormat.ARGBHalf;
        mRT.filterMode = FilterMode.Trilinear;
        mRT.wrapMode = TextureWrapMode.Repeat;
        mRT.Create();
    }
	
	void FixedUpdate ()
    {
        Graphics.Blit(null, mRT, mMat);
    }

    public RenderTexture getBg()
    {
        return mRT;
    }

    private void OnDestroy()
    {
        if (mMat) Destroy(mMat);
        if (mRT) mRT.Release();
    }

    private void OnRenderImage(RenderTexture src, RenderTexture dst)
    {
        Graphics.Blit(mRT, dst);
    }
}
