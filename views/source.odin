package views

import im "../odin-imgui"

import "core:strings"

show_source_view :: proc(data: Global_Data, view_data: View_Data) {
    switch s in view_data.string {
    case nil:
        im.Text("[Source not available]")
    case string:
        im.TextWrapped(strings.unsafe_string_to_cstring(s))
    }
}
