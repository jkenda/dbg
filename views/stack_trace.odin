package views

import im "../odin-imgui"
import "../dap"

import "core:fmt"
import "core:log"

show_stack_view :: proc(view_data: Runtime_View_Data) {
    #partial switch d in view_data.data {
    case []dap.StackFrame:
        if (im.BeginTable("Stack Trace", 3, im.TableFlags_Resizable)) {
            im.TableSetupColumn("Address" , {.WidthStretch})
            im.TableSetupColumn("Function", {.WidthStretch})
            im.TableSetupColumn("Location", {.WidthStretch})

            im.TableHeadersRow()

            for frame in d {
                im.TableNextRow()

                im.TableNextColumn()
                im.Text(cstring(raw_data(frame.instructionPointerReference.? or_else "N/A")))

                im.TableNextColumn()
                im.Text(cstring(raw_data(frame.name)))

                im.TableNextColumn()
                {
                    context.allocator = context.temp_allocator
                    im.Text(fmt.caprintf("{}:{}:{}",
                            frame.source != nil ? frame.source.(dap.Source).name.? or_else "" : "",
                            frame.line, frame.column))
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
