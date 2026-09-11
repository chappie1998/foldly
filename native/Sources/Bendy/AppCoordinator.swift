import AppKit
import Combine
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private let overlay = OverlayController()
    private lazy var capture = CaptureController(renderer: overlay.renderer)
    private let sensor = LidAngleSensor()
    private let promptMonitor = SystemPromptMonitor()
    private let foldSound = FoldSound()
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var displayConfigured = false
    private var captureGate = CaptureGate()
    private var foldVisible = false
    private var sleeping = false
    private var awaitingFreshSensor = false
    private var sensorGeneration: UInt = 0
    private var foldSoundArmed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureCaptureCallbacks()
        configureStatusItem()
        configureObservers()
        configureKeyMonitors()
        startSensor()
        settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.applySettings() }
        }.store(in: &cancellables)
        showSettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopImmediately(); sensor.stop()
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
    }

    private func configureCaptureCallbacks() {
        promptMonitor.onChange = { [weak self] blocked in
            guard let self else { return }
            self.settings.systemPromptVisible = blocked
            self.updateFoldPresentation(self.settings.bendParameters)
        }
        overlay.canPresent = { [weak self] in
            guard let self else { return false }
            return !self.promptMonitor.refresh() && self.captureGate.isActive && self.settings.captureState == .active
        }
        capture.onDisplayReady = { [weak self] displayID in
            guard let self, self.captureGate.isActive else { return }
            self.displayConfigured = self.overlay.configure(displayID: displayID)
            guard self.displayConfigured else {
                self.disableWithError("The built-in display changed before Foldly could attach its overlay.")
                return
            }
        }
        capture.onFailure = { [weak self] message in self?.disableWithError(message) }
        overlay.onFailure = { [weak self] message in self?.disableWithError(message) }
        capture.onStarted = { [weak self] in
            guard let self, self.captureGate.isActive else { return }
            if self.settings.captureState != .active { self.settings.captureState = .active }
            self.promptMonitor.refresh()
            self.updateFoldPresentation(self.settings.bendParameters)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.compress.vertical", accessibilityDescription: "Foldly")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Foldly", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Enable", action: #selector(toggleEnabledFromMenu), keyEquivalent: "e").target = self
        menu.addItem(withTitle: "Pause", action: #selector(togglePause), keyEquivalent: "p").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Foldly", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu; statusItem = item
    }

    private func configureObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func configureKeyMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            Task { @MainActor [weak self] in self?.emergencyPause() }
            return nil
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor [weak self] in self?.emergencyPause() }
        }
    }

    private func startSensor() {
        sensorGeneration &+= 1
        let generation = sensorGeneration
        sensor.start { [weak self] reading in
            DispatchQueue.main.async {
                guard let self, self.sensorGeneration == generation, !self.sleeping else { return }
                self.awaitingFreshSensor = false
                self.settings.currentSensorAngle = reading.angle
                self.settings.sensorStatus = reading.detail
                if reading.angle == nil, self.settings.followLid, self.settings.enabled {
                    self.disableWithError("Lid tracking was lost. Foldly stopped safely; turn off Follow MacBook lid to use the manual angle.")
                } else {
                    self.applySettings()
                }
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard !settings.followLid || settings.currentSensorAngle != nil else {
                settings.lastError = "This Mac did not provide a lid angle. Turn off Follow MacBook lid to use the manual demo."
                settings.enabled = false; return
            }
            settings.enabled = true; settings.paused = false; settings.lastError = nil
            applySettings()
        } else {
            settings.enabled = false; settings.paused = false; displayConfigured = false
            stopImmediately()
        }
        updateMenu()
    }

    private func applySettings() {
        updateMenu()
        let parameters = settings.bendParameters
        if settings.enabled && settings.followLid && settings.currentSensorAngle == nil && !awaitingFreshSensor && !sleeping {
            disableWithError("Lid tracking is unavailable. Turn off Follow MacBook lid to use the manual angle.")
            return
        }
        let active = settings.enabled && !settings.paused && !sleeping &&
            (!settings.followLid || (!awaitingFreshSensor && settings.currentSensorAngle != nil))
        if active && parameters.angle < settings.clearAngle - 7 { foldSoundArmed = true }
        if active && foldSoundArmed && parameters.angle >= settings.clearAngle {
            if settings.sound && settings.captureState == .active && !promptMonitor.isBlocked { foldSound.play() }
            foldSoundArmed = false
        }
        if !active { foldSoundArmed = false }
        switch captureGate.update(angle: parameters.angle, allowed: active) {
        case .start:
            displayConfigured = false
            foldVisible = false
            overlay.setPresentationAllowed(false)
            overlay.hide(clear: true)
            settingsWindow?.level = .normal
            if settings.captureState != .starting { settings.captureState = .starting }
            promptMonitor.start()
            capture.start()
        case .stop:
            overlay.setPresentationAllowed(false)
            capture.stop()
            if settings.captureState != .idle { settings.captureState = .idle }
            foldVisible = false
            overlay.hide(clear: true)
            settingsWindow?.level = .normal
            promptMonitor.stop()
        case .none:
            if !active { overlay.hide(clear: true) }
        }
        if captureGate.isActive && displayConfigured { updateFoldPresentation(parameters) }
    }

    private func updateFoldPresentation(_ parameters: BendParameters) {
        let allowed = captureGate.isActive && displayConfigured && settings.captureState == .active && !promptMonitor.isBlocked
        overlay.setPresentationAllowed(allowed)
        settingsWindow?.level = allowed ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1) : .normal
        guard allowed else { foldVisible = false; return }
        if parameters.angle < parameters.clearAngle {
            foldVisible = true
            overlay.update(parameters, active: true)
        } else if foldVisible {
            // Finish opening once, without restarting capture or repeatedly
            // replacing the renderer's completion while sensor updates arrive.
            foldVisible = false
            overlay.finishOpening()
        }
    }

    private func stopImmediately() {
        _ = captureGate.update(angle: 180, allowed: false)
        displayConfigured = false
        foldVisible = false
        overlay.setPresentationAllowed(false)
        capture.stop()
        overlay.hide(clear: true)
        if settings.captureState != .idle { settings.captureState = .idle }
        settingsWindow?.level = .normal
        promptMonitor.stop()
    }

    private func disableWithError(_ message: String) {
        settings.lastError = message; settings.enabled = false; settings.paused = false; displayConfigured = false
        stopImmediately(); updateMenu()
    }

    private func updateMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.item(withTitle: settings.enabled ? "Disable" : "Enable")?.title = settings.enabled ? "Disable" : "Enable"
        menu.items.first(where: { $0.action == #selector(toggleEnabledFromMenu) })?.title = settings.enabled ? "Disable" : "Enable"
        menu.items.first(where: { $0.action == #selector(togglePause) })?.title = settings.paused ? "Resume" : "Pause"
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = BendySettingsView(settings: settings, setEnabled: { [weak self] in self?.setEnabled($0) }, pause: { [weak self] in self?.togglePause() }, quit: { [weak self] in self?.quit() }, previewSound: { [weak self] in self?.foldSound.play() })
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 520, height: 650), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Foldly"; window.contentView = NSHostingView(rootView: view); window.center()
            window.level = .normal
            window.isReleasedWhenClosed = false; settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleEnabledFromMenu() { setEnabled(!settings.enabled) }
    @objc func togglePause() {
        guard settings.enabled else { overlay.hide(clear: true); return }
        settings.paused.toggle()
        if settings.paused { stopImmediately() }
        else { applySettings() }
        updateMenu()
    }
    private func emergencyPause() { if settings.enabled && !settings.paused { togglePause() } }
    @objc private func displayChanged() {
        stopImmediately()
        applySettings()
    }
    @objc private func willSleep() {
        sleeping = true
        sensorGeneration &+= 1
        stopImmediately()
        sensor.stop()
    }
    @objc private func didWake() {
        sleeping = false
        awaitingFreshSensor = settings.followLid
        settings.currentSensorAngle = nil
        startSensor()
        if !settings.followLid { applySettings() }
    }
    @objc func quit() { NSApp.terminate(nil) }
}
