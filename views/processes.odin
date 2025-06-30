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

                {
                    buf: [64]u8
                    switch pid in process.systemProcessId {
                    case nil:
                        text := "[N/A]"
                        mem.copy(raw_data(buf[:]), raw_data(text), len(text))
                    case dap.number:
                        strconv.itoa(buf[:], int(pid))
                    }

                    im.TableNextColumn()
                    im.Text(cstring(raw_data(buf[:])))
                }

                im.TableNextColumn()
                im.Text(cstring(raw_data(process.name)))

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
