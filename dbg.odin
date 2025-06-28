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

    log.info("initializing SDL")
    window := init_SDL()
    defer sdl.Quit()
    defer sdl.DestroyWindow(window)

    log.info("initializing OpenGL")
    gl_ctx := init_openGL(window)
    defer sdl.GL_DeleteContext(gl_ctx)

    log.info("initializing ImGui")
    io := init_ImGui(window, gl_ctx)
    defer im.DestroyContext()
    defer imgui_impl_sdl2.Shutdown()
    defer imgui_impl_opengl3.Shutdown()

    views.init_data()
    defer views.delete_data()

    state = .Initializing
    dap_connection := init_debugger()
    defer dap.disconnect(&dap_connection)

    for state != .Exiting {
        handle_DAP_messages(&dap_connection)
        handle_SDL_events()

        state_transition(&dap_connection)

        new_frame()
        show_GUI(window)
        render_GUI(window, io^)

        free_all(context.temp_allocator)
    }

    { // save .ini file with custom data added
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
        dap.write_message(&conn.(dap.Connection_Stdio), dap.Arguments_Initialize{
            clientID = "dbg",
            adapterID = "gdb",
            linesStartAt1 = true,
            columnsStartAt1 = true,
        })

        // wait for 'initialized' response
        for !debugger_initialized {
            handle_DAP_messages(&conn)
        }
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
    //{
    //    style := im.GetStyle()
    //    style.WindowRounding = 0
    //    style.Colors[im.Col.WindowBg].w = 1
    //    style.FrameBorderSize = 1
    //}

    im.FontAtlas_AddFontFromFileTTF(io.Fonts, "fonts/NotoSans-Regular.ttf", 18)

    im.StyleColorsDark()

    imgui_impl_sdl2.InitForOpenGL(window, gl_ctx)
    imgui_impl_opengl3.Init(nil)

    return io
}

handle_DAP_messages :: proc(conn: ^dap.Connection) {
    for {
        msg, err := dap.read_message(&conn.(dap.Connection_Stdio), allocator = context.temp_allocator)
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
                case .launch:
                    log.info("program launched")
                case .initialize:
                    log.info("debugger initialized. ready for 'launch'")
                    debugger_capabilities = m.body.(dap.Body_Initialized)
                    debugger_initialized = true

                case .setBreakpoints:
                    log.warn("response not implemented:", m)
                case .configurationDone:
                    log.info("configuration done")
                case .threads:
                    clear(&data.threads)

                    body := m.body.(dap.Body_Threads)
                    for thread in body.threads {
                        append(&data.threads, dap.Thread{
                            name = strings.clone(thread.name),
                            id = thread.id,
                        })
                    }

                    dap.write_message(&conn.(dap.Connection_Stdio), dap.Arguments_StackTrace{
                        threadId = data.threads[0].id
                    })
                case .stackTrace:
                    body := m.body.(dap.Body_StackTrace)
                    log.debug(body)

                    clear(&data.stack_frames)
                    for stack_frame in body.stackFrames {
                        frame := stack_frame
                        frame.name = strings.clone(stack_frame.name)
                        frame.moduleId = strings.clone(stack_frame.moduleId)
                        if frame.instructionPointerReference != nil {
                            frame.instructionPointerReference = strings.clone(frame.instructionPointerReference.?)
                        }
                        append(&data.stack_frames, frame)
                    }

                case ._unknown:
                    log.warn("response not implemented:", m)
                }
            case dap.Event:
                switch m.event {
                case .output:
                    log.debug("output:", strings.trim_space(m.body.(dap.Body_OutputEvent).output))
                    append(&views.runtime_data.output, m.body.(dap.Body_OutputEvent).output)
                case .process:
                    body := m.body.(dap.Body_Process)
                    log.info("new process:", body)

                    append(&data.processes, views.Process{
                        name = strings.clone(body.name),
                        pid = int(body.systemProcessId.? or_else 0),
                        local = body.isLocalProcess.? or_else true,
                        start_method = body.startMethod.? or_else .launch,
                    })
                case .initialized:
                    log.info("program initialized. ready for 'setBreakpoint'")
                    state = .SettingBreakpoints
                case .exited, .terminated:
                    log.info("debugee exited")
                    state = .Initializing
                case .stopped:
                    log.info("stopped:", m.body)
                    state = .Stopped

                case ._unknown:
                    log.warn("event not implemented:", m)
                }
            }
        case:
            log.error(err)
            state = .Error
        }
    }
}

