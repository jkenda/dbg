package dbg

import im "odin-imgui"

import "platform"

import vmem "core:mem/virtual"
import "core:path/filepath"
import "core:strings"
import "core:slice"
import "core:time"
import "core:fmt"
import "core:log"
import "core:os"
import "core:thread"
import "core:sync"

import "views"
import "dap"

main :: proc() {
    when ODIN_DEBUG {
        context.logger = log.create_console_logger(.Debug)
    }
    else {
        context.logger = log.create_console_logger(.Info)
    }

    log.info("initializing ImGui")
    io := init_ImGui()

    platform_state := platform.init()
    defer platform.destroy(platform_state)

    views.init_data()
    defer views.delete_data()

    @(static) sema: sync.Sema
    @(static) mutex: sync.Mutex

    // run DAP in a background thread
    dap_thread := thread.create_and_start(proc() {
        state = .Initializing
        conn := init_debugger()
        defer dap.disconnect(&conn)

        for state != .Exiting {
            sync.wait_with_timeout(&sema, 2 * time.Millisecond)
            sync.cpu_relax()
            if sync.guard(&mutex) {
                for handle_DAP_messages(&conn) || state_transition(&conn) {}
            }
        }
    })

    // TODO: read debugger output synchronously

    for state != .Exiting {
        if !platform.handle_events(platform_state) {
            state = .Exiting
            break
        }
        if handle_key_presses() {
            sync.post(&sema)
        }

        platform.before_show(&platform_state)
        if sync.guard(&mutex) {
            show_GUI(platform_state)
        }
        platform.after_show(platform_state)

        free_all(context.temp_allocator)
    }

    thread.join(dap_thread)

    { // save .ini file with custom data added
        io.WantSaveIniSettings = true
        ini_len: uint
        ini_data := im.SaveIniSettingsToMemory(&ini_len)
        io.WantSaveIniSettings = false

        save_ini_with_extension(ini_data, ini_len)
    }
}

DAP_once :: proc(conn: ^dap.Connection) {
    return
}

init_debugger :: proc() -> dap.Connection {
    // start DAP connection
    conn, err := dap.connect()

    { // initialize debugger
        dap.write_message(&conn, dap.Arguments_Initialize{
            clientID = "dbg",
            adapterID = "gdb",
            linesStartAt1 = true,
            columnsStartAt1 = true,
        })

        // wait for 'initialized' response
        for !debugger_initialized {
            for handle_DAP_messages(&conn) {}
            sync.cpu_relax()
        }
    }

    return conn
}

init_ImGui :: proc() -> ^im.IO {
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

    exec_path, ok := filepath.abs(os.args[0])
    assert(ok)

    font_path := fmt.caprintf("{}/{}", filepath.dir(exec_path), "fonts/CONSOLA.TTF")
    log.info("loading font from", font_path)

    im.FontAtlas_AddFontFromFileTTF(io.Fonts, font_path, 14)
    im.StyleColorsDark()

    delete(font_path)
    return io
}

