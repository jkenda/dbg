package dap

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:log"
import "base:runtime"


parse_message :: proc(msg_str: string, allocator := context.allocator) -> (msg: DAP_Message, err: Error) {
    context.allocator = allocator

    message: ProtocolMessage
    json.unmarshal_string(msg_str, &message) or_return

    #partial switch message.type {
    case .request:
        msg = parse_request(msg_str, message) or_return
    case .response:
        msg = parse_response(msg_str, message) or_return
    case .event:
        msg = parse_event(msg_str, message) or_return
    case nil:
        err = .Unknown_Message
        return
    }

    log.debug("parsed:", msg, "size:", size_of(msg), "B")
    return
}

parse_request :: proc(msg_str: string, base: ProtocolMessage) -> (request: Request, err: Error) {
    request.base = base
    json.unmarshal_string(msg_str, &request) or_return

    switch request.command {
    case .cancel:
        request.arguments = Arguments_Cancel{}
    case nil:
        err = .Unknown_Message
        return
    }

    json.unmarshal_string(msg_str, &request) or_return
    return
}

parse_response :: proc(msg_str: string, base: ProtocolMessage) -> (response: Response, err: Error) {
    response.base = base
    json.unmarshal_string(msg_str, &response) or_return

    if response.success {
        switch response.command {
        case .cancel:
            response.body = Empty{}
        case nil:
            err = .Unknown_Message
            return
        }
    }
    else {
        response.body = Body_Error{}
    }

    json.unmarshal_string(msg_str, &response) or_return
    return
}

parse_event :: proc(msg_str: string, base: ProtocolMessage) -> (event: Event, err: Error) {
    event.base = base
    json.unmarshal_string(msg_str, &event) or_return

    err = .Unknown_Message
    return
}


Error :: union {
    json.Unmarshal_Error,
    Parse_Error,
}

Parse_Error :: enum {
    Unknown_Message,
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
    //testing.expect_value(t, msg, Request{})
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
    //testing.expect_value(t, msg, Request{})
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
    //testing.expect_value(t, msg, Request{})
}
