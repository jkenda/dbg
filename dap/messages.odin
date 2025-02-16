package dap

/*
    https://microsoft.github.io/debug-adapter-protocol/specification
*/


number :: distinct u32

Protocol_Message :: union {
    Request,
    Response,
    Event,
}

MessageType :: enum u8 {
    request,
    response,
    event,
}

Command :: enum u8 {
    cancel,
    disconnect,
    terminate,
}


/*
   Requests.
*/

Request :: struct #packed {
    seq: number,
    type: MessageType,

    command: Command,
    arguments: Arguments,
}

Arguments :: union {
    Arguments_Cancel,
    Arguments_Disconnect,
    Arguments_Terminate,
}

Arguments_Cancel :: struct #packed {
    requestId: Maybe(number) `json:"requestId,omitempty"`,
    progressId: Maybe(string) `json:"progressId, omitempty"`,
}

Arguments_Disconnect :: struct #packed {
    restart: Maybe(bool) `json:"restart,omitempty"`,
    terminateDebuggee: Maybe(bool) `json:"terminateDebuggee,omitempty"`,
    suspendDebuggee: Maybe(bool) `json:"suspendDebuggee,omitempty"`,
}

Arguments_Terminate :: struct #packed {
    restart: Maybe(bool) `json:"omitempty"`,
}

/*
   Responses.
*/

Response :: struct #packed {
    seq: number,
    type: MessageType,

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
        url: Maybe(string) `json:"url,omitempty"`,
        urlLabel: Maybe(string) `json:"urlLabel,omitempty"`,
        //variables: map[string]string,
        sendTelemetry: Maybe(bool) `json:"sendTelemetry,omitempty"`,
        showUser: Maybe(bool) `json:"showUser,omitempty"`,
    }
}

Empty :: struct {}


/*
   Events.
*/

EventType :: enum u8 {
    output,
}

Event :: struct #packed {
    seq: number,
    type: MessageType,

    event: EventType,
    body: union {
        Body_OutputEvent,
    },
}

Body_OutputEvent :: struct #packed {
    category: Maybe(enum u8 { console, important, stdout, stderr, telemetry }) `json:"category,omitempty"`,
    output: string,
    group: Maybe(enum u8 { start, startCollapsed, end }) `json:"group,omitempty"`,
    variablesReference: Maybe(number) `json:"variablesReference,omitempty"`,
    source: Maybe(Source) `json:"source,omitempty"`,
    line: Maybe(number) `json:"line,omitempty"`,
    column: Maybe(number) `json:"column,omitempty"`,
    //data: any,
    locationReference: Maybe(number) `json:"locationReference,omitempty"`,
}


/*
    Structures and such.
*/

Source :: struct #packed {
    name: Maybe(string) `json:"name,omitempty"`,
    path: Maybe(string) `json:"path,omitempty"`,
    sourceReference: Maybe(number) `json:"sourceReference,omitempty"`,
    presentationHint: Maybe(enum u8 { normal, emphasize, deemphasize }) `json:"presentationHint,omitempty"`,
    origin: Maybe(string) `json:"origin,omitempty"`,
    //sources: Maybe([]Source),
    //adapterData: Maybe(any),
    //checksums: Maybe([]Checksum),
}

Checksum :: struct #packed {
    algorithm: enum u8 { MD5, SHA1, SHA256, timestamp },
    checksum: string,
}
