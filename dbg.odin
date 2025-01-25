package dbg

import im "odin-imgui"
import "odin-imgui/imgui_impl_sdl2"
import "odin-imgui/imgui_impl_opengl3"

import sdl "vendor:sdl2"
import gl "vendor:OpenGL"

APPLICATION_NAME :: "Debugger"

main :: proc() {
    // prefer Wayland
    sdl.SetHint("SDL_VIDEODRIVER", "wayland,x11")

    assert(sdl.Init(sdl.INIT_EVERYTHING) == 0)
    defer sdl.Quit()

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
    assert(window != nil)
    defer sdl.DestroyWindow(window)

    gl_ctx := sdl.GL_CreateContext(window)
    defer sdl.GL_DeleteContext(gl_ctx)

    sdl.GL_MakeCurrent(window, gl_ctx)
    sdl.GL_SetSwapInterval(1) // vsync

    gl.load_up_to(3, 2, proc(p: rawptr, name: cstring) {
        (cast(^rawptr)p)^ = sdl.GL_GetProcAddress(name)
    })

    im.CHECKVERSION()
    im.CreateContext()
    defer im.DestroyContext()

    io := im.GetIO()
    {
        io.ConfigFlags += {
            .NavEnableKeyboard,
            .DockingEnable,
            .ViewportsEnable,
        }

        io.IniFilename = "dbg-layout.ini";
    }
    {
        style := im.GetStyle()
        style.WindowRounding = 0
        style.Colors[im.Col.WindowBg].w = 1
        style.FrameBorderSize = 1
    }

    im.FontAtlas_AddFontFromFileTTF(io.Fonts, "fonts/NotoSans-Regular.ttf", 18)

    im.StyleColorsClassic()

    imgui_impl_sdl2.InitForOpenGL(window, gl_ctx)
    defer imgui_impl_sdl2.Shutdown()
    imgui_impl_opengl3.Init(nil)
    defer imgui_impl_opengl3.Shutdown()

    running := true
    for running {
        e: sdl.Event
        for sdl.PollEvent(&e) {
            imgui_impl_sdl2.ProcessEvent(&e)

            #partial switch e.type {
            case .QUIT: running = false
            }
        }

        { // NewFrame
            imgui_impl_opengl3.NewFrame()
            imgui_impl_sdl2.NewFrame()
            im.NewFrame()
        }

        { // show main window
            show_main_window()
        }

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
}

ROOT_DOCK_SPACE :: "RootDockSpace"
show_main_window :: proc() {
    im.SetNextWindowPos({0, 0})
    im.SetNextWindowSize(im.GetIO().DisplaySize)
    im.Begin(ROOT_DOCK_SPACE, nil, {
        .NoTitleBar,
        .NoCollapse,
        .NoResize,
        .NoMove,
        .NoBringToFrontOnFocus,
        .NoNavFocus,
        .NoBackground,
        .NoDocking,

        .MenuBar,
    })
    dockspace_ID := im.GetID(ROOT_DOCK_SPACE)
    im.DockSpace(dockspace_ID, {0, 0}, nil)

    { // MenuBar
        if (im.BeginMenuBar()) {
            if (im.BeginMenu("File")) {
                im.MenuItem("New")
                im.MenuItem("Open")

                im.EndMenu()
            }
            if (im.BeginMenu("View")) {
                im.MenuItemBoolPtr(STR_MEMORY, nil, &show_views.memory)
                im.MenuItemBoolPtr(STR_WATCH, nil, &show_views.watch)
                im.MenuItemBoolPtr(STR_DASM, nil, &show_views.dasm)

                im.EndMenu()
            }

            im.Separator()
            im.MenuItem("Run", "F5")
            im.MenuItem("Reset", "SHIFT+F5")
            im.MenuItem("Pause", "F6")
            im.MenuItem("Step Over", "F10")
            im.MenuItem("Step Into", "F11")
            im.MenuItem("Step Out", "SHIFT+F11")
            im.Separator()

            when ODIN_DEBUG {
                if (im.BeginMenu("_Debug_")) {
                    im.MenuItemBoolPtr("Demo Window", nil, &show_views.demo_window)

                    im.EndMenu()
                }
            }

            im.EndMenuBar()
        }

        { // show views
            show_demo_window(&show_views.demo_window)

            show_memory_view(&show_views.memory)
            show_watch_view(&show_views.watch)
            show_dasm_view(&show_views.dasm)
        }

    }
    im.End()
}

Show_Views :: struct {
    demo_window: bool,
    source, dasm, watch, memory: bool,
}
show_views: Show_Views

DEMO :: "Demo Window"
show_demo_window :: proc(show: ^bool) {
    if ODIN_DEBUG && show^ {
        im.ShowDemoWindow(show)
    }
}

STR_MEMORY :: "Memory"
show_memory_view :: proc(show: ^bool) {
    if !show^ { return }

    im.Begin(STR_MEMORY, show)
    im.End()
}

STR_WATCH :: "Watch"
show_watch_view :: proc(show: ^bool) {
    if !show^ { return }

    im.Begin(STR_WATCH, show)
    im.End()
}

STR_DASM :: "Disassembly"
show_dasm_view :: proc(show: ^bool) {
    if !show^ { return }

    im.Begin(STR_DASM, show)
    im.End()
}
