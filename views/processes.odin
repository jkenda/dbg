package views

import im "../odin-imgui"
import "core:strconv"

show_processes_view :: proc(data: Global_Data, view_data: View_Data) {
    if (im.BeginTable("Processes", 3, im.TableFlags_Resizable)) {
        im.TableSetupColumn("PID"  , {.WidthStretch})
        im.TableSetupColumn("Name" , {.WidthStretch})
        im.TableSetupColumn("Local", {.WidthStretch})

        im.TableHeadersRow()

        for process in data.processes {
            im.TableNextRow()

            {
                buf: [64]u8
                strconv.itoa(buf[:], process.pid)

                im.TableNextColumn()
                im.Text(cstring(raw_data(buf[:])))
            }

            im.TableNextColumn()
            im.Text(cstring(raw_data(process.name)))

            im.TableNextColumn()
            im.Text(process.local ? "true" : "false")
        }

        im.EndTable()
    }
}
