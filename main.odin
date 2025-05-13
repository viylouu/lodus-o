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
        glfw.SetFramebufferSizeCallback(window_handle, fbcbSize)

        gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, proc(p: rawptr, name: cstring) {
            (^rawptr)(p)^ = glfw.GetProcAddress(name)
        })

        gl.Viewport(0,0,win_width,win_height)
    ////// a

    ///// LOAD SHADERS
        vert_src := load_shader_src("assets/shaders/base.vert");   frag_src := load_shader_src("assets/shaders/base.frag", []string{ "assets/shaders/fnl.glsl" })

        vert_shad: u32;                                            frag_shad: u32
        vert_shad = gl.CreateShader(gl.VERTEX_SHADER);             frag_shad = gl.CreateShader(gl.FRAGMENT_SHADER)
        gl.ShaderSource(vert_shad, 1, &vert_src, nil);             gl.ShaderSource(frag_shad, 1, &frag_src, nil)
        gl.CompileShader(vert_shad);                               gl.CompileShader(frag_shad)

        v_succ, f_succ: i32

        gl.GetShaderiv(vert_shad, gl.COMPILE_STATUS, &v_succ)
        if !bool(v_succ) {
            fmt.eprint("vertex shader compilation failed\n")
            log: [512]u8
            gl.GetShaderInfoLog(vert_shad, 512, nil, &log[0])
            fmt.eprintln(string(log[:]))
            return
        }

        gl.GetShaderiv(frag_shad, gl.COMPILE_STATUS, &f_succ)
        if !bool(f_succ) {
            fmt.eprint("fragment shader comp failed\n")
            log: [512]u8
            gl.GetShaderInfoLog(frag_shad, 512, nil, &log[0])
            fmt.eprintln(string(log[:]))
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
        if !bool(shad_succ) {
            fmt.eprintln("SHADER PROGRAM LINKING FAILED\n")
            log: [512]u8
            gl.GetProgramInfoLog(shad_prog, 512, nil, &log[0])
            fmt.eprintln(string(log[:]))
            return
        }
    ////// a

    ////// BUFFERS (i think)
        verts := [?]f32 { 0, 0, 0 }

        VAO: u32
        gl.GenVertexArrays(1, &VAO)
        gl.BindVertexArray(VAO)

        SSBO: u32
        gl.CreateBuffers(1, &SSBO)

        SSBO_VERTS: [dynamic]i32
        
        pos := vec3{0,0,0}

        vtx: i32 = (i32(pos.x) | i32(pos.y) << 10 | i32(pos.z) << 20)

        append_elem(&SSBO_VERTS, vtx)

        gl.UseProgram(shad_prog)

        gl.NamedBufferStorage(SSBO, size_of(SSBO), &SSBO, 0)
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, SSBO)

        gl.UseProgram(0)
    ////// a

    gl.Enable(gl.CULL_FACE)
    gl.CullFace(gl.BACK)
    gl.FrontFace(gl.CW)

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

        //model := glsl.mat4Rotate(vec3{0,1,0}, cast(f32)glfw.GetTime() + 90)
        model := glsl.identity(glsl.mat4)
        view  := glsl.mat4LookAt(vec3{0,0,1}, vec3{0,0,0}, vec3{0,1,0})
        proj  := glsl.mat4PerspectiveInfinite(linalg.to_radians(f32(90)), f32(win_width)/f32(win_height), 0.1)

        // what the fuuuuck is transmute([^]f32)&mat) ????
        gl.UniformMatrix4fv(m_loc, 1, gl.FALSE, transmute([^]f32)&model)
        gl.UniformMatrix4fv(v_loc, 1, gl.FALSE, transmute([^]f32)&view)
        gl.UniformMatrix4fv(p_loc, 1, gl.FALSE, transmute([^]f32)&proj)

        gl.DrawArrays(gl.TRIANGLES, 0, len(verts) * 6)

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

load_shader_src :: proc(path: string, includes: []string = nil) -> cstring {
    data, ok := os.read_entire_file(path)
    if !ok {
        fmt.eprintf("failed to load shader! (%s)\n", path)
        return ""
    } defer delete(data)

    str := string(data)
    
    if includes != nil {
        ver := ""
        // why no thing :(
        arrostr: [dynamic]string

        // jank because i dont know how otherwise
        // apparently strings.split_lines_iterator returns a string???
        for line in strings.split_lines_iterator(&str) {
            if ver != "" {
                append(&arrostr, line)
                continue
            }   ver = line
        }

        ostr := strings.concatenate(arrostr[:])

        // why cant you create a static array of size len(includes), and set all the values to default on initialize???
        toconc: [dynamic]string

        for i in 0..<len(includes) {
            append(&toconc, string(load_shader_src(includes[i])))
        }

        toincl := strings.concatenate(toconc[:])

        str = strings.concatenate([]string{ver, toincl, ostr})
    }

    return strings.clone_to_cstring(str)
}
