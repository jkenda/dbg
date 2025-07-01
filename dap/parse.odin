package dap

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:log"
import "base:runtime"


parse_message :: proc(msg_str: string, allocator := context.allocator) -> (msg: Protocol_Message, err: Error) {
    context.allocator = allocator

    base: struct {
        seq: number,
        type: Message_Type,
    }
    json.unmarshal_string(msg_str, &base) or_return

    switch base.type {
    case .request:
        msg = parse_request(msg_str) or_return
    case .response:
        msg = parse_response(msg_str) or_return
    case .event:
        msg = parse_event(msg_str) or_return
    case nil, ._unknown:
        log.warn("unknown message:", msg_str)
        err = .Unknown_Message
        return
    }

    return
}

@(private)
parse_request :: proc(msg_str: string) -> (request: Request, err: Error) {
    json.unmarshal_string(msg_str, &request) or_return

    switch request.command {
    case .cancel:
        request.arguments = parse_arguments(Arguments_Cancel, msg_str) or_return
    case .initialize:
        request.arguments = parse_arguments(Arguments_Initialize, msg_str) or_return
    case .launch:
        request.arguments = parse_arguments(Arguments_Launch, msg_str) or_return
    case .configurationDone:
        request.arguments = parse_arguments(Arguments_ConfigurationDone, msg_str) or_return
    case .setBreakpoints:
        request.arguments = parse_arguments(Arguments_SetBreakpoints, msg_str) or_return
    case .setFunctionBreakpoints:
        request.arguments = parse_arguments(Arguments_SetFunctionBreakpoints, msg_str) or_return
    case .threads:
        request.arguments = parse_arguments(Arguments_Threads, msg_str) or_return
    case .stackTrace:
        request.arguments = parse_arguments(Arguments_StackTrace, msg_str) or_return
    case .disassemble:
        request.arguments = parse_arguments(Arguments_Disassemble, msg_str) or_return
    case .next:
        request.arguments = parse_arguments(Arguments_Next, msg_str) or_return
    case .stepIn:
        request.arguments = parse_arguments(Arguments_StepIn, msg_str) or_return
    case .disconnect:
        request.arguments = parse_arguments(Arguments_Disconnect, msg_str) or_return
    case .terminate:
        request.arguments = parse_arguments(Arguments_Terminate, msg_str) or_return
    case nil, ._unknown:
        log.warn("unknown message:", msg_str)
        err = .Unknown_Message
    }

    return
}

@(private)
parse_response :: proc(msg_str: string) -> (response: Response, err: Error) {
    json.unmarshal_string(msg_str, &response) or_return

    if response.success {
        switch response.command {
        case .cancel, .launch, .next, .stepIn, .disconnect, .terminate, .configurationDone:
            response.body = Body_Ack{}
        case .initialize:
            response.body = parse_body(Body_Initialized, msg_str) or_return
        case .setBreakpoints:
            unimplemented()
        case .setFunctionBreakpoints:
            response.body = parse_body(Body_SetFunctionBreakpoints, msg_str) or_return
        case .threads:
            response.body = parse_body(Body_Threads, msg_str) or_return
        case .stackTrace:
            response.body = parse_body(Body_StackTrace, msg_str) or_return
        case .disassemble:
            response.body = parse_body(Body_Disassemble, msg_str) or_return
        case nil, ._unknown:
            log.warn("unknown message:", msg_str)
            err = .Unknown_Message
        }
    }
    else {
        response.body = parse_body(Body_Error, msg_str) or_return
    }

    return
}

@(private)
parse_event :: proc(msg_str: string) -> (event: Event, err: Error) {
    json.unmarshal_string(msg_str, &event) or_return

    switch event.event {
    case .output:
        event.body = parse_body(Body_OutputEvent, msg_str) or_return
    case .initialized:
        event.body = Body_Ack{}
    case .process:
        event.body = parse_body(Body_Process, msg_str) or_return
    case .exited:
        event.body = parse_body(Body_Exited, msg_str) or_return
    case .terminated:
        event.body = parse_body(Body_Terminated, msg_str) or_return
    case .stopped:
        event.body = parse_body(Body_Stopped, msg_str) or_return
    case .continued:
        event.body = parse_body(Body_Continued, msg_str) or_return
    case .breakpoint:
        event.body = parse_body(Body_Breakpoint, msg_str) or_return

    case nil, ._unknown:
        log.warn("unknown message:", msg_str)
        err = .Unknown_Message
    }

    return
}

@(private)
parse_arguments :: proc($T: typeid, msg_str: string) -> (arguments: T, er: Error) {
    Arguments_Only :: struct { arguments: T }

    only: Arguments_Only
    json.unmarshal_string(msg_str, &only) or_return
    arguments = only.arguments
    return
}

@(private)
parse_body :: proc($T: typeid, msg_str: string) -> (body: T, er: Error) {
    Body_Only :: struct { body: T }

    only: Body_Only
    json.unmarshal_string(msg_str, &only) or_return
    body = only.body
    return
}


import "core:testing"

@(test)
parse_cancel_req :: proc(t: ^testing.T) {
    msg, err := parse_message(`{
        "seq": 3,
        "type": "request",
        "command": "cancel",
        "arguments": {
            "requestId": 2
        }
    }`, t._log_allocator)

    testing.expect_value(t, err, nil)
    //testing.expect_value(t, msg.(Request), Request{
    //    seq = 3,
    //    type = .request,
    //    command = .cancel,
    //    arguments = Arguments_Cancel{
    //        requestId = 2
    //    }
    //})
}

