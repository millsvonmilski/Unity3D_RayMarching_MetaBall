Shader "Custom/instanceMesh" {
	Properties {
		_Color ("Color", Color) = (1,1,1,1)
		_MainTex ("Albedo (RGB)", 2D) = "white" {}
		_Glossiness ("Smoothness", Range(0,1)) = 0.99
		_Metallic ("Metallic", Range(0,1)) = 0.0
	}
	SubShader {
		Tags { "RenderType"="Opaque" }
		LOD 200

		CGPROGRAM
		// Physically based Standard lighting model, and enable shadows on all light types
		#pragma surface surf Standard fullforwardshadows 

		// https://docs.unity3d.com/ScriptReference/Graphics.DrawMeshInstancedIndirect.html
		#pragma multi_compile_instancing
		#pragma instancing_options procedural:setup

		// Use shader model 3.0 target, to get nicer looking lighting
		#pragma target 3.0

		sampler2D _MainTex;

		// uniforms
		// -
#ifdef UNITY_PROCEDURAL_INSTANCING_ENABLED
		Texture2D u_cs_buf_pos_and_life;
		Texture2D u_cs_buf_vel_and_scale;
#endif
		// -

		struct Input {
			float2 uv_MainTex;
		};

		half _Glossiness;
		half _Metallic;
		fixed4 _Color;
		
		void setup()
		{
			//https://docs.unity3d.com/ScriptReference/Graphics.DrawMeshInstancedIndirect.html
#ifdef UNITY_PROCEDURAL_INSTANCING_ENABLED
			float _buf_size = 16;
			int3 _buf_uv = int3(
				unity_InstanceID % (int)_buf_size,
				(int)((float)unity_InstanceID / _buf_size), 
				0.);
			float4 _data = u_cs_buf_pos_and_life.Load(_buf_uv);
			float3 pos = u_cs_buf_pos_and_life.Load(_buf_uv).xyz;
			float scale = u_cs_buf_vel_and_scale.Load(_buf_uv).w * .5;

			unity_ObjectToWorld._11_21_31_41 = float4(scale, 0, 0, 0);
			unity_ObjectToWorld._12_22_32_42 = float4(0, scale, 0, 0);
			unity_ObjectToWorld._13_23_33_43 = float4(0, 0, scale, 0);
			unity_ObjectToWorld._14_24_34_44 = float4(pos, 1);
			unity_WorldToObject = unity_ObjectToWorld;
			unity_WorldToObject._14_24_34 *= -1;
			unity_WorldToObject._11_22_33 = 1.0f / unity_WorldToObject._11_22_33;
#endif
		}
		

		void surf (Input IN, inout SurfaceOutputStandard o) {
#ifdef UNITY_PROCEDURAL_INSTANCING_ENABLED

			float _buf_size = 16;
			int3 _buf_uv = int3(
				unity_InstanceID % (int)_buf_size,
				(int)((float)unity_InstanceID / _buf_size),
				0.);
			float4 _data = u_cs_buf_pos_and_life.Load(_buf_uv);
			float3 pos = _data.xyz;
			float life = _data.w;
			_data = u_cs_buf_vel_and_scale.Load(_buf_uv);
			float3 vel = _data.xyz;
			float scale = _data.w;

			// Albedo comes from a texture tinted by color
			//fixed4 c = tex2D (_MainTex, IN.uv_MainTex) * _Color;
			fixed4 c = fixed4(1., 1., 1., 1.);
			o.Albedo = c.rgb;
			// Metallic and smoothness come from slider variables
			o.Metallic = _Metallic;
			o.Smoothness = _Glossiness;
			o.Emission = vel * 100.;
			o.Alpha = c.a;
#endif
		}
		ENDCG
	}
	FallBack "Diffuse"
}
