package views

import im "../odin-imgui"
import "../dap"

show_dasm_view :: proc(view_data: ^Runtime_View_Data) {
    #partial switch d in view_data.data {
    case []dap.DisassembledInstruction:
        stack_frames := runtime_data.view_data[.Stack_Trace][0].data.([]dap.StackFrame)

        if (im.BeginTable("Threads", 2, im.TableFlags_Resizable)) {
            im.TableSetupColumn("Address"    , {.WidthStretch})
            im.TableSetupColumn("Instruction", {.WidthStretch})

            im.TableHeadersRow()

            for line in d {
                im.TableNextRow()

                if stack_frames[0].instructionPointerReference == line.address {
                    im.TableSetBgColor(.RowBg1, im.GetColorU32(.Header))

                    if view_data.first {
                        im.SetScrollHereY(0.5);
                        view_data.first = false
                    }
                }

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
