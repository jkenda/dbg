package views

import im "../odin-imgui"

show_output_view :: proc(data: Global_Data) {
    im.TextWrapped(cstring(raw_data(runtime_data.output[:])))
}
