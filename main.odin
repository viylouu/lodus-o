package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:math/linalg"
import "core:math/linalg/glsl"

import "vendor:glfw"
import gl "vendor:OpenGL"

vec3 :: glsl.vec3

win_width: i32  = 800
win_height: i32 = 600

GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

main :: proc() {
    ////// LOAD GLFW AND OPENGL
        if !bool(glfw.Init()) {
            fmt.eprint("glfw failed to init!")
            return
        }

        window_handle := glfw.CreateWindow(win_width, win_height, "hi", nil, nil)

        defer glfw.Terminate()
        defer glfw.DestroyWindow(window_handle)

        if window_handle == nil {
            fmt.eprint("failed to create window!")
            return
        }

        glfw.MakeContextCurrent(window_handle)
        glfw.SwapInterval(0)
        glfw.SetFramebufferSizeCallback(window_handle, fbcb_size)

        gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, proc(p: rawptr, name: cstring) {
            (^rawptr)(p)^ = glfw.GetProcAddress(name)
        })

        gl.Viewport(0,0,win_width,win_height)
    ////// a

    ///// LOAD SHADERS
        vert_shad := load_shader(gl.VERTEX_SHADER, "assets/shaders/base.vert")
        frag_shad := load_shader(gl.FRAGMENT_SHADER, "assets/shaders/base.frag", []string{ "assets/shaders/fnl.glsl" })        

        if vert_shad == 0 { return }
        if frag_shad == 0 { return }

        shad_succ: i32
        shad_prog: u32
        shad_prog = gl.CreateProgram(); defer gl.DeleteProgram(shad_prog)
        gl.AttachShader(shad_prog, vert_shad)
        gl.AttachShader(shad_prog, frag_shad)
        gl.LinkProgram(shad_prog)

        gl.DeleteShader(vert_shad)
        gl.DeleteShader(frag_shad)

        gl.GetProgramiv(shad_prog, gl.LINK_STATUS, &shad_succ)
        if !bool(shad_succ) {
            fmt.eprintln("SHADER PROGRAM LINKING FAILED\n")
            log: [512]u8
            gl.GetProgramInfoLog(shad_prog, 512, nil, &log[0])
            fmt.eprintln(string(log[:]))
            return
        }
    ////// a

    ////// BUFFERS (i think)
        VAO: u32
        gl.GenVertexArrays(1, &VAO)
        gl.BindVertexArray(VAO)

        SSBO: u32
        gl.CreateBuffers(1, &SSBO)

        SSBO_VERTS: [dynamic]i32
    
        add_cube(&SSBO_VERTS, 0,0,0)
        add_cube(&SSBO_VERTS, 0,1,0)
        add_cube(&SSBO_VERTS, 1,0,0)
        add_cube(&SSBO_VERTS, 0,0,1)

        gl.UseProgram(shad_prog)

        gl.NamedBufferStorage(SSBO, len(SSBO_VERTS) * size_of(i32), &SSBO_VERTS[0], gl.NONE)
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, SSBO)

        gl.UseProgram(0)
    ////// a

    gl.Enable(gl.DEPTH_TEST)

    gl.Enable(gl.CULL_FACE)
    gl.CullFace(gl.BACK)
    gl.FrontFace(gl.CW)

    lastTime: f64;

    for !glfw.WindowShouldClose(window_handle) {
        delta := glfw.GetTime() - lastTime;
        lastTime = glfw.GetTime()

        proc_inp(window_handle)
        glfw.PollEvents()

        gl.ClearColor(0.2, 0.3, 0.3, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        gl.UseProgram(shad_prog)
        gl.BindVertexArray(VAO)

        m_loc := gl.GetUniformLocation(shad_prog, "model")
        v_loc := gl.GetUniformLocation(shad_prog, "view")
        p_loc := gl.GetUniformLocation(shad_prog, "proj")

        model := glsl.identity(glsl.mat4)
        view  := glsl.mat4LookAt(vec3{2,2,2}, vec3{0,0,0}, vec3{0,1,0})
        proj  := glsl.mat4PerspectiveInfinite(linalg.to_radians(f32(90)), f32(win_width)/f32(win_height), 0.1)

        gl.UniformMatrix4fv(m_loc, 1, gl.FALSE, mat4_to_gl(&model))
        gl.UniformMatrix4fv(v_loc, 1, gl.FALSE, mat4_to_gl(&view))
        gl.UniformMatrix4fv(p_loc, 1, gl.FALSE, mat4_to_gl(&proj))

        gl.DrawArrays(gl.TRIANGLES, 0, cast(i32)len(SSBO_VERTS) * 6)

        glfw.SwapBuffers(window_handle)

        fmt.printf("%d FPS\n", i32(1/delta))
    }
}

fbcb_size :: proc "c" (window: glfw.WindowHandle, width,height: i32) {
    gl.Viewport(0,0,width,height)
    win_width  = width
    win_height = height
}

proc_inp :: proc(window: glfw.WindowHandle) {
    if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
        glfw.SetWindowShouldClose(window, true)
    }
}

load_shader_src :: proc(path: string, includes: []string = nil) -> cstring {
    data, ok := os.read_entire_file(path)
    if !ok {
        fmt.eprintf("failed to load shader! (%s)\n", path)
        return ""
    } defer delete(data)

    str := string(data)
    
    if includes != nil {
        ver := ""
        arrostr: [dynamic]string

        for line in strings.split_lines_iterator(&str) {
            if ver != "" {
                append(&arrostr, line)
                append(&arrostr, "\n")
                continue
            }   ver = line
        }

        fmt.println(ver)

        ostr := strings.concatenate(arrostr[:])

        toconc: [dynamic]string

        for i in 0..<len(includes) {
            append(&toconc, cast(string)load_shader_src(includes[i]))
        }

        toincl := strings.concatenate(toconc[:])

        str = strings.concatenate([]string{ver, toincl, ostr})
    }

    return strings.clone_to_cstring(str)
}

load_shader :: proc(type: u32, path: string, include: []string = nil) -> u32 {
    src := load_shader_src(path, include)

    shad: u32                          
    shad = gl.CreateShader(type)           
    gl.ShaderSource(shad, 1, &src, nil)            
    gl.CompileShader(shad)

    succ: i32
    gl.GetShaderiv(shad, gl.COMPILE_STATUS, &succ)
    if !bool(succ) {
        fmt.eprintf("shader compilation failed! (%s)\n", path)
        log: [512]u8
        gl.GetShaderInfoLog(shad, 512, nil, &log[0])
        fmt.eprintln(string(log[:]))
        return 0
    }

    return shad
}

add_cube :: proc(SSBO_VERTS: ^[dynamic]i32, x,y,z: i32) {
    for i in 0..<6 {
        vtx: i32 = (x | y << 6 | z << 12 | i32(i) << 18)
        append(SSBO_VERTS, vtx)
    }
}

mat4_to_gl :: proc(mat: ^glsl.mat4) -> [^]f32 {
    // magic function
    return transmute([^]f32)mat
}
