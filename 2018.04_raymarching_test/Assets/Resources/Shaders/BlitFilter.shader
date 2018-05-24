Shader "Custom/BlitFilter"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}
	SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		// alpha blending
		Tags{ "Queue" = "Transparent" }
		Blend SrcAlpha OneMinusSrcAlpha

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
			
			float _EnableBiCubic;
			sampler2D _MainTex;
			Texture2D _FilterLayer;
			SamplerState sampler_FilterLayer;

			float Triangular(float f)
			{
				f = f / 2.0;
				if (f < 0.0)
				{
					return (f + 1.0);
				}
				else
				{
					return (1.0 - f);
				}
				return 0.0;
			}

			float BellFunc(float x)
			{
				float f = (x / 2.0) * 1.5; // Converting -2 to +2 to -1.5 to +1.5
				if (f > -1.5 && f < -0.5)
				{
					return(0.5 * pow(f + 1.5, 2.0));
				}
				else if (f > -0.5 && f < 0.5)
				{
					return 3.0 / 4.0 - (f * f);
				}
				else if ((f > 0.5 && f < 1.5))
				{
					return(0.5 * pow(f - 1.5, 2.0));
				}
				return 0.0;
			}

			float BSpline(float x)
			{
				float f = x;
				if (f < 0.0)
				{
					f = -f;
				}

				if (f >= 0.0 && f <= 1.0)
				{
					return (2.0 / 3.0) + (0.5) * (f* f * f) - (f*f);
				}
				else if (f > 1.0 && f <= 2.0)
				{
					return 1.0 / 6.0 * pow((2.0 - f), 3.0);
				}
				return 1.0;
			}

			// https://www.codeproject.com/articles/236394/bi-cubic-and-bi-linear-interpolation-with-glsl
			half4 BiCubic(in Texture2D _src, in float2 _coord)
			{
				float texelSizeX = 1.0 / _ScreenParams.x; //size of one texel 
				float texelSizeY = 1.0 / _ScreenParams.y; //size of one texel 

				float4 nSum = float4(0.0, 0.0, 0.0, 0.0);
				float4 nDenom = float4(0.0, 0.0, 0.0, 0.0);

				float a = frac(_coord.x * _ScreenParams.x); // get the decimal part
				float b = frac(_coord.y * _ScreenParams.y); // get the decimal part

				for (int m = -1; m <= 2; m++)
				{
					for (int n = -1; n <= 2; n++)
					{
						float4 vecData = _src.SampleLevel(sampler_FilterLayer,
							_coord + float2(texelSizeX * float(m),
								texelSizeY * float(n)), 0);
						
						float f = BSpline(float(m) - a);
						float4 vecCooef1 = float4(f, f, f, f);
						float f1 = BSpline(-(float(n) - b));
						float4 vecCoeef2 = float4(f1, f1, f1, f1);
						nSum = nSum + (vecData * vecCoeef2 * vecCooef1);
						nDenom = nDenom + ((vecCoeef2 * vecCooef1));
					}
				}
				return nSum / nDenom;
			}			

			half4 frag (v2f i) : SV_Target
			{
				half4 src = tex2D(_MainTex, i.uv);
				half4 layer = _EnableBiCubic ? BiCubic(_FilterLayer, i.uv) : _FilterLayer.SampleLevel(sampler_FilterLayer, i.uv, .0);

				layer.rgb = layer.rgb * (1. - src.a) + src.rgb * src.a;

				return float4(layer.rgb, 1.);
			}
			ENDCG
		}
	}
}
