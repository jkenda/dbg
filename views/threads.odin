package views

import im "../odin-imgui"
import "../dap"
import "core:strconv"

show_threads_view :: proc(view_data: ^Runtime_View_Data) {
    #partial switch d in view_data.data {
    case Threads:
        if (im.BeginTable("Threads", 2, im.TableFlags_Resizable)) {
            im.TableSetupColumn("ID"  , {.WidthStretch})
            im.TableSetupColumn("Name", {.WidthStretch})

            im.TableHeadersRow()

            for thread in d.threads {
                im.TableNextRow()

                im.TableNextColumn()
                im.Text("%d", thread.id)

                im.TableNextColumn()
                im.Text("%s", thread.name)
            }

            im.EndTable()
        }

    case nil:
        im.Text("[N/A]")
    case:
        unreachable()
    }
}
