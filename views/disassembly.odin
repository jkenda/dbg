package views

import im "../odin-imgui"
import "../dap"

show_dasm_view :: proc(view_data: Runtime_View_Data) {
    #partial switch d in view_data.data {
    case []dap.DisassembledInstruction:
        if (im.BeginTable("Threads", 2, im.TableFlags_Resizable)) {
            im.TableSetupColumn("Address"    , {.WidthStretch})
            im.TableSetupColumn("Instruction", {.WidthStretch})

            im.TableHeadersRow()

            for line in d {
                im.TableNextRow()

                im.TableNextColumn()
                im.Text(cstring(raw_data(line.address)))

                im.TableNextColumn()
                im.Text(cstring(raw_data(line.instruction)))
            }

            im.EndTable()
        }

    case nil:
        im.Text("[N/A]")
    case:
        unreachable()
    }
}
