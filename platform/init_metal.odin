#+build darwin
package platform

import "core:log"
import "core:fmt"
import "core:os"
import "base:runtime"

import ns "core:sys/darwin/Foundation"
import ca "vendor:darwin/QuartzCore"
import mtl "vendor:darwin/Metal"

import "vendor:glfw"

import imgui "../odin-imgui"

import "../odin-imgui/imgui_impl_metal"
import "../odin-imgui/imgui_impl_glfw"

State :: struct {
    window: glfw.WindowHandle,
    device: ^mtl.Device,
    layer: ^ca.MetalLayer,
    drawable: ^ca.MetalDrawable,
    command_queue: ^mtl.CommandQueue,
    command_buffer: ^mtl.CommandBuffer,
    render_encoder: ^mtl.RenderCommandEncoder,
}

init :: proc() -> State {
    using state: State

    glfw.SetErrorCallback(proc "c" (error: i32, description: cstring) {
        context = runtime.default_context()
        fmt.fprintf(os.stderr, "Glfw Error %d: %s\n", error, description)
    })
    assert(bool(glfw.Init()), "failed to initialize GLFW")

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

    window = glfw.CreateWindow(1280, 720, APPLICATION_NAME, nil, nil)
    assert(window != nil, "GLFW: failed to initialize window")

    device = mtl.CreateSystemDefaultDevice()
	fmt.println("created device:", device->name()->odinString())

    command_queue = device->newCommandQueue()
    fmt.println("created comand queue:", command_queue->label()->odinString())

    log.info("initializing ImGui")
    imgui_impl_glfw.InitForOther(window, true)
    imgui_impl_metal.Init(device)
    
    layer = ca.MetalLayer.layer()
	layer->setDevice(device)
	layer->setPixelFormat(.BGRA8Unorm)

    nswin := glfw.GetCocoaWindow(window)
	nswin->contentView()->setLayer(layer)
	nswin->contentView()->setWantsLayer(true)

    return state
}

before_show :: proc(using state: ^State) {

    io := imgui.GetIO()

    width, height := glfw.GetFramebufferSize(window)
    layer->setDrawableSize({ width = ns.Float(width), height = ns.Float(height) })
    drawable = layer->nextDrawable()

    command_buffer = command_queue->commandBuffer()

    // setup render pass
    descriptor := mtl.RenderPassDescriptor.renderPassDescriptor()
    attachment := descriptor->colorAttachments()->object(0)
    attachment->setClearColor(mtl.ClearColor{ 0, 0, 0, 1 })
    attachment->setTexture(drawable->texture())
    attachment->setLoadAction(.Clear)
    attachment->setStoreAction(.Store)

    render_encoder = command_buffer->renderCommandEncoderWithDescriptor(descriptor)
    render_encoder->pushDebugGroup(ns.String.alloc()->initWithOdinString("dbg"))

    imgui_impl_metal.NewFrame(descriptor)
    imgui_impl_glfw.NewFrame()
    imgui.NewFrame()
}

after_show :: proc(using state: State) {
    io := imgui.GetIO()

    imgui.Render()
    imgui_impl_metal.RenderDrawData(imgui.GetDrawData(), command_buffer, render_encoder)

    if (.ViewportsEnable in io.ConfigFlags) {
        imgui.UpdatePlatformWindows();
        imgui.RenderPlatformWindowsDefault();
    }

    render_encoder->popDebugGroup()
    render_encoder->endEncoding()

    command_buffer->presentDrawable(drawable)
    command_buffer->commit()
}

destroy :: proc(using state: State) {
    imgui_impl_metal.Shutdown()
    imgui_impl_glfw.Shutdown()
    imgui.DestroyContext()

    glfw.DestroyWindow(window)
    glfw.Terminate()
}

handle_events :: proc(using state: State) -> bool {
    glfw.PollEvents()
    return !glfw.WindowShouldClose(window)
}

window_pos :: proc(using state: State) -> [2]f32 {
    xpos, ypos := glfw.GetWindowPos(window)
    return { f32(xpos), f32(ypos) }
}
