import SwiftUI

struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var setup: SetupState
    @State private var confirmClear = false
    var body: some View {
        VStack(spacing: 0) {
            header
            input
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            if let result = model.result {
                resultView(result)
            } else if model.running {
                VStack(spacing: 17) {
                    ProgressView().controlSize(.large)
                    Text(model.resultTitle + " 正在处理").font(.system(size: 18, weight: .medium))
                    Text(model.status).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Button("停止执行", action: model.cancel).buttonStyle(.bordered)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.mode == .clipboard { clipboardBody }
            else { actionBody }
            footer
        }
        .background(Palette.background)
        .preferredColorScheme(.dark)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .alert("清空全部剪贴板历史？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { clipboard.clear() }
        } message: { Text("包括置顶内容及保存的图片，无法撤销。系统剪贴板和原始文件不受影响。") }
    }
    private var header: some View {
        HStack(spacing: 10) {
            AppMark(size: 26)
            Text("Wisp").font(.system(size: 13, weight: .semibold))
            Text("/ 你的效率入口").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            Spacer()
            ForEach(Array(PanelMode.allCases.enumerated()), id: \.element) { index, mode in
                Button { model.switchMode(mode) } label: {
                    HStack(spacing: 5) { Image(systemName: mode.symbol); Text(mode.title); Text("⌘\(index + 1)").opacity(0.45) }
                        .font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 7)
                        .foregroundStyle(model.mode == mode ? .white : Palette.secondary)
                        .background(model.mode == mode ? .white.opacity(0.085) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
            }
            Button { model.onSetup?(.shortcuts) } label: { Image(systemName: "questionmark.circle").foregroundStyle(Palette.secondary).padding(4) }.buttonStyle(.plain).help("配置引导")
            Button { model.onSettings?() } label: { Image(systemName: "gearshape").foregroundStyle(Palette.secondary).padding(4) }.buttonStyle(.plain).help("设置 ⌘,")
        }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)
    }
    private var input: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: model.mode == .clipboard ? "magnifyingglass" : "arrow.turn.down.right")
                .font(.system(size: 21, weight: .light)).foregroundStyle(Palette.accent).frame(width: 27).padding(.top, 9)
            ZStack(alignment: .topLeading) {
                if model.query.isEmpty { Text(model.placeholder).font(.system(size: 21)).foregroundStyle(.white.opacity(0.28)).padding(.top, 7).allowsHitTesting(false) }
                CommandInput(text: $model.query, resetToken: model.inputSessionID, focusToken: model.focusToken, onSubmit: model.execute, onMove: model.move, onSwitchColumn: model.switchActionColumn, onEscape: { model.onHide?() }, onChange: model.inputChanged)
            }.frame(height: 62)
        }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)
    }
    private var actionBody: some View {
        HStack(spacing: 0) {
            if model.mode == .actions {
                let columns = model.actionColumns
                actionColumn("快捷动作", symbol: "sparkles", indices: columns[0], emptyMessage: "当前关键词已匹配其他列入口。")
                Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
                actionColumn("工作流程", symbol: "point.3.connected.trianglepath.dotted", indices: columns[1], emptyMessage: model.settings.workflows.contains(where: \.enabled) ? "当前关键词未匹配工作流程。" : "添加并启用工作流程，直接处理输入内容。", canAddWorkflow: !model.settings.workflows.contains(where: \.enabled))
                Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
                actionColumn("文件搜索", symbol: "doc.text.magnifyingglass", indices: columns[2], emptyMessage: model.hasActionKeyword ? "当前输入已匹配快捷关键词。" : (model.localSearch.searchingFiles ? "正在搜索本机文件…" : model.localSearch.fileMessage), isFileSearch: true)
            } else {
                actionColumn(model.lockedWorkflow == nil ? "选择工作流程" : "已绑定的工作流程", symbol: "point.3.connected.trianglepath.dotted", indices: Array(model.actions.indices), emptyMessage: "暂无启用的流程，请在设置中添加。", canAddWorkflow: true)
                Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
                workflowHelp
            }
        }.frame(maxHeight: .infinity)
    }
    private func actionColumn(_ title: String, symbol: String, indices: [Int], emptyMessage: String, canAddWorkflow: Bool = false, isFileSearch: Bool = false) -> some View {
        let actions = model.actions
        let rows = indices.filter { actions.indices.contains($0) }.map { (index: $0, action: actions[$0]) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
                Spacer()
                if isFileSearch && model.localSearch.searchingFiles { ProgressView().controlSize(.mini) }
                Text("\(rows.count)\(isFileSearch && model.localSearch.moreFiles ? "+" : "") 项").font(.system(size: 10))
            }.foregroundStyle(Palette.secondary).padding(.horizontal, 12).padding(.top, 3)
            if rows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 25, weight: .light)).foregroundStyle(Palette.accent.opacity(0.7))
                    Text(emptyMessage).font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                    if isFileSearch && model.query.isEmpty { Text("使用 macOS 文件索引，按文件名查找。支持文件夹。").font(.system(size: 10)).foregroundStyle(Palette.secondary.opacity(0.7)).multilineTextAlignment(.center) }
                    if canAddWorkflow {
                        Button("添加工作流程") { model.requestedSettingsPage = .workflows; model.onSettings?() }.buttonStyle(.bordered)
                    }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(rows, id: \.action.id) { row in
                                actionRow(row.action, index: row.index).id(row.action.id)
                            }
                        }
                    }.onChange(of: model.selection) { _, value in
                        if let row = rows.first(where: { $0.index == value }) { proxy.scrollTo(row.action.id, anchor: .center) }
                    }.onChange(of: model.query) { _, _ in
                        if let row = rows.first(where: { $0.index == model.selection }) { proxy.scrollTo(row.action.id, anchor: .center) }
                    }
                }
            }
            if isFileSearch && !rows.isEmpty {
                Text("回车打开 · 右键在 Finder 中显示").font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.horizontal, 12)
            } else if model.mode == .actions && title == "快捷动作" {
                Text(model.localSearch.loadingApplications ? "正在读取应用列表…" : "输入应用名可直接打开本机应用").font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.horizontal, 12)
            }
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private var workflowHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 24, weight: .light)).foregroundStyle(Palette.accent).padding(.top, 2)
            Text("把重复交给流程").font(.system(size: 19, weight: .medium))
            Text("输入内容，选择流程。脚本依次执行，结果自动传给下一步。")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            Divider().overlay(.white.opacity(0.05))
            Text("↑ ↓ 选择   ·   ↵ 执行\n⇧ ↵ 换行   ·   esc 收起")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary).lineSpacing(7)
            Spacer(minLength: 0)
            Text("在设置中为每个流程绑定独立快捷键。")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary.opacity(0.7)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 24).padding(.vertical, 20).frame(width: 255, alignment: .leading)
    }
    private func actionRow(_ action: ActionItem, index: Int) -> some View {
        Button { model.executeAction(id: action.id) } label: {
            HStack(spacing: 12) {
                Group {
                    if let item = action.localResult {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().scaledToFit().padding(4)
                    } else { Image(systemName: action.symbol).font(.system(size: 18)).foregroundStyle(Palette.tint(action.tint)) }
                }.frame(width: 38, height: 38).background(Palette.tint(action.tint).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(action.title).font(.system(size: action.id == "calculator" ? 23 : 14, weight: .medium)).foregroundStyle(.white.opacity(0.92)).lineLimit(1).truncationMode(action.localResult == nil ? .tail : .middle)
                    Text(action.subtitle).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if !action.keyword.isEmpty { KeyCap(text: action.keyword) }
                if model.selection == index { Image(systemName: "return").font(.system(size: 12)).foregroundStyle(Palette.accent) }
            }.padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
                .background(model.selection == index ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(model.selection == index ? Palette.accent.opacity(0.2) : .clear))
        }.buttonStyle(.plain).help(action.title + " · " + action.subtitle)
            .accessibilityAddTraits(model.selection == index ? .isSelected : [])
            .contextMenu {
                if let item = action.localResult {
                    Button("打开") { model.openLocal(item) }
                    Button("在 Finder 中显示") { model.openLocal(item, reveal: true) }
                }
            }
    }
    private var clipboardBody: some View {
        HStack(spacing: 0) {
            VStack(spacing: 7) {
                clipboardCategories
                HStack {
                    Text("\(model.clips.count) 条记录").font(.system(size: 10))
                    Spacer()
                    Button { clipboard.paused.toggle() } label: { Image(systemName: clipboard.paused ? "play.fill" : "pause.fill") }.help(clipboard.paused ? "恢复记录" : "暂停记录")
                    Button { confirmClear = true } label: { Image(systemName: "trash") }.help("清空全部历史")
                }.buttonStyle(.plain).foregroundStyle(Palette.secondary).padding(.horizontal, 12).padding(.vertical, 6)
                if model.clips.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: model.clipboardCategory.symbol).font(.system(size: 30))
                        Text(clipboardEmptyMessage).font(.system(size: 12))
                    }.foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                                    Button { model.executeClip(id: clip.id) } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: clip.symbol).foregroundStyle(Palette.accent).frame(width: 24)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(clip.title).font(.system(size: 12)).lineLimit(1).foregroundStyle(.white.opacity(0.9))
                                                Text(clip.source + " · " + clip.createdAt.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                            }; Spacer(minLength: 0)
                                            if clip.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Palette.accent) }
                                        }.padding(10).contentShape(Rectangle()).background(model.selection == index ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    }.buttonStyle(.plain).id(clip.id)
                                    .contextMenu {
                                        Button(clip.pinned ? "取消置顶" : "置顶") { clipboard.togglePin(clip.id) }
                                        Button("删除", role: .destructive) { clipboard.delete(clip.id) }
                                    }
                                }
                            }
                        }.onChange(of: model.selection) { _, value in if model.clips.indices.contains(value) { proxy.scrollTo(model.clips[value].id, anchor: .center) } }
                        .onChange(of: model.clipboardCategory) { _, _ in if let clip = model.clips.first { proxy.scrollTo(clip.id, anchor: .top) } }
                        .onChange(of: model.query) { _, _ in if let clip = model.clips.first { proxy.scrollTo(clip.id, anchor: .top) } }
                    }
                }
            }.padding(12).frame(width: 410)
            Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
            VStack(alignment: .leading, spacing: 10) {
                if let clip = model.selectedClip {
                    HStack {
                        Text("内容预览").font(.system(size: 10)).foregroundStyle(Palette.secondary); Spacer()
                        Button { clipboard.togglePin(clip.id) } label: { Image(systemName: clip.pinned ? "pin.fill" : "pin") }.help("置顶 ⌘P")
                        Button { clipboard.delete(clip.id); model.selection = max(0, min(model.selection, model.clips.count - 1)) } label: { Image(systemName: "trash") }.help("删除 ⌘⌫")
                    }.buttonStyle(.plain).foregroundStyle(Palette.secondary).padding(.horizontal, 16).padding(.top, 17)
                    if clip.kind == .image, let url = clipboard.imageURL(for: clip), let image = NSImage(contentsOf: url) {
                        Image(nsImage: image).resizable().scaledToFit().padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else { OutputText(text: clip.kind == .files ? clip.files.joined(separator: "\n") : clip.text) }
                    Text(clip.source + "  ·  " + clip.createdAt.formatted()).font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.horizontal, 16).padding(.bottom, 14)
                } else { Text("你的剪贴板，有了记忆").font(.system(size: 14)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private var clipboardCategories: some View {
        HStack(spacing: 3) {
            ForEach(ClipboardCategory.allCases, id: \.self) { category in
                Button { model.switchClipboardCategory(category) } label: {
                    Text(category.title).font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 8).contentShape(Rectangle())
                        .foregroundStyle(model.clipboardCategory == category ? .white : Palette.secondary)
                        .background(model.clipboardCategory == category ? Palette.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).accessibilityAddTraits(model.clipboardCategory == category ? .isSelected : [])
            }
        }.padding(3).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain).accessibilityLabel("剪贴板分类")
    }
    private var clipboardEmptyMessage: String {
        if !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "当前分类没有匹配的记录" }
        return model.clipboardCategory == .all ? "复制一些内容，从这里开始" : "暂无\(model.clipboardCategory.title)记录"
    }
    private func resultView(_ result: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label(model.resultTitle + " · 处理结果", systemImage: "checkmark.circle").foregroundStyle(Palette.tint("green"))
                Spacer()
                Button("返回") { model.result = nil; model.focusToken = UUID() }
                Button("复制结果", action: model.copyResult).buttonStyle(.borderedProminent).tint(Palette.accent)
            }.font(.system(size: 11)).padding(14)
            OutputText(text: result)
        }.frame(maxHeight: .infinity)
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
            HStack(spacing: 7) {
                Circle().fill(model.isError || clipboard.error != nil ? .orange : (clipboard.paused || !model.settings.clipboardEnabled ? Palette.secondary : Palette.tint("green"))).frame(width: 5, height: 5)
                Text(clipboard.error ?? model.status).font(.system(size: 10)).foregroundStyle(model.isError ? .orange : Palette.secondary).lineLimit(1).help(clipboard.error ?? model.status)
                Spacer()
                if let notice = setup.notice(model.settings) { Button(notice) { model.onSetup?(.permissions) }.font(.system(size: 10)).foregroundStyle(.orange).buttonStyle(.plain) }
                if clipboard.paused || !model.settings.clipboardEnabled { Text("剪贴板记录已暂停").font(.system(size: 10)).foregroundStyle(.orange) }
                if model.mode == .clipboard { KeyCap(text: "↵"); Text(model.settings.pasteOnSelect ? "粘贴到原应用" : "复制选中项").font(.system(size: 10)).foregroundStyle(Palette.secondary) }
                else {
                    if model.mode == .actions, !model.running, model.result == nil, model.actionColumns.filter({ !$0.isEmpty }).count > 1 {
                        KeyCap(text: "Tab"); Text("切列").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                    KeyCap(text: "↑ ↓"); Text("选择").font(.system(size: 10)).foregroundStyle(Palette.secondary); KeyCap(text: "↵"); Text("执行").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
            }.padding(.horizontal, 22).frame(height: 43)
        }
    }
}
