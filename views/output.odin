package views

import im "../odin-imgui"
import "core:strings"

show_output_view :: proc(view_data: ^Runtime_View_Data) {
    im.TextWrapped(strings.unsafe_string_to_cstring(string(runtime_data.output[:])))
}
