// Upgrade NOTE: replaced '_World2Object' with 'unity_WorldToObject'

// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "Custom/metaBall"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}
	SubShader
	{
		// alpha blending
		Tags{ "Queue" = "Transparent" }
		Blend SrcAlpha OneMinusSrcAlpha

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
				float3 worldPos : TEXCOORD0;
				float4 vertex : SV_POSITION;
			};

			sampler2D _MainTex;
			sampler2D _CameraDepthTexture;

			// uniforms
			//			
			Texture2D u_cs_buf_pos_and_life;
			Texture2D u_cs_buf_vel_and_scale;

			samplerCUBE u_cubemap;
						
			float u_EPSILON;

			float3 u_translate;

			int u_particle_num_sqrt;
			// -

			// Blob
			//
			struct Blob
			{
				float3 pos;
				float scale;
				float3 vel;
				float life;
			};
			// -

			// custom functions
			//
			// raymarching codes from "Metaballs - Quintic" by Inigo Quilze
			//
			// The MIT License
			// Copyright © 2013 Inigo Quilez
			// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

			// Using polynomial fallof of degree 5 for bounded metaballs, which produce smooth normals
			// unlike the cubic (smoothstep) based fallofs recommended in literature (such as John Hart).

			// The quintic polynomial p(x) = 6x5 - 15x4 + 10x3 has zero first and second derivatives in
			// its corners. The maxium slope p''(x)=0 happens in the middle x=1/2, and its value is 
			// p'(1/2) = 15/8. Therefore the  minimum distance to a metaball (in metaball canonical 
			// coordinates) is at least 8/15 = 0.533333 (see line 63).

			// This shader uses bounding spheres for each ball so that rays traver much faster when far
			// or outside their radius of influence.
			// https://www.shadertoy.com/view/ld2GRz
			//
			float3 hash3(float n)
			{
				return frac(sin(float3(n, n + 1.0, n + 2.0))*float3(43758.5453123, 22578.1459123, 19642.3490423));
			}

			float sdSphere(float3 p, float s)
			{
				return length(p) - s;
			}

			float opBlend(float a, float b, float k = 0.2)
			{
				float h = clamp(0.5 + 0.5*(b - a) / k, 0.0, 1.0);
				return lerp(b, a, h) - k * h*(1.0 - h);
			}

			float sdf_metaBall(float3 _point)
			{
				float is_in_sphere = 0.0;
				float p = 0.0;
				float dmin = 1e20; 

				float h = 1.; // track Lipschitz constant

				for (int i = 0; i < u_particle_num_sqrt; i++)
				{
					for (int j = 0; j < u_particle_num_sqrt; j++)
					{
						int3 _texel_coords = int3(i, j, 0);
						float3 blob_pos = u_cs_buf_pos_and_life.Load(_texel_coords).xyz + u_translate;
						float blob_scale = u_cs_buf_vel_and_scale.Load(_texel_coords).w;

						// bounding sphere for ball
						float db = length(blob_pos - _point);
						if (db < blob_scale)
						{
							float x = db / blob_scale;
							p += 1.0 - x * x*x*(x*(x*6.0 - 15.0) + 10.0);
							is_in_sphere = 1.0;
							h = max(h, 0.5333 * blob_scale);
						}
						else // this is out of bounding sphere 
						{
							dmin = min(dmin, db - blob_scale);
						}
					}
				}

				float d  = dmin + .1;

				if (is_in_sphere > 0.5)
				{
					float th = 0.2;
					d = h * (th - p);
				}

				return d;
			}

			float distanceField(in float3 _point)
			{
				return sdf_metaBall(_point);
				/*float map = 1e20;
				for (int i = 0; i < u_particle_num_sqrt; i++)
				{
					for (int j = 0; j < u_particle_num_sqrt; j++)
					{
						int3 _texel_coords = int3(i, j, 0);
						float3 blob_pos = u_cs_buf_pos_and_life.Load(_texel_coords).xyz + u_translate;
						float blob_scale = u_cs_buf_vel_and_scale.Load(_texel_coords).w;

						map = opBlend(map, sdSphere(blob_pos-_point, blob_scale));
					}
				}

				return map;*/
			}

			float2 intersect(in float3 _rayOrigin, in float3 _rayDirection)
			{
				float epsilon = u_EPSILON;
				float maxDist = _ProjectionParams.z;
				float step = epsilon * 2.0;
				float dist = 0.0;
				float m = 1.0;

				for (int i = 0; i < 75; i++)
				{
					if (step < epsilon || dist > maxDist)
						continue;// break;

					dist += step;
					step = distanceField(_rayOrigin + _rayDirection * dist);
				}

				// this ray goes out of far plane 
				if (dist > maxDist)
					m = -1.0;
				
				return float2(dist, m);
			}

			float3 calcNormal(in float3 _point)
			{
				float3 nor = float3(0.0, 0.0001, 0.0);
				
				for (int i = 0; i < u_particle_num_sqrt; i++)
				{
					for (int j = 0; j < u_particle_num_sqrt; j++)
					{
						int3 _texel_coords = int3(i, j, 0);
						float3 blob_pos = u_cs_buf_pos_and_life.Load(_texel_coords).xyz + u_translate;
						float blob_scale = u_cs_buf_vel_and_scale.Load(_texel_coords).w;

						float db = length(blob_pos - _point);
						float x = clamp(db / blob_scale, 0.0, 1.0);
						float p = x * x*(30.0*x*x - 60.0*x + 30.0);
						nor += normalize(_point - blob_pos) *p / blob_scale;
					}
					
				}

				return normalize(nor);
			}

			float calcAO(in float3 _point, in float3 _normal)
			{
				float totao = 0.0;
				for (int aoi = 0; aoi < 16; aoi++)
				{
					float3 aopos = -1.0 + 2.0 * hash3(float(aoi)*213.47);
					aopos *= sign(dot(aopos, _normal));
					aopos = _point + aopos * 0.5;
					float dd = clamp(distanceField(aopos).x*4.0, 0.0, 1.0);
					totao += dd;
				}
				totao /= 16.0;
				return clamp(totao*totao*1.5, 0.0, 1.0);
			}

			float calcShadow(in float3 _rayOrigin, in float3 _rayDirection, float _mint, float _k)
			{
				float res = 1.0;
				float t = _mint;
				for (int i = 0; i < 32; i++)
				{
					float h = distanceField(_rayOrigin + _rayDirection * t).x;
					res = min(res, _k * h / t);
					if (res < 0.0001) break;
					t += clamp(h, 0.01, 0.5);
				}
				return clamp(res, 0.0, 1.0);
			}

			void render(in float3 _pixels, inout float4 _col)
			{
				// Setup rays
				//
				float3 m_pixels = _pixels;
				float3 m_rayOrigin = _WorldSpaceCameraPos;
				float3 m_rayDir = normalize(m_pixels - m_rayOrigin);

				// TODO - depth seems incorrect
				//
				// linear view space depth for depth testing between raymarch and mesh geometry
				// https://flafla2.github.io/2016/10/01/raymarching.html
				//
				// float m_geo_depth = LinearEyeDepth(tex2D(_CameraDepthTexture, m_uv).r);

				// march ray
				// https://www.shadertoy.com/view/ld2GRz
				// https://www.shadertoy.com/view/lssGRM
				//
				float2 m_rayMarch = intersect(m_rayOrigin, m_rayDir);

				if (m_rayMarch.y > -.5)
				{
					// Geometry 
					float m_distanceMap = m_rayMarch.x;
					float3 m_geometry = m_rayOrigin + m_distanceMap * m_rayDir;
					float3 m_normal = calcNormal(m_geometry);
					float3 m_reflect = reflect(m_rayDir, m_normal);

					// material
					float3 m_material = float3(.3, .3, .3);
					float3 m_blob_col = float3(1., 1., 1.);

					float m_metaball_blend = 1.0;
					for (int i = 0; i < u_particle_num_sqrt; i++)
					{
						for (int j = 0; j < u_particle_num_sqrt; j++)
						{
							int3 _texel_coords = int3(i, j, 0);
							float4 _data = u_cs_buf_vel_and_scale.Load(_texel_coords);
							float3 blob_vel = _data.xyz;
							float blob_scale = _data.w;
							_data = u_cs_buf_pos_and_life.Load(_texel_coords);
							float3 blob_pos = _data.xyz + u_translate;
							float blob_life = _data.w;

							float x = clamp(length(blob_pos - m_geometry) / blob_scale, 0.0, 1.0);
							
							float p = 1.0 - x * x*(3.0 - 2.0*x);
							m_metaball_blend += p;

							m_blob_col += (abs(blob_vel*10.) * p);
							
							m_material.r += blob_life * p;
							m_material.b += blob_scale * .5 * p;
						}
					}
					m_blob_col /= m_metaball_blend;

					// lighting
					float m_occ = calcAO(m_geometry, m_normal);
					float m_amb = 0.8 + 0.2 * m_normal.y;
					float m_dif = max(dot(m_normal, _WorldSpaceLightPos0), 0.0);
					float m_bac = max(dot(m_normal, normalize(float3(-_WorldSpaceLightPos0.x, 0.0, -_WorldSpaceLightPos0.z))), 0.0);
					float m_sha = 0.0;
					if (m_dif>0.001)
						m_sha = calcShadow(m_geometry + 0.001*m_normal, _WorldSpaceLightPos0, 0.1, 32.0);
					float m_fre = pow(clamp(1.0 + dot(m_normal, m_rayDir), 0.0, 1.0), 2.0);

					// brdf
					float3 m_brdf = float3(0., 0., 0.);
					m_brdf += 1. * m_dif * m_blob_col * pow(float3(m_sha, m_sha, m_sha), float3(1.0, 1.2, 1.5));
					m_brdf += 1.3 * m_amb * m_blob_col * m_occ;
					m_brdf += .6 * m_bac * m_blob_col.bgr * m_occ;
					m_brdf += 3. * m_fre * m_blob_col.bgr * m_occ * (0.2 + 0.8 * m_sha);
					m_brdf += 1. * m_occ * float3(1., .0, .0) * m_occ*max(dot(-m_normal, m_rayDir), 0.0)*pow(clamp(dot(m_rayDir, _WorldSpaceLightPos0), 0.0, 1.0), 64.0)*m_rayMarch.y*2.0;

					// environmental map 
					m_brdf += pow(texCUBE(u_cubemap, m_reflect).rgb, 4.2) * (m_fre * .99 + .01);

					// surface-light interacion
					_col.rgb = m_brdf * m_material;
					_col.a = 1.;
					
					// debug
					// blob color
					//_col = m_blob_col;
					// normal 
					//_col = m_normal;
					// height map
					//_col = float3(pow(m_distanceMap/20., 2.), pow(m_distanceMap / 20., 2.), pow(m_distanceMap / 20., 2.));

					// post processing
					// https://www.shadertoy.com/view/ld2GRz
					//
					// gamma
					_col.rgb = pow(clamp(_col.rgb, 0.0, 1.0), 0.45);
				}
			}
			// -

			// vertex shader
			//
			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
				return o;
			}
			// -

			// fragment shader
			//
			fixed4 frag (v2f vert_in) : SV_Target
			{
				float3 mPixels = vert_in.worldPos;
				float4 mCol = float4(0.0, 0.0, 0.0, 0.0);

				render(mPixels, mCol);

				return mCol;
			}
			ENDCG
		}
	}
}
