import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let style = "style"
        static let perspective = "perspective"
        static let blur = "blur"
        static let shadow = "shadow"
        static let followLid = "followLid"
        static let manualAngle = "manualAngle"
        static let sound = "sound"
        static let captureMode = "captureMode"
        static let captureTrigger = "captureTrigger"
    }

    private let defaults: UserDefaults
    @Published var enabled = false
    @Published var paused = false
    @Published var sensorStatus = "Checking lid sensor…"
    @Published var currentSensorAngle: Double?
    @Published var lastError: String?
    enum CaptureState { case idle, starting, active }
    @Published var captureState: CaptureState = .idle
    @Published var systemPromptVisible = false

    var activityDescription: String {
        if !enabled { return "Foldly is off" }
        if paused { return "Paused · screen capture off" }
        switch captureState {
        case .idle: return captureMode == .byLidAngle ? "Waiting below \(Int(captureTrigger))° · capture off" : "Ready · screen capture off"
        case .starting: return "Starting screen capture…"
        case .active:
            if systemPromptVisible { return "Effect hidden for macOS · capture on" }
            return effectiveAngle < clearAngle ? "Folding · screen capture on" : "Ready · screen capture on"
        }
    }

    @Published var style: BendyStyle { didSet { defaults.set(style.rawValue, forKey: Key.style) } }
    @Published var perspective: Double { didSet { defaults.set(perspective, forKey: Key.perspective) } }
    @Published var blur: Double { didSet { defaults.set(blur, forKey: Key.blur) } }
    @Published var shadow: Double { didSet { defaults.set(shadow, forKey: Key.shadow) } }
    @Published var followLid: Bool { didSet { defaults.set(followLid, forKey: Key.followLid) } }
    @Published var manualAngle: Double { didSet { defaults.set(manualAngle, forKey: Key.manualAngle) } }
    @Published var sound: Bool { didSet { defaults.set(sound, forKey: Key.sound) } }
    @Published var captureMode: CaptureMode { didSet { defaults.set(captureMode.rawValue, forKey: Key.captureMode) } }
    @Published var captureTrigger: Double {
        didSet {
            let normalized = CaptureGate.normalizedTrigger(captureTrigger)
            if captureTrigger != normalized { captureTrigger = normalized }
            defaults.set(captureTrigger, forKey: Key.captureTrigger)
        }
    }

    var captureStopAngle: Double { captureTrigger + 2 }
    var captureCaption: String {
        captureMode == .byLidAngle ? "Capture below \(Int(captureTrigger))° · off at \(Int(captureStopAngle))°" : "Screen capture while enabled"
    }

    let clearAngle = 107.0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        style = BendyStyle(rawValue: defaults.string(forKey: Key.style) ?? "") ?? .silk
        perspective = defaults.object(forKey: Key.perspective) == nil ? 0.72 : defaults.double(forKey: Key.perspective)
        blur = defaults.object(forKey: Key.blur) == nil ? 0.25 : defaults.double(forKey: Key.blur)
        shadow = defaults.object(forKey: Key.shadow) == nil ? 0.58 : defaults.double(forKey: Key.shadow)
        followLid = defaults.object(forKey: Key.followLid) == nil ? true : defaults.bool(forKey: Key.followLid)
        manualAngle = defaults.object(forKey: Key.manualAngle) == nil ? 64 : defaults.double(forKey: Key.manualAngle)
        sound = defaults.object(forKey: Key.sound) == nil ? false : defaults.bool(forKey: Key.sound)
        captureMode = CaptureMode(rawValue: defaults.string(forKey: Key.captureMode) ?? "") ?? .byLidAngle
        captureTrigger = CaptureGate.normalizedTrigger(defaults.object(forKey: Key.captureTrigger) == nil ? 105 : defaults.double(forKey: Key.captureTrigger))
        perspective = Self.bounded(perspective, fallback: 0.72)
        blur = Self.bounded(blur, fallback: 0.25)
        shadow = Self.bounded(shadow, fallback: 0.58)
        manualAngle = manualAngle.isFinite ? min(120, max(15, manualAngle)) : 64
        // enabled is intentionally never restored. Screen capture needs a fresh,
        // explicit action on every launch.
    }

    private static func bounded(_ value: Double, fallback: Double) -> Double { value.isFinite ? min(1, max(0, value)) : fallback }

    var effectiveAngle: Double {
        followLid ? (currentSensorAngle ?? manualAngle) : manualAngle
    }

    var bendParameters: BendParameters {
        BendParameters(
            angle: effectiveAngle,
            clearAngle: clearAngle,
            perspective: perspective,
            blur: blur,
            shadow: shadow,
            style: style
        )
    }
}
