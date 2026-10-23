import SwiftUI
import ServiceManagement

enum SettingsPage: String, CaseIterable {
    case general = "通用", clipboard = "剪贴板", search = "搜索引擎", ai = "AI 助手", workflows = "工作流程"
    var symbol: String { switch self { case .general: return "slider.horizontal.3"; case .clipboard: return "clipboard"; case .search: return "magnifyingglass"; case .ai: return "sparkles"; case .workflows: return "point.3.connected.trianglepath.dotted" } }
    var subtitle: String { switch self { case .general: return "让工具融入你的使用习惯"; case .clipboard: return "为剪贴板留一点记忆"; case .search: return "为常用网站设置搜索入口"; case .ai: return "连接你的 AI 工具"; case .workflows: return "输入一次，让脚本接着完成" } }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft: Settings
    @State private var page = SettingsPage.general
    @State private var message = ""
    @State private var error = false
    @State private var workflowID: UUID?
    @State private var apiKey = ""
    @State private var originalAPIKey = ""
    @State private var keyLoaded = false
    @State private var scriptAPIKey = ""
    @State private var originalScriptKey = ""
    @State private var scriptKeyLoaded = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var clearHistory = false
    @State private var accessibilityGranted = AXIsProcessTrusted()
    init(model: AppModel) { self.model = model; _draft = State(initialValue: model.settings); _workflowID = State(initialValue: model.settings.workflows.first?.id) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(page.rawValue).font(.system(size: 25, weight: .semibold))
                        Text(page.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 26).padding(.top, 25).padding(.bottom, 10)
                    Group {
                        switch page {
                        case .general: general
                        case .clipboard: clipboard
                        case .search: search
                        case .ai: ai
                        case .workflows: workflows
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                Text(message.isEmpty ? (hasUnsavedChanges ? "有未保存的更改" : "所有设置已保存") : message)
                    .font(.system(size: 11)).foregroundStyle(error ? .orange : .secondary).lineLimit(2).textSelection(.enabled)
                Spacer()
                Button("还原更改") { draft = model.settings; apiKey = originalAPIKey; scriptAPIKey = originalScriptKey; message = ""; error = false }
                Button("保存设置", action: save).keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent).tint(Palette.accent)
            }.padding(16)
        }.frame(minWidth: 940, minHeight: 680).preferredColorScheme(.dark)
        .onChange(of: page) { _, value in if value == .ai { loadKey() } }
        .onChange(of: model.requestedSettingsPage) { _, value in if let value { page = value; model.requestedSettingsPage = nil } }
        .onAppear { if let value = model.requestedSettingsPage { page = value; model.requestedSettingsPage = nil; if value == .ai { loadKey() } } }
        .onChange(of: model.settings) { old, value in if draft == old { draft = value } }
        .onChange(of: draft) { _, _ in message = ""; error = false }
        .onChange(of: apiKey) { _, _ in message = ""; error = false }
        .onChange(of: scriptAPIKey) { _, _ in message = ""; error = false }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in accessibilityGranted = AXIsProcessTrusted() }
        .alert("清空全部历史？", isPresented: $clearHistory) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { model.clipboard.clear() }
        } message: { Text("包括置顶内容，删除后无法恢复。") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) { AppMark(size: 35); VStack(alignment: .leading, spacing: 3) { Text("Wisp").font(.headline); Text("让操作更轻一点").font(.system(size: 10)).foregroundStyle(.secondary) } }.padding(.bottom, 25).padding(.top, 18)
            ForEach(SettingsPage.allCases, id: \.self) { item in
                Button { page = item } label: {
                    Label(item.rawValue, systemImage: item.symbol).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 11)
                        .foregroundStyle(page == item ? .white : .secondary).background(page == item ? Palette.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
            Spacer()
            Button { model.onSetup?(.shortcuts) } label: {
                Label("配置引导", systemImage: "questionmark.circle").font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 11)
                    .foregroundStyle(.secondary).contentShape(Rectangle())
            }.buttonStyle(.plain).help("查看快捷入口、后台唤起和工具连接").padding(.bottom, 10)
            Text("本地优先 · 键盘优先").font(.system(size: 10)).foregroundStyle(.secondary)
            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(16).frame(width: 186).background(.white.opacity(0.025))
    }
    private var general: some View {
        Form {
            Section("全局快捷键") {
                shortcut("快捷动作", value: $draft.launcherHotKey)
                shortcut("剪贴板历史", value: $draft.clipboardHotKey)
                shortcut("工作流程", value: $draft.workflowsHotKey)
                HStack {
                    Text("连续按键最大间隔"); Spacer()
                    Picker("间隔", selection: Binding(get: { draft.keySequenceInterval }, set: { draft.sequenceInterval = $0 })) {
                        Text("200 ms").tag(0.2); Text("400 ms").tag(0.4); Text("600 ms").tag(0.6); Text("800 ms").tag(0.8); Text("1 秒").tag(1.0)
                    }.labelsHidden().frame(width: 120)
                }
                Text("组合键需含 ⌘、⌥ 或 ⌃。连续按键先按下并松开第一个键，再按第二个；同一个键按两次就是双击，例如 ⌘ → ⌘。Esc 取消录制。").font(.caption).foregroundStyle(.secondary)
                Text("连续按键不会拦截原始输入，建议使用修饰键双击，避免影响正常打字。").font(.caption).foregroundStyle(.secondary)
                if draft.hasKeySequences && !accessibilityGranted { Text("连续按键跨应用唤起需要辅助功能授权；当前仅在 Wisp 内生效。").font(.caption).foregroundStyle(.orange) }
            }
            Section("启动与权限") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text("配置引导与后台诊断"); Text("查看真实授权、重新授权步骤与后台唤起测试").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("打开配置引导") { model.onSetup?(.permissions) }
                }
                Toggle("登录时启动", isOn: Binding(get: { loginEnabled }, set: setLogin))
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("辅助功能")
                        Text(accessibilityGranted ? "系统授权已生效；可在配置引导中测试后台唤起" : "系统实际授权未生效；开关已开时，请在配置引导中查看重新授权步骤").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开系统设置") { SetupState.openAccessibilitySettings() }
                }
            }
            Section("本地数据") {
                Text(model.disk.directory.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                HStack { Text("设置、历史和图片保存在这台 Mac").foregroundStyle(.secondary); Spacer(); Button("在 Finder 中显示") { NSWorkspace.shared.open(model.disk.directory) } }
            }
        }.formStyle(.grouped)
    }
    private var clipboard: some View {
        Form {
            Section("历史记录") {
                Toggle("记录剪贴板", isOn: $draft.clipboardEnabled)
                Stepper("最多保存 \(draft.historyLimit) 条", value: $draft.historyLimit, in: 20...5000, step: 20)
                Stepper("保留 \(draft.retentionDays) 天", value: $draft.retentionDays, in: 1...365)
                Text("置顶内容不受保留天数影响，仍计入总条数与 256 MB 总容量上限。文本最大 2 MB，图片最大 20 MB。").font(.caption).foregroundStyle(.secondary)
                Toggle("回车选中后粘贴到原应用", isOn: $draft.pasteOnSelect)
                Text("默认只复制选中内容。自动粘贴需要辅助功能授权；未授权时仍会复制。").font(.caption).foregroundStyle(.secondary)
            }
            Section("忽略这些应用") {
                Text("每行一个 Bundle ID，可在下方添加当前打开的应用。").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $draft.excludedApps).font(.system(size: 12, design: .monospaced)).frame(height: 100)
                Menu("添加正在运行的应用") {
                    ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier!) { if let id = app.bundleIdentifier, !draft.excludedApps.components(separatedBy: "\n").contains(id) { draft.excludedApps += "\n" + id } }
                    }
                }
                Text("自动跳过带隐藏或临时标记的内容。未标记的敏感文本仍可能被记录，请按需暂停或排除应用。").font(.caption).foregroundStyle(.secondary)
            }
            Section { Button("清空全部剪贴板历史…", role: .destructive) { clearHistory = true } }
        }.formStyle(.grouped)
    }
    private var search: some View {
        Form {
            Section {
                Text("URL 中使用 {query} 代表输入内容，应用会自动编码。输入「关键词 + 空格 + 内容」可直接定位搜索引擎。").font(.callout).foregroundStyle(.secondary)
            }
            ForEach($draft.searchEngines) { $engine in
                Section {
                    HStack { TextField("名称", text: $engine.name); TextField("关键词", text: $engine.keyword).frame(width: 100); Button(role: .destructive) { draft.searchEngines.removeAll { $0.id == engine.id } } label: { Image(systemName: "trash") } }
                    TextField("搜索 URL", text: $engine.urlTemplate).font(.system(size: 11, design: .monospaced))
                }
            }
            Button { draft.searchEngines.append(SearchEngine(name: "自定义搜索", keyword: "", urlTemplate: "https://example.com/search?q={query}")) } label: { Label("添加搜索引擎", systemImage: "plus") }
        }.formStyle(.grouped)
    }
    private var ai: some View {
        Form {
            Section("问题问答") {
                Picker("问答模型", selection: Binding(get: { draft.questionProvider ?? .modelAPI }, set: { draft.questionProvider = $0 })) {
                    ForEach(QuestionProvider.allCases, id: \.self) { provider in Text(provider.title).tag(provider) }
                }
                Text("首页输入以 ? 或 ？ 结尾，按回车提问。默认使用下方通用模型配置；仅请求所选服务，失败时不会自动切换。").font(.caption).foregroundStyle(.secondary)
            }
            Section("问答与脚本模型（OpenAI 兼容）") {
                TextField("Base URL", text: Binding(get: { (draft.scriptModel ?? ModelConfiguration()).baseURL }, set: { value in var config = draft.scriptModel ?? ModelConfiguration(); config.baseURL = value; draft.scriptModel = config }))
                TextField("模型名称", text: Binding(get: { draft.scriptModel?.model ?? "" }, set: { value in var config = draft.scriptModel ?? ModelConfiguration(); config.model = value; draft.scriptModel = config }))
                SecureField("API Key（本地无鉴权服务可留空）", text: $scriptAPIKey).disabled(!scriptKeyLoaded)
                if !scriptKeyLoaded { Button("读取模型密钥", action: loadKey) }
                Text("此模型用于通用问答和「AI 写脚本」。Base URL 自动拼接 /chat/completions；密钥单独存入系统钥匙串。问答只发送当前问题，按回车才请求。").font(.caption).foregroundStyle(.secondary)
            }
            Section("豆包") {
                Picker("处理方式", selection: $draft.doubaoMode) { Text("唤起应用 / 网页").tag(DoubaoMode.handoff); Text("API 直接处理").tag(DoubaoMode.api) }
                if draft.doubaoMode == .handoff {
                    TextField("网页 / 链接", text: $draft.doubaoURL)
                    HStack {
                        TextField("应用路径（可选，优先打开）", text: $draft.doubaoAppPath)
                        Button("选择…") { pickApplication() }
                        if !draft.doubaoAppPath.isEmpty { Button("清除") { draft.doubaoAppPath = "" } }
                    }
                    Toggle("应用打开后自动粘贴（需辅助功能权限）", isOn: $draft.doubaoPaste)
                    Text("输入先复制到剪贴板，再打开所选应用或网页。网页模式请手动 ⌘V；应用模式可尝试自动粘贴，发送前请检查输入框。").font(.caption).foregroundStyle(.secondary)
                } else {
                    TextField("Chat Completions 地址", text: $draft.apiEndpoint).font(.system(size: 11, design: .monospaced))
                    TextField("Model ID / Endpoint ID", text: $draft.apiModel)
                    SecureField("API Key（保存在系统钥匙串）", text: $apiKey).disabled(!keyLoaded)
                    if !keyLoaded { Button("读取钥匙串", action: loadKey) }
                    Text("使用火山方舟兼容的 Chat Completions API。仅执行豆包动作时发送输入内容，可能产生服务费用。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Codex CLI") {
                TextField("可执行文件路径（留空自动发现）", text: $draft.codexPath)
                HStack {
                    Text((try? ActionService.codexExecutable(settings: draft)) ?? "尚未发现 Codex CLI").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                TextField("模型（留空使用 CLI 默认配置）", text: $draft.codexModel)
                HStack { Text("执行超时（秒）"); Spacer(); TextField("180", value: $draft.codexTimeout, format: .number).frame(width: 90) }
                Text("先在终端执行 codex login。任务在独立临时目录运行，使用 read-only 沙箱；结果在面板内显示，可复制。").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var workflows: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(draft.workflows) { workflow in
                            Button { workflowID = workflow.id } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(workflow.name).font(.system(size: 12, weight: .medium)).lineLimit(1); Spacer(); if !workflow.enabled { Image(systemName: "pause.circle") } }
                                    Text(workflow.hotKey?.display ?? "\(workflow.steps.count) 个步骤").font(.system(size: 10)).foregroundStyle(.secondary)
                                }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(workflowID == workflow.id ? Palette.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button { let workflow = Workflow(); draft.workflows.append(workflow); workflowID = workflow.id } label: { Label("新建流程", systemImage: "plus").frame(maxWidth: .infinity) }
            }.padding(12).frame(width: 180)
            Divider()
            ForEach($draft.workflows) { $workflow in
                if workflow.id == workflowID {
                    WorkflowEditor(workflow: $workflow, modelConfiguration: model.settings.scriptModel, onRecording: { model.onRecording?($0) }, onDelete: {
                        draft.workflows.removeAll { $0.id == workflow.id }; workflowID = draft.workflows.first?.id
                    })
                }
            }
            if workflowID == nil { Text("创建一个流程开始").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }
    private func shortcut(_ label: String, value: Binding<HotKey>) -> some View {
        HStack { Text(label); Spacer(); ShortcutControl(hotKey: Binding(get: { value.wrappedValue }, set: { if let key = $0 { value.wrappedValue = key } }), allowsClear: false, onRecording: { model.onRecording?($0) }) }
    }
    private var hasUnsavedChanges: Bool {
        draft != model.settings || (keyLoaded && apiKey != originalAPIKey) || (scriptKeyLoaded && scriptAPIKey != originalScriptKey)
    }
    private func save() {
        var changedKeys: [(String, String)] = []
        do {
            try draft.validate()
            if keyLoaded && apiKey != originalAPIKey { try Keychain.save(apiKey); changedKeys.append(("doubao-api-key", originalAPIKey)) }
            if scriptKeyLoaded && scriptAPIKey != originalScriptKey { try Keychain.save(scriptAPIKey, account: LLMService.scriptKeyAccount); changedKeys.append((LLMService.scriptKeyAccount, originalScriptKey)) }
            try model.save(draft)
            originalAPIKey = apiKey; originalScriptKey = scriptAPIKey
            message = draft.hasKeySequences && !accessibilityGranted ? "设置已保存；连续按键跨应用生效需辅助功能授权" : "设置已保存，快捷键已更新"; error = false
        } catch { for (account, previous) in changedKeys { try? Keychain.save(previous, account: account) }; message = error.localizedDescription; self.error = true }
    }
    private func loadKey() {
        do {
            if !keyLoaded { apiKey = try Keychain.read(); originalAPIKey = apiKey; keyLoaded = true }
            if !scriptKeyLoaded { scriptAPIKey = try Keychain.read(account: LLMService.scriptKeyAccount); originalScriptKey = scriptAPIKey; scriptKeyLoaded = true }
        }
        catch { message = error.localizedDescription; self.error = true }
    }
    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            message = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许 Wisp" : "登录启动设置已更新"; error = false
        } catch { message = "登录启动设置失败：\(error.localizedDescription)"; self.error = true }
    }
    private func pickApplication() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { draft.doubaoAppPath = url.path }
    }
}

private struct WorkflowEditor: View {
    @Binding var workflow: Workflow
    let modelConfiguration: ModelConfiguration?
    let onRecording: (Bool) -> Void
    let onDelete: () -> Void
    @State private var confirmDelete = false
    @State private var generationStep: WorkflowStep?
    var body: some View {
        Form {
            Section("流程信息") {
                TextField("名称", text: $workflow.name)
                TextField("说明", text: $workflow.summary)
                TextField("关键词（可选）", text: $workflow.keyword)
                Toggle("启用流程", isOn: $workflow.enabled)
                HStack {
                    Text("独立快捷键"); Spacer()
                    ShortcutControl(hotKey: $workflow.hotKey, onRecording: onRecording)
                    if workflow.hotKey != nil { Button("清除") { workflow.hotKey = nil } }
                }
                TextField("工作目录", text: $workflow.workingDirectory)
                HStack { Text("整个流程超时（秒）"); Spacer(); TextField("60", value: $workflow.timeout, format: .number).frame(width: 75) }
                Toggle("自动复制最终结果", isOn: $workflow.copyOutput)
            }
            Section {
                Text("每步读取 stdin，上一步 stdout 传给下一步。不超过 32,000 字节的输入同时可用环境变量 WISP_INPUT（兼容 PERSONALAI_INPUT）读取。脚本以当前用户权限运行。").font(.caption).foregroundStyle(.secondary)
            }
            ForEach($workflow.steps) { $step in
                Section {
                    HStack {
                        TextField("步骤名称", text: $step.name)
                        Button { generationStep = step } label: { Label("AI 写脚本", systemImage: "sparkles") }
                        Button { move(step.id, by: -1) } label: { Image(systemName: "arrow.up") }.help("上移")
                        Button { move(step.id, by: 1) } label: { Image(systemName: "arrow.down") }.help("下移")
                        Button(role: .destructive) { workflow.steps.removeAll { $0.id == step.id } } label: { Image(systemName: "trash") }.disabled(workflow.steps.count == 1)
                    }
                    TextField("解释器绝对路径", text: $step.interpreter).font(.system(size: 11, design: .monospaced))
                    ScriptEditor(text: $step.script).frame(minHeight: 130)
                }
            }
            HStack {
                Button { workflow.steps.append(WorkflowStep()) } label: { Label("添加脚本步骤", systemImage: "plus") }
                Spacer()
                Button("删除流程…", role: .destructive) { confirmDelete = true }
            }
        }.formStyle(.grouped)
        .sheet(item: $generationStep) { step in
            ScriptGeneratorView(step: step, configuration: modelConfiguration) { code in
                if let index = workflow.steps.firstIndex(where: { $0.id == step.id }) { workflow.steps[index].script = code }
            }
        }
        .alert("删除「\(workflow.name)」？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: onDelete)
        }
    }
    private func move(_ id: UUID, by offset: Int) {
        guard let index = workflow.steps.firstIndex(where: { $0.id == id }), workflow.steps.indices.contains(index + offset) else { return }
        workflow.steps.swapAt(index, index + offset)
    }
}
