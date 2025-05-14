package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"

import "vendor:glfw"
import gl "vendor:OpenGL"

vec3 :: glsl.vec3

//// BACKEND
win_width: i32  = 800
win_height: i32 = 600

GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

//// CAMERA SYSTEM
camera_pos: vec3   = vec3{0,0,3}
camera_front: vec3 = vec3{0,0,-1}
camera_up:  vec3   = vec3{0,1,0}

camera_yaw: f32    = -90
camera_pitch:f32   = 0

first_mouse: bool = true

last_mouse_x, last_mouse_y: f32

//// GLOBALS
delta: f64

main :: proc() {
    window_handle := init_glfw_and_window()
    if window_handle == nil { fmt.eprintln("failed to init glfw!"); return }

    defer glfw.Terminate()
    defer glfw.DestroyWindow(window_handle)

    shad_prog, succ := load_shaders()
    if !succ { fmt.eprintln("failed to load shaders!"); return }

    defer gl.DeleteProgram(shad_prog)

    VAO, SSBO_VERTS := gen_buffers(shad_prog)

    enable_gl()

    lastTime: f64;
    for !glfw.WindowShouldClose(window_handle) {
        delta = get_delta(&lastTime)

        proc_inp(window_handle)
        glfw.PollEvents()

        gl.ClearColor(0.2, 0.3, 0.3, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)


        gl.UseProgram(shad_prog)
        gl.BindVertexArray(VAO)

        pv_loc   := gl.GetUniformLocation(shad_prog, "projview")

        view     := glsl.mat4LookAt(camera_pos, camera_pos + camera_front, camera_up)
        proj     := glsl.mat4PerspectiveInfinite(linalg.to_radians(f32(90)), f32(win_width)/f32(win_height), 0.1)
        projview := proj * view

        gl.UniformMatrix4fv(pv_loc, 1, gl.FALSE, mat4_to_gl(&projview))

        gl.DrawArrays(gl.TRIANGLES, 0, cast(i32)len(SSBO_VERTS) * 6)

        glfw.SwapBuffers(window_handle)


        fmt.printf("%d FPS\n", i32(1/delta))
    }
}


proc_inp :: proc(window: glfw.WindowHandle) {
    if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS { glfw.SetWindowShouldClose(window, true) }
    
    speed: f32 = 4

    camera_right := glsl.normalize(glsl.cross(camera_front, camera_up))

    if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS          { camera_pos -= glsl.cross(camera_right, camera_up) * f32(delta) * speed }
    if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS          { camera_pos += glsl.cross(camera_right, camera_up) * f32(delta) * speed }
    if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS          { camera_pos -= camera_right * f32(delta) * speed }
    if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS          { camera_pos += camera_right * f32(delta) * speed }
    if glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS { camera_pos.y -= f32(delta) * speed }
    if glfw.GetKey(window, glfw.KEY_SPACE) == glfw.PRESS      { camera_pos.y += f32(delta) * speed }

    if camera_pitch > 89  { camera_pitch = 89  }
    if camera_pitch < -89 { camera_pitch = -89 }

    dir: vec3
    dir.x = math.cos_f32(linalg.to_radians(camera_yaw)) * math.cos_f32(linalg.to_radians(camera_pitch))
    dir.z = math.sin_f32(linalg.to_radians(camera_yaw)) * math.cos_f32(linalg.to_radians(camera_pitch))
    dir.y = math.sin_f32(linalg.to_radians(camera_pitch))
    camera_front = glsl.normalize(dir)

}

