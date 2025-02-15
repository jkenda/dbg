package connection

import "core:os/os2"
import "core:net"
import "core:io"


Connection :: union {
    Connection_Stdio,
    net.TCP_Socket,
}

Connection_Stdio :: struct {
    process: os2.Process,
    stdin, stdout: ^os2.File,
}

Error :: union {
    os2.Error,
    net.Network_Error,
}

GDB :: "gdb"


start_stdio :: proc() -> (conn: Connection, err: Error) {
    r_in , w_in := os2.pipe() or_return
    r_out, w_out  := os2.pipe() or_return

    process := os2.process_start(os2.Process_Desc{
        command = { GDB, "--interpreter=dap" },
        stdin = r_in,
        stdout = w_out,
    }) or_return
    os2.close(r_in)
    os2.close(w_out)

    conn = Connection_Stdio{
        process = process,
        stdin = w_in,
        stdout = r_out,
    }
    return
}

start_TCP :: proc(port: int) -> (conn: Connection, err: Error) {
    conn = net.dial_tcp(net.IP4_Address{ 128, 0, 0, 1 }, port) or_return
    return
}

start :: proc{
    start_stdio,
    start_TCP,
}


import "core:testing"
import "core:log"

@(test)
test_start_stdio :: proc(t: ^testing.T) {
    conn, err_start := start_stdio()
    assert(err_start == nil)

    conn_stdio := conn.(Connection_Stdio)
    defer assert(os2.process_kill(conn_stdio.process) == nil)

    {
        buf: [256]u8
        n, err := io.read(conn_stdio.stdout.stream, buf[:])
        testing.expect_value(t, err, nil)
        testing.expect(t, n > 0)

        log.debug(string(buf[:n]))
    }
}
