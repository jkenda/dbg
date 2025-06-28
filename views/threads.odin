package views

import im "../odin-imgui"
import "core:strconv"

show_threads_view :: proc(data: Global_Data) {
    if (im.BeginTable("Threads", 3, im.TableFlags_Resizable)) {
        im.TableSetupColumn("ID"  , {.WidthStretch})
        im.TableSetupColumn("Name", {.WidthStretch})

        im.TableHeadersRow()

        for thread in data.threads {
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
}
