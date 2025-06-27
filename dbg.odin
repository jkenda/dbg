package dbg

import im "odin-imgui"
import "odin-imgui/imgui_impl_sdl2"
import "odin-imgui/imgui_impl_opengl3"

import sdl "vendor:sdl2"
import gl "vendor:OpenGL"

import "core:strings"
import "core:fmt"
import "core:log"

import "views"
import "dap"

APPLICATION_NAME :: "Debugger"

main :: proc() {
    when ODIN_DEBUG {
        context.logger = log.create_console_logger(.Debug)
    }
    else {
        context.logger = log.create_console_logger(.Info)
    }

    window := init_SDL()
    defer sdl.Quit()
    defer sdl.DestroyWindow(window)

    gl_ctx := init_openGL(window)
    defer sdl.GL_DeleteContext(gl_ctx)

    io := init_ImGui(window, gl_ctx)
    defer im.DestroyContext()
    defer imgui_impl_sdl2.Shutdown()
    defer imgui_impl_opengl3.Shutdown()

    views.init_data()
    defer views.delete_data()

    dap_connection := init_debugger()
    defer dap.disconnect(&dap_connection)

    running := true
    for running {
        handle_DAP_events(&dap_connection)
        handle_SDL_events(&running)

        { // NewFrame
            imgui_impl_opengl3.NewFrame()
            imgui_impl_sdl2.NewFrame()
            im.NewFrame()
        }

        { // show main window
            show_main_window(window)
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

    { // save .ini file with custom data added ()
        io.WantSaveIniSettings = true
        ini_len: uint
        ini_data := im.SaveIniSettingsToMemory(&ini_len)
        io.WantSaveIniSettings = false

        save_ini_with_extension(ini_data, ini_len)
    }
}

init_debugger :: proc() -> dap.Connection {
    // start DAP connection
    conn, err := dap.connect()
    assert(err == nil, strings.clone_from(sdl.GetError()))

    { // initialize debugger
        req : dap.Protocol_Message = dap.Request{
            type = .request,
            command = .initialize,
            arguments = dap.Arguments_Initialize{
                clientID = "dbg",
                adapterID = "gdb",
                linesStartAt1 = true,
                columnsStartAt1 = true,
            }
        }
        dap.write_message(&conn.(dap.Connection_Stdio), &req)

        // wait for 'initialized' response
        for !debugger_initialized {
            handle_DAP_events(&conn)
        }

        log.info("debugger initialized")
    }

    return conn
}

init_SDL :: proc() -> ^sdl.Window {
    // prefer Wayland
    if sdl.GetPlatform() == "Linux" {
        sdl.SetHint("SDL_VIDEODRIVER", "wayland,x11")
    }

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

init_openGL :: proc(window: ^sdl.Window) -> sdl.GLContext {
    gl_ctx := sdl.GL_CreateContext(window)
    gl.load_up_to(3, 2, proc(p: rawptr, name: cstring) {
        (cast(^rawptr)p)^ = sdl.GL_GetProcAddress(name)
    })

    sdl.GL_MakeCurrent(window, gl_ctx)
    sdl.GL_SetSwapInterval(1) // vsync

    return gl_ctx
}

init_ImGui :: proc(window: ^sdl.Window, gl_ctx: sdl.GLContext) -> ^im.IO {
    im.CHECKVERSION()
    im.CreateContext()

    { // load .ini file but strip custom data
        ini_string, ini_len := read_and_strip_ini_file()
        im.LoadIniSettingsFromMemory(ini_string, ini_len)
    }

    io := im.GetIO()
    {
        io.ConfigFlags += {
            .NavEnableKeyboard,
            .DockingEnable,
            .ViewportsEnable,
        }

        io.IniFilename = nil
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
    imgui_impl_opengl3.Init(nil)

    return io
}

handle_DAP_events :: proc(connection: ^dap.Connection) {
    for {
        msg, err := dap.read_message(&connection.(dap.Connection_Stdio), allocator = context.temp_allocator)
        if err == .Empty_Input do break

        switch err {
        case nil:
            switch m in msg {
            case dap.Request:
                log.warn("unexpected - got request:", m)
            case dap.Response:
                switch m.command {
                case .cancel, .disconnect, .terminate:
                    unreachable()
                case .initialize:
                    debugger_capabilities = m.body.(dap.Body_Initialized)
                    debugger_initialized = true
                case:
                    log.warn("response handling not implemented:", m)
                }
            case dap.Event:
                switch m.event {
                case .output:
                    log.debug("output:", strings.trim_space(m.body.(dap.Body_OutputEvent).output))
                    append(&views.runtime_data.output, m.body.(dap.Body_OutputEvent).output)
                case:
                    log.warn("event handling not implemented:", m)
                }
            }
        case:
            log.error(err)
        }
    }

    free_all(context.temp_allocator)
}

handle_SDL_events :: proc(running: ^bool) {
    e: sdl.Event
    for sdl.PollEvent(&e) {
        imgui_impl_sdl2.ProcessEvent(&e)

        #partial switch e.type {
        case .QUIT: running^ = false
        }
    }
}

ROOT_DOCK_SPACE :: "RootDockSpace"
show_main_window :: proc(window: ^sdl.Window) {
    x, y: i32
    sdl.GetWindowPosition(window, &x, &y)

    im.SetNextWindowPos({f32(x), f32(y)})
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
    im.DockSpace(dockspace_ID)

    { // MenuBar
        if (im.BeginMenuBar()) {
            if (im.BeginMenu("File")) {
                im.MenuItem("New")
                im.MenuItem("Open")

                im.EndMenu()
            }
            if (im.BeginMenu("View")) {
                for view_type in views.View_Type {
                    type_name := views.View_Names[view_type]
                    if view_type in views.singletons {
                        resize(&views.data[view_type], 1)
                        im.MenuItemBoolPtr(type_name, nil, &views.data[view_type][0].show)
                    }
                    else {
                        if (im.BeginMenu(type_name)) {
                            for &view in views.data[view_type] {
                                view_name := strings.unsafe_string_to_cstring(view.name)
                                im.MenuItemBoolPtr(view_name, nil, &view.show)
                            }

                            if (im.MenuItem("Add", nil)) {
                                append(&views.data[view_type], views.View_Data{
                                    name = fmt.aprintf("{} #{}", type_name, len(views.data[view_type])),
                                    show = true,
                                })
                            }
                            im.EndMenu()
                        }
                    }
                }

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
                    im.MenuItemBoolPtr("Demo Window", nil, &show_demo_window)
                    im.EndMenu()
                }
            }

            im.EndMenuBar()
        }

        { // show views
            for view_type in views.View_Type {
                if view_type in views.singletons {
                    resize(&views.data[view_type], 1)
                    views.show_view(view_type, &views.data[view_type][0])
                }
                else {
                    for &view_data in views.data[view_type] {
                        views.show_view(view_type, &view_data)
                    }
                }

            }

            when ODIN_DEBUG {
                if show_demo_window {
                    im.ShowDemoWindow()
                }
            }
        }

    }
    im.End()
}

debugger_capabilities: dap.Capabilities
debugger_initialized := false

when ODIN_DEBUG {
    show_demo_window: bool
}
