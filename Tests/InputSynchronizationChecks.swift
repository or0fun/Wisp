import SwiftUI

@main enum InputSynchronizationChecks {
    @MainActor static func main() {
        testRefreshKeepsMarkedTextAndCandidateSelection()
        testNativeEditsPublishWithoutAcceptingStaleModelEchoes()
        testExplicitNewSessionClearsAnUncommittedDraftEvenWhenModelIsEmpty()
        testScriptRefreshKeepsCompositionAndStillLoadsExplicitReplacements()
        print("PASS: composition and candidate selection survive refreshes; native edits and cursor survive stale echoes; explicit session reset and script replacement still work.")
    }
    private static func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
        precondition(lhs == rhs, "Values differ: \(lhs) vs \(rhs)", file: file, line: line)
    }
    private static func checkTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
        precondition(value, "Expected true", file: file, line: line)
    }
    private static func checkFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
        precondition(!value, "Expected false", file: file, line: line)
    }
    @MainActor private static func command(_ text: Binding<String>, token: UUID) -> CommandInput {
        CommandInput(text: text, resetToken: token, focusToken: UUID(), onSubmit: {}, onMove: { _ in }, onSwitchColumn: { _ in false }, onEscape: {}, onChange: {})
    }

    @MainActor private static func testRefreshKeepsMarkedTextAndCandidateSelection() {
        _ = NSApplication.shared
        let token = UUID()
        let coordinator = Self.command(.constant("original"), token: token).makeCoordinator()
        let view = CommandTextView()
        coordinator.resetIfNeeded(view, text: "original", token: token)
        view.setMarkedText("zhongwen", selectedRange: NSRange(location: 2, length: 3), replacementRange: NSRange(location: NSNotFound, length: 0))
        let composition = view.string, selection = view.selectedRange(), marked = view.markedRange()
        checkTrue(view.hasMarkedText())
        for _ in 0..<20 { coordinator.resetIfNeeded(view, text: "original", token: token) }
        checkEqual(view.string, composition)
        checkEqual(view.selectedRange(), selection)
        checkEqual(view.markedRange(), marked)
    }

    @MainActor private static func testNativeEditsPublishWithoutAcceptingStaleModelEchoes() {
        _ = NSApplication.shared
        var modelText = "old"
        let token = UUID()
        let binding = Binding(get: { modelText }, set: { modelText = $0 })
        let coordinator = Self.command(binding, token: token).makeCoordinator()
        let view = CommandTextView()
        coordinator.resetIfNeeded(view, text: modelText, token: token)
        view.string = "A🙂中文B"
        let selection = NSRange(location: 1, length: 2)
        view.setSelectedRange(selection)
        coordinator.resetIfNeeded(view, text: "old", token: token)
        checkEqual(view.string, "A🙂中文B")
        checkEqual(view.selectedRange(), selection)
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        checkEqual(modelText, "A🙂中文B")
        coordinator.resetIfNeeded(view, text: "old", token: token)
        checkEqual(view.string, modelText)
        checkEqual(view.selectedRange(), selection)
    }

    @MainActor private static func testExplicitNewSessionClearsAnUncommittedDraftEvenWhenModelIsEmpty() {
        _ = NSApplication.shared
        let token = UUID()
        let coordinator = Self.command(.constant(""), token: token).makeCoordinator()
        let view = CommandTextView()
        coordinator.resetIfNeeded(view, text: "", token: token)
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        checkTrue(view.hasMarkedText())
        coordinator.resetIfNeeded(view, text: "", token: UUID())
        checkEqual(view.string, "")
        checkFalse(view.hasMarkedText())
        checkEqual(view.selectedRange(), NSRange(location: 0, length: 0))
    }

    @MainActor private static func testScriptRefreshKeepsCompositionAndStillLoadsExplicitReplacements() {
        _ = NSApplication.shared
        var modelText = "print('hello')"
        let editor = ScriptEditor(text: Binding(get: { modelText }, set: { modelText = $0 }))
        let coordinator = editor.makeCoordinator()
        let view = NSTextView()
        coordinator.update(view, text: modelText)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        view.setMarkedText("zhushi", selectedRange: NSRange(location: 6, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let composition = view.string, selection = view.selectedRange()
        coordinator.update(view, text: modelText)
        checkEqual(view.string, composition)
        checkTrue(view.hasMarkedText())
        checkEqual(view.selectedRange(), selection)
        view.insertText("注释", replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        checkEqual(modelText, view.string)
        checkFalse(view.hasMarkedText())
        coordinator.update(view, text: "print('replacement')")
        checkEqual(view.string, "print('replacement')")
    }
}
