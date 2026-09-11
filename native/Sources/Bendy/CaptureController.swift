import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

final class CaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private let renderer: MetalOverlayView
    private let failure: (String) -> Void

    init(renderer: MetalOverlayView, failure: @escaping (String) -> Void) {
        self.renderer = renderer
        self.failure = failure
    }

    func deactivate() { lock.withLock { active = false } }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusNumber = attachments.first?[.status] as? NSNumber,
           SCFrameStatus(rawValue: statusNumber.intValue) != .complete {
            // Idle/blank/suspended samples must not replace the last good frame.
            return
        }
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        lock.lock()
        guard active else { lock.unlock(); return }
        renderer.submit(pixelBuffer)
        lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard lock.withLock({ active }) else { return }
        deactivate()
        failure("Screen capture stopped: \(error.localizedDescription)")
    }
}

@MainActor
final class CaptureController {
    private let renderer: MetalOverlayView
    private let callbackQueue = DispatchQueue(label: "com.bendy.capture", qos: .userInteractive)
    private var stream: SCStream?
    private var output: CaptureOutput?
    private var startTask: Task<Void, Never>?
    private var generation: UInt = 0
    private var stopTask: Task<Void, Never>?

    var onDisplayReady: ((CGDirectDisplayID) -> Void)?
    var onFailure: ((String) -> Void)?
    var onStarted: (() -> Void)?

    init(renderer: MetalOverlayView) { self.renderer = renderer }

    func start() {
        stop()
        let previousStop = stopTask
        generation &+= 1
        let requestedGeneration = generation
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                await previousStop?.value
                guard requestedGeneration == self.generation else { return }
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard requestedGeneration == self.generation else { return }
                guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) else {
                    throw CaptureProblem.noBuiltInDisplay
                }
                guard let ownApplication = content.applications.first(where: { $0.processID == getpid() }) else {
                    throw CaptureProblem.cannotExcludeSelf
                }

                let filter = SCContentFilter(display: display, excludingApplications: [ownApplication], exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                let maxWidth = min(2560, display.width)
                let scale = Double(maxWidth) / Double(display.width)
                configuration.width = maxWidth
                configuration.height = max(1, Int(Double(display.height) * scale))
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                configuration.queueDepth = 3
                configuration.capturesAudio = false
                configuration.showsCursor = true
                configuration.pixelFormat = kCVPixelFormatType_32BGRA

                let output = CaptureOutput(renderer: self.renderer) { [weak self] message in
                    Task { @MainActor [weak self] in self?.handleFailure(message, generation: requestedGeneration) }
                }
                let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: self.callbackQueue)
                guard requestedGeneration == self.generation else { output.deactivate(); return }
                self.output = output
                self.stream = stream
                self.onDisplayReady?(display.displayID)
                guard requestedGeneration == self.generation else { return }
                try await stream.startCapture()
                guard requestedGeneration == self.generation else {
                    output.deactivate()
                    // stop() owns teardown and waits for this startup to settle.
                    return
                }
                self.onStarted?()
            } catch is CancellationError {
                return
            } catch {
                self.handleFailure(error.localizedDescription, generation: requestedGeneration)
            }
        }
    }

    func stop(preserveFrame: Bool = false) {
        generation &+= 1
        let pendingStart = startTask
        pendingStart?.cancel()
        startTask = nil
        output?.deactivate()
        output = nil
        if !preserveFrame { renderer.clearFrame() }
        let oldStream = stream
        self.stream = nil
        if pendingStart != nil || oldStream != nil {
            stopTask = CaptureLifecycle.finish(previous: stopTask, startup: pendingStart) {
                if let oldStream { try? await oldStream.stopCapture() }
            }
        }
    }

    private func handleFailure(_ message: String, generation: UInt) {
        guard generation == self.generation else { return }
        stop()
        onFailure?(message)
    }
}

private enum CaptureProblem: LocalizedError {
    case noBuiltInDisplay
    case cannotExcludeSelf
    var errorDescription: String? {
        switch self {
        case .noBuiltInDisplay: return "No built-in display is available. Foldly never captures external displays."
        case .cannotExcludeSelf: return "Foldly could not exclude its own process, so capture was stopped to prevent feedback."
        }
    }
}