@(test)
parse_terminate_req :: proc(t: ^testing.T) {
    msg, err := parse_message(`{
        "seq": 6,
        "type": "request",
        "command": "terminate",
        "arguments": {
            "restart": false
        }
    }`, t._log_allocator)

    testing.expect_value(t, err, nil)
    //testing.expect_value(t, msg.(Request), Request{
    //    seq = 6,
    //    type = .request,
    //    command = .terminate,
    //    arguments = Arguments_Terminate{
    //        restart = false
    //    }
    //})
}

@(test)
parse_cancel_res :: proc(t: ^testing.T) {
    msg, err := parse_message(`{
        "seq": 4,
        "type": "response",
        "request_seq": 3,
        "command": "cancel",
        "success": true
    }`, t._log_allocator)

    testing.expect_value(t, err, nil)
    //testing.expect_value(t, msg.(Response), Response{
    //    seq = 4,
    //    type = .response,
    //    request_seq = 3,
    //    command = .cancel,
    //    success = true,
    //    body = Body_Empty{}
    //})
}

@(test)
parse_error_res :: proc(t: ^testing.T) {
    msg, err := parse_message(`{
        "seq": 5,
        "type": "response",
        "request_seq": 3,
        "command": "cancel",
        "success": false,
        "message": "Request cannot be canceled",
        "body": {
            "error": {
                "id": 1,
                "format": "The request with ID 2 is not cancellable.",
                "variables": {
                    "requestId": "2"
                },
                "sendTelemetry": false,
                "showUser": true,
                "url": "https://example.com/debugger-errors#request-not-cancellable",
                "urlLabel": "More Information"
            }
        }
    }`, t._log_allocator)

    testing.expect_value(t, err, nil)
    //assert(Response{} == Response{})
    //testing.expect_value(t, msg.(Response), Response{
    //    seq = 5,
    //    type = .response,
    //    request_seq = 3,
    //    command = .cancel,
    //    success = false,
    //    //message = "Request cannot be canceled",
    //    body = Body_Error{
    //        error = {
    //            id = 1,
    //            format = "The request with ID 2 is not cancellable.",
    //            //variables = {
    //            //    ["requestId"] = "2"
    //            //},
    //            sendTelemetry = false,
    //            showUser = true,
    //            url = "https://example.com/debugger-errors#request-not-cancellable",
    //            urlLabel = "More Information"
    //        }
    //    }
    //})
}

@(test)
parse_terminate_res :: proc(t: ^testing.T) {
    msg, err := parse_message(`{
        "seq": 4,
        "type": "response",
        "request_seq": 3,
        "command": "terminate",
        "success": true
    }`, t._log_allocator)

    testing.expect_value(t, err, nil)
    //testing.expect_value(t, msg.(Response), Response{
    //    seq = 4,
    //    type = .response,
    //    request_seq = 3,
    //    command = .terminate,
    //    success = true,
    //    body = Body_Empty{}
    //})
}

@(test)
parse_set_function_breakpoints_res :: proc(t: ^testing.T) {
    msg, err := parse_message(`{"body":{"breakpoints":[{"column":57,"id":1,"instructionReference":"0x100014618","line":53,"source":{"name":"entry_unix.odin","path":"/nix/store/drmvn956ak02rw7ka1q9kpf9amk1zack-odin-dev-2025-01/share/base/runtime/entry_unix.odin"},"verified":true}]},"command":"setFunctionBreakpoints","request_seq":3,"seq":0,"success":true,"type":"response"}`, t._log_allocator)

    testing.expect_value(t, err, nil)
    log.debug(msg.(Response).body)
    //testing.expect_value(t, msg.(Response), Response{
    //    seq = 4,
    //    type = .response,
    //    request_seq = 3,
    //    command = .terminate,
    //    success = true,
    //    body = Body_Empty{}
    //})
}

@(test)
parse_stack_trace_res :: proc(t: ^testing.T) {
    msg, err := parse_message(`{"body":{"stackFrames":[{"column":57,"id":524288,"instructionPointerReference":"0x100016FA8","line":53,"name":"main","source":{"name":"entry_unix.odin","path":"/nix/store/drmvn956ak02rw7ka1q9kpf9amk1zack-odin-dev-2025-01/share/base/runtime/entry_unix.odin"}},{"column":0,"id":524289,"instructionPointerReference":"0x18FD9AB98","line":0,"name":"start"}],"totalFrames":2},"command":"stackTrace","request_seq":6,"seq":0,"success":true,"type":"response"}`, t._log_allocator)

    testing.expect_value(t, err, nil)
    log.debug(msg.(Response).body)
    //testing.expect_value(t, msg.(Response), Response{
    //    seq = 4,
    //    type = .response,
    //    request_seq = 3,
    //    command = .terminate,
    //    success = true,
    //    body = Body_Empty{}
    //})
}

@(test)
parse_output_evt :: proc(t: ^testing.T) {
    msg, err := parse_message(`{
        "type": "event",
        "event": "output",
        "body": {
            "category": "stdout",
            "output": "GNU gdb (GDB) 14.2\n"
        },
        "seq": 1
    }`, t._log_allocator)

    testing.expect_value(t, err, nil)
    //testing.expect_value(t, msg.(Event), Event{
    //    seq = 1,
    //    type = .event,
    //    event = .output,
    //    body = Body_OutputEvent{
    //        category = .stdout,
    //        output = "GNU gdb (GDB) 14.2\n"
    //    }
    //})
}
