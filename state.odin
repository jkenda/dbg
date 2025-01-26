package dbg

import "core:strings"
import "core:bytes"
import "core:os"
import "core:c"
import "core:encoding/json"

import "core:fmt"

SAVE_FILE_PATH :: "dbg.layout"
@(private="file") INI_SEPARATOR :: "-------------"

View :: struct {
    source, dasm, watch, memory: bool,
}
Show :: struct {
    demo_window: bool,
    view: View,
}
show: Show

read_and_strip_ini_file :: proc() -> (cstring, c.size_t) {
    bytes, ok := os.read_entire_file(SAVE_FILE_PATH)
    if !ok {
        return "", 0
    }

    layout := string(bytes)
    ini_end := len(layout)

    idx_separator := strings.index(layout, INI_SEPARATOR)
    if idx_separator != -1 {
        // we have extended the .ini with our own layout data
        ini_end = idx_separator + len(INI_SEPARATOR)
        deserialize_ini_extension(layout[ini_end:])
    }

    ini_cstring := strings.unsafe_string_to_cstring(layout[:ini_end])
    return ini_cstring, uint(ini_end)
}

@(private="file")
deserialize_ini_extension :: proc(extension: string) {
    err := json.unmarshal_string(extension, &show.view, .MJSON)
    assert(err == nil)

    fmt.println(show)
}

save_ini_with_extension :: proc(ini_cstring: cstring, ini_len: c.size_t) {
    buffer: bytes.Buffer

    ini_string := strings.string_from_null_terminated_ptr(transmute([^]u8)ini_cstring, int(ini_len))
    bytes.buffer_write_string(&buffer, ini_string)
    bytes.buffer_write_string(&buffer, INI_SEPARATOR)
    when ODIN_OS == .Windows {
        bytes.buffer_write_string(&buffer, "\r\n")
    }
    else {
        bytes.buffer_write_string(&buffer, "\n")
    }

    { // marshal MJSON
        MARSHAL_OPTIONS : json.Marshal_Options : {
            spec = .MJSON,
            pretty = true,
            mjson_keys_use_equal_sign = true,
            use_enum_names = true,
        }
        data, err := json.marshal(show.view, MARSHAL_OPTIONS)
        assert(err == nil)

        bytes.buffer_write(&buffer, data)
    }

    success := os.write_entire_file(SAVE_FILE_PATH, bytes.buffer_to_bytes(&buffer))
    assert(success)
}
