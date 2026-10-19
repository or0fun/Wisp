import Foundation
import Darwin

/// Each job owns a POSIX process group so cancellation also stops script children.
final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var cancelled = false
    static let outputLimit = 4 * 1024 * 1024

    func cancel() {
        lock.lock(); cancelled = true
        if pid > 0 { kill(-pid, SIGTERM) }
        lock.unlock()
    }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func run(executable: String, arguments: [String], input: String, directory: URL, timeout: Double,
             script: String? = nil, outputFile: Bool = false) async throws -> String {
        try await withTaskCancellationHandler(operation: {
            try await Task.detached(priority: .userInitiated) { [self] in
                try runSync(executable: executable, arguments: arguments, input: input, directory: directory, timeout: timeout, script: script, outputFile: outputFile)
            }.value
        }, onCancel: { self.cancel() })
    }

    private func runSync(executable: String, arguments: [String], input: String, directory: URL, timeout: Double, script: String?, outputFile: Bool) throws -> String {
        if isCancelled { throw CancellationError() }
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appendingPathComponent("wisp-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: temporary) }
        let stdinURL = temporary.appendingPathComponent("input")
        let stdoutURL = temporary.appendingPathComponent("stdout")
        let stderrURL = temporary.appendingPathComponent("stderr")
        let resultURL = temporary.appendingPathComponent("result.md")
        let scriptURL = temporary.appendingPathComponent("script")
        try Data(input.utf8).write(to: stdinURL)
        manager.createFile(atPath: stdoutURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        manager.createFile(atPath: stderrURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        if let script { try Data(script.utf8).write(to: scriptURL) }
        let stdin = try FileHandle(forReadingFrom: stdinURL)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer { try? stdin.close(); try? stdout.close(); try? stderr.close() }

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, stdin.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stdout.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderr.fileDescriptor, STDERR_FILENO)
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let args = [executable] + arguments.map { $0 == "{output}" ? resultURL.path : $0 } + (script == nil ? [] : [scriptURL.path])
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
        let inputEnvironment = input.utf8.count <= 32_000 ? input : ""
        environment["WISP_INPUT"] = inputEnvironment
        environment["PERSONALAI_INPUT"] = inputEnvironment // Compatibility with existing workflows.
        // Large inputs always remain available in stdin; avoid exceeding exec's environment limit.
        let argv = args.map { strdup($0) } + [nil]
        let env = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.compactMap { $0 }.forEach { free($0) }; env.compactMap { $0 }.forEach { free($0) } }
        var child: pid_t = 0
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        let launchStatus = argv.withUnsafeBufferPointer { argvBuffer in
            env.withUnsafeBufferPointer { envBuffer in
                posix_spawn(&child, executable, &actions, &attributes, argvBuffer.baseAddress!, envBuffer.baseAddress!)
            }
        }
        if launchStatus == 0 { pid = child }
        lock.unlock()
        guard launchStatus == 0 else { throw AppError.message("启动失败：\(String(cString: strerror(launchStatus)))。请检查可执行文件与工作目录。") }

        var status: Int32 = 0
        var reaped = false
        defer {
            lock.lock()
            // Also clean up children left in the group by a completed shell script.
            kill(-child, SIGKILL); pid = 0
            lock.unlock()
            if !reaped { while waitpid(child, &status, 0) < 0 && errno == EINTR {} }
        }
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if isCancelled { throw CancellationError() }
            if Date() >= deadline { throw AppError.message("执行超过 \(Int(timeout)) 秒，已停止任务及其子进程。") }
            for url in [stdoutURL, stderrURL, resultURL] {
                let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                if size > Self.outputLimit { throw AppError.message("输出超过 4 MB，任务已停止。") }
            }
            let result = waitpid(child, &status, WNOHANG)
            if result == child { reaped = true; break }
            if result < 0 && errno != EINTR { throw AppError.message("无法读取任务状态。") }
            Thread.sleep(forTimeInterval: 0.04)
        }
        if isCancelled { throw CancellationError() }
        let errorHandle = try FileHandle(forReadingFrom: stderrURL)
        defer { try? errorHandle.close() }
        let stderrData = try errorHandle.read(upToCount: 12_000) ?? Data()
        let detail = String(decoding: stderrData, as: UTF8.self)
        guard status == 0 else { throw AppError.message("任务退出（状态 \(status >> 8)）。\n\(detail)") }
        let chosen = outputFile ? resultURL : stdoutURL
        guard manager.fileExists(atPath: chosen.path) else { throw AppError.message("任务未生成结果。\(detail)") }
        let outputHandle = try FileHandle(forReadingFrom: chosen)
        defer { try? outputHandle.close() }
        let resultData = try outputHandle.read(upToCount: Self.outputLimit + 1) ?? Data()
        guard resultData.count <= Self.outputLimit else { throw AppError.message("结果超过 4 MB。") }
        guard let text = String(data: resultData, encoding: .utf8) else { throw AppError.message("脚本输出必须为 UTF-8 文本。") }
        return text
    }
}
