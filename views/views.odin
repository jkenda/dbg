package views

import im "../odin-imgui"
import "core:strings"

View_Type :: enum {
    Source,
    Watch,
    Memory,
    Disassembly,
}

View_Names: [View_Type]cstring = {
    .Source      = "Source",
    .Watch       = "Watch",
    .Memory      = "Memory",
    .Disassembly = "Disassembly",
}

view_show_proc: [View_Type]proc(View_Data) = {
    .Source      = show_source_view,
    .Watch       = show_watch_view,
    .Memory      = show_memory_view,
    .Disassembly = show_dasm_view,
}

View_Data :: struct {
    name: string,
    show: bool,
}

singletons: bit_set[View_Type] = {.Disassembly}
data: [View_Type][dynamic]View_Data

show_view :: proc(view_type: View_Type, view_data: ^View_Data) {
    if !view_data.show { return }

    name := View_Names[view_type] if view_type in singletons else
            strings.unsafe_string_to_cstring(view_data.name)

    im.Begin(name, &view_data.show)
    {
        show_proc := view_show_proc[view_type]
        if show_proc != nil {
            show_proc(view_data^)
        }
    }
    im.End()
}
