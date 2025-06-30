package views

import im "../odin-imgui"

show_memory_view :: proc(view_data: ^Runtime_View_Data) {
    NUM_COLUMNS :: 8
    if (im.BeginTable(
            "table1",
            NUM_COLUMNS,
            im.TableFlags_RowBg | im.TableFlags_SizingFixedFit | im.TableFlags_NoHostExtendX,
            {0, im.GetTextLineHeightWithSpacing() * 6}))
    {
        for row in 0..<10 {
            im.TableNextRow()
            for column in 0..<NUM_COLUMNS {
                im.TableNextColumn()
                im.Text("00", column, row)
            }
        }
        im.EndTable();
    }
}

