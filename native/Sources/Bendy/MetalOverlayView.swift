import AppKit
import CoreImage
import CoreVideo
import MetalKit

final class MetalOverlayView: MTKView, MTKViewDelegate, @unchecked Sendable {
    #if RENDERER_TEST
    var failNextCompletion = false
    var hasFrameForTesting: Bool { lock.withLock { latest != nil } }
    var inspectFrame: ((CVPixelBuffer, MTLTexture, MTLCommandBuffer) -> Void)?
    #endif
    var onFailure: ((String) -> Void)?
    private var renderGeneration: UInt = 0
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var parameters = BendParameters(angle: 105, perspective: 0.7, blur: 0.2, shadow: 0.5, style: .silk)
    private var firstPresentation: (() -> Void)?
    private var motion = FoldMotion(angle: 105)
    private var previousDrawTime: TimeInterval?
    private var opened: (() -> Void)?
    private let inFlight = DispatchSemaphore(value: 2)
    private let context: CIContext
    private let commandQueue: MTLCommandQueue
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init() {
        guard let metal = MTLCreateSystemDefaultDevice() else { fatalError("Foldly requires Metal") }
        guard let queue = metal.makeCommandQueue() else { fatalError("Foldly could not create a Metal command queue") }
        commandQueue = queue
        context = CIContext(mtlDevice: metal, options: [.cacheIntermediates: false])
        super.init(frame: .zero, device: metal)
        delegate = self; framebufferOnly = false; colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 1); preferredFramesPerSecond = 60; enableSetNeedsDisplay = false; isPaused = true
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    func submit(_ buffer: CVPixelBuffer) { lock.withLock { latest = buffer } }
    func update(_ value: BendParameters) { lock.withLock { parameters = value } }
    func begin(_ value: BendParameters, fromOpen: Bool) {
        update(value)
        renderGeneration &+= 1
        opened = nil
        if fromOpen { motion.angle = value.clearAngle; previousDrawTime = nil }
        isPaused = false
    }
    func arm(_ callback: @escaping () -> Void) { lock.withLock { firstPresentation = callback } }
    func finishOpening(_ callback: @escaping () -> Void) {
        lock.withLock { parameters.angle = parameters.clearAngle }
        opened = callback
        isPaused = false
    }
    func stopAnimation() { renderGeneration &+= 1; isPaused = true; previousDrawTime = nil; opened = nil }
    func clearFrame() { lock.withLock { latest = nil; firstPresentation = nil } }

    func draw(in view: MTKView) { autoreleasepool { renderFrame() } }

    private func renderFrame() {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        var committed = false
        defer { if !committed { inFlight.signal() } }
        let values = lock.withLock { (latest, parameters) }
        guard let buffer = values.0, let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let now = CACurrentMediaTime()
        let dt = previousDrawTime.map { now - $0 } ?? 1.0 / 60
        previousDrawTime = now
        var eased = values.1
        eased.angle = motion.advance(toward: values.1.angle, deltaTime: dt,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let source = CIImage(cvPixelBuffer: buffer)
        let bent = BendRenderer.image(source, parameters: eased)
        let size = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let output = bent.transformed(by: .init(
            scaleX: size.width / source.extent.width, y: size.height / source.extent.height))
        context.render(output, to: drawable.texture, commandBuffer: commandBuffer,
                       bounds: .init(origin: .zero, size: size), colorSpace: colorSpace)
        #if RENDERER_TEST
        inspectFrame?(buffer, drawable.texture, commandBuffer)
        #endif
        let callback = lock.withLock { () -> (() -> Void)? in let value = firstPresentation; firstPresentation = nil; return value }
        let finish = eased.angle >= eased.clearAngle && values.1.angle >= eased.clearAngle ? opened : nil
        if finish != nil { opened = nil }
        let semaphore = inFlight
        let generation = renderGeneration
        #if RENDERER_TEST
        let forceFailure = failNextCompletion
        failNextCompletion = false
        #else
        let forceFailure = false
        #endif
        commandBuffer.addCompletedHandler { [weak self, buffer] command in
            withExtendedLifetime(buffer) {
                semaphore.signal()
                DispatchQueue.main.async {
                    guard let self, self.renderGeneration == generation else { return }
                    guard command.status == .completed, !forceFailure else {
                        self.onFailure?("Foldly stopped because the display could not finish drawing. Try enabling it again.")
                        return
                    }
                    callback?()
                    finish?()
                }
            }
        }
        commandBuffer.present(drawable)
        committed = true
        commandBuffer.commit()
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

@MainActor
final class OverlayController {
    let renderer = MetalOverlayView()
    var onFailure: ((String) -> Void)?
    var canPresent: (() -> Bool)?
    private var presentationAllowed = false
    private let window: NSPanel
    #if RENDERER_TEST
    var testWindow: NSPanel { window }
    #endif
    private var wantsVisible = false
    private var presentationGeneration: UInt = 0
    private var presentationPending = false

    init() {
        // Attaching an MTKView to a zero-sized panel leaves its presented
        // surface black after resize, even though the GPU texture has pixels.
        let initialFrame = NSScreen.screens.first(where: {
            guard let number = $0.deviceDescription[.init("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        })?.frame ?? CGRect(x: 0, y: 0, width: 640, height: 400)
        window = NSPanel(contentRect: initialFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = renderer; window.backgroundColor = .black; window.isOpaque = true; window.hasShadow = false
        window.ignoresMouseEvents = true; window.level = .floating; window.hidesOnDeactivate = false; window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        renderer.onFailure = { [weak self] message in
            self?.hide(clear: true)
            self?.onFailure?(message)
        }
    }

    func configure(displayID: CGDirectDisplayID) -> Bool {
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }) else { return false }
        window.setFrame(screen.frame, display: true); renderer.frame = .init(origin: .zero, size: screen.frame.size); return true
    }

    func setPresentationAllowed(_ allowed: Bool) {
        guard allowed != presentationAllowed else { return }
        presentationAllowed = allowed
        if !allowed { hide() }
    }

    func prepare(_ parameters: BendParameters) {
        guard presentationAllowed else { return }
        wantsVisible = true
        presentationGeneration &+= 1
        let generation = presentationGeneration
        if window.isVisible && window.alphaValue == 1 {
            renderer.begin(parameters, fromOpen: false)
            return
        }
        presentationPending = true
        window.alphaValue = 0
        window.orderFrontRegardless()
        renderer.arm { [weak self] in
            guard let self, self.canPresent?() ?? true,
                  self.presentationAllowed, self.wantsVisible, self.presentationGeneration == generation else { return }
            self.presentationPending = false
            self.window.alphaValue = 1
        }
        renderer.begin(parameters, fromOpen: true)
    }

    func update(_ parameters: BendParameters, active: Bool) {
        guard active, presentationAllowed else { return }
        if !wantsVisible { prepare(parameters) }
        else { renderer.update(parameters) }
    }

    func finishOpening() {
        wantsVisible = false
        presentationGeneration &+= 1
        let generation = presentationGeneration
        // Capture stays running while open. Keep its last complete frame because
        // a static desktop may send only idle samples until content changes.
        guard window.isVisible, !presentationPending else { hide(); return }
        renderer.finishOpening { [weak self] in
            guard let self, self.presentationGeneration == generation, !self.wantsVisible else { return }
            self.hide()
        }
    }

    func hide(clear: Bool = false) {
        presentationGeneration &+= 1
        presentationPending = false
        wantsVisible = false
        window.orderOut(nil)
        window.alphaValue = 0
        renderer.stopAnimation()
        if clear { renderer.clearFrame() }
    }
}
