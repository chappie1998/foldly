import Foundation
import CoreImage

@main enum MotionPolicyTests {
    @MainActor static func main() async {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        let size = CGSize(width: 1000, height: 600)
        let nearOpen = BendGeometry.calculate(size: size, parameters: .init(angle: 106, perspective: 0.7, blur: 0.7, shadow: 0.5, style: .frost))
        check(nearOpen.outputHeight / size.height > 0.999, "fold must ease gently away from open, without a linear cut")
        let halfway = BendGeometry.calculate(size: size, parameters: .init(angle: 60, perspective: 0.7, blur: 0.7, shadow: 0.5, style: .frost))
        check(halfway.outputHeight / size.height > 0.75, "half-fold must preserve the website's taller projection")
        var gate = CaptureGate()
        check(gate.update(angle: 120, allowed: true) == .none, "default capture must stay off above 105 degrees")
        check(gate.update(angle: 105, allowed: true) == .none, "default capture waits until below105")
        check(gate.update(angle: 104, allowed: true) == .start, "crossing105 starts capture")
        for angle in [104.0, 105, 106, 105, 104] {
            check(gate.update(angle: angle, allowed: true) == .none, "sensor jitter must not restart capture")
        }
        check(gate.update(angle: 107, allowed: true) == .stop, "reopening to107 stops capture")
        for threshold in [60.0, 80, 105, 115] {
            check(gate.update(angle: threshold, allowed: true, triggerAngle: threshold) == .none, "wait at configured start boundary")
            check(gate.update(angle: threshold - 1, allowed: true, triggerAngle: threshold) == .start, "configured threshold starts capture")
            check(gate.update(angle: threshold + 1, allowed: true, triggerAngle: threshold) == .none, "configured threshold preserves dead band")
            check(gate.update(angle: threshold + 2, allowed: true, triggerAngle: threshold) == .stop, "configured reopening stops capture")
        }
        check(gate.update(angle: 120, allowed: true, mode: .alwaysOn) == .start, "Always on must start capture immediately, even while open")
        for angle in [120.0, 105, 104, 60, 15, 107, 120, 60, 120] {
            check(gate.update(angle: angle, allowed: true, mode: .alwaysOn) == .none, "Always on keeps one capture session through lid movement")
        }
        check(gate.update(angle: 120, allowed: false) == .stop, "pause must stop capture even while open")
        check(gate.update(angle: 60, allowed: false) == .none, "disabled/paused/sleeping must not start capture")
        check(gate.update(angle: 60, allowed: true) == .start, "resuming closed starts once")
        check(gate.update(angle: 60, allowed: false) == .stop, "disable/pause/sleep must stop active capture")
        check(gate.update(angle: .nan, allowed: true) == .none, "invalid sensor data cannot start capture")
        check(gate.update(angle: 90, allowed: true, triggerAngle: 100) == .start, "raising threshold applies immediately")
        check(gate.update(angle: 90, allowed: true, triggerAngle: 80) == .stop, "lowering threshold stops an out-of-range session")
        check(gate.update(angle: 90, allowed: true, mode: .alwaysOn) == .start, "switching to Always on applies immediately")
        check(gate.update(angle: 90, allowed: true, triggerAngle: 80) == .stop, "switching back to angle mode applies immediately")

        let suite = "com.whiteduck.foldly.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        check(settings.captureMode == .byLidAngle && settings.captureTrigger == 105 && !settings.enabled,
              "new and existing installations default to105 with capture disabled")
        settings.captureMode = .alwaysOn
        settings.captureTrigger = 82
        let restored = AppSettings(defaults: defaults)
        check(restored.captureMode == .alwaysOn && restored.captureTrigger == 82 && restored.captureStopAngle == 84,
              "capture mode and custom angle persist across launches")
        settings.captureTrigger = .nan
        check(settings.captureTrigger == 105, "invalid live values normalize safely")
        settings.captureTrigger = 300
        check(settings.captureTrigger == 115, "live values clamp to safe upper bound")
        defaults.set("invalid-mode", forKey: "captureMode")
        defaults.set(-12, forKey: "captureTrigger")
        let invalid = AppSettings(defaults: defaults)
        check(invalid.captureMode == .byLidAngle && invalid.captureTrigger == 60,
              "malformed preferences restore safe values")
        check(invalid.clearAngle == 107, "capture settings must not distort the established fold geometry")
        let promptBounds = CGRect(x: 0, y: 0, width: 400, height: 200)
        check(SystemPromptSnapshot(foregroundBundleIdentifier: "com.apple.systempreferences").blocksOverlay,
              "System Settings must be accessible even without an active modal")
        for host in SystemPromptSnapshot.dialogHosts {
            let prompt = SystemPromptWindow(bundleIdentifier: host, bounds: promptBounds, alpha: 1)
            check(SystemPromptSnapshot(foregroundBundleIdentifier: "com.whiteduck.bendy", windows: [prompt]).blocksOverlay,
                  "nonactivating system prompts must block the overlay")
            let hidden = SystemPromptWindow(bundleIdentifier: host, bounds: promptBounds, alpha: 0)
            check(!SystemPromptSnapshot(foregroundBundleIdentifier: nil, windows: [hidden]).blocksOverlay,
                  "invisible helper windows must not keep the effect hidden")
        }
        check(!SystemPromptSnapshot(foregroundBundleIdentifier: "com.apple.finder").blocksOverlay,
              "ordinary app activation must not block folding")
        check(!SystemPromptSnapshot(foregroundBundleIdentifier: nil).blocksOverlay,
              "dismissing a prompt must release the blocker")
        check(SystemPromptSnapshot(foregroundBundleIdentifier: nil, hasOwnModal: true).blocksOverlay,
              "app-owned modal sheets must stay accessible")
        var motion = FoldMotion(angle: 107)
        let first = motion.advance(toward: 30, deltaTime: 1.0 / 60)
        check(first < 107 && first > 90, "first animation frame must interpolate rather than jump")
        var previous = first
        for _ in 0..<90 {
            let next = motion.advance(toward: 30, deltaTime: 1.0 / 60)
            check(next <= previous && next >= 30, "closing must stay monotonic without overshoot")
            previous = next
        }
        check(motion.angle == 30, "motion must eventually settle exactly")
        for _ in 0..<90 { _ = motion.advance(toward: 107, deltaTime: 1.0 / 60) }
        check(motion.angle == 107, "opening must finish so retained frames can be cleared")
        check(motion.advance(toward: 60, deltaTime: 1.0 / 60, reduceMotion: true) == 60, "respect Reduce Motion")
        var at30 = FoldMotion(angle: 107), at60 = FoldMotion(angle: 107)
        for _ in 0..<15 { _ = at30.advance(toward: 30, deltaTime: 1.0 / 30) }
        for _ in 0..<30 { _ = at60.advance(toward: 30, deltaTime: 1.0 / 60) }
        check(abs(at30.angle - at60.angle) < 0.001, "motion timing must be frame-rate independent")
        var startContinuation: CheckedContinuation<Void, Never>?
        var events: [String] = []
        let startup = Task { @MainActor in
            await withCheckedContinuation { startContinuation = $0 }
            events.append("old started")
        }
        while startContinuation == nil { await Task.yield() }
        let teardown = CaptureLifecycle.finish(previous: nil, startup: startup) { events.append("old stopped") }
        let replacement = Task { @MainActor in await teardown.value; events.append("new started") }
        for _ in 0..<10 { await Task.yield() }
        check(events.isEmpty, "replacement must wait for a pending startup, even before stop returns")
        startContinuation?.resume()
        await replacement.value
        check(events == ["old started", "old stopped", "new started"], "startup, teardown and replacement must never overlap")
        print("PASS: configurable capture, preference persistence, Frost projection, prompt policy, and motion easing")
    }
}
