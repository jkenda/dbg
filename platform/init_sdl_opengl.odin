#+build linux
package platform

import "core:log"

import "odin-imgui/imgui_impl_sdl2"
import "odin-imgui/imgui_impl_opengl3"

init :: proc() {
    log.info("initializing SDL")
    window := init_SDL()

    log.info("initializing OpenGL")
    gl_ctx := init_openGL(window)

    log.info("initializing ImGui")
    io := init_ImGui(window, gl_ctx)
}

destroy() :: proc() {
    imgui_impl_opengl3.Shutdown()
    imgui_impl_sdl2.Shutdown()
    im.DestroyContext()

    sdl.GL_DeleteContext(gl_ctx)

    sdl.DestroyWindow(window)
    sdl.Quit()
}

before_show :: proc() {
    im.NewFrame()
    imgui_impl_opengl3.NewFrame()
    imgui_impl_sdl2.NewFrame()
}

after_show :: proc() {
    io := im.GetIO()

    { // Render
        im.Render()
        gl.Viewport(0, 0, i32(io.DisplaySize.x), i32(io.DisplaySize.y))
        gl.ClearColor(0, 0, 0, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        imgui_impl_opengl3.RenderDrawData(im.GetDrawData())
    }

    if (.ViewportsEnable in io.ConfigFlags) {
        backup_current_window := sdl.GL_GetCurrentWindow()
        backup_current_context := sdl.GL_GetCurrentContext()

        im.UpdatePlatformWindows();
        im.RenderPlatformWindowsDefault();

        sdl.GL_MakeCurrent(backup_current_window, backup_current_context);
    }

    sdl.GL_SwapWindow(window)
}

handle_events :: proc() {
    e: sdl.Event
    for sdl.PollEvent(&e) {
        imgui_impl_sdl2.ProcessEvent(&e)

        #partial switch e.type {
        case .QUIT: return false
        }
    }

    return true
}

@(private)
init_SDL :: proc() -> ^sdl.Window {
    // prefer Wayland
    sdl.SetHint("SDL_VIDEODRIVER", "wayland,x11")

    // don't keep the screen from sleeping
    sdl.EnableScreenSaver()

    assert(sdl.Init(sdl.INIT_EVERYTHING) == 0, strings.clone_from(sdl.GetError()))

    sdl.GL_SetAttribute(.CONTEXT_FLAGS, i32(sdl.GLcontextFlag.FORWARD_COMPATIBLE_FLAG))
    sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GLprofile.CORE))
    sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
    sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 2)

    window := sdl.CreateWindow(
        APPLICATION_NAME,
        sdl.WINDOWPOS_CENTERED,
        sdl.WINDOWPOS_CENTERED,
        960, 720,
        {.OPENGL, .RESIZABLE, .ALLOW_HIGHDPI})
    assert(window != nil, strings.clone_from(sdl.GetError()))

    return window
}

@(private)
init_openGL :: proc(window: ^sdl.Window) -> sdl.GLContext {
    gl_ctx := sdl.GL_CreateContext(window)
    gl.load_up_to(3, 2, proc(p: rawptr, name: cstring) {
        (cast(^rawptr)p)^ = sdl.GL_GetProcAddress(name)
    })

    sdl.GL_MakeCurrent(window, gl_ctx)
    sdl.GL_SetSwapInterval(1) // vsync

    return gl_ctx
}

@(private)
init_ImGui :: proc() {
    imgui_impl_sdl2.InitForOpenGL(window, gl_ctx)
    imgui_impl_opengl3.Init(nil)
}
