Shader "Hidden/BgCam"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}
	SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
			};

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}
			
			sampler2D _MainTex;

			fixed4 frag (v2f i) : SV_Target
			{
				float4 mCol = float4(0, 0, 0, 1);

				float2 U = i.uv * _ScreenParams.xy * .25;
				U = (U + U - (mCol.xy = _ScreenParams.xy)) / mCol.y * 8.;


				float Pi = 3.14159265359,
					t = 5. * _Time.y,
			   		e = 15. / mCol.y, v;
				// animation ( switch dir )
				U = mul(
					float2x2(sin(Pi / 3.*ceil(t / 2. / Pi) + Pi * float4(.5, 1, 0, .5)))
					, U);      

				U.y /= .866;
				U -= .5;
				v = ceil(U.y);
				// hexagonal tiling
				U.x += .5*v;
				// animation ( scissor )
				U.x += sin(t) > 0. ? (1. - cos(t)) * (fmod(v, 2.) - .5) : 0.;

				// dots
				U = 2.*frac(U) - 1.;
				U.y *= .866;
				mCol += smoothstep(e, -e, length(U) - .6) - mCol;
				mCol.rgb = 1. - mCol.rgb;
				mCol.a = 1.;

				return mCol*.97;
			}
			ENDCG
		}
	}
}
