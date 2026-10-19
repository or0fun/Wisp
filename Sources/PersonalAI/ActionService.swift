import AppKit

enum ActionDestination {
    case codex, doubao, search(SearchEngine), workflow(Workflow), calculation(CalculationResult)
}
struct ActionItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: String
    let keyword: String
    let destination: ActionDestination
}
enum ActionService {
    static func codexExecutable(settings: Settings) throws -> String {
        let configured = (settings.codexPath as NSString).expandingTildeInPath
        if !configured.isEmpty {
            guard FileManager.default.isExecutableFile(atPath: configured) else { throw AppError.message("Codex 路径不可执行，请在设置中修改。") }
            return configured
        }
        let candidates = [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw AppError.message("未找到 Codex CLI。请先安装并完成 codex login，或在设置中填写绝对路径。") }
        return path
    }
    static func codex(input: String, settings: Settings, runner: ProcessRunner) async throws -> String {
        let executable = try codexExecutable(settings: settings)
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("personalai-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: workspace) }
        var arguments = ["exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only", "--color", "never", "--output-last-message", "{output}"]
        if !settings.codexModel.isEmpty { arguments += ["--model", settings.codexModel] }
        arguments += ["-"]
        return try await runner.run(executable: executable, arguments: arguments, input: input, directory: workspace, timeout: settings.codexTimeout, outputFile: true)
    }
    static func workflow(_ workflow: Workflow, input: String, runner: ProcessRunner, progress: @escaping @MainActor (String) -> Void) async throws -> String {
        var output = input
        let deadline = Date().addingTimeInterval(workflow.timeout)
        for (index, step) in workflow.steps.enumerated() {
            try Task.checkCancellation()
            await progress("\(index + 1)/\(workflow.steps.count) · \(step.name)")
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw AppError.message("流程已超时。") }
            do {
                output = try await runner.run(executable: step.interpreter, arguments: [], input: output,
                    directory: URL(fileURLWithPath: (workflow.workingDirectory as NSString).expandingTildeInPath), timeout: remaining, script: step.script)
            } catch is CancellationError { throw CancellationError() }
            catch { throw AppError.message("步骤「\(step.name)」失败：\n\(error.localizedDescription)") }
        }
        return output
    }
    static func doubao(input: String, settings: Settings) async throws -> String {
        let key = try Keychain.read()
        guard !key.isEmpty, !settings.apiModel.isEmpty else { throw AppError.message("请先在 AI 设置中填写豆包模型 / Endpoint ID 和 API Key。") }
        guard let endpoint = URL(string: settings.apiEndpoint), endpoint.scheme == "https" else { throw AppError.message("API 地址必须使用 HTTPS。") }
        return try await LLMService.complete(endpoint: endpoint, model: settings.apiModel, key: key, messages: [["role": "user", "content": input]])
    }
}
