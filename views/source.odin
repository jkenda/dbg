package views

import im "../odin-imgui"
import "../dap"

import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:log"

show_source_view :: proc(view_data: ^Runtime_View_Data) {
    #partial switch s in view_data.data {
    case string:
        stack_frames := runtime_data.view_data[.Stack_Trace][0].data.([]dap.StackFrame)
        str := s

        if (im.BeginTable("Source", 2, im.TableFlags_SizingStretchProp)) {
            im.TableSetupColumn("Number", {.WidthFixed})
            im.TableSetupColumn("Line"  , {.WidthFixed})

            lineno := 1
            for line in strings.split_lines_iterator(&str) {
                im.TableNextRow()

                if int(stack_frames[0].line) == lineno {
                    im.TableSetBgColor(.RowBg1, im.GetColorU32(.Header))

                    if view_data.first {
                        im.SetScrollHereY(0.5);
                        view_data.first = false
                    }
                }

                {
                    buf: [64]u8
                    strconv.itoa(buf[:], lineno)

                    im.TableNextColumn()
                    im.Text(cstring(raw_data(buf[:])))
                }

                im.TableNextColumn()
                im.Text(strings.clone_to_cstring(line, context.temp_allocator))

                lineno += 1
            }

            im.EndTable()
        }

    case nil:
        im.Text("[Source not available]")
    case:
        unreachable()
    }
}
