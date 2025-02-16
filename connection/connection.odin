package connection

import "core:os/os2"
import "core:encoding/json"
import "core:net"
import "core:io"
import "core:fmt"
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
    seq: dap.number,
}

Connection_Socket :: struct {
    socket: net.TCP_Socket,
    buf: [dynamic]u8,
    seq: dap.number,
}

Error :: union #shared_nil {
    os2.Error,
    net.Network_Error,
    dap.Error,
}

GDB             :: "gdb"
DAP             :: "--interpreter=dap"
CONTENT_LENGTH  :: "Content-Length: "


start_stdio :: proc() -> (conn: Connection, err: Error) {
    r_in , w_in := os2.pipe() or_return
    r_out, w_out  := os2.pipe() or_return

    process := os2.process_start(os2.Process_Desc{
        command = { GDB, DAP },
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
    socket := net.dial_tcp(net.IP4_Address{ 127, 0, 0, 1 }, port) or_return
    conn = Connection_Socket{ socket = socket }

    return
}

start :: proc{
    start_stdio,
    start_TCP,
}

stop :: proc(conn: ^Connection_Stdio, allocator := context.allocator) -> bool {
    log.debug("requesting disconnect")
    msg: dap.Protocol_Message = dap.Request{
        type = .request,
        command = .disconnect,
        arguments = dap.Arguments_Disconnect{},
    }
    write_message(conn, &msg)
    disconnect_request_seq := conn.seq

    log.debug("waiting for response")

    ok := true
    response: dap.Protocol_Message
    waiting: for {
        msg, err := read_message(conn, true, allocator)
        if err != nil { 
            ok = false
            log.error(err)
            break waiting
        }

        switch m in msg {
        case dap.Response:
            if m.request_seq == disconnect_request_seq {
                ok = m.success
                response = msg
                break waiting
            }
        case dap.Request, dap.Event:
            // ignore
        }
    }

    if !ok {
        log.warn("unexpected message:", response, "; killing process")
        assert(os2.process_kill(conn.process) != nil)
    }

    {
        log.debug("waiting for shutdown")
        state, err := os2.process_wait(conn.process)
        assert(state.exited)
    }

    return ok
}

read_message :: proc(conn: ^Connection_Stdio, sync := false, allocator := context.allocator) -> (msg: dap.Protocol_Message, err: Error) {
    str: string

    str = read_text(conn, sync, allocator) or_return
    msg = dap.parse_message(str, allocator) or_return
    return
}

write_message :: proc(conn: ^Connection_Stdio, msg: ^dap.Protocol_Message) -> (err: json.Marshal_Error) {
    set_seq :: proc(msg: ^dap.Protocol_Message, seq: dap.number) {
        switch &m in msg {
        case dap.Request:
            m.seq = seq
        case dap.Response:
            m.seq = seq
        case dap.Event:
            m.seq = seq
        }
    }

    conn.seq += 1
    set_seq(msg, conn.seq)

    text := json.marshal(msg^, { use_enum_names = true }) or_return
    write_text(conn^, string(text))

    return
}

@(private)
read_text :: proc(conn: ^Connection_Stdio, sync := false, allocator := context.allocator) -> (str: string, err: os2.Error) {
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

@(private)
write_text :: proc(conn: Connection_Stdio, text: string) {
    fmt.wprint(conn.stdin.stream, CONTENT_LENGTH)
    fmt.wprint(conn.stdin.stream, len(text))
    fmt.wprint(conn.stdin.stream, "\r\n\r\n")
    fmt.wprint(conn.stdin.stream, text)
}


import "core:testing"
import "core:log"

@(test)
test_read_message_stdio :: proc(t: ^testing.T) {
    conn, err_start := start_stdio()
    assert(err_start == nil)

    conn_stdio := conn.(Connection_Stdio)
    ok := stop(&conn_stdio, t._log_allocator)
    testing.expect(t, ok)
}
