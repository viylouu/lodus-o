package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"

import fnl "libs/fastnoiselite"
import im "libs/imgui"
import imgl "libs/imgui/opengl3"
import imfw "libs/imgui/glfw"

import "vendor:glfw"
import gl "vendor:OpenGL"

vec3 :: glsl.vec3
vec4 :: glsl.vec4

texIndex :: distinct int

mode :: enum {
    game,
    menu,

    block_creator
}

cur_mode: mode = mode.game


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

in_focus: bool = false
focusing: bool


//// GLOBALS
delta: f64

tex_size: f32 = 8


//// TEXTURES
texture :: struct #align(16) {
    layerSI: i32,
    layers: i32,

    _pad0: i32,
    _pad1: i32
}

blendMode :: enum {
    add,
    sub,
    mul,
    div,
    mix
}

texLayer :: struct #align(16) { 
    col_dark:  vec4,
    col_light: vec4,
    contrast:  f32,
    frequency: f32,
    fractal:   i32,
    octaves:   i32,
    blend:     i32,
    noise:     i32,
    seed_off:  i32
}

textures:  [dynamic]texture
texlayers: [dynamic]texLayer

grass: texIndex


main :: proc() {
    window_handle := init_glfw_and_window()
    if window_handle == nil { fmt.eprintln("failed to init glfw!"); return }

    defer glfw.Terminate()
    defer glfw.DestroyWindow(window_handle)
    defer im.DestroyContext()
    defer imfw.Shutdown()
    defer imgl.Shutdown()

    shad_prog, succ := load_shaders()
    if !succ { fmt.eprintln("failed to load shaders!"); return }

    defer gl.DeleteProgram(shad_prog)

    VAO, SSBO, SSBO_VERTS     := gen_buffers()
    SSBO_2, SSBO_VERTS_2 := gen_buffers_b()

    defer delete_dynamic_array(SSBO_VERTS)
    defer delete_dynamic_array(SSBO_VERTS_2)

    enable_gl()

    init_textures()

    pv_loc := gl.GetUniformLocation(shad_prog, "projview")
    ts_loc := gl.GetUniformLocation(shad_prog, "texSize")
    cp_loc := gl.GetUniformLocation(shad_prog, "camPos")
    md_loc := gl.GetUniformLocation(shad_prog, "model")
    bi_loc := gl.GetUniformLocation(shad_prog, "bind")
    sd_loc := gl.GetUniformLocation(shad_prog, "seed")
    tx_loc := gl.GetUniformLocation(shad_prog, "textures")

    TSSBO: u32
    LSSBO: u32

    gl.CreateBuffers(1, &TSSBO)
    gl.CreateBuffers(1, &LSSBO)

    texs := textures[:]
    lays := texlayers[:]

    gl.NamedBufferStorage(TSSBO, len(textures) * size_of(texture), &texs[0], gl.DYNAMIC_STORAGE_BIT)
    gl.NamedBufferStorage(LSSBO, len(texlayers) * size_of(texLayer), &lays[0], gl.DYNAMIC_STORAGE_BIT)

    identity_mat := glsl.identity(glsl.mat4)

    lastTime: f64;
    for !glfw.WindowShouldClose(window_handle) {
        time := glfw.GetTime()
        delta = get_delta(&lastTime)

        proc_inp(window_handle)
        glfw.PollEvents()

        gl.ClearColor(0.2, 0.3, 0.3, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        imgl.NewFrame()
        imfw.NewFrame()
        im.NewFrame()

        gl.UseProgram(shad_prog)
        gl.BindVertexArray(VAO)

        gl.Uniform1f(ts_loc, tex_size)

        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 1, TSSBO)
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 2, LSSBO)

        #partial switch cur_mode {
            case mode.game:
                gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, SSBO)                                
                gl.Uniform3f(cp_loc, camera_pos.x, camera_pos.y, camera_pos.z)
                
                view     := glsl.mat4LookAt(camera_pos, camera_pos + camera_front, camera_up)
                proj     := glsl.mat4PerspectiveInfinite(linalg.to_radians(f32(90)), f32(win_width)/f32(win_height), 0.1)
                projview := proj * view

                gl.UniformMatrix4fv(md_loc, 1, gl.FALSE, mat4_to_gl(&identity_mat))
                gl.UniformMatrix4fv(pv_loc, 1, gl.FALSE, mat4_to_gl(&projview))

                gl.DrawArrays(gl.TRIANGLES, 0, cast(i32)len(SSBO_VERTS) * 6)

            case mode.block_creator:
                gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, SSBO_2)
                gl.Uniform3f(cp_loc, 0,0,0)

                model    := glsl.mat4Rotate(vec3{1,0,0}, linalg.to_radians(f32(45))) * glsl.mat4Rotate(vec3{0,1,0}, linalg.to_radians(f32(45))) * glsl.mat4Translate(vec3{-0.5,-0.5,-0.5})             
                view     := glsl.mat4LookAt(vec3{0,0,2}, vec3{0,0,0}, vec3{0,1,0})
                proj     := glsl.mat4PerspectiveInfinite(linalg.to_radians(f32(90)), f32(win_width)/f32(win_height), 0.1)
                projview := proj * view

                gl.UniformMatrix4fv(md_loc, 1, gl.FALSE, mat4_to_gl(&model))
                gl.UniformMatrix4fv(pv_loc, 1, gl.FALSE, mat4_to_gl(&projview))

                gl.NamedBufferSubData(TSSBO, 0, len(textures) * size_of(texture), &textures[0])
                gl.NamedBufferSubData(LSSBO, 0, len(texlayers) * size_of(texLayer), &texlayers[0])

                gl.DrawArrays(gl.TRIANGLES, 0, cast(i32)len(SSBO_VERTS_2) * 6)

                if im.Begin("CREATOR") {
                    t := &textures[grass]

                    if im.Button("+ layer") {
                        append(&texlayers, texLayer{ 
                            col_dark =  vec4{0,0,0,1},
                            col_light = vec4{1,1,1,1},
                            contrast  = 1,
                            frequency = 2,
                            blend = i32(blendMode.add),
                            noise = i32(fnl.Noise_Type.Open_Simplex_2),
                            fractal = i32(fnl.Fractal_Type.None),
                            octaves = 1,
                            seed_off = 0
                        })
                        t^.layers += 1

                        gl.DeleteBuffers(1, &LSSBO)
                        gl.CreateBuffers(1, &LSSBO)
                        gl.NamedBufferStorage(LSSBO, len(texlayers) * size_of(texLayer), &texlayers[0], gl.DYNAMIC_STORAGE_BIT)
                    }

                    buf: [2]u8

                    for i in t^.layerSI..<(t^.layerSI+t^.layers) {
                        lay := &texlayers[i]

                        if !im.TreeNode(strings.clone_to_cstring(strings.concatenate([]string{ "layer", strconv.append_int(buf[:], i64(i), 10) }))) {
                            continue
                        }

                        if im.TreeNode("main") {
                            noises := [6]cstring{ "opensimplex2", "opensimplex2 smoothed", "cellular (voronoi)", "perlin", "value smoothed", "value" }
                            im.ComboChar("type", &lay^.noise, raw_data(noises[:]), 6)

                            im.InputInt("seed offset", &lay^.seed_off)

                            im.InputFloat("freq", &lay^.frequency, 0.05)

                            if (i >= t^.layerSI+t^.layers-2) || (i < t^.layerSI+t^.layers-2 && texlayers[i+1].blend != i32(blendMode.mix)) {
                                blends := [5]cstring{ "add", "sub", "mul", "div", "mix" }
                                im.ComboChar("blend", &lay^.blend, raw_data(blends[:]), 5)
                            }

                            if im.TreeNode("colors") {
                                im.SliderFloat("contrast", &lay^.contrast, 0, 2)

                                lcol := lay^.col_light.rgb
                                dcol := lay^.col_dark.rgb

                                im.ColorPicker3("light", &lcol)
                                im.ColorPicker3("dark",  &dcol)

                                lay^.col_light = vec4{lcol.r,lcol.g,lcol.b,1}
                                lay^.col_dark = vec4{dcol.r,dcol.g,dcol.b,1}

                                im.TreePop()
                            }

                            im.TreePop()
                        }  /// main

                        if im.TreeNode("fractal") {
                            fractals := [4]cstring{ "none", "fbm", "ridged", "pingpong" }
                            im.ComboChar("type", &lay^.fractal, raw_data(fractals[:]), 4)

                            if lay^.fractal != 0 {
                                im.InputInt("octaves", &lay^.octaves)
                            }

                            im.TreePop()
                        }  /// fractal

                        im.TreePop()
                        
                    }

                }   im.End()
        }

        if im.Begin("MAIN") {
            buf: [6]u8
            im.Text(strings.clone_to_cstring(strings.concatenate([]string{ strconv.append_int(buf[:], i64(1/delta), 10), " FPS" })))

            #partial switch cur_mode {
                case mode.game:
                    if im.Button("block creator") {
                        cur_mode = mode.block_creator
                    }
                case mode.block_creator:
                    if im.Button("game") {
                        cur_mode = mode.game
                    }
            }

            tres := i32(tex_size)
            im.SliderInt("tex resolution", &tres, 0, 64, "%d")
            tex_size = f32(tres)

        }   im.End() 

        im.Render()

        imgl.RenderDrawData(im.GetDrawData())

        glfw.SwapBuffers(window_handle)
    }
}