state_transition :: proc(conn: ^dap.Connection) {
    switch state {
    case .Initializing:
        show_exec_dialog = true
        state = .SettingExecutable
    case .SettingExecutable:
        if !show_exec_dialog {
            // dialog has been closed
            state = .Launching
        }
    case .Launching:
        args: []string
        if len(data.executable.args) > 0 {
            args = strings.split(string(data.executable.args[:]), " ", context.temp_allocator)
        }
        program := string(data.executable.program[:])
        cwd := string(data.executable.cwd[:])

        log.info("launching program ", program, "with args", args, "in cwd", cwd)
        dap.write_message(&conn.(dap.Connection_Stdio), dap.Arguments_Launch{
            program = program,
            args = args,
            cwd = cwd,
            stopOnEntry = true,
        })

        state = .Waiting
    case .SettingBreakpoints:
        log.info("setting breakpoints")

        for bp in data.breakpoints {
            dap.write_message(&conn.(dap.Connection_Stdio), dap.Arguments_SetBreakpoints(bp))
        }
        state = .ConfigurationDone
    case .ConfigurationDone:
        if debugger_capabilities.supportsConfigurationDoneRequest {
            dap.write_message(&conn.(dap.Connection_Stdio), dap.Arguments_ConfigurationDone{})
        }
        else {
            assert(false, "not supported")
        }
        state = .Waiting
    case .Waiting:

    case .Running:
    case .Stopped:
        dap.write_message(&conn.(dap.Connection_Stdio), dap.Arguments_Threads{})

        state = .Waiting
    case .Error:
    case .Exiting:
    }
}

handle_SDL_events :: proc() {
    e: sdl.Event
    for sdl.PollEvent(&e) {
        imgui_impl_sdl2.ProcessEvent(&e)

        #partial switch e.type {
        case .QUIT: state = .Exiting
        }
    }
}

new_frame :: proc() {
    imgui_impl_opengl3.NewFrame()
    imgui_impl_sdl2.NewFrame()
    im.NewFrame()
}

show_GUI :: proc(window: ^sdl.Window) {
    show_main_window(window)

    if show_exec_dialog {
        if im.Begin("Executable", &show_exec_dialog, { .NoDocking, }) {
            {
                reserve(&data.executable.program, 2 * len(data.executable.program) + 0x10)
                cstr_buf := cstring(raw_data(data.executable.program))

                im.InputTextWithHint("Program", "Path to executable", cstr_buf, cap(data.executable.program))
                resize(&data.executable.program, len(cstr_buf))
            }
            {
                reserve(&data.executable.args, 2 * len(data.executable.args) + 0x10)
                cstr_buf := cstring(raw_data(data.executable.args))

                im.InputTextWithHint("Args", "Command-line arguments", cstr_buf, cap(data.executable.args))
                resize(&data.executable.args, len(cstr_buf))
            }
            {
                reserve(&data.executable.cwd, 2 * len(data.executable.cwd) + 0x10)
                cstr_buf := cstring(raw_data(data.executable.cwd))

                im.InputTextWithHint("CWD", "Current working directory", cstr_buf, cap(data.executable.cwd))
                resize(&data.executable.cwd, len(cstr_buf))
            }
            im.End()
        }
    }
}

render_GUI :: proc(window: ^sdl.Window, io: im.IO) {
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
                    views.show_view(view_type, &views.data[view_type][0], data)
                }
                else {
                    for &view_data in views.data[view_type] {
                        views.show_view(view_type, &view_data, data)
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

State :: enum {
    Initializing,
    SettingExecutable,
    Launching,
    SettingBreakpoints,
    ConfigurationDone,
    Waiting,

    Running,
    Stopped,

    Error,
    Exiting,
}
state: State

debugger_capabilities: dap.Capabilities
debugger_initialized := false

data: views.Global_Data

show_exec_dialog: bool

when ODIN_DEBUG {
    show_demo_window: bool
}
