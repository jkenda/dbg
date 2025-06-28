package views

import im "../odin-imgui"

show_dasm_view :: proc(data: Global_Data) {
    if (im.BeginTable("Threads", 2, im.TableFlags_Resizable)) {
        im.TableSetupColumn("Address"    , {.WidthStretch})
        im.TableSetupColumn("Instruction", {.WidthStretch})

        im.TableHeadersRow()

        for line in data.disassembly {
            im.TableNextRow()

            im.TableNextColumn()
            im.Text(cstring(raw_data(line.address)))

            im.TableNextColumn()
            im.Text(cstring(raw_data(line.instr)))
        }

        im.EndTable()
    }
}
