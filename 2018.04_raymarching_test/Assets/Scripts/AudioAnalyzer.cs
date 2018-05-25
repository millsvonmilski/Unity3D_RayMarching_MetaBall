using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class AudioAnalyzer : MonoBehaviour {
    [Range(0f, 1f)]
    public float mBassScaleMin, mBassScaleMax;
    [Range(0f, 1f)]
    public float mTrebScaleMin, mTrebScaleMax;

    [Header("Debug - just for visualizing")]
    [Range(0f, 1f)]
    public float mBass;
    [Range(0f, 1f)]
    public float mTreb;
    public bool isBassHit = false, isTrebHit = false;
    float pBass, pTreb;

    public float bass
    {
        get { return mBass; }
    }

    public float treb
    {
        get { return mTreb; }
    }

    public bool bassHit
    {
        get { return isBassHit; }
    }

    public bool trebHit
    {
        get { return isTrebHit; }
    }

	void Start ()
    {
		
	}

    float normalizeRange(float range, float min, float max)
    {
        return (Mathf.Clamp(range, min, max)-min)/(max-min);
    }
    void Update()
    {
        isBassHit = false;
        isTrebHit = false;

        float cBass = Mathf.Clamp(Lasp.AudioInput.CalculateRMS(Lasp.FilterType.LowPass) * 100f, 0f, 1f);
        float cTreb = Mathf.Clamp(Lasp.AudioInput.CalculateRMS(Lasp.FilterType.HighPass) * 100f, 0f, 1f);
        cBass = normalizeRange(cBass, mBassScaleMin, mBassScaleMax);
        cTreb = normalizeRange(cTreb, mTrebScaleMin, mTrebScaleMax);

        if (cBass > pBass) { mBass = cBass; isBassHit = true; }
        if (cTreb > pTreb) { mTreb = cTreb; isTrebHit = true; }

        if (mBass > 0.01f) mBass *= 0.99f;
        else mBass = 0f;

        if (mTreb > 0.01f) mTreb *= 0.99f;
        else mTreb = 0f;

        pBass = cBass;
        pTreb = cTreb;
    }
}