handle_DAP_messages :: proc(conn: ^dap.Connection) -> bool {
    for {
        arena: vmem.Arena
        msg, err := dap.read_message(&conn.(dap.Connection_Stdio), allocator = vmem.arena_allocator(&arena))
        if err == .Empty_Input { return false }

        switch err {
        case nil:
            switch m in msg {
            case dap.Request:
                log.warn("unexpected - got request:", m)
                vmem.arena_destroy(&arena)
            case dap.Response:
                switch m.command {
                case "cancel", "disconnect", "terminate":
                    vmem.arena_destroy(&arena)
                case "launch":
                    log.info("program launched")
                    vmem.arena_destroy(&arena)
                case "restart":
                    log.info("program restarting")
                    vmem.arena_destroy(&arena)
                case "initialize":
                    log.info("debugger initialized. ready for 'launch'")
                    debugger_capabilities = m.body.(dap.Body_Initialized)
                    debugger_initialized = true
                    vmem.arena_destroy(&arena)

                case "setBreakpoints":
                    log.warn("response not implemented:", m)
                    vmem.arena_destroy(&arena)
                case "setFunctionBreakpoints":
                    log.debug("setFunctionBreakpoints")

                    if data.executable.stop_on == .StopOnMain {
                        state = .ConfigurationDone
                        vmem.arena_destroy(&arena)
                    }
                    else {
                        body := m.body.(dap.Body_SetFunctionBreakpoints)
                        view_data := &views.runtime_data.view_data[.Breakpoints][0].data
                        if view_data^ == nil {
                            view_data^ = views.Breakpoints{}
                        }

                        bp_data := &view_data.(views.Breakpoints)

                        // delete previous breakpoints from the map
                        for bp in bp_data.function_breakpoints.data {
                            if id, ok := bp.id.?; ok {
                                delete_key(&bp_data.bp_map, id)
                            }
                        }

                        // replace with new function breakpoints
                        vmem.arena_destroy(&bp_data.function_breakpoints.arena)
                        bp_data.function_breakpoints.data = body.breakpoints

                        // add new breakpoints to the map
                        for &bp in bp_data.function_breakpoints.data {
                            if id, ok := bp.id.?; ok {
                                bp_data.bp_map[id] = &bp
                            }
                        }
                    }
                case "configurationDone":
                    log.info("configuration done")
                    vmem.arena_destroy(&arena)
                case "threads":
                    view_data := &views.runtime_data.view_data[.Threads][0]
                    vmem.arena_destroy(&view_data.arena)
                    view_data.arena = arena

                    body := m.body.(dap.Body_Threads)
                    view_data.data = views.Threads{
                        threads = body.threads,
                        selected = 0,
                    }

                    dap.write_message(conn, dap.Arguments_StackTrace{
                        threadId = body.threads[0].id
                    })
                case "stackTrace":
                    view_data := &views.runtime_data.view_data[.Stack_Trace][0]
                    vmem.arena_destroy(&view_data.arena)
                    view_data.arena = arena

                    body := m.body.(dap.Body_StackTrace)
                    view_data.data = body.stackFrames

                    if len(body.stackFrames) == 0 { break }
                    stack_frame := body.stackFrames[0]

                    if source, ok := stack_frame.source.?; ok {
                        {
                            views_data := &views.runtime_data.view_data[.Source]
                            if len(views_data) < 1 {
                                resize(views_data, 1)
                            }
                        }
                        view_data := &views.runtime_data.view_data[.Source][0]
                        view_data.first = true
                        vmem.arena_destroy(&view_data.arena)

                        switch s in source.path {
                        case nil:
                            vmem.arena_destroy(&view_data.arena)
                            view_data.data = nil
                        case string:
                            data, ok := os.read_entire_file(s)
                            if ok {
                                view_data.data = string(data)
                            }
                            else {
                                view_data.data = nil
                            }
                        }
                    }

                    if stack_instr, ok := stack_frame.instructionPointerReference.?; ok {
                        dasm_data := &views.runtime_data.view_data[.Disassembly][0]
                        dasm_data.first = true

                        contains_addr := false
                        if dasm_data.data != nil {
                            for dasm_instr in dasm_data.data.([]dap.DisassembledInstruction) {
                                if stack_instr != dasm_instr.address { continue }

                                contains_addr = true
                                break
                            }
                        }

                        if !contains_addr {
                            dap.write_message(conn, dap.Arguments_Disassemble{
                                memoryReference = stack_frame.instructionPointerReference.?,
                                instructionOffset = -4,
                                instructionCount = 100,
                                resolveSymbols = true,
                            })
                        }
                    }

                case "disassemble":
                    view_data := &views.runtime_data.view_data[.Disassembly][0]
                    vmem.arena_destroy(&view_data.arena)
                    view_data.arena = arena
                    view_data.first = true

                    body := m.body.(dap.Body_Disassemble)
                    view_data.data = body.instructions
                case "next":
                    vmem.arena_destroy(&arena)
                case "stepIn":
                    vmem.arena_destroy(&arena)
                case "stepOut":
                    vmem.arena_destroy(&arena)
                case "continue":
                    state = .Running
                    vmem.arena_destroy(&arena)

                case:
                    log.warn("response not implemented:", m)
                    vmem.arena_destroy(&arena)
                }
            case dap.Event:
                switch m.event {
                case .output:
                    log.debug("output:", strings.trim_space(m.body.(dap.Body_OutputEvent).output))
                    append(&views.runtime_data.output, m.body.(dap.Body_OutputEvent).output)
                    vmem.arena_destroy(&arena)
                case .process:
                    processes := &views.runtime_data.processes
                    body := m.body.(dap.Body_Process)

                    append(&processes.data, body)
                    append(&processes.arenas, arena)
                case .initialized:
                    log.info("program initialized. ready for 'setBreakpoint'")
                    state = .SettingBreakpoints
                    vmem.arena_destroy(&arena)
                case .exited, .terminated:
                    log.info("debugee exited")
                    state = .Initializing
                    vmem.arena_destroy(&arena)
                case .stopped:
                    if data.executable.stop_on == .StopOnMain {
                        log.info("stopped on main")
                        dap.write_message(conn, dap.Arguments_SetFunctionBreakpoints{})
                        data.executable.stop_on = .None
                    }
                    else {
                        log.debug("stopped")
                    }

                    state = .Stopped
                    vmem.arena_destroy(&arena)
                case .continued:
                    log.debug("continued")
                    state = .Running
                case .breakpoint:
                    log.debug("BP event")

                    if data.executable.stop_on == .StopOnMain {
                        continue
                    }

                    body := m.body.(dap.Body_Breakpoint)
                    switch body.reason {
                    case .changed:
                        view_data := views.runtime_data.view_data[.Breakpoints][0].data.(views.Breakpoints)
                        if id, ok := body.breakpoint.id.?; ok {
                            switch v in view_data.bp_map[id] {
                            case ^views.Line_Breakpoint:
                                vmem.arena_destroy(&v.arena)
                                v.data = body.breakpoint
                                v.arena = arena
                            case ^dap.Breakpoint:
                                v^ = body.breakpoint
                            }
                        }

                    case .new:
                        // adding and removing function breakpoints is illegal
                        unimplemented("new breakpoint")
                    case .removed:
                        // adding and removing function breakpoints is illegal
                        unimplemented("removed breakpoint")
                    }

                    vmem.arena_destroy(&arena)

                case ._unknown:
                    log.warn("event not implemented:", m)
                    vmem.arena_destroy(&arena)
                }
            }
        case:
            log.error(err)
            state = .Error
        }
    }

    return true
}

