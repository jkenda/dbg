package views

import im "../odin-imgui"
import "core:strconv"

show_stack_view :: proc(data: Global_Data) {
    if (im.BeginTable("Stack Trace", 3, im.TableFlags_Resizable)) {
        im.TableSetupColumn("Address" , {.WidthStretch})
        im.TableSetupColumn("Function", {.WidthStretch})
        im.TableSetupColumn("Line"    , {.WidthStretch})

        im.TableHeadersRow()

        for frame in data.stack_frames {
            im.TableNextRow()

            im.TableNextColumn()
            im.Text(cstring(raw_data(frame.instructionPointerReference.? or_else "N/A")))

            im.TableNextColumn()
            im.Text(cstring(raw_data(frame.name)))

            {
                buf: [64]u8
                strconv.itoa(buf[:], int(frame.line))

                im.TableNextColumn()
                im.Text(cstring(raw_data(buf[:])))
            }
        }

        im.EndTable()
    }
}
