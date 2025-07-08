package views

import im "../odin-imgui"
import "../dap"

import "core:strconv"
import "core:mem"

show_processes_view :: proc(view_data: ^Runtime_View_Data) {
    if len(runtime_data.processes.data) > 0 {
        if (im.BeginTable("Processes", 3, im.TableFlags_Resizable)) {
            im.TableSetupColumn("PID"  , {.WidthStretch})
            im.TableSetupColumn("Name" , {.WidthStretch})
            im.TableSetupColumn("Local", {.WidthStretch})

            im.TableHeadersRow()

            for process in runtime_data.processes.data {
                im.TableNextRow()

                im.TableNextColumn()
                switch pid in process.systemProcessId {
                case nil:
                    im.Text("[N/A]")
                case dap.number:
                    im.Text("%d", pid)
                }


                im.TableNextColumn()
                im.Text("%s", process.name)

                im.TableNextColumn()
                switch is_local in process.isLocalProcess {
                case nil:
                    im.Text("[N/A]")
                case bool:
                    im.Text(is_local ? "true" : "false")
                }
            }

            im.EndTable()
        }
    }
    else {
        im.Text("[N/A]")
    }
}
