import AppKit
import Carbon

@MainActor final class HotKeyManager {
    typealias Binding = (HotKey, () -> Void)
    private var references: [EventHotKeyRef] = []
    private var callbacks: [UInt32: Binding] = [:]
    var onTrigger: ((HotKey, Bool) -> Void)?
    var onMonitorChange: ((SequenceMonitorState) -> Void)?
    var onBackgroundEvent: (() -> Void)?
    private var bindings: [Binding] = []
    private var handler: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var permissionTimer: Timer?
    private var recording = false
    private var taps = KeyTapRecognizer()
    private var sequences = KeySequenceMatcher()
    private var sequenceBindings: [Binding] = []
    private let globalSequencesEnabled: Bool
    init(globalSequencesEnabled: Bool = true) {
        self.globalSequencesEnabled = globalSequencesEnabled
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            MainActor.assumeIsolated {
                let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
                manager.resetSequence()
                if let binding = manager.callbacks[id.id] { manager.trigger(binding, background: NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier) }
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func apply(_ newBindings: [Binding], interval: TimeInterval = 0.4) throws {
        let previous = bindings
        let previousInterval = sequences.interval
        clear()
        sequences.interval = interval
        do { if !recording { try register(newBindings) }; bindings = newBindings }
        catch {
            clear()
            sequences.interval = previousInterval
            // Restore working shortcuts if any requested shortcut is occupied by another app.
            try? register(previous); bindings = previous
            throw error
        }
    }
    private func register(_ newBindings: [Binding]) throws {
        for (index, binding) in newBindings.enumerated() where !binding.0.isSequence {
            let id = UInt32(index + 1)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.0.keyCode, binding.0.modifiers, EventHotKeyID(signature: 0x50414931, id: id), GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else { throw AppError.message("无法注册 \(binding.0.display)，可能已被其他应用占用（\(status)）。") }
            references.append(reference); callbacks[id] = binding
        }
        sequenceBindings = newBindings.filter { $0.0.isSequence }
        if !sequenceBindings.isEmpty { installSequenceMonitors() }
        else { onMonitorChange?(.notNeeded) }
    }
    private func resetSequence() {
        taps.reset(modifiers: KeyStroke.modifiers(from: NSEvent.modifierFlags)); sequences.reset()
    }
    private func installSequenceMonitors() {
        resetSequence()
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.receive(event, background: false); return event
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetSequence() }
        }
        if globalSequencesEnabled {
            refreshGlobalMonitor()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshGlobalMonitor() }
            }
        } else { onMonitorChange?(.preview) }
    }
    func refreshGlobalMonitor() {
        guard !recording else { onMonitorChange?(.recording); return }
        guard !sequenceBindings.isEmpty else { onMonitorChange?(.notNeeded); return }
        guard globalSequencesEnabled else { onMonitorChange?(.preview); return }
        let trusted = AXIsProcessTrusted()
        if trusted, globalMonitor == nil {
            let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                MainActor.assumeIsolated { self?.receive(event, background: true) }
            }
            resetSequence()
        } else if !trusted, let globalMonitor {
            NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil; resetSequence()
        }
        onMonitorChange?(trusted ? (globalMonitor == nil ? .failed : .listening) : .permissionRequired)
    }
    private func trigger(_ binding: Binding, background: Bool) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let confirmedBackground = background && frontmost != nil && frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier
        onTrigger?(binding.0, confirmedBackground); binding.1()
    }
    private func receive(_ event: NSEvent, background: Bool) {
        if background && [.keyDown, .keyUp, .flagsChanged].contains(event.type) { onBackgroundEvent?() }
        guard !recording, !IsSecureEventInputEnabled() else { resetSequence(); return }
        switch taps.consume(KeyInput(event), at: event.timestamp) {
        case .none: break
        case .interrupted: sequences.reset()
        case .tap(let stroke):
            if let index = sequences.consume(stroke, at: event.timestamp, shortcuts: sequenceBindings.map(\.0)) { trigger(sequenceBindings[index], background: background) }
        }
    }
    private func clear() {
        references.forEach { UnregisterEventHotKey($0) }; references.removeAll(); callbacks.removeAll()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; globalMonitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }; activationObserver = nil
        permissionTimer?.invalidate(); permissionTimer = nil; sequenceBindings.removeAll(); resetSequence()
    }
    func setRecording(_ recording: Bool) throws {
        guard self.recording != recording else { return }
        self.recording = recording
        clear()
        if !recording { try register(bindings) } else { onMonitorChange?(.recording) }
    }
    func stop() { clear(); bindings.removeAll(); if let handler { RemoveEventHandler(handler) }; handler = nil }
}
