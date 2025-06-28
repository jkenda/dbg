package dap

import "core:os/os2"
import "core:encoding/json"
import "core:strconv"
import "core:strings"
import "core:net"
import "core:fmt"
import "core:log"
import "core:io"

import "../dap"


Connection :: union {
    Connection_Stdio,
    Connection_Socket,
}

Connection_Stdio :: struct {
    process: os2.Process,
    stdin, stdout: ^os2.File,
    buf: [dynamic]u8,
    seq: number,
}

Connection_Socket :: struct {
    socket: net.TCP_Socket,
    buf: [dynamic]u8,
    seq: number,
}

when ODIN_OS == .Darwin {
    COMMAND: []string : { "lldb-dap" }
}
else {
    COMMAND: []string : { "gdb", "--interpreter=dap" }
}

CONTENT_LENGTH  :: "Content-Length: "


connect_stdio :: proc() -> (conn: Connection, err: Error) {
    r_in , w_in  := os2.pipe() or_return
    r_out, w_out := os2.pipe() or_return

    log.info("starting debugger:", strings.join(COMMAND, " "))

    process := os2.process_start(os2.Process_Desc{
        command = COMMAND,
        stdin = r_in,
        stdout = w_out,
    }) or_return
    os2.close(r_in)
    os2.close(w_out)
    log.info("debugger started. ready for 'initialize'")

    conn = Connection_Stdio{
        process = process,
        stdin = w_in,
        stdout = r_out,
    }
    return
}

connect_TCP :: proc(port: int) -> (conn: Connection, err: Error) {
    socket := net.dial_tcp(net.IP4_Address{ 127, 0, 0, 1 }, port) or_return
    conn = Connection_Socket{ socket = socket }

    return
}

connect :: proc{
    connect_stdio,
    connect_TCP,
}

disconnect :: proc(conn: ^Connection, allocator := context.allocator) -> bool {
    switch &c in conn {
    case Connection_Stdio:
        return disconnect_stdio(&c, allocator)
    case Connection_Socket:
        log.error("not yet implemented")
        return false
    }

    return false
}

disconnect_stdio :: proc(conn: ^Connection_Stdio, allocator := context.allocator) -> bool {
    log.info("shutting down debug adapter")
    write_message(conn, Arguments_Disconnect{})
    disconnect_request_seq := conn.seq

    log.info("waiting for shutdown")

    ok := true
    response: Protocol_Message
    wait_response: for {
        msg, err := read_message(conn, true, allocator)
        if err != nil { 
            ok = false
            log.error(err)
            break wait_response
        }

        switch m in msg {
        case Response:
            if m.request_seq == disconnect_request_seq {
                ok = m.success
                response = msg
                break wait_response
            }
        case Request, Event:
            // ignore
        }
    }

    wait_process: if ok {
        state, err := os2.process_wait(conn.process)
        if err != nil {
            ok = false
            break wait_process
        }
        log.info("shutdown successful")
    }

    os2.close(conn.stdin)
    os2.close(conn.stdout)

    if !ok {
        log.warn("unexpected message:", response, "; killing process")
        assert(os2.process_kill(conn.process) != nil)
    }
    return ok
}

read_message :: proc(conn: ^Connection_Stdio, sync := false, allocator := context.allocator) -> (msg: Protocol_Message, err: Error) {
    str: string

    str = read_text(conn, sync, allocator) or_return
    //log.debug(str)
    msg = parse_message(str, allocator) or_return
    return
}

write_message_msg :: proc(conn: ^Connection_Stdio, msg: ^Protocol_Message) -> (err: json.Marshal_Error) {
    set_seq :: proc(msg: ^Protocol_Message, seq: number) {
        switch &m in msg {
        case Request:
            m.seq = seq
        case Response:
            m.seq = seq
        case Event:
            m.seq = seq
        }
    }

    conn.seq += 1
    set_seq(msg, conn.seq)

    text := json.marshal(msg^, { use_enum_names = true }, context.temp_allocator) or_return
    write_text(conn^, string(text))
    //log.debug(string(text))

    return
}

write_message_request :: proc(conn: ^Connection_Stdio, args: Arguments) -> (err: json.Marshal_Error) {
    get_command :: proc(args: Arguments) -> Command {
        switch a in args {
        case Arguments_Cancel:
            return .cancel
        case Arguments_Initialize:
            return .initialize
        case Arguments_Launch:
            return .launch
        case Arguments_Disconnect:
            return .disconnect
        case Arguments_Terminate:
            return .terminate
        }

        return nil
    }

    msg: Protocol_Message = Request {
        type = .request,
        command = get_command(args),
        arguments = args,
    }

    return write_message_msg(conn, &msg)
}

write_message :: proc {
    write_message_msg,
    write_message_request,
}

@(private)
read_text :: proc(conn: ^Connection_Stdio, sync := false, allocator := context.allocator) -> (str: string, err: Error) {
    if !sync {
        if !(os2.pipe_has_data(conn.stdout) or_return) {
            err = .Empty_Input
            return
        }
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
    len_buf: [256]u8
    content_length := strconv.itoa(len_buf[:], len(text))

    io.write_string(conn.stdin.stream, CONTENT_LENGTH)
    io.write_string(conn.stdin.stream, content_length)
    io.write_string(conn.stdin.stream, "\r\n\r\n")
    io.write_string(conn.stdin.stream, text)
    io.flush(conn.stdin.stream)
}


import "core:testing"

@(test)
test_read_message_stdio :: proc(t: ^testing.T) {
    conn, err_start := connect_stdio()
    assert(err_start == nil)

    conn_stdio := conn.(Connection_Stdio)
    ok := disconnect(&conn, t._log_allocator)
    testing.expect(t, ok)
}
