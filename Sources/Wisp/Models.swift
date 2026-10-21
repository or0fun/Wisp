import AppKit
import Carbon

enum PanelMode: String, CaseIterable {
    case actions, clipboard, workflows
    var title: String { switch self { case .actions: return "快捷动作"; case .clipboard: return "剪贴板"; case .workflows: return "工作流程" } }
    var symbol: String { switch self { case .actions: return "sparkles"; case .clipboard: return "clipboard"; case .workflows: return "point.3.connected.trianglepath.dotted" } }
}

struct HotKey: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
    var second: KeyStroke?
    static let launcher = HotKey(keyCode: 49, modifiers: UInt32(optionKey))
    static let clipboard = HotKey(keyCode: 9, modifiers: UInt32(optionKey | cmdKey))
    static let workflows = HotKey(keyCode: 49, modifiers: UInt32(optionKey | cmdKey))
    var display: String {
        guard let second else { return first.display }
        return first == second ? "双击 \(first.display)" : "\(first.display) → \(second.display)"
    }
    var first: KeyStroke { KeyStroke(keyCode: keyCode, modifiers: modifiers) }
    var isSequence: Bool { second != nil }
    init(keyCode: UInt32, modifiers: UInt32, second: KeyStroke? = nil) { self.keyCode = keyCode; self.modifiers = modifiers; self.second = second }
    init(first: KeyStroke, second: KeyStroke? = nil) { self.init(keyCode: first.keyCode, modifiers: first.modifiers, second: second) }
    init(event: NSEvent) { self.init(first: KeyStroke(event: event)) }
}