proc_inp :: proc(window: glfw.WindowHandle) {
    if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS { glfw.SetWindowShouldClose(window, true) }
    
    if in_focus {
        speed: f32 = 4

        camera_right := glsl.normalize(glsl.cross(camera_front, camera_up))

        if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS          { camera_pos -= glsl.cross(camera_right, camera_up) * f32(delta) * speed }
        if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS          { camera_pos += glsl.cross(camera_right, camera_up) * f32(delta) * speed }
        if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS          { camera_pos -= camera_right * f32(delta) * speed }
        if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS          { camera_pos += camera_right * f32(delta) * speed }
        if glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS { camera_pos.y -= f32(delta) * speed }
        if glfw.GetKey(window, glfw.KEY_SPACE) == glfw.PRESS      { camera_pos.y += f32(delta) * speed }

        glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_DISABLED)

        if camera_pitch > 89.9  { camera_pitch = 89.9  }
        if camera_pitch < -89.9 { camera_pitch = -89.9 }

        dir: vec3
        dir.x = math.cos_f32(linalg.to_radians(camera_yaw)) * math.cos_f32(linalg.to_radians(camera_pitch))
        dir.z = math.sin_f32(linalg.to_radians(camera_yaw)) * math.cos_f32(linalg.to_radians(camera_pitch))
        dir.y = math.sin_f32(linalg.to_radians(camera_pitch))
        camera_front = glsl.normalize(dir)
    } else {
        glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_NORMAL)

        first_mouse = true
    }

    if glfw.GetKey(window, glfw.KEY_TAB) == glfw.PRESS { 
        if !focusing {
            in_focus = !in_focus 
        }   focusing = true
    } else { focusing = false }
}


