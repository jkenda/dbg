package dap

/*
    https://microsoft.github.io/debug-adapter-protocol/specification
*/


number :: distinct u64

Protocol_Message :: union {
    Request,
    Response,
    Event,
}

Message_Type :: enum u8 {
    _unknown,

    request,
    response,
    event,
}

Command :: enum u8 {
    _unknown,

    cancel,
    initialize,
    launch,
    setBreakpoints,
    configurationDone,
    threads,
    stackTrace,
    disconnect,
    terminate,
}

Empty :: struct {}


/*
   Requests.
*/

Request :: struct #packed {
    seq: number,
    type: Message_Type,

    command: Command,
    arguments: Arguments,
}

Arguments :: union {
    Arguments_Cancel,
    Arguments_Initialize,
    Arguments_Launch,
    Arguments_SetBreakpoints,
    Arguments_ConfigurationDone,
    Arguments_Threads,
    Arguments_StackTrace,
    Arguments_Disconnect,
    Arguments_Terminate,
}

Arguments_Cancel :: struct #packed {
    requestId: Maybe(number) `json:"requestId,omitempty"`,
    progressId: Maybe(string) `json:"progressId, omitempty"`,
}

Arguments_Initialize :: struct #packed {
    clientID: Maybe(string) `json:"clientID,omitempty"`,
    clientName: Maybe(string) `json:"clientName,omitempty"`,
    adapterID: string,
    locale: Maybe(string) `json:"locale,omitempty"`,
    linesStartAt1: Maybe(bool) `json:"linesStartAt1,omitempty"`,
    columnsStartAt1: Maybe(bool) `json:"columnsStartAt1,omitempty"`,
    pathFormat: Maybe(string) `json:"pathFormat,omitempty"`,
    supportsVariableType: Maybe(bool) `json:"supportsVariableType,omitempty"`,
    supportsVariablePaging: Maybe(bool) `json:"supportsVariablePaging,omitempty"`,
    supportsRunInTerminalRequest: Maybe(bool) `json:"supportsRunInTerminalRequest,omitempty"`,
    supportsMemoryReferences: Maybe(bool) `json:"supportsMemoryReferences,omitempty"`,
    supportsProgressReporting: Maybe(bool) `json:"supportsProgressReporting,omitempty"`,
    supportsInvalidatedEvent: Maybe(bool) `json:"supportsInvalidatedEvent,omitempty"`,
    supportsMemoryEvent: Maybe(bool) `json:"supportsMemoryEvent,omitempty"`,
    supportsArgsCanBeInterpretedByShell: Maybe(bool) `json:"supportsArgsCanBeInterpretedByShell,omitempty"`,
    supportsStartDebuggingRequest: Maybe(bool) `json:"supportsStartDebuggingRequest,omitempty"`,
    supportsANSIStyling: Maybe(bool) `json:"supportsANSIStyling,omitempty"`,
}

Arguments_Launch :: struct #packed {
    program: string,
    args: []string `json:"args,omitempty"`,
    cwd: string `json:"cwd,omitempty"`,
    stopOnEntry: Maybe(bool) `json:"stopOnEntry,omitempty"`,
    noDebug: Maybe(bool) `json:"noDebug,omitempty"`,
}

Arguments_SetBreakpoints :: SourceBreakpoints
Arguments_ConfigurationDone :: distinct Empty
Arguments_Threads :: distinct Empty

Arguments_StackTrace :: struct #packed {
    threadId: number,
    startFrame: Maybe(number) `json:"startFrame,omitempty"`,
    levels: Maybe(number) `json:"levels,omitempty"`,
    format: Maybe(StackFrameFormat) `json:"format,omitempty"`,
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
    type: Message_Type,

    request_seq: number,
    success: bool,
    command: Command,
    message: Maybe(Message) `json:"message,omitempty"`,

    body: union {
        Body_Error,
        Body_Initialized,
        Body_Threads,
        Body_StackTrace,

        Body_Empty,
    },
}
Message :: enum u8 {
    cancelled,
    notStopped,
}

Body_Empty :: distinct Empty

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

Body_Initialized :: Capabilities

Body_Threads :: struct #packed {
    threads: []Thread,
}

Body_StackTrace :: struct #packed {
    stackFrames: []StackFrame,
    totalFrames: Maybe(number),
}


/*
   Events.
*/

Event_Type :: enum u8 {
    _unknown,

    output,
    initialized,
    process,
    exited,
    terminated,
    stopped,
}

Event :: struct #packed {
    seq: number,
    type: Message_Type,

    event: Event_Type,
    body: union {
        Body_OutputEvent,
        Body_Process,
        Body_Exited,
        Body_Terminated,
        Body_Stopped,

        Body_Empty,
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

Body_Process :: struct #packed {
    name: string,
    systemProcessId: Maybe(number) `json:"systemProcessId,omitempty"`,
    isLocalProcess: Maybe(bool) `json:"isLocalProcess,omitempty"`,
    startMethod: Maybe(StartMethod) `json:"startMethod,omitempty"`,
    pointerSize: Maybe(number) `json:"pointerSize,omitempty"`,
}
StartMethod :: enum u8 {
    launch,
    attach,
    attachForSuspendedLaunch,
}

