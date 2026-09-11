import AppKit

struct SystemPromptWindow {
    var bundleIdentifier: String
    var bounds: CGRect
    var alpha: Double
}

struct SystemPromptSnapshot {
    var foregroundBundleIdentifier: String?
    var windows: [SystemPromptWindow] = []
    var hasOwnModal = false

    static let dialogHosts: Set<String> = [
        "com.apple.UserNotificationCenter",
        "com.apple.SecurityAgent",
        "com.apple.coreservices.uiagent"
    ]

    var blocksOverlay: Bool {
        if hasOwnModal || foregroundBundleIdentifier == "com.apple.systempreferences" { return true }
        return windows.contains {
            Self.dialogHosts.contains($0.bundleIdentifier) && $0.alpha > 0 &&
                $0.bounds.width >= 80 && $0.bounds.height >= 40
        }
    }
}

/// Observes window metadata only; never reads dialog text or requests Accessibility.
@MainActor
final class SystemPromptMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var isBlocked = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.refresh() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.refresh() }
            })
        }
        refresh()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }; observers.removeAll()
        setBlocked(false)
    }

    @discardableResult func refresh() -> Bool {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let ownModal = NSApp.modalWindow != nil || NSApp.windows.contains { $0.attachedSheet != nil }
        // Resolve only dialog-host processes. Ignore dormant hosts with no
        // visible window and avoid fetching any window names or contents.
        let hosts = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String)? in
            guard let identifier = app.bundleIdentifier, SystemPromptSnapshot.dialogHosts.contains(identifier),
                  app.bundleURL?.path.hasPrefix("/System/") == true else { return nil }
            return (app.processIdentifier, identifier)
        })
        var windows: [SystemPromptWindow] = []
        if !hosts.isEmpty,
           let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            windows = infos.compactMap { info in
                guard let pid = info[kCGWindowOwnerPID as String] as? Int32, let identifier = hosts[pid],
                      let bounds = info[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                      let alpha = info[kCGWindowAlpha as String] as? Double else { return nil }
                return .init(bundleIdentifier: identifier, bounds: rect, alpha: alpha)
            }
        }
        let blocked = SystemPromptSnapshot(foregroundBundleIdentifier: front, windows: windows, hasOwnModal: ownModal).blocksOverlay
        setBlocked(blocked)
        return blocked
    }

    private func setBlocked(_ blocked: Bool) {
        guard blocked != isBlocked else { return }
        isBlocked = blocked
        onChange?(blocked)
    }
}
