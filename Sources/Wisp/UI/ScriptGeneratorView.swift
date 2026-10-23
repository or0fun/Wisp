import SwiftUI

struct ScriptGeneratorView: View {
    let step: WorkflowStep
    let configuration: ModelConfiguration?
    let apply: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var request = ""
    @State private var generated = ""
    @State private var running = false
    @State private var error = ""
    @State private var job: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 写脚本").font(.title2.bold())
                    Text("\(step.name) · \(step.interpreter)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let configuration { Text(configuration.model).font(.caption).foregroundStyle(.secondary) }
            }
            if let configuration {
                Text("使用 \(configuration.baseURL)；只发送本次需求、当前脚本和解释器信息。").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            } else {
                Text("请先在「AI 助手 → 问答与脚本模型」配置 Base URL、API Key 和模型名称并保存。").font(.callout).foregroundStyle(.orange)
            }
            Text("描述脚本要做什么").font(.headline)
            TextEditor(text: $request).font(.system(size: 13)).frame(height: 105)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.1)))
            HStack {
                if running { ProgressView().controlSize(.small); Text("正在生成…").font(.caption).foregroundStyle(.secondary); Button("停止") { job?.cancel() } }
                Spacer()
                Button(generated.isEmpty ? "生成脚本" : "重新生成", action: generate)
                    .disabled(running || configuration == nil || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack { Text("生成结果（可编辑）").font(.headline); Spacer(); Text("应用后仍需保存流程").font(.caption).foregroundStyle(.secondary) }
            ScriptEditor(text: $generated).frame(minHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.1)))
            Text(error.isEmpty ? "生成和应用不会执行脚本。确认内容后再运行流程。" : error)
                .font(.caption).foregroundStyle(error.isEmpty ? Color.secondary : Color.orange).lineLimit(3).textSelection(.enabled)
            HStack {
                Spacer()
                Button("取消") { job?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("应用到步骤") { apply(generated); dismiss() }
                    .buttonStyle(.borderedProminent).tint(Palette.accent).disabled(running || generated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 700, height: 650).preferredColorScheme(.dark)
        .onDisappear { job?.cancel() }
    }
    private func generate() {
        guard let configuration else { return }
        running = true; error = ""
        let description = request
        job = Task { @MainActor in
            defer { running = false; job = nil }
            do {
                let code = try await LLMService.generateScript(description: description, step: step, configuration: configuration)
                try Task.checkCancellation(); generated = code
            } catch is CancellationError { error = "已停止生成，原脚本未修改。" }
            catch { self.error = Task.isCancelled ? "已停止生成，原脚本未修改。" : error.localizedDescription }
        }
    }
}
