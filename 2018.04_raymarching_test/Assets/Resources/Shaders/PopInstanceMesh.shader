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

			sampler2D _MainTex;

	// uniforms
	// -
	Texture2D uCsBufPosLife;
	Texture2D uCsBufVelScale;
	Texture2D uCsBufCollision;
	TextureCube<float4> uCube;
	SamplerState sampleruCube;
	sampler2D uRayMarchingDepth;
	float u_time;
	float uBgExposure;
	// -

	struct v2f
	{
		float4 pos : SV_POSITION;
		float2 uv_MainTex : TEXCOORD0;
		float3 ambient : TEXCOORD1;
		float3 diffuse : TEXCOORD2;
		float4 fillFresnel : TEXCOORD3;
		float3 reflect : TEXCOORD4;
		float3 normal : TEXCOORD5;
		float3 rayDir : TEXCOORD6;
		float4 posScale : TEXCOORD7;
		float4 velLife : TEXCOORD8;
		float3 worldPos : TEXCOORD9;
		float4 screenPos : TEXCOORD10;
		float4 collision : TEXCOORD11;
	};

	float4x4 rotationMatrix(float3 axis, float angle)
	{
		axis = normalize(axis);
		float s = sin(angle);
		float c = cos(angle);
		float oc = 1.0 - c;

		return float4x4(oc * axis.x * axis.x + c, oc * axis.x * axis.y - axis.z * s, oc * axis.z * axis.x + axis.y * s, 0.0,
			oc * axis.x * axis.y + axis.z * s, oc * axis.y * axis.y + c, oc * axis.y * axis.z - axis.x * s, 0.0,
			oc * axis.z * axis.x - axis.y * s, oc * axis.y * axis.z + axis.x * s, oc * axis.z * axis.z + c, 0.0,
			0.0, 0.0, 0.0, 1.0);
	}

	v2f vert(appdata_full v, uint instanceID : SV_InstanceID)
	{
#if SHADER_TARGET >= 45
			float _buf_size = 80;
			int3 _buf_uv = int3(
				instanceID % (int)_buf_size,
				(int)((float)instanceID / _buf_size),
				0.);
			float4 _data = uCsBufPosLife.Load(_buf_uv);
			float3 pos = _data.xyz;
			float life = _data.w;
			_data = uCsBufVelScale.Load(_buf_uv).w;
			float3 vel = _data.xyz;
			float scale = _data.w;

			float4 collision = uCsBufCollision.Load(_buf_uv);
#endif
			float3 localPosition = v.vertex.xyz * scale;
			float3 worldPosition = pos + localPosition;
			float3 worldNormal = v.normal;
			float3 rayDir = -normalize(UnityWorldSpaceViewDir(worldPosition));
			float3 reflectDir = reflect(rayDir, worldNormal);
			reflectDir = mul(rotationMatrix(float3(0, 1, 0), -u_time), float4(reflectDir, 1.)).xyz;


			float3 m_light = normalize(_WorldSpaceLightPos0);
			float3 m_fill = float3(0, -1, 0);
			float3 color = float3(1., 1., 1.);

			float3 ambient = 0.8 + 0.2 * worldNormal.y;
			float3 diffuse = max(dot(worldNormal, m_light), 0.0);
			float3 m_fil = max(dot(worldNormal, m_fill), 0.0);

			float m_fre = pow(clamp(1.0 + dot(worldNormal, rayDir), 0.0, 1.0), 2.0);


			v2f o;
			o.pos = mul(UNITY_MATRIX_VP, float4(worldPosition, 1.0f));
			o.uv_MainTex = v.texcoord;
			o.ambient = ambient;
			o.diffuse = diffuse;
			o.fillFresnel = float4(m_fil, m_fre);
			o.reflect = reflectDir;
			o.normal = worldNormal;
			o.rayDir = rayDir;
			o.posScale = float4(pos, scale);
			o.velLife = float4(vel, life);
			o.worldPos = worldPosition;
			o.screenPos = ComputeScreenPos(o.pos);
			o.collision = collision;
				return o;
		}

		float4 frag(v2f i) : SV_Target
		{
			// depth testing
			float rmDepth = tex2D(uRayMarchingDepth, i.screenPos.xy / i.screenPos.w).w;
			float curDepth = distance(_WorldSpaceCameraPos, i.worldPos);

			float alpha = rmDepth < curDepth ? 0. : 1.;

			float3 mCollision = i.collision.xyz * i.collision.w;
			//float3 mEnvMap = pow(max(uCube.SampleLevel(sampleruCube, i.reflect, 0).ggg, 0.), 4.2)
			//	* i.fillFresnel.w + mCollision;
			float3 albedo = pow(i.velLife.w, 4.) * .5;

			float mExposure = pow(uBgExposure, 2.);

			float3 m_brdf = albedo * mExposure;
			m_brdf += .6 * i.ambient * albedo * mExposure;
			m_brdf += 1. * i.diffuse * albedo;
			m_brdf += 1.3 * i.fillFresnel.rgb * albedo;
			m_brdf += 3. * i.fillFresnel.w * albedo;

			float3 mCol = mCollision * m_brdf * mExposure;
			mCol = pow(max(mCol, 0.), 0.45);

			alpha = lerp(alpha, 0,
				clamp(1.0 - 1.2 * exp(-0.0002 * curDepth*curDepth), 0.0, 1.0));


			float4 output = float4(mCol, alpha);
			return output;
		}
		ENDCG
		}
	}
}