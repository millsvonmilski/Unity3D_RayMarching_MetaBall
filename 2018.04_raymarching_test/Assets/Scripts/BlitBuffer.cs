using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class BlitBuffer : MonoBehaviour {
    public Material mMat;
    public RayMarchCtrl_ComputeShader mSrcComp;
    public bool enableBiCubicFilter = false;
    RenderTexture mSrc;

    private void OnRenderImage(RenderTexture src, RenderTexture dst)
    {
        if (!mSrc)
        {
            mSrc = mSrcComp.getRayMarchBuffer();
        }

        float _b = enableBiCubicFilter ? 1.0f : 0.0f;
        mMat.SetFloat("_EnableBiCubic", _b);
        mMat.SetTexture("_FilterLayer", mSrc);
        Graphics.Blit(src, dst, mMat);
    }
}
