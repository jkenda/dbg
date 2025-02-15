package dap

/*
    https://microsoft.github.io/debug-adapter-protocol/specification
*/


number :: distinct u32

DAP_Message :: union {
    Request,
    Response,
    Event,
}

ProtocolMessage :: struct #packed {
    seq: number,
    type: MessageType,
}

Command :: enum u8 {
    cancel,
}

MessageType :: enum u8 {
    request,
    response,
    event,
}


/*
   Requests.
*/

Request :: struct #packed {
    using base: ProtocolMessage `json:"-"`,

    command: Command,
    arguments: Arguments,
}

Arguments :: union {
    Arguments_Cancel
}

Arguments_Cancel :: struct #packed {
    requestId: Maybe(number),
    progressId: Maybe(string),
}


/*
   Responses.
*/

Response :: struct #packed {
    using base: ProtocolMessage,

    request_seq: number,
    success: bool,
    command: Command,
    message: enum u8 {
        cancelled,
        notStopped,
    },

    body: union {
        Body_Error,
        Empty,
    },
}

Body_Error :: struct {
    error: struct #packed {
        id: number,
        format: string,
        url: Maybe(string),
        urlLabel: Maybe(string),
        //variables: map[string]string,
        sendTelemetry: Maybe(bool),
        showUser: Maybe(bool),
    }
}

Empty :: struct {}


/*
   Events.
*/

Event :: struct #packed {
    using base: ProtocolMessage,

    event: enum u8 {
        output,
    },
    body: union {
        Body_OutputEvent,
    },
}

Body_OutputEvent :: struct #packed {
    category: Maybe(enum u8 { console, important, stdout, stderr, telemetry }),
    output: string,
    group: Maybe(enum u8 { start, startCollapsed, end }),
    variablesReference: Maybe(number),
    source: Maybe(Source),
    line: Maybe(number),
    column: Maybe(number),
    //data: any,
    locationReference: Maybe(number),
}


/*
    Structures and such.
*/

Source :: struct #packed {
    name: Maybe(string),
    path: Maybe(string),
    sourceReference: Maybe(number),
    presentationHint: Maybe(enum u8 { normal, emphasize, deemphasize }),
    origin: Maybe(string),
    //sources: Maybe([]Source),
    //adapterData: Maybe(any),
    //checksums: Maybe([]Checksum),
}

Checksum :: struct #packed {
    algorithm: enum u8 { MD5, SHA1, SHA256, timestamp },
    checksum: string,
}
