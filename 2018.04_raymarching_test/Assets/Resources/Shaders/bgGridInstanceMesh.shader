Shader "Custom/PopInstanceMesh" {
	Properties {
		_MainTex ("Albedo (RGB)", 2D) = "white" {}
	}
	SubShader {
		Pass{
			Tags { "LightMode" = "ForwardBase" }

			CGPROGRAM

	#pragma vertex vert
	#pragma fragment frag
	#pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight

			#pragma target 4.5

	#include "UnityCG.cginc"
	#include "UnityLightingCommon.cginc"
	#include "AutoLight.cginc"

#include "Assets/Resources/Shaders/SimplexNoise3D.cginc"

			sampler2D _MainTex;

	// uniforms
	// -
	Texture2D uCsBufParticle;
	sampler2D uRayMarchingDepth;
	float uTime;
	float uTreb;
	float uBass;
	float uBgExposure;
	// -

	struct v2f
	{
		float4 pos : SV_POSITION;
		float2 uv_MainTex : TEXCOORD0;
		float3 ambient : TEXCOORD1;
		float3 diffuse : TEXCOORD2;
		float4 fillFresnel : TEXCOORD3;
		float3 normal : TEXCOORD4;
		float3 rayDir : TEXCOORD5;
		float3 worldPos : TEXCOORD6;
		float4 screenPos : TEXCOORD7;
	};

	v2f vert(appdata_full v, uint instanceID : SV_InstanceID)
	{
#if SHADER_TARGET >= 45
			float _buf_size = 40;
			int3 _buf_uv = int3(
				instanceID % (int)_buf_size,
				(int)((float)instanceID / _buf_size),
				0.);
			float4 _data = uCsBufParticle.Load(_buf_uv);
			float3 pos = _data.xyz;
			float scale = _data.w;
#endif
			float3 localPosition = v.vertex.xyz * scale;
			float3 worldPosition = pos + localPosition;
			float3 worldNormal = v.normal;
			float3 rayDir = -normalize(UnityWorldSpaceViewDir(worldPosition));

			float3 m_light = normalize(_WorldSpaceLightPos0);
			float3 m_fill = float3(0, -1, 0);
			float3 color = float3(1., 1., 1.);

			float3 ambient = 0.8 + 0.2 * worldNormal.y * scale;
			float3 diffuse = max(dot(worldNormal, m_light), 0.0) * scale;
			float3 m_fil = max(dot(worldNormal, m_fill), 0.0);

			float m_fre = pow(clamp(1.0 + dot(worldNormal, rayDir), 0.0, 1.0), 2.0);


			v2f o;
			o.pos = mul(UNITY_MATRIX_VP, float4(worldPosition, 1.0f));
			o.uv_MainTex = v.texcoord;
			o.ambient = ambient;
			o.diffuse = diffuse;
			o.fillFresnel = float4(m_fil, m_fre);
			o.normal = worldNormal;
			o.rayDir = rayDir;
			o.worldPos = worldPosition;
			o.screenPos = ComputeScreenPos(o.pos);
				return o;
		}

		float4 frag(v2f i) : SV_Target
		{
			// depth testing
			float rmDepth = tex2D(uRayMarchingDepth, i.screenPos.xy / i.screenPos.w).w;
			float curDepth = distance(_WorldSpaceCameraPos, i.worldPos);

			float alpha = rmDepth < curDepth ? 0. : 1.;
			float3 albedo = float3(1, 1, 1) + pow((uBass+uTreb), 3.)*2.;

			float mExposure = pow(uBgExposure, 2.);

			float3 m_brdf = albedo;
			m_brdf += .2 * i.ambient * albedo;
			//m_brdf += 1. * i.diffuse * albedo;
			//m_brdf += .3 * i.fillFresnel.rgb * albedo;
			m_brdf *= i.fillFresnel.w;

			float3 mCol = m_brdf;
			mCol = pow(max(mCol, 0.), 0.45);

			alpha = lerp(alpha, 0,
				clamp(1.0 - 1.2 * exp(-0.00001 * curDepth*curDepth), 0.0, 1.0));

			alpha *= mExposure;

			float4 output = float4(mCol, alpha);
			return output;
		}
		ENDCG
		}
	}
}