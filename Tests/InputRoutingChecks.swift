import AppKit

@main enum InputRoutingChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WispRoutingChecks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = try DiskStore(directory: directory)
        let clipboardChanges = NSPasteboard.general.changeCount
        let service = LocalSearchService(applicationRoots: [], fileScopes: [directory])
        let model = AppModel(disk: disk, localSearchService: service)
        defer { model.stopLocalSearch() }
        func check(_ value: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) { precondition(value, message, file: file, line: line) }
        for text in ["https://example.com", " HTTP://localhost:8080/a?x=1 ", "https://example.com/search?", "www.example.com/path"] {
            guard case .link = InputIntent.detect(text) else { preconditionFailure("Expected a link: \(text)") }
        }
        check(InputIntent.detect("www.example.com") == .link(URL(string: "https://www.example.com")!), "www links should use HTTPS")
        for text in ["javascript:alert(1)", "file:///tmp/a", "mailto:a@example.com", "README.md", "search https://example.com", "", "?", "？？"] {
            check(InputIntent.detect(text) == nil, "Unexpected intent for \(text)")
        }
        for text in ["为什么？", "what is Swift?", "  多行\n问题？ \n"] { check(InputIntent.detect(text) == .question, "Question suffix missing") }
        check(InputIntent.detect("a? b") == nil, "An internal question mark should not trigger QA")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as! [String: Any]
        legacy.removeValue(forKey: "questionProvider")
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(decoded.resolvedQuestionProvider == .modelAPI, "Legacy settings should default to the chosen general API")

        model.open(.actions)
        let originalLink = "  https://example.com/search?  "
        model.query = originalLink; model.inputChanged()
        check(model.actions[model.selection].id == "open-url", "Link should be the default action even when ending in ?")
        var opened: [URL] = [], hideCount = 0
        model.urlOpener = { opened.append($0); return true }; model.onHide = { hideCount += 1 }
        model.execute()
        check(opened == [URL(string: "https://example.com/search?")!] && hideCount == 0, "Enter should open the parsed URL without invoking the callback that restores the previous app")
        check(model.query == originalLink, "Opening a URL must not rewrite input")
        model.urlOpener = { _ in false }; model.execute()
        check(model.isError && hideCount == 0, "Failed URL opens must leave the panel visible")

        var setupCount = 0
        model.onSettings = { setupCount += 1 }
        model.query = "这是什么？"; model.inputChanged(); model.execute()
        check(setupCount == 1 && model.requestedSettingsPage == .ai && !model.running, "Missing model configuration should open AI settings without a request")
        model.settings.scriptModel = ModelConfiguration(baseURL: "http://127.0.0.1:1/v1", model: "fixture")
        var requests: [String] = []
        model.questionResponder = { input, settings, _ in
            check(settings.resolvedQuestionProvider == .modelAPI, "Wrong question provider")
            requests.append(input)
            return "# 回答\n原样保留 Markdown"
        }
        let question = " 为什么天空是蓝色的？ "
        model.query = question; model.inputChanged()
        let lateFile = LocalSearchResult(url: directory.appendingPathComponent("late.txt"), title: "late.txt", kind: .file)
        service.onUpdate?(LocalSearchSnapshot(files: [lateFile]))
        check(model.actions[model.selection].id == "ask-question", "Late search results must not steal the default QA selection")
        check(requests.isEmpty, "Typing must never make a model request")
        model.execute(); model.execute()
        try await waitUntil { !model.running }
        check(requests == [question], "Repeated Return while running should not submit duplicate requests")
        check(model.result == "# 回答\n原样保留 Markdown" && model.resultTitle == "问大模型", "QA output should be shown without script extraction")
        check(model.query == question, "The answer must not rewrite the original question")
        check(LLMService.questionMessages(question) == [["role": "user", "content": question]], "Only the question should be sent")

        model.query = "g 为什么？"; model.inputChanged()
        check(model.inputIntent == nil && model.actions.count == 1 && model.actions[0].title == "Google", "Explicit search keywords must take precedence")
        model.query = "json {}？"; model.inputChanged()
        check(model.inputIntent == nil && model.actions.count == 1 && model.actions[0].isWorkflow, "Explicit workflow keywords must take precedence")
        model.open(.workflows); model.query = "为什么？"; model.inputChanged()
        check(model.inputIntent == nil && model.actions.allSatisfy(\.isWorkflow), "Workflow mode must keep its own input semantics")
        model.open(.clipboard); model.query = "https://example.com?"; model.inputChanged()
        check(model.inputIntent == nil, "Clipboard search must not launch links or QA")

        model.open(.actions); model.query = "能取消吗？"; model.inputChanged()
        model.questionResponder = { _, _, _ in try await Task.sleep(for: .seconds(10)); return "late" }
        model.execute(); model.cancel()
        try await waitUntil { !model.running }
        check(model.result == nil && model.status == "已取消", "Cancellation must not show a late answer")
        model.questionResponder = { _, _, _ in throw AppError.message("fixture failure") }
        model.execute(); try await waitUntil { !model.running }
        check(model.isError && model.status == "fixture failure", "Provider failures should be shown without fallback")
        check(NSPasteboard.general.changeCount == clipboardChanges, "Routing checks must leave the system clipboard unchanged")
        if let index = CommandLine.arguments.firstIndex(of: "--endpoint"), CommandLine.arguments.indices.contains(index + 1) {
            let endpoint = URL(string: CommandLine.arguments[index + 1])!
            var fixtureSettings = Settings()
            fixtureSettings.scriptModel = ModelConfiguration(baseURL: endpoint.absoluteString, model: "fixture-model")
            let answer = try await ActionService.answer(input: "为什么？", settings: fixtureSettings, runner: ProcessRunner(), keyReader: { account in
                check(account == LLMService.scriptKeyAccount, "Question API should share the configured model key")
                return "fixture-key"
            })
            check(answer == "这是本地模拟回答。", "Unexpected HTTP fixture response")
        }
        print("PASS: URL/question detection and precedence, default selection, explicit Enter, missing configuration, QA output, stale search results, cancellation, errors, legacy settings; system clipboard unchanged.")
    }
    @MainActor private static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        precondition(condition(), "Timed out waiting for the action")
    }
}
