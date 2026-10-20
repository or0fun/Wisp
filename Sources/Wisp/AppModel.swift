import AppKit

@MainActor final class AppModel: ObservableObject {
    @Published var settings: Settings
    @Published var mode: PanelMode = .actions
    @Published var query = ""
    @Published var selection = 0
    @Published var result: String?
    @Published var resultTitle = ""
    @Published var running = false
    @Published var status = "随时调用你的工具"
    @Published var isError = false
    @Published var focusToken = UUID()
    @Published var lockedWorkflow: UUID?
    @Published var requestedSettingsPage: SettingsPage?
    let disk: DiskStore
    let clipboard: ClipboardStore
    let setup: SetupState
    var onHide: (() -> Void)?
    var onSettings: (() -> Void)?
    var onPaste: (() -> Void)?
    var onHandoff: ((String) -> Void)?
    var onSave: ((Settings) throws -> Void)?
    var onRecording: ((Bool) -> Void)?
    var onSetup: ((SetupPage) -> Void)?
    var onRefreshPermissions: (() -> Void)?
    var onDidSave: ((Settings, Settings) -> Void)?
    private var task: Task<Void, Never>?
    private var runner: ProcessRunner?

    init(disk: DiskStore) {
        self.disk = disk
        setup = SetupState(disk: disk)
        var settings = Settings(); var loadError: String?
        do { settings = try disk.load(Settings.self, from: "settings.json") ?? Settings(); try settings.validate() }
        catch { loadError = error.localizedDescription }
        settings.historyLimit = min(5000, max(20, settings.historyLimit))
        settings.retentionDays = min(365, max(1, settings.retentionDays))
        self.settings = settings
        clipboard = ClipboardStore(disk: disk, settings: settings)
        if let loadError { status = loadError; isError = true }
    }
    var clips: [Clip] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return clipboard.items.filter { term.isEmpty || $0.text.localizedCaseInsensitiveContains(term) || $0.source.localizedCaseInsensitiveContains(term) }
    }
    var allActions: [ActionItem] {
        var values = [
            ActionItem(id: "doubao", title: "豆包", subtitle: settings.doubaoMode == .api ? "使用豆包 API 处理输入" : "复制输入并打开豆包", symbol: "bubble.left.and.bubble.right", tint: "blue", keyword: "", destination: .doubao),
            ActionItem(id: "codex", title: "Codex", subtitle: "用本机 Codex CLI 处理，结果在此显示", symbol: "terminal", tint: "green", keyword: "", destination: .codex)
        ]
        values += settings.searchEngines.map { ActionItem(id: $0.id.uuidString, title: $0.name, subtitle: $0.urlTemplate, symbol: "magnifyingglass", tint: "orange", keyword: $0.keyword, destination: .search($0)) }
        values += workflowActions
        if let calculation = Calculator.evaluate(query) {
            let title: String, subtitle: String
            switch calculation {
            case .value(let value): title = value; subtitle = "计算结果 · 回车复制"
            case .issue(let message): title = "计算器"; subtitle = message
            }
            values.insert(ActionItem(id: "calculator", title: title, subtitle: subtitle, symbol: "equal.circle", tint: "green", keyword: "", destination: .calculation(calculation)), at: 0)
        }
        return values
    }
    private var workflowActions: [ActionItem] {
        settings.workflows.filter { $0.enabled && (mode != .workflows || lockedWorkflow == nil || $0.id == lockedWorkflow) }.map {
            ActionItem(id: $0.id.uuidString, title: $0.name, subtitle: $0.summary.isEmpty ? "\($0.steps.count) 个脚本步骤" : $0.summary, symbol: "point.3.connected.trianglepath.dotted", tint: "purple", keyword: $0.keyword, destination: .workflow($0))
        }
    }
    var actions: [ActionItem] {
        let values = mode == .workflows ? workflowActions : allActions
        if let keyword = query.split(separator: " ", maxSplits: 1).first, query.contains(" "), let match = values.first(where: { !$0.keyword.isEmpty && $0.keyword.lowercased() == keyword.lowercased() }) { return [match] }
        return values
    }
    var actionColumns: [[Int]] {
        let values = actions
        return [values.indices.filter { !values[$0].isWorkflow }, values.indices.filter { values[$0].isWorkflow }]
    }
    var rowCount: Int { mode == .clipboard ? clips.count : actions.count }
    var selectedClip: Clip? { guard mode == .clipboard, clips.indices.contains(selection) else { return nil }; return clips[selection] }
    var placeholder: String { switch mode { case .clipboard: return "搜索剪贴板内容或来源应用…"; case .actions: return "输入想法、问题，或 g 搜索内容…"; case .workflows: return "输入内容，交给工作流程…" } }
    func open(_ mode: PanelMode, workflow: UUID? = nil) {
        self.mode = mode; lockedWorkflow = workflow; query = ""; selection = 0
        if !running { result = nil; status = mode == .clipboard ? "内容仅保存在这台 Mac" : "随时调用你的工具"; isError = false }
        focusToken = UUID()
    }
    func switchMode(_ mode: PanelMode) { open(mode) }
    func move(_ delta: Int) {
        guard rowCount > 0 else { return }
        let current = max(0, min(selection, rowCount - 1))
        let rows = mode == .actions ? actionColumns.first(where: { $0.contains(current) }) ?? Array(0..<rowCount) : Array(0..<rowCount)
        let position = rows.firstIndex(of: current) ?? 0
        selection = rows[(position + delta % rows.count + rows.count) % rows.count]
    }
    func switchActionColumn() -> Bool {
        guard mode == .actions, !running, result == nil else { return false }
        let columns = actionColumns
        guard columns.allSatisfy({ !$0.isEmpty }) else { return false }
        let current = columns[0].contains(selection) ? 0 : 1
        let row = columns[current].firstIndex(of: selection) ?? 0
        let target = columns[1 - current]
        selection = target[min(row, target.count - 1)]
        return true
    }
    func inputChanged() { selection = 0; if !running { result = nil } }
    func execute() {
        guard !running else { return }
        if mode == .clipboard {
            guard let clip = selectedClip else { return }
            do { try clipboard.restore(clip); if settings.pasteOnSelect { onPaste?() } else { onHide?() } }
            catch { showError(error) }
            return
        }
        guard actions.indices.contains(selection) else { return }
        let action = actions[selection]
        var input = query
        if !action.keyword.isEmpty, input.lowercased().hasPrefix(action.keyword.lowercased() + " ") { input = String(input.dropFirst(action.keyword.count + 1)) }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "先输入需要处理的内容"; isError = true; focusToken = UUID(); return }
        switch action.destination {
        case .calculation(let calculation):
            switch calculation {
            case .value(let value): clipboard.copyText(value); status = "计算结果已复制"; isError = false
            case .issue(let message): showError(AppError.message(message))
            }
        case .search(let search):
            do { let url = try search.url(for: input); onHide?(); guard NSWorkspace.shared.open(url) else { throw AppError.message("无法打开浏览器。") } }
            catch { showError(error) }
        case .doubao where settings.doubaoMode == .handoff:
            clipboard.copyText(input); onHandoff?(input)
        default: start(action, input: input)
        }
    }
    private func start(_ action: ActionItem, input: String) {
        let runner = ProcessRunner(); self.runner = runner
        running = true; result = nil; resultTitle = action.title; status = "正在处理…"; isError = false
        let settings = self.settings
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.running = false; self.runner = nil; self.task = nil }
            do {
                let output: String
                switch action.destination {
                case .codex: output = try await ActionService.codex(input: input, settings: settings, runner: runner)
                case .doubao: output = try await ActionService.doubao(input: input, settings: settings)
                case .workflow(let workflow):
                    output = try await ActionService.workflow(workflow, input: input, runner: runner) { [weak self] in self?.status = $0 }
                    if workflow.copyOutput { self.clipboard.copyText(output) }
                case .search, .calculation: return
                }
                try Task.checkCancellation()
                self.result = output.isEmpty ? "（流程执行成功，没有文本输出）" : output
                self.status = "处理完成"; self.isError = false
            } catch is CancellationError { self.status = "已取消"; self.isError = false }
            catch { self.showError(error) }
        }
    }
    func cancel() { runner?.cancel(); task?.cancel() }
    func copyResult() { if let result { clipboard.copyText(result); status = "结果已复制" } }
    func showError(_ error: Error) { status = error.localizedDescription; isError = true }
    func save(_ updated: Settings) throws {
        try updated.validate()
        try onSave?(updated)
        do { try disk.save(updated, to: "settings.json") }
        catch { try? onSave?(settings); throw error }
        let previous = settings
        settings = updated; clipboard.settings = updated; clipboard.prune()
        status = "设置已保存"; isError = false
        onDidSave?(previous, updated)
    }
}
