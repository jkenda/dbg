package connection

import "core:os/os2"
import "core:net"
import "core:io"
import "core:strconv"
import "core:strings"

import "../dap"


Connection :: union {
    Connection_Stdio,
    Connection_Socket,
}

Connection_Stdio :: struct {
    process: os2.Process,
    stdin, stdout: ^os2.File,
    buf: [dynamic]u8,
}

Connection_Socket :: struct {
    socket: net.TCP_Socket,
    buf: [dynamic]u8,
}

Error :: union {
    os2.Error,
    net.Network_Error,
    dap.Error,
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
    socket := net.dial_tcp(net.IP4_Address{ 128, 0, 0, 1 }, port) or_return
    conn = Connection_Socket{ socket = socket }

    return
}

start :: proc{
    start_stdio,
    start_TCP,
}

read_message :: proc(conn: ^Connection_Stdio, sync := false, allocator := context.allocator) -> (msg: dap.DAP_Message, err: Error) {
    str := read_text(conn, sync, allocator) or_return
    msg = dap.parse_message(str, allocator) or_return
    return
}

read_text :: proc(conn: ^Connection_Stdio, sync := false, allocator := context.allocator) -> (str: string, err: os2.Error) {
    CONTENT_LENGTH :: "Content-Length: "

    if !sync && (os2.pipe_has_data(conn.stdout) or_return) {
        return
    }

    // read "Content-Length: " and ensure its validity
    len_buf: [len(CONTENT_LENGTH)]u8
    io.read(conn.stdout.stream, len_buf[:])
    assert(len_buf == CONTENT_LENGTH)

    // read until newline
    len := 0
    for {
        len_buf[len] = io.read_byte(conn.stdout.stream) or_return
        if len_buf[len] == '\r' { break }
        len += 1
    }

    // parse content length
    content_length := strconv.atoi(string(len_buf[:len]))
    {
        context.allocator = allocator
        resize(&conn.buf, content_length)
    }

    // skip the rest of the "\r\n\r\n" pattern
    io.read(conn.stdout.stream, conn.buf[:3])
    assert(string(conn.buf[:3]) == "\n\r\n")

    // read the message
    io.read(conn.stdout.stream, conn.buf[:])
    str = string(conn.buf[:])
    return
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
    }
}

@(test)
test_read_message_stdio :: proc(t: ^testing.T) {
    conn, err_start := start_stdio()
    assert(err_start == nil)

    conn_stdio := conn.(Connection_Stdio)
    defer assert(os2.process_kill(conn_stdio.process) == nil)

    {
        msg, err := read_message(&conn_stdio, true, t._log_allocator)
        testing.expect_value(t, err, nil)

        log.debug(msg)
    }
}