////////////// WORLD GENERATION

        gen_chunk :: proc(SV: ^[dynamic]i32, i,j,k: int) {
            noise := fnl.create_state(0)
            noise.frequency = 0.05
            noise.noise_type = fnl.Noise_Type.Perlin
            noise.fractal_type = fnl.Fractal_Type.FBM
            noise.octaves = 2

            dat:= new([32][32][32]bool)

            for x in 0..<32 {
                for z in 0..<32 {
                    for y in 0..<32 {
                        if y > int(f32(fnl.get_noise_2d(noise, f32(x + i*32),f32(z + k*32)) * 12 + 16)) { continue }

                        dat[x][y][z] = true
                    }
                }
            }

            for x: i32; x < 32; x += 1 {
                for y: i32; y < 32; y += 1 {
                    for z: i32; z < 32; z += 1 {
                        if !dat[x][y][z] { continue }

                        if x > 0 && !dat[x-1][y][z] {
                            add_face(SV, x,y,z, 2)
                        } if x < 31 && !dat[x+1][y][z] {
                            add_face(SV, x,y,z, 3)
                        }

                        if y > 0 && !dat[x][y-1][z] {
                            add_face(SV, x,y,z, 5)
                        } if y < 31 && !dat[x][y+1][z] {
                            add_face(SV, x,y,z, 4)
                        }

                        if z > 0 && !dat[x][y][z-1] {
                            add_face(SV, x,y,z, 1)
                        } if z < 31 && !dat[x][y][z+1] {
                            add_face(SV, x,y,z, 0)
                        }
                    }
                }
            }
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

            sens :f32: 0.1
            xoff *= sens
            yoff *= sens

            camera_yaw   += xoff
            camera_pitch += yoff
        }

        add_cube :: proc(SSBO_VERTS: ^[dynamic]i32, x,y,z: i32) {
            for i in 0..<6 {
                vtx: i32 = (x | y << 5 | z << 10 | i32(i) << 15)
                append(SSBO_VERTS, vtx)
            }
        }

        // normal: 
        // 0 -> front
        // 1 -> back
        // 2 -> left
        // 3 -> right
        // 4 -> top
        // 5 -> bottom
        add_face :: proc(SSBO_VERTS: ^[dynamic]i32, x,y,z: i32, normal: u8) {
            vtx: i32 = (x | y << 5 | z << 10 | i32(normal) << 15)
            append(SSBO_VERTS, vtx)
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

    if window_handle == nil {
        fmt.eprint("failed to create window!")
        return nil
    }

    glfw.MakeContextCurrent(window_handle)
    glfw.SwapInterval(0)
    glfw.SetFramebufferSizeCallback(window_handle, fbcb_size)
    glfw.SetCursorPosCallback(window_handle, cpcb)

    gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, proc(p: rawptr, name: cstring) {
        (^rawptr)(p)^ = glfw.GetProcAddress(name)
    })

    im.CHECKVERSION()
    im.CreateContext()
    //io := im.GetIO()

    im.StyleColorsDark()

    imfw.InitForOpenGL(window_handle, true)
    imgl.Init("#version 450")

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

