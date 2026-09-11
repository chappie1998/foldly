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
        check(gate.update(angle: 120, allowed: true) == .start, "Enable must start capture immediately, even while open")
        for angle in [120.0, 105, 104, 60, 15, 107, 120, 60, 120] {
            check(gate.update(angle: angle, allowed: true) == .none, "folding and reopening must keep one capture session")
        }
        check(gate.update(angle: 120, allowed: false) == .stop, "pause must stop capture even while open")
        check(gate.update(angle: 60, allowed: false) == .none, "disabled/paused/sleeping must not start capture")
        check(gate.update(angle: 60, allowed: true) == .start, "resuming closed starts once")
        check(gate.update(angle: 60, allowed: false) == .stop, "disable/pause/sleep must stop active capture")
        check(gate.update(angle: .nan, allowed: true) == .none, "invalid sensor data cannot start capture")
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
        print("PASS: Frost projection, continuous capture lifecycle, system prompt policy, and motion easing")
    }
}
