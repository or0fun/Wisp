import AppKit

enum KeyInput {
    case down(KeyStroke, repeatEvent: Bool)
    case up(UInt32)
    case flags(UInt32, modifiers: UInt32)
    case interrupt
    init(_ event: NSEvent) {
        switch event.type {
        case .keyDown: self = .down(KeyStroke(event: event), repeatEvent: event.isARepeat)
        case .keyUp: self = .up(UInt32(event.keyCode))
        case .flagsChanged: self = .flags(UInt32(event.keyCode), modifiers: KeyStroke.modifiers(from: event.modifierFlags))
        default: self = .interrupt
        }
    }
}

/// Recognizes completed taps, never text. Holding a modifier for a normal shortcut is not a tap.
struct KeyTapRecognizer {
    enum Result { case none, interrupted, tap(KeyStroke) }
    private var pressed = Set<UInt32>()
    private var ordinary: (KeyStroke, TimeInterval)?
    private var modifier: (KeyStroke, TimeInterval)?
    private var flags: UInt32 = 0
    mutating func reset(modifiers: UInt32 = 0) {
        pressed.removeAll(); ordinary = nil; modifier = nil; flags = modifiers
    }
    mutating func consume(_ input: KeyInput, at time: TimeInterval) -> Result {
        switch input {
        case .interrupt: reset(modifiers: flags); return .interrupted
        case .down(let stroke, let repeatEvent):
            modifier = nil
            if repeatEvent || !pressed.isEmpty { pressed.insert(stroke.keyCode); ordinary = nil; return .interrupted }
            pressed.insert(stroke.keyCode); ordinary = (stroke, time); return .none
        case .up(let code):
            pressed.remove(code)
            guard let candidate = ordinary, candidate.0.keyCode == code else { return .none }
            ordinary = nil
            guard pressed.isEmpty, time >= candidate.1, time - candidate.1 <= 0.5 else { return .interrupted }
            return .tap(candidate.0)
        case .flags(let rawCode, let current):
            let previous = flags; flags = current
            guard pressed.isEmpty else { modifier = nil; return .none }
            guard let mask = KeyStroke.modifierMask(for: rawCode) else { modifier = nil; return .interrupted }
            let code = KeyStroke.canonicalCode(rawCode)
            if current == mask && previous & mask == 0 {
                modifier = (KeyStroke(keyCode: code), time)
            } else if current == 0, previous == mask, let candidate = modifier, candidate.0.keyCode == code {
                modifier = nil
                guard time >= candidate.1, time - candidate.1 <= 0.5 else { return .interrupted }
                return .tap(candidate.0)
            } else { modifier = nil }
            return .none
        }
    }
}

struct KeySequenceMatcher {
    var interval: TimeInterval = 0.4
    private var pending: (KeyStroke, TimeInterval)?
    mutating func reset() { pending = nil }
    mutating func consume(_ stroke: KeyStroke, at time: TimeInterval, shortcuts: [HotKey]) -> Int? {
        if let pending, time >= pending.1, time - pending.1 <= interval,
           let index = shortcuts.firstIndex(where: { $0.first == pending.0 && $0.second == stroke }) {
            self.pending = nil; return index
        }
        pending = shortcuts.contains(where: { $0.first == stroke }) ? (stroke, time) : nil
        return nil
    }
}
