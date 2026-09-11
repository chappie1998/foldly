import AppKit
@preconcurrency import CoreVideo
import Foundation
@preconcurrency import Metal

private final class SyntheticBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
    init(_ value: CVPixelBuffer) { self.value = value }
}

@main
enum RendererFramebufferHarness {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()

        let width = 1728
        let height = 1117
        var optionalBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &optionalBuffer) == kCVReturnSuccess,
              let buffer = optionalBuffer else {
            fputs("FAIL: could not create synthetic pixel buffer\n", stderr)
            exit(EXIT_FAILURE)
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            fputs("FAIL: synthetic pixel buffer has no base address\n", stderr)
            exit(EXIT_FAILURE)
        }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let pixel = row.advanced(by: x * 4)
                switch (x >= width / 2, y >= height / 2) {
                case (false, false): (pixel[0], pixel[1], pixel[2], pixel[3]) = (0, 0, 255, 255)
                case (true, false):  (pixel[0], pixel[1], pixel[2], pixel[3]) = (0, 255, 0, 255)
                case (false, true):  (pixel[0], pixel[1], pixel[2], pixel[3]) = (255, 0, 0, 255)
                case (true, true):   (pixel[0], pixel[1], pixel[2], pixel[3]) = (255, 255, 255, 255)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let overlay = OverlayController()
        let renderer = overlay.renderer
        let window = overlay.testWindow
        guard window.frame.width > 0, window.frame.height > 0 else {
            fputs("FAIL: attaching Metal to a zero-size overlay reproduces black presentation\n", stderr)
            exit(EXIT_FAILURE)
        }
        let display = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }!
        let displayID = (display.deviceDescription[.init("NSScreenNumber")] as! NSNumber).uint32Value
        guard overlay.configure(displayID: displayID) else { exit(EXIT_FAILURE) }
        window.title = "Foldly Synthetic Renderer Harness"
        let parameters = BendParameters(angle: 61, perspective: 0.391, blur: 0.744, shadow: 0.58, style: .frost)
        overlay.prepare(parameters)
        guard !window.isVisible && renderer.isPaused else {
            fputs("FAIL: overlay must stay hidden before capture startup is approved\n", stderr)
            exit(EXIT_FAILURE)
        }
        overlay.setPresentationAllowed(true)
        overlay.prepare(parameters)

        var completedFrames = 0
        var finished = false
        var passed = true
        let visualOnly = CommandLine.arguments.contains("--no-readback")
        renderer.inspectFrame = { _, texture, command in
            if visualOnly {
                command.addCompletedHandler { command in
                    if command.status == .completed { DispatchQueue.main.async { completedFrames += 1 } }
                }
                return
            }
            guard !finished else { return }
            let width = texture.width, height = texture.height
            let bytesPerRow = width * 4
            let readback = renderer.device!.makeBuffer(length: bytesPerRow * height, options: .storageModeShared)!
            let blit = command.makeBlitCommandEncoder()!
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: .init(x: 0, y: 0, z: 0),
                      sourceSize: .init(width: width, height: height, depth: 1),
                      to: readback, destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
                      destinationBytesPerImage: bytesPerRow * height)
            blit.endEncoding()
            command.addCompletedHandler { command in
                let bytes = readback.contents().assumingMemoryBound(to: UInt8.self)
                var nonblack = 0, red = 0, green = 0, blue = 0
                for i in 0..<(width * height) {
                    let b = Int(bytes[i*4]), g = Int(bytes[i*4+1]), r = Int(bytes[i*4+2])
                    if max(r, g, b) > 16 { nonblack += 1 }
                    if r > g + 30 && r > b + 30 { red += 1 }
                    if g > r + 30 && g > b + 30 { green += 1 }
                    if b > r + 30 && b > g + 30 { blue += 1 }
                }
                print("drawable=\(width)x\(height) status=\(command.status.rawValue) nonblack=\(nonblack) red=\(red) green=\(green) blue=\(blue) error=\(String(describing: command.error))")
                let valid = command.status == .completed && nonblack > 10_000 && min(red, green, blue) > 1_000
                DispatchQueue.main.async {
                    guard !finished else { return }
                    completedFrames += 1
                    passed = passed && valid
                    finished = !passed || completedFrames >= 90
                }
            }
        }
        let retainedBuffer = SyntheticBuffer(buffer)
        let animationStart = CACurrentMediaTime()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
            renderer.submit(retainedBuffer.value)
            if CommandLine.arguments.contains("--animate") {
                let phase = (CACurrentMediaTime() - animationStart) / 4.2
                var animated = parameters
                animated.angle = 107 - (0.5 - cos(phase * 2 * .pi) / 2) * 83
                MainActor.assumeIsolated { overlay.update(animated, active: true) }
            }
        }
        renderer.submit(buffer)

        let deadline = Date().addingTimeInterval(visualOnly ? 3 : 8)
        while !finished, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        if !CommandLine.arguments.contains("--animate") { timer.invalidate() }
        print("layerFrame=\(String(describing: renderer.layer?.frame)) layerBounds=\(String(describing: renderer.layer?.bounds)) hidden=\(renderer.isHidden) alpha=\(window.alphaValue) layerOpacity=\(String(describing: renderer.layer?.opacity))")
        if visualOnly { print("GPU frames in 3-second no-readback run: \(completedFrames)") }
        if CommandLine.arguments.contains("--show") {
            RunLoop.main.run(until: Date().addingTimeInterval(45))
        }
        timer.invalidate()
        if !visualOnly {
            overlay.setPresentationAllowed(false)
            for _ in 0..<10 { overlay.update(parameters, active: true) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let blockedSafely = !window.isVisible && renderer.isPaused && renderer.hasFrameForTesting
            overlay.setPresentationAllowed(true)
            overlay.update(parameters, active: true)
            let restoreDeadline = Date().addingTimeInterval(2)
            while window.alphaValue < 1, Date() < restoreDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            let restored = window.isVisible && window.alphaValue == 1 && renderer.hasFrameForTesting
            passed = passed && blockedSafely && restored
            print("System prompt suppression: hidden=\(blockedSafely), restored=\(restored)")
            // A static desktop may only produce idle capture samples. Reopening
            // and closing again must work without receiving another pixel buffer.
            overlay.finishOpening()
            let openingDeadline = Date().addingTimeInterval(2)
            while window.isVisible, Date() < openingDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            let openedWithFrame = !window.isVisible && renderer.isPaused && renderer.hasFrameForTesting
            overlay.prepare(parameters)
            let reclosingDeadline = Date().addingTimeInterval(2)
            while window.alphaValue < 1, Date() < reclosingDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            let reclosed = window.isVisible && window.alphaValue == 1 && !renderer.isPaused && renderer.hasFrameForTesting
            passed = passed && openedWithFrame && reclosed
            print("Static desktop reopen/reclose: retained=\(openedWithFrame), presented=\(reclosed)")
            var openingCompletions = 0
            overlay.finishOpening {
                openingCompletions += 1
                overlay.hide(clear: true)
            }
            let stoppedDeadline = Date().addingTimeInterval(2)
            while window.isVisible, Date() < stoppedDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            let stoppedCleanly = openingCompletions == 1 && !window.isVisible && !renderer.hasFrameForTesting && renderer.isPaused
            passed = passed && stoppedCleanly
            print("Capture-stop opening: completedOnce=\(openingCompletions == 1), cleared=\(stoppedCleanly)")

            renderer.submit(buffer)
            overlay.prepare(parameters)
            let restartDeadline = Date().addingTimeInterval(2)
            while window.alphaValue < 1, Date() < restartDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            var staleCompletion = false
            overlay.finishOpening { staleCompletion = true; overlay.hide(clear: true) }
            overlay.prepare(parameters)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            passed = passed && !staleCompletion && window.alphaValue == 1 && renderer.hasFrameForTesting
            print("Opening reversal: staleCompletion=\(staleCompletion), visible=\(window.alphaValue == 1)")
            renderer.failNextCompletion = true
            overlay.finishOpening()
            let failureDeadline = Date().addingTimeInterval(2)
            while window.isVisible, Date() < failureDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            passed = passed && !window.isVisible && renderer.isPaused && !renderer.hasFrameForTesting
            print("Render failure cleanup: hidden=\(!window.isVisible), paused=\(renderer.isPaused), frameCleared=\(!renderer.hasFrameForTesting)")
        }
        overlay.hide(clear: true)
        if visualOnly {
            print("Manual presentation check ended; pixel readback was disabled.")
            exit(EXIT_SUCCESS)
        }
        passed = passed && completedFrames >= 90
        print("completedFrames=\(completedFrames)")
        print(passed ? "PASS: actual drawable preserves synthetic colors" : "FAIL: actual drawable is missing synthetic colors")
        exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
