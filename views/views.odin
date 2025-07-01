package views

import im "../odin-imgui"
import "../dap"

import "core:strings"
import vmem "core:mem/virtual"

View_Type :: enum {
    Output,
    Source,
    Watch,
    Memory,
    Disassembly,
    Processes,
    Threads,
    Stack_Trace,
    Breakpoints,
}

View_Names: [View_Type]cstring = {
    .Output      = "Output",
    .Source      = "Source",
    .Watch       = "Watch",
    .Memory      = "Memory",
    .Disassembly = "Disassembly",
    .Processes   = "Processes",
    .Threads     = "Threads",
    .Stack_Trace = "Stack Trace",
    .Breakpoints = "Breakpoints",
}

view_show_proc: [View_Type]proc(^Runtime_View_Data) = {
    .Output      = show_output_view,
    .Source      = show_source_view,
    .Watch       = show_watch_view,
    .Memory      = show_memory_view,
    .Disassembly = show_dasm_view,
    .Processes   = show_processes_view,
    .Threads     = show_threads_view,
    .Stack_Trace = show_stack_view,
    .Breakpoints = show_breakpoints_view,
}

View_Data :: struct {
    name: string,
    show: bool,
}

Line_Breakpoint :: struct #packed {
    data: dap.Breakpoint,
    arena: vmem.Arena,
}
Function_Breakpoints :: struct #packed {
    data: []dap.Breakpoint,
    arena: vmem.Arena,
}
Function_Breakpoint :: struct #packed {
    bps: ^Function_Breakpoints,
    bp: ^dap.Breakpoint,
}
Breakpoints :: struct #packed {
    line_breakpoints: map[dap.number]Line_Breakpoint,
    function_breakpoints: Function_Breakpoints,
    bp_map: map[dap.number]union { ^Line_Breakpoint, ^dap.Breakpoint }
}
Runtime_View_Data :: struct #packed {
    arena: vmem.Arena,
    first: bool,

    data: union {
        string,
        []dap.Thread,
        []dap.StackFrame,
        []dap.DisassembledInstruction,
        Breakpoints,
    },
}

runtime_data: struct {
    output: [dynamic]u8,
    processes: struct {
        data: [dynamic]dap.Process,
        arenas: [dynamic]vmem.Arena,
    },

    view_data: [View_Type][dynamic]Runtime_View_Data,
}

singletons: bit_set[View_Type] : { .Output, .Disassembly, .Processes, .Threads, .Stack_Trace, .Breakpoints }
data: [View_Type][dynamic]View_Data

StopOn :: enum u8 {
    None,
    StopOnEntry,
    StopOnMain,
}

Global_Data :: struct {
    executable: struct {
        program: [dynamic]u8,
        args: [dynamic]u8,
        cwd:  [dynamic]u8,
        stop_on: StopOn
    },
    breakpoints: [dynamic]dap.SourceBreakpoints,
}

init_data :: proc() {
    reserve(&runtime_data.output, 0x1000)
}

delete_data :: proc() {
    delete(runtime_data.output)
}

show_view :: proc(view_type: View_Type, view_data: ^View_Data, rt_views_data: ^Runtime_View_Data) {
    if !view_data.show { return }

    name := View_Names[view_type] if view_type in singletons else
            strings.unsafe_string_to_cstring(view_data.name)

    im.Begin(name, &view_data.show)
    {
        show_proc := view_show_proc[view_type]
        if show_proc != nil {
            show_proc(rt_views_data)
        }
    }
    im.End()
}
