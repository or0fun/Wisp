import SwiftUI
import Carbon

struct CommandInput: NSViewRepresentable {
    @Binding var text: String
    let focusToken: UUID
    let onSubmit: () -> Void
    let onMove: (Int) -> Void
    let onSwitchColumn: () -> Bool
    let onEscape: () -> Void
    let onChange: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = CommandTextView()
        view.isRichText = false; view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.font = .systemFont(ofSize: 21, weight: .regular)
        view.textColor = .white; view.insertionPointColor = NSColor(Palette.accent)
        view.drawsBackground = false; view.textContainerInset = NSSize(width: 0, height: 6)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator
        scroll.documentView = view
        update(view, coordinator: context.coordinator)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? CommandTextView else { return }
        update(view, coordinator: context.coordinator)
        if context.coordinator.lastFocus != focusToken {
            context.coordinator.lastFocus = focusToken
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }
    private func update(_ view: CommandTextView, coordinator: Coordinator) {
        if view.string != text { view.string = text; view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0)) }
        view.onSubmit = onSubmit; view.onMove = onMove; view.onSwitchColumn = onSwitchColumn; view.onEscape = onEscape
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommandInput
        var lastFocus: UUID?
        init(_ parent: CommandInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string; parent.onChange()
        }
    }
}

final class CommandTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onMove: ((Int) -> Void)?
    var onSwitchColumn: (() -> Bool)?
    var onEscape: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        // Let the input method finish composing Chinese before interpreting Return/arrows.
        if hasMarkedText() { super.keyDown(with: event); return }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 36 where !modifiers.contains(.shift), 76 where !modifiers.contains(.shift): onSubmit?()
        case 125 where modifiers.isEmpty: onMove?(1)
        case 126 where modifiers.isEmpty: onMove?(-1)
        case 48 where modifiers.isEmpty || modifiers == .shift:
            if onSwitchColumn?() != true { super.keyDown(with: event) }
        case 53: onEscape?()
        default: super.keyDown(with: event)
        }
    }
}

struct OutputText: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let view = NSTextView(); view.isEditable = false; view.isSelectable = true; view.drawsBackground = false
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular); view.textColor = .init(white: 0.87, alpha: 1)
        view.textContainerInset = NSSize(width: 16, height: 14); view.autoresizingMask = [.width]
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.textContainer?.widthTracksTextView = true
        scroll.documentView = view; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let view = scroll.documentView as? NSTextView, view.string != text { view.string = text; view.scrollToBeginningOfDocument(nil) }
    }
}

struct ScriptEditor: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = NSTextView(); view.isRichText = false; view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular); view.textColor = .textColor
        view.textContainerInset = NSSize(width: 7, height: 7); view.autoresizingMask = [.width]
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator; view.string = text; scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let view = scroll.documentView as? NSTextView, view.string != text { view.string = text }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptEditor
        init(_ parent: ScriptEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let view = notification.object as? NSTextView { parent.text = view.string } }
    }
}

enum ShortcutKind: String { case combination, sequence }

struct ShortcutControl: View {
    @Binding var hotKey: HotKey?
    var allowsClear = true
    var onRecording: (Bool) -> Void = { _ in }
    var body: some View {
        HStack(spacing: 8) {
            Picker("触发方式", selection: Binding(get: { hotKey?.isSequence == true ? ShortcutKind.sequence : .combination }, set: { kind in
                let first = hotKey?.first ?? KeyStroke(keyCode: 55)
                if kind == .sequence { hotKey = HotKey(first: first, second: first) }
                else { hotKey = first.modifiers != 0 && KeyStroke.modifierMask(for: first.keyCode) == nil ? HotKey(first: first) : .launcher }
            })) {
                Text("组合键").tag(ShortcutKind.combination)
                Text("连续按键").tag(ShortcutKind.sequence)
            }.labelsHidden().frame(width: 110)
            ShortcutRecorder(hotKey: $hotKey, kind: hotKey?.isSequence == true ? .sequence : .combination, allowsClear: allowsClear, onRecording: onRecording).frame(width: 195, height: 27)
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var hotKey: HotKey?
    var kind = ShortcutKind.combination
    var allowsClear = true
    var onRecording: (Bool) -> Void = { _ in }
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(); button.bezelStyle = .rounded; button.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.value = hotKey; button.kind = kind; button.allowsClear = allowsClear
        button.onChange = { hotKey = $0 }; button.onRecording = onRecording
        if !button.recording { button.title = hotKey?.display ?? "录制快捷键" }
    }
}
final class RecorderButton: NSButton {
    var value: HotKey?
    var onChange: ((HotKey?) -> Void)?
    var onRecording: ((Bool) -> Void)?
    var recording = false
    var kind = ShortcutKind.combination { didSet { if oldValue != kind { finish() } } }
    var allowsClear = true
    private var taps = KeyTapRecognizer()
    private var firstTap: (KeyStroke, TimeInterval)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self; action = #selector(beginRecording)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    @objc private func beginRecording() {
        firstTap = nil; taps.reset(modifiers: KeyStroke.modifiers(from: NSEvent.modifierFlags))
        recording = true; title = kind == .sequence ? "按下第一个键…" : "按下组合键…"
        onRecording?(true); window?.makeFirstResponder(self)
    }
    override func mouseDown(with event: NSEvent) { beginRecording() }
    override func resignFirstResponder() -> Bool {
        finish(); return true
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { finish() }; super.viewWillMove(toWindow: newWindow) }
    private func finish() {
        guard recording else { return }; recording = false; title = value?.display ?? "录制快捷键"; onRecording?(false)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }; return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        if event.keyCode == 51 || event.keyCode == 117 {
            if allowsClear { value = nil; onChange?(nil) }; finish(); return
        }
        if kind == .sequence { recordTap(event); return }
        let value = HotKey(event: event)
        guard value.modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else { title = "请加 ⌘ / ⌥ / ⌃"; return }
        self.value = value; onChange?(value); finish()
    }
    override func keyUp(with event: NSEvent) {
        if recording && kind == .sequence { recordTap(event) } else { super.keyUp(with: event) }
    }
    override func flagsChanged(with event: NSEvent) {
        if recording && kind == .sequence { recordTap(event) } else { super.flagsChanged(with: event) }
    }
    private func recordTap(_ event: NSEvent) {
        switch taps.consume(KeyInput(event), at: event.timestamp) {
        case .none: break
        case .interrupted: firstTap = nil; title = "重新按第一个键…"
        case .tap(let stroke):
            if let firstTap, event.timestamp - firstTap.1 <= 1 {
                let shortcut = HotKey(first: firstTap.0, second: stroke)
                value = shortcut; onChange?(shortcut); finish()
            } else { firstTap = (stroke, event.timestamp); title = "\(stroke.display) → 第二个键…" }
        }
    }
}
