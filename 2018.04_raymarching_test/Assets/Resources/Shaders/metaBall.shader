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

			sampler2D _MainTex;
			sampler2D _CameraDepthTexture;

			// uniforms
			//			
			Texture2D u_cs_buf_pos_and_life;
			Texture2D u_cs_buf_vel_and_scale;

			samplerCUBE u_cubemap;
			
			float4x4 u_inv_proj_mat;
			float4x4 u_inv_view_mat;
			
			float u_EPSILON;
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
			// https://www.shadertoy.com/view/ld2GRz
			//
			float hash(float n)
			{
				return frac(sin(n)*1751.5453);
			}

			float hash1(float2 p)
			{
				return frac(sin(p.x + 131.1*p.y)*1751.5453);
			}

			float3 hash3(float n)
			{
				return frac(sin(float3(n, n + 1.0, n + 2.0))*float3(43758.5453123, 22578.1459123, 19642.3490423));
			}

			float sdf_union(float _d1, float _d2)
			{
				return min(_d1, _d2);
			}

			float sdf_subtract(float _d1, float _d2)
			{
				return max(_d1, -_d2);
			}

			float sdf_intersect(float _d1, float _d2)
			{
				return max(_d1, _d2);
			}

			float sdf_metaBall(float3 _point)
			{
				float m = 0.0;
				float p = 0.0;
				float dmin = 1e20;

				float h = .5; // track Lipschitz constant

				for (int i = 0; i < 8; i++)
				{
					for (int j = 0; j < 8; j++)
					{
						int3 _texel_coords = int3(i, j, 0);
						float3 blob_pos = u_cs_buf_pos_and_life.Load(_texel_coords).xyz;
						float blob_scale = u_cs_buf_vel_and_scale.Load(_texel_coords).w;

						// bounding sphere for ball
						float db = length(blob_pos - _point);
						if (db < blob_scale)
						{
							float x = db / blob_scale;
							p += 1.0 - x * x*x*(x*(x*6.0 - 15.0) + 10.0);
							m += 1.0;
							h = max(h, 0.5333 * blob_scale);
						}
						else // bouncing sphere distance
						{
							dmin = min(dmin, db - blob_scale);
						}
					}
				}

				float d = dmin + 0.1;

				if (m > 0.5)
				{
					float th = 0.2;
					d = h * (th - p);
				}

				return d;
			}

			float sdf_sphere(float3 _point, float3 _center, float _radius)
			{
				return distance(_point, _center) - _radius;
			}

			float map(in float3 _point)
			{
				float dist_map = 1.;

				/*for (int i = 0; i < 8; i++)
				{
					for (int j = 0; j < 8; j++)
					{
						int3 _texel_coords = int3(i, j, 0);
						float3 blob_pos = u_cs_buf_pos_and_life.Load(_texel_coords).xyz;
						float blob_scale = u_cs_buf_vel_and_scale.Load(_texel_coords).w;

						dist_map = sdf_union(dist_map, sdf_sphere(_point, blob_pos, blob_scale));
					}
				}*/

				//return dist_map;
				return sdf_metaBall(_point);
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
						continue;

					dist += step;
					step = map(_rayOrigin + _rayDirection * dist);
				}

				if (dist > maxDist)
					m = -1.0;
				
				return float2(dist, m);
			}

			float3 calcNormal(in float3 _point)
			{
				float3 eps = float3(u_EPSILON, 0., 0.);
				return normalize(float3(
					map(_point + eps.xyy) - map(_point - eps.xyy),
					map(_point + eps.yxy) - map(_point - eps.yxy),
					map(_point + eps.yyx) - map(_point - eps.yyx)));
			}

			float calcAO(in float3 _point, in float3 _normal)
			{
				float totao = 0.0;
				for (int aoi = 0; aoi < 16; aoi++)
				{
					float3 aopos = -1.0 + 2.0 * hash3(float(aoi)*213.47);
					aopos *= sign(dot(aopos, _normal));
					aopos = _point + aopos * 0.5;
					float dd = clamp(map(aopos).x*4.0, 0.0, 1.0);
					totao += dd;
				}
				totao /= 16.0;
				return clamp(totao*totao*1.5, 0.0, 1.0);
			}

			float calcShadow(in float3 _rayOrigin, in float3 _rayDirection, float _mint, float _k)
			{
				float res = 1.0;
				float t = _mint;
				for (int i = 0; i < 64; i++)
				{
					float h = map(_rayOrigin + _rayDirection * t).x;
					res = min(res, _k * h / t);
					if (res < 0.0001) break;
					t += clamp(h, 0.01, 0.5);
				}
				return clamp(res, 0.0, 1.0);
			}

			void applyFog(inout float3 _col, in float _dist, in float3 _rayDir)
			{
				float fogAmount = clamp(1.0 - 1.2*exp(-0.001*_dist*_dist), 0.0, 1.0);
				float3  fogColor = texCUBE(u_cubemap, _rayDir).rgb;
				
				_col =  lerp(_col, fogColor, fogAmount);
			}

			void render(in float2 _uv, inout float3 _col)
			{
				// marching-ray in world space to match with unity convention 
				//
				float4 m_viewRay = mul(u_inv_proj_mat, float4(_uv*2. - 1., 1., 1.));
				m_viewRay.rgb /= m_viewRay.w;
				float4 m_worldRay = mul(u_inv_view_mat, m_viewRay);
				float3 m_rayOrigin = m_worldRay.rgb;

				float3 m_eyeOrigin = _WorldSpaceCameraPos;
				float3 m_rayDir = normalize(m_rayOrigin - m_eyeOrigin);

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
				float2 m_rayMarch = intersect(m_eyeOrigin, m_rayDir);

				if (m_rayMarch.y > -.5)
				{
					// Geometry 
					float m_dist = m_rayMarch.x;
					float3 m_rayLoc = m_eyeOrigin + m_dist * m_rayDir;
					float3 m_normal = calcNormal(m_rayLoc);
					float3 m_reflect = reflect(m_rayDir, m_normal);

					// material
					float3 m_material = float3(.3, .3, .3);
					float3 m_blob_col = float3(1., 1., 1.);

					for (int i = 0; i < 8; i++)
					{
						for (int j = 0; j < 8; j++)
						{
							int3 _texel_coords = int3(i, j, 0);
							float4 _data = u_cs_buf_vel_and_scale.Load(_texel_coords);
							float3 blob_vel = _data.xyz;
							float blob_scale = _data.w;
							_data = u_cs_buf_pos_and_life.Load(_texel_coords);
							float3 blob_pos = _data.xyz;
							float blob_life = _data.w;

							float x = clamp(length(blob_pos - m_rayLoc) / blob_scale, 0.0, 1.0);
							float p = 1.0 - x * x*(3.0 - 2.0*x);

							m_blob_col *= (abs(blob_vel*10.) * max(p, 0.) + 1.);
							
							m_material.r += blob_life * max(p, 0.);
							m_material.b += blob_scale * .5 * max(p, 0.);
						}
					}

					// lighting
					float m_occ = calcAO(m_rayLoc, m_normal);
					float m_amb = 0.8 + 0.2 * m_normal.y;
					float m_dif = max(dot(m_normal, _WorldSpaceLightPos0), 0.0);
					float m_bac = max(dot(m_normal, normalize(float3(-_WorldSpaceLightPos0.x, 0.0, -_WorldSpaceLightPos0.z))), 0.0);
					float m_sha = 0.0;
					if (m_dif>0.001)
						m_sha = calcShadow(m_rayLoc + 0.001*m_normal, _WorldSpaceLightPos0, 0.1, 32.0);
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
					_col = m_brdf * m_material;

					applyFog(_col, m_dist, m_rayDir);
				}

				// post processing
				// https://www.shadertoy.com/view/ld2GRz
				//
				// gamma
				_col = pow(clamp(_col, 0.0, 1.0), 0.45);
			}
			// -

			// vertex shader
			//
			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}
			// -

			// fragment shader
			//
			fixed4 frag (v2f vert_in) : SV_Target
			{
				float2 m_uv = vert_in.uv;
				float3 m_col = pow(tex2D(_MainTex, m_uv).rgb, 2.2);

				render(m_uv, m_col);

				return float4(m_col, 1.0 );
			}
			ENDCG
		}
	}
}