handle_key_presses :: proc() -> bool {
    io := im.GetIO()

         if                im.IsKeyPressed(.F10) || im.IsKeyPressed(.N) do state = .SteppingOver
    else if                im.IsKeyPressed(.F11) || im.IsKeyPressed(.S) do state = .SteppingInto
    else if io.KeyShift && im.IsKeyPressed(.F11) || im.IsKeyPressed(.F) do state = .SteppingOut
    else if                im.IsKeyPressed( .F5) || im.IsKeyPressed(.R) do state = .Starting
    else if io.KeyShift && im.IsKeyPressed( .F5)                        do state = .Resetting

    return state != .Waiting
}

state_transition :: proc(conn: ^dap.Connection) -> bool {
    state_prev := state

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

        dap_args := dap.Arguments_Launch{
            program = program,
            args = args,
            cwd = cwd,
            stopOnEntry = data.executable.stop_on == .StopOnEntry,
        }
        dap.write_message(conn, dap_args)
        launched_with_arguments = dap_args

        state = .Waiting
    case .SettingBreakpoints:
        log.debug("setting breakpoints")

        for bp in data.breakpoints {
            dap.write_message(conn, dap.Arguments_SetBreakpoints(bp))
        }

        if data.executable.stop_on == .StopOnMain {
            // set function BP on main
            dap.write_message(conn, dap.Arguments_SetFunctionBreakpoints{
                breakpoints = {
                    { name = "main" }
                }
            })

            state = .Waiting
        }
        else {
            state = .ConfigurationDone
        }
    case .ConfigurationDone:
        if debugger_capabilities.supportsConfigurationDoneRequest {
            dap.write_message(conn, dap.Arguments_ConfigurationDone{})
        }
        else {
            assert(false, "not supported")
        }
        state = .Waiting
    case .Waiting:
    case .Resetting:
        if debugger_capabilities.supportsRestartRequest {
            dap.write_message(conn, launched_with_arguments)
            state = .Waiting
        }
        else do log.error("This feature isn't supported by the debugger.")
    case .Starting:
        view_data := &views.runtime_data.view_data[.Threads][0].data.(views.Threads)
        thread := view_data.threads[view_data.selected]

        dap.write_message(conn, dap.Arguments_Continue{ threadId = thread.id })
    case .Running:
    case .Stopping:
        if debugger_capabilities.supportsTerminateRequest {
            dap.write_message(conn, dap.Arguments_Terminate{})
            state = .Waiting
        }
        else do log.error("This feature isn't supported by the debugger.")
    case .Stopped:
        dap.write_message(conn, dap.Arguments_Threads{})
        state = .Waiting
    case .SteppingOver:
        view_data := &views.runtime_data.view_data[.Threads][0].data.(views.Threads)
        thread := view_data.threads[view_data.selected]

        dap.write_message(conn, dap.Arguments_Next{ threadId = thread.id })
        state = .Waiting
    case .SteppingInto:
        view_data := &views.runtime_data.view_data[.Threads][0].data.(views.Threads)
        thread := view_data.threads[view_data.selected]

        dap.write_message(conn, dap.Arguments_StepIn{ threadId = thread.id })
        state = .Waiting
    case .SteppingOut:
        view_data := &views.runtime_data.view_data[.Threads][0].data.(views.Threads)
        thread := view_data.threads[view_data.selected]

        dap.write_message(conn, dap.Arguments_StepOut{ threadId = thread.id })
        state = .Waiting
    case .Error:
    case .Exiting:
    }

    return state_prev != state
}

