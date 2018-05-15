using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class RayMarchCtrl : MonoBehaviour {

    // global variables 
    // -
    [Header("scene")]
    public Camera m_cam;
    public bool is_cam_moving = true;

    [Range (0.0f, 1.0f)]
    public float m_time_delta;

    private bool is_init = false;
    private int cur_frame = 0;

    [Header("downSampling")]
    public bool is_downSampling = false;

    [Range(1.0f, 3.0f)]
    public float m_downSample_rate = 1.0f;
    // -

    // cs_particle variables
    // -
    [Header("cs particle behaviours")]
    public ComputeShader m_cs_particleCtrl;

    [Range(0.01f, 1.0f)]
    public float m_blob_scale_factor;
    [Range(1.0f, 16.0f)]
    public float m_particle_num_sqrt;

    private int tex_size_sqrt = 16;
    private int num_particles;
    private int num_cs_thread = 16; // need to be matched with [numthreads(num_cs_thread, num_cs_thread, 1)] in compute shader
    private int num_cs_threadGroup;
    private RenderTexture[] m_cs_out_pos_and_life;
    private RenderTexture[] m_cs_out_vel_and_scale;
    // -

    // instances mesh 
    // https://docs.unity3d.com/ScriptReference/Graphics.DrawMeshInstancedIndirect.html
    // -
    [Header("debug mesh")]
    public Mesh m_mesh_instance;
    public Shader m_shdr_instance;
    public bool render_debug_mesh = true;

    private ComputeBuffer m_buf_args;
    private Material m_mat_instance;
    private uint[] m_args = new uint[5] { 0, 0, 0, 0, 0 };
    // -

    // metaball variables
    // -
    [Header("raymarch metaball")]
    public Shader m_shdr_metaBall;
    public Cubemap m_cubemap_sky;

    private Mesh mCube;
    private MeshFilter mMeshFilter;
    private MeshRenderer mMeshRenderer;

    [Range(0.0001f, 0.01f)]
    public float m_EPSILON;

    public bool render_rayMarch = true;

    private Material m_mat_metaBall;
    // -

    // MonoBehaviour Funtions
    // -
    private void Start()
    {
        init_resources();
    }

    private void Update()
    {
        // just in case resources are initialized
        if (!is_init)
            init_resources();

        // update camera motion
        if(is_cam_moving)
            update_camera();

        // update cs-particle textures
        update_cs_particleCtrl();

        // draw instance
        if(render_debug_mesh)
            render_instancedMesh();

        // update and render metalball
        if (render_rayMarch)
            update_metaBall();

        // swap index for pingponging buffer
        cur_frame ^= 1;
    }

    private void OnDestroy()
    {
        destroy_resources();
    }
    // -


    // Custom Functions
    // 
    private RenderTexture create_cs_out_texture(int _w, int _h)
    {
        RenderTexture _out = new RenderTexture(_w, _h, 24);
        _out.format = RenderTextureFormat.ARGBFloat; // 32bit to encode pos/vel data
        _out.filterMode = FilterMode.Point;
        _out.wrapMode = TextureWrapMode.Clamp;
        _out.enableRandomWrite = true;
        _out.Create();

        return _out;
    }

    private void init_resources()
    {
        // ref - how numthreads works in compute shader
        // https://msdn.microsoft.com/en-us/library/windows/desktop/ff471442(v=vs.85).aspx
        num_particles = tex_size_sqrt * tex_size_sqrt;
        num_cs_threadGroup = (int)((float)tex_size_sqrt / num_cs_thread);

        // init materials 
        m_mat_metaBall = new Material(m_shdr_metaBall);
        m_mat_instance = new Material(m_shdr_instance);
        m_mat_instance.enableInstancing = true;

        // build cube
        mCube = buildCube();
        // mesh filter 
        mMeshFilter = gameObject.AddComponent<MeshFilter>() as MeshFilter;
        mMeshFilter.sharedMesh = mCube;
        // mesh renderer
        mMeshRenderer = gameObject.AddComponent<MeshRenderer>() as MeshRenderer;
        mMeshRenderer.sharedMaterial = m_mat_metaBall;

        // init render textures 
        m_cs_out_pos_and_life = new RenderTexture[2];
        m_cs_out_vel_and_scale = new RenderTexture[2];

        for (int i = 0; i < 2; i++)
        {
            m_cs_out_pos_and_life[i] = create_cs_out_texture(tex_size_sqrt, tex_size_sqrt);
            m_cs_out_vel_and_scale[i] = create_cs_out_texture(tex_size_sqrt, tex_size_sqrt);
        }
        init_cs_buffers();

        // init compute buffers
        m_buf_args = new ComputeBuffer(
            1, m_args.Length * sizeof(uint), ComputeBufferType.IndirectArguments);

        uint num_indices = m_mesh_instance != null ? (uint)m_mesh_instance.GetIndexCount(0) : 0;
        m_args[0] = num_indices;
        m_args[1] = (uint)num_particles;

        m_buf_args.SetData(m_args);


        is_init = true;
    }

    private void destroy_resources()
    {
        if (mCube)
            Destroy(mCube);

        if (mMeshFilter)
            Destroy(mMeshFilter);
        if (mMeshRenderer)
            Destroy(mMeshRenderer);

        if(m_mat_metaBall)
            Destroy(m_mat_metaBall);
        if (m_mat_instance)
            Destroy(m_mat_instance);

        for (int i = 0; i < 2; i++)
        {
            if (m_cs_out_pos_and_life[i])
                m_cs_out_pos_and_life[i].Release();
            m_cs_out_pos_and_life[i] = null;

            if (m_cs_out_vel_and_scale[i])
                m_cs_out_vel_and_scale[i].Release();
            m_cs_out_vel_and_scale[i] = null;
        }

        if (m_buf_args != null)
            m_buf_args.Release();
        m_buf_args = null;
    }

    private void init_cs_buffers()
    {
        int kernel_id = m_cs_particleCtrl.FindKernel("cs_init_buffers");

        m_cs_particleCtrl.SetTexture(kernel_id, "out_pos_and_life", m_cs_out_pos_and_life[cur_frame^1]);
        m_cs_particleCtrl.SetTexture(kernel_id, "out_vel_and_scale", m_cs_out_vel_and_scale[cur_frame^1]);
        
        m_cs_particleCtrl.Dispatch(
            kernel_id, num_cs_threadGroup, num_cs_threadGroup, 1);
    }

    private void update_camera()
    {
        float _deg = (float)Time.frameCount * 0.5f;
        float _rad = _deg * (Mathf.PI / 180.0f) * m_time_delta;
        float _r = Mathf.Sin(_rad) * 2.0f + 9.0f;

        Vector3 pos = Vector3.zero;
        pos.x = Mathf.Sin(_rad) * _r;
        pos.y = Mathf.Cos(_rad * 0.4f);
        pos.z = Mathf.Cos(_rad) * _r;

        m_cam.transform.position = pos;
        m_cam.transform.LookAt(Vector3.zero, Vector3.up);
    }

    private void update_cs_particleCtrl()
    {
        int kernel_id = m_cs_particleCtrl.FindKernel("cs_update_buffers");

        m_cs_particleCtrl.SetTexture(kernel_id, "u_p_pos_and_life", m_cs_out_pos_and_life[cur_frame^1]);
        m_cs_particleCtrl.SetTexture(kernel_id, "u_p_vel_and_scale", m_cs_out_vel_and_scale[cur_frame^1]);

        m_cs_particleCtrl.SetTexture(kernel_id, "out_pos_and_life", m_cs_out_pos_and_life[cur_frame]);
        m_cs_particleCtrl.SetTexture(kernel_id, "out_vel_and_scale", m_cs_out_vel_and_scale[cur_frame]);

        m_cs_particleCtrl.SetFloat("u_time_delta", m_time_delta);
        m_cs_particleCtrl.SetFloat("u_time", Time.fixedTime);
        m_cs_particleCtrl.SetFloat("u_blob_scale_factor", m_blob_scale_factor);

        m_cs_particleCtrl.SetVector("u_stay_in_cube_range", 
            new Vector3(transform.localScale.x, transform.localScale.y, transform.localScale.z));
  
        m_cs_particleCtrl.Dispatch(
            kernel_id, num_cs_threadGroup, num_cs_threadGroup, 1);
    }

    private void update_metaBall()
    {
        m_mat_metaBall.SetFloat("u_EPSILON", m_EPSILON);
        m_mat_metaBall.SetFloat("u_particle_num_sqrt", (int)m_particle_num_sqrt);

        m_mat_metaBall.SetVector("u_translate", transform.position);

        m_mat_metaBall.SetTexture("u_cubemap", m_cubemap_sky);

        m_mat_metaBall.SetTexture("u_cs_buf_pos_and_life", m_cs_out_pos_and_life[cur_frame]);
        m_mat_metaBall.SetTexture("u_cs_buf_vel_and_scale", m_cs_out_vel_and_scale[cur_frame]);
    }

    private void render_instancedMesh()
    {
        m_mat_instance.SetTexture("u_cs_buf_pos_and_life", m_cs_out_pos_and_life[cur_frame]);
        m_mat_instance.SetTexture("u_cs_buf_vel_and_scale", m_cs_out_vel_and_scale[cur_frame]);

        Graphics.DrawMeshInstancedIndirect(
            m_mesh_instance, 0, m_mat_instance, 
            new Bounds( Vector3.zero, new Vector3(100.0f, 100.0f, 100.0f) ), 
            m_buf_args);
    }

    private Mesh buildCube()
    {
        var vertices = new Vector3[] {
                new Vector3 (-1.0f, -1.0f, -1.0f),
                new Vector3 ( 1.0f, -1.0f, -1.0f),
                new Vector3 ( 1.0f,  1.0f, -1.0f),
                new Vector3 (-1.0f,  1.0f, -1.0f),
                new Vector3 (-1.0f,  1.0f,  1.0f),
                new Vector3 ( 1.0f,  1.0f,  1.0f),
                new Vector3 ( 1.0f, -1.0f,  1.0f),
                new Vector3 (-1.0f, -1.0f,  1.0f),
            };

        var triangles = new int[] {
                0, 2, 1,
                0, 3, 2,
                2, 3, 4,
                2, 4, 5,
                1, 2, 5,
                1, 5, 6,
                0, 7, 4,
                0, 4, 3,
                5, 4, 7,
                5, 7, 6,
                0, 6, 7,
                0, 1, 6
            };

        Mesh mesh = new Mesh();
        mesh.vertices = vertices;
        mesh.triangles = triangles;
        mesh.RecalculateNormals();

        return mesh;
    }
    // -
}
