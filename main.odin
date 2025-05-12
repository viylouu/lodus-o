package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:math/linalg"
import "core:math/linalg/glsl"

import "vendor:glfw"
import gl "vendor:OpenGL"

win_width  :i32= 800
win_height :i32= 600

GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

main :: proc() {
    glfw.Init(); defer glfw.Terminate()

    glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
    glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_VERSION_MAJOR)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_VERSION_MINOR)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

    window_handle := glfw.CreateWindow(win_width, win_height, "hi", nil, nil)
    if window_handle == nil {
        fmt.eprint("failed to create window!")
        return
    }

    glfw.MakeContextCurrent(window_handle)
    glfw.SwapInterval(0)
    glfw.SetFramebufferSizeCallback(window_handle, fbcbSize)

    gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, proc(p: rawptr, name: cstring) {
        (^rawptr)(p)^ = glfw.GetProcAddress(name)
    })

    gl.Viewport(0,0,win_width,win_height)

    /*
    v_data, v_ok := os.read_entire_file("assets/shaders/base.vert")
    if !v_ok {
        fmt.eprint("failed to load vertex shader! (base.vert)")
        return
    }
    v_str    := strings.clone_from_bytes(v_data)
    vert_src := strings.clone_to_cstring(v_str)

    f_data, f_ok := os.read_entire_file("assets/shaders/base.frag")
    if !f_ok {
        fmt.eprint("failed to load fragment shader! (base.frag)")
        return
    }
    f_str    := strings.clone_from_bytes(f_data)
    frag_src := strings.clone_to_cstring(f_str)

    frag_shad, vert_shad: u32
    vert_shad = gl.CreateShader(gl.VERTEX_SHADER)
    frag_shad = gl.CreateShader(gl.FRAGMENT_SHADER)

    gl.ShaderSource(vert_shad, 1, &vert_src,nil)
    gl.ShaderSource(frag_shad, 1, &frag_src,nil)
    gl.CompileShader(vert_shad)
    gl.CompileShader(frag_shad)

    shad_succ: i32
    shad_prog: u32
    shad_prog = gl.CreateProgram(); defer gl.DeleteProgram(shad_prog)
    gl.AttachShader(shad_prog, vert_shad)
    gl.AttachShader(shad_prog, frag_shad)
    gl.LinkProgram(shad_prog)

    gl.DeleteShader(vert_shad)
    gl.DeleteShader(frag_shad)
    defer gl.DeleteProgram(shad_prog)

    gl.GetProgramiv(shad_prog, gl.LINK_STATUS, &shad_succ)
    if shad_succ == 0 {
        fmt.eprintln("SHADER ERR")
        return
    }
    */

    v_data, v_ok := os.read_entire_file("assets/shaders/base.vert")
    if !v_ok {
        fmt.eprint("failed to load vertex shader! (base.vert)")
        return
    }
    v_str    := strings.clone_from_bytes(v_data)
    vert_src := strings.clone_to_cstring(v_str)

    f_data, f_ok := os.read_entire_file("assets/shaders/base.frag")
    if !f_ok {
        fmt.eprint("failed to load fragment shader! (base.frag)")
        return
    }
    f_str    := strings.clone_from_bytes(f_data)
    frag_src := strings.clone_to_cstring(f_str)

    frag_shad, vert_shad: u32
    vert_shad = gl.CreateShader(gl.VERTEX_SHADER)
    frag_shad = gl.CreateShader(gl.FRAGMENT_SHADER)

    gl.ShaderSource(vert_shad, 1, &vert_src, nil)
    gl.ShaderSource(frag_shad, 1, &frag_src, nil)
    gl.CompileShader(vert_shad)
    gl.CompileShader(frag_shad)

    v_success: i32
    f_success: i32

    // Check vertex shader compilation status
    gl.GetShaderiv(vert_shad, gl.COMPILE_STATUS, &v_success)
    if v_success == 0 {
        fmt.eprint("vertex shader compilation failed\n")
        log: [512]u8
        gl.GetShaderInfoLog(vert_shad, 512, nil, &log[0])
        fmt.eprintln(strings.clone_from_bytes(log[:]))
        return
    }

    // Check fragment shader compilation status
    gl.GetShaderiv(frag_shad, gl.COMPILE_STATUS, &f_success)
    if f_success == 0 {
        fmt.eprint("fragment shader compilation failed\n")
        log: [512]u8
        gl.GetShaderInfoLog(frag_shad, 512, nil, &log[0])
        fmt.eprintln(strings.clone_from_bytes(log[:]))
        return
    }

    shad_succ: i32
    shad_prog: u32
    shad_prog = gl.CreateProgram(); defer gl.DeleteProgram(shad_prog)
    gl.AttachShader(shad_prog, vert_shad)
    gl.AttachShader(shad_prog, frag_shad)
    gl.LinkProgram(shad_prog)

    gl.DeleteShader(vert_shad)
    gl.DeleteShader(frag_shad)

    gl.GetProgramiv(shad_prog, gl.LINK_STATUS, &shad_succ)
    if shad_succ == 0 {
        fmt.eprintln("SHADER PROGRAM LINKING FAILED\n")
        log: [512]u8
        gl.GetProgramInfoLog(shad_prog, 512, nil, &log[0])
        fmt.eprintln(strings.clone_from_bytes(log[:]))
        return
    }


    ///////////

    verts := [?]f32 {
         0,  5, 0,
       -5, -5, 0,
        5, -5, 0
    }

    VAO: u32
    gl.GenVertexArrays(1, &VAO)
    gl.BindVertexArray(VAO)

    VBO: u32
    gl.GenBuffers(1, &VBO)

    gl.BindBuffer(gl.ARRAY_BUFFER, VBO)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(verts), &verts, gl.STATIC_DRAW)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(f32)*3, uintptr(0))
    gl.EnableVertexAttribArray(0)

    gl.Enable(gl.CULL_FACE)
    gl.CullFace(gl.BACK)
    gl.FrontFace(gl.CCW)

    lastTime: f64;

    for !glfw.WindowShouldClose(window_handle) {
        delta := glfw.GetTime() - lastTime;
        lastTime = glfw.GetTime()

        procInp(window_handle)
        glfw.PollEvents()

        gl.ClearColor(0.2, 0.3, 0.3, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.UseProgram(shad_prog)
        gl.BindVertexArray(VAO)

        m_loc := gl.GetUniformLocation(shad_prog, "model")
        v_loc := gl.GetUniformLocation(shad_prog, "view")
        p_loc := gl.GetUniformLocation(shad_prog, "proj")

        model := glsl.mat4Rotate(glsl.vec3{0,1,0}, cast(f32)glfw.GetTime() + 90)
        //model := glsl.identity(glsl.mat4)
        view  := glsl.mat4LookAt(glsl.vec3{0,0,1}, glsl.vec3{0,0,0}, glsl.vec3{0,1,0})
        proj  := glsl.mat4PerspectiveInfinite(linalg.to_radians(f32(90)), f32(win_width)/f32(win_height), 0.1)

        gl.UniformMatrix4fv(m_loc, 1, gl.FALSE, transmute([^]f32)&model)
        gl.UniformMatrix4fv(v_loc, 1, gl.FALSE, transmute([^]f32)&view)
        gl.UniformMatrix4fv(p_loc, 1, gl.FALSE, transmute([^]f32)&proj)

        gl.DrawArrays(gl.TRIANGLES, 0, 3)

        glfw.SwapBuffers(window_handle)


        fmt.printf("%d FPS\n", i32(1/delta))
    }
}

fbcbSize :: proc "c" (window: glfw.WindowHandle, width,height: i32) {
    gl.Viewport(0,0,width,height)
    win_width  = width
    win_height = height
}

procInp :: proc(window: glfw.WindowHandle) {
    if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
        glfw.SetWindowShouldClose(window, true)
    }
}