////////////// HELPER FUNCTIONS

        fbcb_size :: proc "c" (window: glfw.WindowHandle, width,height: i32) {
            gl.Viewport(0,0,width,height)
            win_width  = width
            win_height = height
        }

        cpcb :: proc "c" (window: glfw.WindowHandle, x,y: f64) {
            mx, my := f32(x), f32(y)

            if first_mouse {
                last_mouse_x = mx
                last_mouse_y = my
                first_mouse = false
            }
            
            xoff, yoff := mx - last_mouse_x, last_mouse_y - my
            last_mouse_x = mx
            last_mouse_y = my

            sens :f32: 800
            xoff *= sens * f32(delta)
            yoff *= sens * f32(delta)

            camera_yaw   += xoff
            camera_pitch += yoff
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


/////////////// BIG HELPER FUNCTIONS

        load_shader :: proc(type: u32, path: string, include: []string = nil) -> (u32, bool) {
            src, src_succ := load_shader_src(path, include)
            if !src_succ { fmt.eprintf("failed to load shader source! (%s)\n", path); return 0, false }

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
                return 0, false
            }

            return shad, true
        }

        load_shader_src :: proc(path: string, includes: []string = nil) -> (cstring, bool) {
            data, ok := os.read_entire_file(path)
            if !ok {
                fmt.eprintf("failed to load shader! (%s)\n", path)
                return "", false
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

                ostr := strings.concatenate(arrostr[:])

                toconc: [dynamic]string

                for i in 0..<len(includes) { 
                    ssrc, s_succ := load_shader_src(includes[i])
                    if !s_succ { fmt.eprintf("failed to load include shader! (%s)\n", includes[i]); return "", false }
                    append(&toconc, cast(string)ssrc) 
                }

                toincl := strings.concatenate(toconc[:])

                str = strings.concatenate([]string{ver, toincl, ostr})
            }

            return strings.clone_to_cstring(str), true
        }







////// BACKEND
init_glfw_and_window :: proc() -> glfw.WindowHandle {
    if !bool(glfw.Init()) {
        fmt.eprint("glfw failed to init!")
        return nil
    }

    window_handle := glfw.CreateWindow(win_width, win_height, "hi", nil, nil)

    // defer glfw.Terminate()
    // defer glfw.DestroyWindow(window_handle)

    if window_handle == nil {
        fmt.eprint("failed to create window!")
        return nil
    }

    glfw.MakeContextCurrent(window_handle)
    glfw.SwapInterval(0)
    glfw.SetFramebufferSizeCallback(window_handle, fbcb_size)
    glfw.SetInputMode(window_handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
    glfw.SetCursorPosCallback(window_handle, cpcb)

    gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, proc(p: rawptr, name: cstring) {
        (^rawptr)(p)^ = glfw.GetProcAddress(name)
    })

    gl.Viewport(0,0,win_width,win_height)

    return window_handle
}

load_shaders :: proc() -> (u32, bool) {
    vert_shad, v_succ := load_shader(gl.VERTEX_SHADER, "assets/shaders/base.vert")
    frag_shad, f_succ := load_shader(gl.FRAGMENT_SHADER, "assets/shaders/base.frag", []string{ "assets/shaders/fnl.glsl" })        

    if !v_succ { return 0, false }
    if !f_succ { return 0, false }

    shad_succ: i32
    shad_prog: u32
    shad_prog = gl.CreateProgram() 
    gl.AttachShader(shad_prog, vert_shad)
    gl.AttachShader(shad_prog, frag_shad)
    gl.LinkProgram(shad_prog)

    gl.DeleteShader(vert_shad)
    gl.DeleteShader(frag_shad)

    gl.GetProgramiv(shad_prog, gl.LINK_STATUS, &shad_succ)
    if !bool(shad_succ) {
        fmt.eprintln("failed to link shader program!")
        log: [512]u8
        gl.GetProgramInfoLog(shad_prog, 512, nil, &log[0])
        fmt.eprintln(string(log[:]))
        return 0, false
    }

    return shad_prog, true
}

gen_buffers :: proc(shad_prog: u32) -> (u32, [dynamic]i32) {
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

    return VAO, SSBO_VERTS
}

enable_gl :: proc() {
    gl.Enable(gl.DEPTH_TEST)

    gl.Enable(gl.CULL_FACE)
    gl.CullFace(gl.BACK)
    gl.FrontFace(gl.CW)
}

get_delta :: proc(lastTime: ^f64) -> f64 {
    delta := glfw.GetTime() - lastTime^;
    lastTime^ = glfw.GetTime()

    return delta
}
