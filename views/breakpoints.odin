package views

import im "../odin-imgui"
import "../dap"

import "core:strings"

show_breakpoints_view :: proc(view_data: ^Runtime_View_Data) {
    #partial switch d in view_data.data {
    case Breakpoints:
        if (im.BeginTable("Threads", 3, im.TableFlags_Resizable)) {
            im.TableSetupColumn("Address", {.WidthStretch})
            im.TableSetupColumn("Line"   , {.WidthStretch})
            im.TableSetupColumn("Column" , {.WidthStretch})

            im.TableHeadersRow()

            for id, bp in d.line_breakpoints {
                im.TableNextRow()

                im.TableNextColumn()
                im.Text(strings.unsafe_string_to_cstring(bp.data.instructionReference.? or_else "[N/A]"))

                im.TableNextColumn()
                switch line in bp.data.line {
                case nil:
                    im.Text("[N/A]")
                case dap.number:
                    im.Text("%s", line)
                }

                im.TableNextColumn()
                switch column in bp.data.column {
                case nil:
                    im.Text("[N/A]")
                case dap.number:
                    im.Text("%s", column)
                }
            }

            im.EndTable()
        }

    case nil:
        im.Text("[N/A]")
    case:
        unreachable()
    }
}