gen_buffers :: proc() -> (u32, u32, [dynamic]i32) {
    VAO: u32
    gl.GenVertexArrays(1, &VAO)
    gl.BindVertexArray(VAO)

    SSBO: u32
    gl.CreateBuffers(1, &SSBO)

    SSBO_VERTS: [dynamic]i32

    gen_chunk(&SSBO_VERTS, 0,0,0)

    gl.NamedBufferStorage(SSBO, len(SSBO_VERTS) * size_of(i32), &SSBO_VERTS[0], 0)

    return VAO, SSBO, SSBO_VERTS
}

gen_buffers_b :: proc() -> (u32, [dynamic]i32) {
    VAO: u32
    gl.GenVertexArrays(1, &VAO)
    gl.BindVertexArray(VAO)

    SSBO: u32
    gl.CreateBuffers(1, &SSBO)

    SSBO_VERTS: [dynamic]i32

    add_cube(&SSBO_VERTS, 0,0,0)

    gl.NamedBufferStorage(SSBO, len(SSBO_VERTS) * size_of(i32), &SSBO_VERTS[0], 0)

    return SSBO, SSBO_VERTS
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

init_textures :: proc() {
    grass = texIndex(0)
    
    append(&textures, texture { layerSI = 0, layers = 3 })

    append(&texlayers, texLayer {
        noise = i32(fnl.Noise_Type.Open_Simplex_2S),
        seed_off = 0,
        frequency = 2.5,
        blend = i32(blendMode.add),
        contrast = 1.13,
        col_light = vec4{164,191,71,256} / 256.0,
        col_dark = vec4{49,105,61,256} / 256.0,
        fractal = i32(fnl.Fractal_Type.FBM),
        octaves = 3
    })

    append(&texlayers, texLayer {
        noise = i32(fnl.Noise_Type.Open_Simplex_2S),
        seed_off = 1,
        frequency = 0.1,
        blend = i32(blendMode.sub),
        contrast = 1.994,
        col_light = vec4{12,12,12,256} / 256.0,
        col_dark = vec4{0,0,0,256} / 256.0,
        fractal = i32(fnl.Fractal_Type.FBM),
        octaves = 4
    })

    append(&texlayers, texLayer {
        noise = i32(fnl.Noise_Type.Open_Simplex_2S),
        seed_off = 2,
        frequency = 0.1,
        blend = i32(blendMode.add),
        contrast = 1.913,
        col_light = vec4{8,8,8,256} / 256.0,
        col_dark = vec4{0,0,0,256} / 256.0,
        fractal = i32(fnl.Fractal_Type.FBM),
        octaves = 2
    })
}