Body_Exited :: struct #packed {
    exitCode: number,
}

Body_Terminated :: struct #packed {
}

Body_Stopped :: struct #packed {
    reason: StoppedReason,
    description: Maybe(string),
    threadId: Maybe(number),
    preserveFocusHint: Maybe(bool),
    text: Maybe(string),
    allThreadsStopped: Maybe(bool),
    hitBreakpointIds: Maybe([]number),
}
StoppedReason :: enum u8 {
    step,
    breakpoint,
    exception,
    pause,
    entry,
    goto,
}

/*
    Structures and such.
*/

Capabilities :: struct #packed {
    supportsConfigurationDoneRequest: bool,
    supportsFunctionBreakpoints: bool,
    supportsConditionalBreakpoints: bool,
    supportsHitConditionalBreakpoints: bool,
    supportsEvaluateForHovers: bool,
    //exceptionBreakpointFilters: [dynamic]ExceptionBreakpointsFilter,
    supportsStepBack: bool,
    supportsSetVariable: bool,
    supportsRestartFrame: bool,
    supportsGotoTargetsRequest: bool,
    supportsStepInTargetsRequest: bool,
    supportsCompletionsRequest: bool,
    //completionTriggerCharacters: [dynamic]string,
    supportsModulesRequest: bool,
    //additionalModuleColumns: [dynamic]ColumnDescriptor,
    supportedChecksumAlgorithms: string,
    supportsRestartRequest: bool,
    supportsExceptionOptions: bool,
    supportsValueFormattingOptions: bool,
    supportsExceptionInfoRequest: bool,
    supportTerminateDebuggee: bool,
    supportSuspendDebuggee: bool,
    supportsDelayedStackTraceLoading: bool,
    supportsLoadedSourcesRequest: bool,
    supportsLogPoints: bool,
    supportsTerminateThreadsRequest: bool,
    supportsSetExpression: bool,
    supportsTerminateRequest: bool,
    supportsDataBreakpoints: bool,
    supportsReadMemoryRequest: bool,
    supportsWriteMemoryRequest: bool,
    supportsDisassembleRequest: bool,
    supportsCancelRequest: bool,
    supportsBreakpointLocationsRequest: bool,
    supportsClipboardContext: bool,
    supportsSteppingGranularity: bool,
    supportsInstructionBreakpoints: bool,
    supportsExceptionFilterOptions: bool,
    supportsSingleThreadExecutionRequests: bool,
    supportsDataBreakpointBytes: bool,
    //breakpointModes: [dynamic]BreakpointMode,
    supportsANSIStyling: bool,
}
ExceptionBreakpointsFilter :: struct #packed {
    filter: string,
    label: string,
    description: Maybe(string),
    default: Maybe(bool),
    supportsCondition: Maybe(bool),
    conditionDescription: Maybe(string),
}
ColumnDescriptor :: struct #packed {
    attributeName: string,
    label: string,
    format: Maybe(string),
    //type?: 'string' | 'number' | 'boolean' | 'unixTimestampUTC';
    width: Maybe(number),
}
BreakpointMode :: struct #packed {
    mode: string,
    label: string,
    description: Maybe(string),
    appliesTo: string,
}

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

SourceBreakpoints :: struct #packed {
    source: Source,
    breakpoints: Maybe([]SourceBreakpoint) `json:"breakpoints,omitempty"`,
    sourceModified: Maybe(bool) `json:"sourceModified,omitempty"`,
}

Thread :: struct #packed {
  id: number,
  name: string,
}

StackFrameFormat :: struct #packed {
    parameters: Maybe(bool) `json:"parameters,omitempty"`,
    parameterTypes: Maybe(bool) `json:"parameterTypes,omitempty"`,
    parameterNames: Maybe(bool) `json:"parameterNames,omitempty"`,
    parameterValues: Maybe(bool) `json:"parameterValues,omitempty"`,
    line: Maybe(bool) `json:"line,omitempty"`,
    module: Maybe(bool) `json:"module,omitempty"`,
    includeAll: Maybe(bool) `json:"includeAll,omitempty"`,
}
StackFrame :: struct #packed {
    id: number,
    name: string,
    source: Maybe(Source),
    line: number,
    column: number,
    endLine: Maybe(number),
    endColumn: Maybe(number),
    canRestart: Maybe(bool),
    instructionPointerReference: Maybe(string),
    moduleId: string,
    presentationHint: Maybe(enum { normal, label, subtle }),
}

SourceBreakpoint :: struct #packed {
    line: number,
    column: Maybe(number),
    condition: Maybe(string),
    hitCondition: Maybe(string),
    logMessage: Maybe(string),
    mode: Maybe(string),
}
Checksum :: struct #packed {
    algorithm: enum u8 { MD5, SHA1, SHA256, timestamp },
    checksum: string,
}
