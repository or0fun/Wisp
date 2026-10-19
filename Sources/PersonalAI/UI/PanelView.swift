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
            Text("PersonalAI").font(.system(size: 13, weight: .semibold))
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
                CommandInput(text: $model.query, focusToken: model.focusToken, onSubmit: model.execute, onMove: model.move, onEscape: { model.onHide?() }, onChange: model.inputChanged)
            }.frame(height: 62)
        }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)
    }
    private var actionBody: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.lockedWorkflow == nil ? (model.mode == .workflows ? "选择工作流程" : "使用输入内容") : "已绑定的工作流程")
                    Spacer(); Text("\(model.actions.count) 项")
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondary).padding(.horizontal, 12)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                                actionRow(action, index: index).id(action.id)
                            }
                        }
                    }.onChange(of: model.selection) { _, value in if model.actions.indices.contains(value) { proxy.scrollTo(model.actions[value].id, anchor: .center) } }
                }
                if model.actions.isEmpty { Text("暂无启用的流程，请在设置中添加。").foregroundStyle(Palette.secondary).padding(12) }
            }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: model.mode == .workflows ? "point.3.connected.trianglepath.dotted" : "sparkle")
                    .font(.system(size: 24, weight: .light)).foregroundStyle(Palette.accent).padding(.top, 2)
                Text(model.mode == .workflows ? "把重复交给流程" : "从一个想法开始").font(.system(size: 19, weight: .medium))
                Text(model.mode == .workflows ? "输入内容，选择流程。脚本依次执行，结果自动传给下一步。" : "输入内容，选择 AI、搜索或工作流程。用键盘把想法交给合适的工具。")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                Divider().overlay(.white.opacity(0.05))
                Text("↑ ↓ 选择   ·   ↵ 执行\n⇧ ↵ 换行   ·   esc 收起")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary).lineSpacing(7)
                Spacer(minLength: 0)
                Text(model.mode == .workflows ? "在设置中为每个流程绑定独立快捷键。" : "试试：g macOS 快捷键\n也可以直接粘贴一整段内容。")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary.opacity(0.7)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 24).padding(.vertical, 20).frame(width: 255, alignment: .leading)
        }.frame(maxHeight: .infinity)
    }
    private func actionRow(_ action: ActionItem, index: Int) -> some View {
        Button { model.selection = index; model.execute() } label: {
            HStack(spacing: 12) {
                Image(systemName: action.symbol).font(.system(size: 18)).foregroundStyle(Palette.tint(action.tint))
                    .frame(width: 38, height: 38).background(Palette.tint(action.tint).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(action.title).font(.system(size: action.id == "calculator" ? 23 : 14, weight: .medium)).foregroundStyle(.white.opacity(0.92))
                    Text(action.subtitle).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if !action.keyword.isEmpty { KeyCap(text: action.keyword) }
                if model.selection == index { Image(systemName: "return").font(.system(size: 12)).foregroundStyle(Palette.accent) }
            }.padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
                .background(model.selection == index ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(model.selection == index ? Palette.accent.opacity(0.2) : .clear))
        }.buttonStyle(.plain)
    }
    private var clipboardBody: some View {
        HStack(spacing: 0) {
            VStack(spacing: 7) {
                HStack {
                    Text("\(model.clips.count) 条记录").font(.system(size: 10))
                    Spacer()
                    Button { clipboard.paused.toggle() } label: { Image(systemName: clipboard.paused ? "play.fill" : "pause.fill") }.help(clipboard.paused ? "恢复记录" : "暂停记录")
                    Button { confirmClear = true } label: { Image(systemName: "trash") }.help("清空历史")
                }.buttonStyle(.plain).foregroundStyle(Palette.secondary).padding(.horizontal, 12).padding(.vertical, 6)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                                Button { model.selection = index; model.execute() } label: {
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
                }
                if model.clips.isEmpty {
                    VStack(spacing: 10) { Image(systemName: "clipboard").font(.system(size: 30)); Text(model.query.isEmpty ? "复制一些内容，从这里开始" : "没有匹配的记录").font(.system(size: 12)) }.foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
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
                else { KeyCap(text: "↑ ↓"); Text("选择").font(.system(size: 10)).foregroundStyle(Palette.secondary); KeyCap(text: "↵"); Text("执行").font(.system(size: 10)).foregroundStyle(Palette.secondary) }
            }.padding(.horizontal, 22).frame(height: 43)
        }
    }
}
