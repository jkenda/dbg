package views

import im "../odin-imgui"

import "core:strings"

show_source_view :: proc(view_data: Runtime_View_Data) {
    #partial switch s in view_data.data {
    case string:
        im.TextWrapped(strings.unsafe_string_to_cstring(s))
    case:
        im.Text("[Source not available]")
    }
}