show_GUI :: proc(platform_state: platform.State) {
    if state > State.SettingExecutable {
        show_main_window(platform_state)
    }

    if show_exec_dialog {
        if im.Begin("Executable", &show_exec_dialog, { .NoDocking, }) {
            {
                @(static)
                buf: [256]u8
                cstr_buf := cstring(raw_data(buf[:]))

                if im.InputTextWithHint("Program", "Path to executable", cstr_buf, len(buf)) {
                    data.executable.program = string(cstr_buf)
                }
            }
            {
                @(static)
                buf: [256]u8
                cstr_buf := cstring(raw_data(buf[:]))

                if im.InputTextWithHint("Args", "Command-line arguments", cstr_buf, len(buf)) {
                    data.executable.args = string(cstr_buf)
                }
            }
            {
                @(static)
                buf: [256]u8
                cstr_buf := cstring(raw_data(buf[:]))

                if im.InputTextWithHint("CWD", "Current working directory", cstr_buf, len(buf)) {
                    data.executable.args = string(cstr_buf)
                }
            }

            stop_on := i32(data.executable.stop_on)
            if im.RadioButtonIntPtr("Don't stop"   , &stop_on, i32(views.StopOn.None)) ||
               im.RadioButtonIntPtr("Stop on entry", &stop_on, i32(views.StopOn.StopOnEntry)) ||
               im.RadioButtonIntPtr("Stop on main" , &stop_on, i32(views.StopOn.StopOnMain)) {
                   data.executable.stop_on = views.StopOn(stop_on)
            }

            im.End()
        }
    }
}

ROOT_DOCK_SPACE :: "RootDockSpace"
show_main_window :: proc(platform_state: platform.State) {
    im.SetNextWindowPos(platform.window_pos(platform_state))
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
                        resize(&views.runtime_data.view_data[view_type], 1)
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
            if im.MenuItem("Run", "F5")             do state = .Starting
            if im.MenuItem("Stop", "F6")            do state = .Stopping
            if im.MenuItem("Reset", "SHIFT+F5")     do state = .Resetting
            if im.MenuItem("Step Over", "F10")      do state = .SteppingOver
            if im.MenuItem("Step Into", "F11")      do state = .SteppingInto
            if im.MenuItem("Step Out", "SHIFT+F11") do state = .SteppingOut
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
                views_data := &views.data[view_type]
                rt_views_data := &views.runtime_data.view_data[view_type]

                if view_type in views.singletons {
                    resize(views_data, 1)
                    resize(rt_views_data, 1)

                    views.show_view(view_type, &views_data[0], &rt_views_data[0])
                }
                else {
                    for &v, i in soa_zip(data=views_data[:], rt_data=rt_views_data[:]) {
                        views.show_view(view_type, &v.data, &v.rt_data)
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

    Resetting,
    Starting,
    Running,
    Stopping,
    Stopped,
    SteppingOver,
    SteppingInto,
    SteppingOut,

    Error,
    Exiting,
}
state: State

debugger_capabilities: dap.Capabilities
debugger_initialized := false

data: views.Global_Data

show_exec_dialog: bool
launched_with_arguments: dap.Arguments_Restart

when ODIN_DEBUG {
    show_demo_window: bool
}
