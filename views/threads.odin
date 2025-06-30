package views

import im "../odin-imgui"
import "../dap"
import "core:strconv"

show_threads_view :: proc(view_data: ^Runtime_View_Data) {
    #partial switch d in view_data.data {
    case []dap.Thread:
        if (im.BeginTable("Threads", 2, im.TableFlags_Resizable)) {
            im.TableSetupColumn("ID"  , {.WidthStretch})
            im.TableSetupColumn("Name", {.WidthStretch})

            im.TableHeadersRow()

            for thread in d {
                im.TableNextRow()

                {
                    buf: [64]u8
                    strconv.itoa(buf[:], int(thread.id))

                    im.TableNextColumn()
                    im.Text(cstring(raw_data(buf[:])))
                }

                im.TableNextColumn()
                im.Text(cstring(raw_data(thread.name)))
            }

            im.EndTable()
        }

    case nil:
        im.Text("[N/A]")
    case:
        unreachable()
    }
}
