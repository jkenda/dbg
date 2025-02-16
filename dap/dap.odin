package dap

import "core:encoding/json"
import "core:os/os2"
import "core:net"
import "core:io"

Parse_Error :: enum {
    Empty_Input,
    Unknown_Message,
}

Error :: union {
    Parse_Error,
    io.Error,
    os2.Error,
    net.Network_Error,
    json.Unmarshal_Error,
}