struct KeyStroke: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String {
        if let symbol = Self.modifierSymbol(for: keyCode), modifiers == 0 { return symbol }
        let keys: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",49:"Space",50:"`",122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12"]
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + (keys[keyCode] ?? "Key \(keyCode)")
    }
    init(keyCode: UInt32, modifiers: UInt32 = 0) { self.keyCode = Self.canonicalCode(keyCode); self.modifiers = modifiers }
    init(event: NSEvent) {
        keyCode = Self.canonicalCode(UInt32(event.keyCode))
        modifiers = Self.modifiers(from: event.modifierFlags)
    }
    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
    static func canonicalCode(_ code: UInt32) -> UInt32 {
        switch code { case 54: return 55; case 60: return 56; case 61: return 58; case 62: return 59; default: return code }
    }
    static func modifierMask(for code: UInt32) -> UInt32? {
        switch canonicalCode(code) { case 55: return UInt32(cmdKey); case 56: return UInt32(shiftKey); case 58: return UInt32(optionKey); case 59: return UInt32(controlKey); default: return nil }
    }
    static func modifierSymbol(for code: UInt32) -> String? {
        switch canonicalCode(code) { case 55: return "⌘"; case 56: return "⇧"; case 58: return "⌥"; case 59: return "⌃"; default: return nil }
    }
}

struct SearchEngine: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var keyword: String
    var urlTemplate: String
    static let defaults = [
        SearchEngine(name: "Google", keyword: "g", urlTemplate: "https://www.google.com/search?q={query}"),
        SearchEngine(name: "百度", keyword: "bd", urlTemplate: "https://www.baidu.com/s?wd={query}"),
        SearchEngine(name: "GitHub", keyword: "gh", urlTemplate: "https://github.com/search?q={query}")
    ]
    func url(for input: String) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard urlTemplate.contains("{query}"),
              let encoded = input.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: urlTemplate.replacingOccurrences(of: "{query}", with: encoded)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw AppError.message("搜索地址必须是包含 {query} 的 HTTP(S) URL。")
        }
        return url
    }
}

struct WorkflowStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "脚本步骤"
    var interpreter = "/bin/zsh"
    var script = "cat"
}

struct Workflow: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "新流程"
    var keyword = ""
    var summary = ""
    var hotKey: HotKey?
    var workingDirectory = "~"
    var timeout: Double = 60
    var copyOutput = true
    var enabled = true
    var steps = [WorkflowStep()]
    static var defaults: [Workflow] {
        [Workflow(name: "整理文本", keyword: "trim", summary: "去掉首尾空白，连续空行合并为一行", steps: [
            WorkflowStep(name: "清理空白", interpreter: "/usr/bin/python3", script: "import sys, re\ntext = sys.stdin.read().strip()\nprint(re.sub(r'\\n{3,}', '\\n\\n', text))")
        ]), Workflow(name: "JSON 格式化", keyword: "json", summary: "格式化 JSON，保留中文字符", steps: [
            WorkflowStep(name: "格式化 JSON", interpreter: "/usr/bin/python3", script: "import sys, json\nprint(json.dumps(json.load(sys.stdin), ensure_ascii=False, indent=2))")
        ])]
    }
}

enum DoubaoMode: String, Codable, CaseIterable { case handoff, api }

struct Settings: Codable, Equatable {
    var launcherHotKey = HotKey.launcher
    var clipboardHotKey = HotKey.clipboard
    var workflowsHotKey = HotKey.workflows
    var sequenceInterval: Double?
    var scriptModel: ModelConfiguration?
    var keySequenceInterval: Double { sequenceInterval ?? 0.4 }
    var hasKeySequences: Bool { ([launcherHotKey, clipboardHotKey, workflowsHotKey] + workflows.filter(\.enabled).compactMap(\.hotKey)).contains(where: \.isSequence) }
    var clipboardEnabled = true
    var historyLimit = 300
    var retentionDays = 30
    var excludedApps = "com.agilebits.onepassword7\ncom.1password.1password\ncom.apple.keychainaccess"
    var pasteOnSelect = false
    var searchEngines = SearchEngine.defaults
    var workflows = Workflow.defaults
    var codexPath = ""
    var codexModel = ""
    var codexTimeout: Double = 180
    var doubaoMode = DoubaoMode.handoff
    var doubaoURL = "https://www.doubao.com/chat/"
    var doubaoAppPath = ""
    var doubaoPaste = false
    var apiEndpoint = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
    var apiModel = ""

    func validate() throws {
        guard (20...5000).contains(historyLimit), (1...365).contains(retentionDays) else { throw AppError.message("历史上限应为 20–5000 条，保留期限为 1–365 天。") }
        guard (10...900).contains(codexTimeout) else { throw AppError.message("Codex 超时应为 10–900 秒。") }
        guard (0.2...1).contains(keySequenceInterval) else { throw AppError.message("连续按键间隔应为 0.2–1 秒。") }
        var shortcuts: Set<HotKey> = []
        let allKeys = [launcherHotKey, clipboardHotKey, workflowsHotKey] + workflows.filter(\.enabled).compactMap(\.hotKey)
        for key in allKeys {
            if !key.isSequence {
                guard KeyStroke.modifierMask(for: key.keyCode) == nil, key.modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else { throw AppError.message("组合快捷键至少包含 ⌘、⌥ 或 ⌃ 和一个普通按键。") }
            }
            guard shortcuts.insert(key).inserted else { throw AppError.message("快捷键 \(key.display) 重复，请更换。") }
        }
        let combinations = Set(allKeys.filter { !$0.isSequence }.map(\.first))
        for key in allKeys where key.isSequence {
            guard !combinations.contains(key.first), !combinations.contains(key.second!) else { throw AppError.message("连续快捷键「\(key.display)」包含已被组合快捷键占用的按键，请更换。") }
        }
        if let scriptModel { try scriptModel.validate() }
        var keywords = Set<String>()
        for search in searchEngines {
            guard !search.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("搜索名称不能为空。") }
            _ = try search.url(for: "验证 & 搜索")
            try validateKeyword(search.keyword, used: &keywords)
        }
        for workflow in workflows {
            guard !workflow.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !workflow.steps.isEmpty else { throw AppError.message("流程需要名称和至少一个脚本步骤。") }
            guard (1...900).contains(workflow.timeout) else { throw AppError.message("流程超时应为 1–900 秒。") }
            for step in workflow.steps {
                guard step.interpreter.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: step.interpreter), !step.script.isEmpty else { throw AppError.message("步骤「\(step.name)」需要可执行解释器的绝对路径及脚本。") }
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: (workflow.workingDirectory as NSString).expandingTildeInPath, isDirectory: &isDir), isDir.boolValue else { throw AppError.message("流程「\(workflow.name)」的工作目录不存在。") }
            if workflow.enabled { try validateKeyword(workflow.keyword, used: &keywords) }
        }
        guard let endpoint = URL(string: apiEndpoint), endpoint.scheme == "https", endpoint.host != nil else { throw AppError.message("API 地址必须使用 HTTPS。") }
        guard let handoff = URL(string: doubaoURL), ["http", "https", "doubao"].contains(handoff.scheme ?? "") else { throw AppError.message("豆包地址需要有效的网页地址或 doubao:// 链接。") }
    }

    private func validateKeyword(_ keyword: String, used: inout Set<String>) throws {
        guard !keyword.isEmpty else { return }
        guard !keyword.contains(where: \.isWhitespace), used.insert(keyword.lowercased()).inserted else { throw AppError.message("关键词不能含空格或重复：\(keyword)") }
    }
}

enum ClipKind: String, Codable { case text, image, files }
enum ClipboardCategory: CaseIterable {
    case all, text, image, files
    var title: String { switch self { case .all: return "全部"; case .text: return "文字"; case .image: return "图片"; case .files: return "文件" } }
    var symbol: String { switch self { case .all: return "clipboard"; case .text: return "text.alignleft"; case .image: return "photo"; case .files: return "doc.on.doc" } }
    func contains(_ clip: Clip) -> Bool {
        switch self { case .all: return true; case .text: return clip.kind == .text; case .image: return clip.kind == .image; case .files: return clip.kind == .files }
    }
}
struct Clip: Codable, Identifiable {
    var id = UUID()
    var kind: ClipKind
    var text: String
    var imageFile: String?
    var files: [String] = []
    var createdAt = Date()
    var source: String
    var pinned = false
    var title: String { kind == .image ? "图片" : String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)) }
    var symbol: String { switch kind { case .text: return "text.alignleft"; case .image: return "photo"; case .files: return "doc.on.doc" } }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): return message } }
}
