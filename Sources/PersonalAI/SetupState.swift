import AppKit
import Carbon

enum SetupPage: Int, CaseIterable {
    case shortcuts, permissions, tools
    var title: String { switch self { case .shortcuts: "快捷入口"; case .permissions: "后台唤起"; case .tools: "连接工具" } }
}

enum SequenceMonitorState: String {
    case notNeeded = "未配置连续按键", permissionRequired = "等待辅助功能授权", listening = "全局监听已建立"
    case failed = "全局监听建立失败", preview = "预览模式仅监听应用内", recording = "录制时暂停监听"
}

@MainActor final class SetupState: ObservableObject {
    private struct Progress: Codable { var seen = false; var completed = false }
    @Published var page: SetupPage = .shortcuts
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var secureInput = false
    @Published private(set) var monitor: SequenceMonitorState = .notNeeded
    @Published private(set) var lastBackgroundEvent: Date?
    @Published private(set) var verifiedShortcut: HotKey?
    @Published private(set) var testMessage = "尚未进行后台测试"
    @Published private(set) var testing = false
    @Published private(set) var storageError: String?
    private var progress: Progress
    private let disk: DiskStore
    private var expected: HotKey?
    private var deadline: Date?
    private let permissionProbe: () -> Bool
    private let secureInputProbe: () -> Bool
    var needsFirstRun: Bool { !progress.seen }
    var completed: Bool { progress.completed }

    init(disk: DiskStore, permissionProbe: @escaping () -> Bool = { AXIsProcessTrusted() }, secureInputProbe: @escaping () -> Bool = { IsSecureEventInputEnabled() }) {
        self.disk = disk; self.permissionProbe = permissionProbe; self.secureInputProbe = secureInputProbe
        do { progress = try disk.load(Progress.self, from: "setup.json") ?? Progress() }
        catch { progress = Progress(); storageError = error.localizedDescription }
        refresh()
    }
    func presented() { progress.seen = true; persist() }
    func finish() { progress.seen = true; progress.completed = true; persist() }
    private func persist() {
        do { try disk.save(progress, to: "setup.json"); storageError = nil }
        catch { storageError = error.localizedDescription }
    }
    func refresh() {
        let trusted = permissionProbe(), secure = secureInputProbe()
        if accessibilityGranted != trusted { accessibilityGranted = trusted }
        if secureInput != secure { secureInput = secure }
        if !trusted && verifiedShortcut?.isSequence == true { verifiedShortcut = nil }
        if testing, let deadline, Date() >= deadline { cancelTest("未收到匹配的后台快捷键。检查授权、按键间隔或冲突后重试。") }
    }
    func updateMonitor(_ state: SequenceMonitorState) { if monitor != state { monitor = state } }
    func receivedBackgroundEvent() { lastBackgroundEvent = Date() }
    func beginTest(_ key: HotKey) {
        expected = key; deadline = Date().addingTimeInterval(20); testing = true
        testMessage = "等待后台按下 \(key.display)，20 秒内有效；点击菜单栏可返回引导。"
    }
    func triggered(_ key: HotKey, background: Bool) {
        guard testing, background, let deadline, Date() < deadline, key == expected else { return }
        verifiedShortcut = key; cancelTest("已通过实际后台唤起测试：\(key.display)")
    }
    func cancelTest(_ message: String) { testing = false; deadline = nil; expected = nil; testMessage = message }
    func configurationChanged() { verifiedShortcut = nil; if testing { cancelTest("快捷键已变更，请重新测试。") } }
    func needsPermission(_ settings: Settings) -> Bool { settings.hasKeySequences || settings.pasteOnSelect || (settings.doubaoMode == .handoff && settings.doubaoPaste && !settings.doubaoAppPath.isEmpty) }
    func notice(_ settings: Settings) -> String? {
        if needsPermission(settings) && !accessibilityGranted { return "后台唤起 / 自动粘贴待授权" }
        if settings.hasKeySequences && secureInput { return "安全输入开启，连续按键已暂停" }
        if settings.hasKeySequences && monitor == .failed { return monitor.rawValue }
        return nil
    }
    static let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
    @discardableResult static func openAccessibilitySettings() -> Bool { NSWorkspace.shared.open(accessibilityURL) }
    static func revealApplication() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
}
