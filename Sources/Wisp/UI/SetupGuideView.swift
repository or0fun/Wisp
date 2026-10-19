import SwiftUI

struct SetupGuideView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var setup: SetupState
    let openSettings: (SettingsPage) -> Void
    let testShortcut: () -> Void
    let close: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                AppMark(size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text("让 Wisp 随时响应你").font(.system(size: 24, weight: .semibold))
                    Text("先配置快捷入口，再验证后台唤起。AI 工具可以稍后连接。").foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(28)
            HStack(spacing: 8) {
                ForEach(SetupPage.allCases, id: \.self) { item in
                    Button { setup.page = item } label: {
                        Text("\(item.rawValue + 1)  \(item.title)").frame(maxWidth: .infinity).padding(11)
                            .background(setup.page == item ? Palette.accent.opacity(0.2) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch setup.page {
                    case .shortcuts: shortcuts
                    case .permissions: permissions
                    case .tools: tools
                    }
                    if let error = setup.storageError { Text(error).foregroundStyle(.orange) }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("稍后配置") { close(false) }
                Spacer()
                if setup.page != .shortcuts { Button("上一步") { setup.page = SetupPage(rawValue: setup.page.rawValue - 1)! } }
                if setup.page != .tools { Button("下一步") { setup.page = SetupPage(rawValue: setup.page.rawValue + 1)! }.buttonStyle(.borderedProminent).tint(Palette.accent) }
                else { Button(setup.notice(model.settings) == nil ? "开始使用" : "先使用基础功能") { close(true) }.buttonStyle(.borderedProminent).tint(Palette.accent) }
            }.padding(20)
        }.frame(minWidth: 760, minHeight: 670).background(Palette.background).preferredColorScheme(.dark)
    }
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("从你习惯的按键开始").font(.title2.bold())
            Text("组合键同时按下；连续按键先按下并松开第一个键，再按第二个。相同按键连按两次就是双击。").foregroundStyle(.secondary)
            card {
                keyRow("快捷动作", model.settings.launcherHotKey)
                keyRow("剪贴板历史", model.settings.clipboardHotKey)
                keyRow("工作流程", model.settings.workflowsHotKey)
                Divider()
                Text("连续按键间隔：\(Int(model.settings.keySequenceInterval * 1000)) ms。建议双击 ⌘ 或 ⌥；普通字母仍会输入到当前应用。").font(.callout).foregroundStyle(.secondary)
                Button("修改快捷键") { openSettings(.general) }
            }
            Text("唤起后输入内容，用 ↑ ↓ 选择豆包、Codex、搜索或工作流程，回车执行。输入 3+4 可直接看到计算结果。").foregroundStyle(.secondary)
        }
    }
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("让连续按键在其他应用中生效").font(.title2.bold())
            Text("辅助功能权限用于后台连续按键与自动粘贴。组合快捷键、搜索和剪贴板记录可先使用。").foregroundStyle(.secondary)
            card {
                statusRow("系统实际授权", setup.accessibilityGranted ? "已生效" : "未生效", ok: setup.accessibilityGranted)
                statusRow("连续按键监听", setup.monitor.rawValue, ok: setup.monitor == .listening || setup.monitor == .notNeeded)
                statusRow("安全输入", setup.secureInput ? "开启，连续按键暂时停用" : "未开启", ok: !setup.secureInput)
                if let date = setup.lastBackgroundEvent { Text("最近后台键盘事件：\(date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("前往辅助功能授权") { if !SetupState.openAccessibilitySettings() { model.status = "请手动打开系统设置 → 隐私与安全性 → 辅助功能" } }
                    Button("显示当前应用", action: SetupState.revealApplication)
                    Button("重新检测") { model.onRefreshPermissions?() }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("1. 打开「系统设置 → 隐私与安全性 → 辅助功能」，找到 Wisp 并开启。")
                Text("2. 列表没有应用时，点「＋」添加下方路径的应用。授权后返回，本页会自动检测。")
                Text("3. 开关已开但这里仍显示未生效：移除列表中的旧应用条目，再用「＋」添加当前应用并开启，然后退出并重新打开 Wisp。").foregroundStyle(.orange)
                Text(Bundle.main.bundleURL.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                if Bundle.main.object(forInfoDictionaryKey: "WispAdHocBuild") as? Bool == true {
                    Text("当前是临时签名的本地开发版本；覆盖更新后旧授权可能失效。正式分发应使用固定的开发者签名。").font(.caption).foregroundStyle(.secondary)
                }
            }.font(.callout)
            card {
                Text("验证真实后台唤起").font(.headline)
                Text("点击后收起窗口并切换到其他应用，在 20 秒内按 \(model.settings.launcherHotKey.display)。只有从后台唤起成功才会通过。").foregroundStyle(.secondary)
                Text(setup.testMessage).font(.callout).foregroundStyle(setup.verifiedShortcut == nil ? Color.secondary : Color.green)
                Button(setup.testing ? "正在等待后台按键…" : "开始后台唤起测试", action: testShortcut)
                    .disabled(CommandLine.arguments.contains("--preview") || setup.testing || (model.settings.launcherHotKey.isSequence && (!setup.accessibilityGranted || setup.secureInput || setup.monitor != .listening)))
            }
        }
    }
    private var tools: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("按需连接你的工具").font(.title2.bold())
            Text("这些配置可选。配置检查不会发送输入内容，也不会调用模型。").foregroundStyle(.secondary)
            card {
                Label("豆包", systemImage: "bubble.left.and.bubble.right").font(.headline)
                Text(model.settings.doubaoMode == .handoff ? "当前使用应用 / 网页：输入会先复制，打开豆包后可按 ⌘V 带入。" : "当前使用 API 模式，请在设置中检查接口、模型和密钥。")
                Button("配置豆包") { openSettings(.ai) }
            }
            card {
                Label("AI 写脚本", systemImage: "sparkles").font(.headline)
                Text(model.settings.scriptModel?.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? "已填写模型：\(model.settings.scriptModel!.model)。连接和密钥将在实际生成时验证。" : "填写 OpenAI 兼容的 Base URL、API Key 和模型名称，即可在流程编辑器中使用「AI 写脚本」。")
                Text("生成的脚本先展示供你编辑；保存流程后才用于执行。").font(.caption).foregroundStyle(.secondary)
                Button("配置脚本模型") { openSettings(.ai) }
            }
            card {
                Label("Codex", systemImage: "terminal").font(.headline)
                Text((try? ActionService.codexExecutable(settings: model.settings)) == nil ? "尚未找到 Codex CLI，可在设置中填写路径。" : "已找到 Codex CLI；请确认已在终端执行 codex login，登录状态尚未验证。")
                Button("配置 Codex") { openSettings(.ai) }
            }
            Button("创建 / 编辑工作流程") { openSettings(.workflows) }
            Text("之后可从主界面问号、菜单栏或设置重新打开配置引导。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func keyRow(_ title: String, _ key: HotKey) -> some View { HStack { Text(title); Spacer(); Text(key.display).font(.system(.body, design: .monospaced)) } }
    private func statusRow(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack { Text(title); Spacer(); Label(value, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(ok ? .green : .orange) }.font(.callout)
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}
