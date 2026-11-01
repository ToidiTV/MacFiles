import Foundation
import FilesShared

public struct CommandResult: Sendable {
    public let status: Int32
    public let data: Data
    public var output: String { String(decoding: data, as: UTF8.self) }
}
public struct CommandFailure: LocalizedError {
    public let message: String
    public var errorDescription: String? { NativeLocalization.text(message) }
    public init(_ message: String) { self.message = message }
}
private final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func start(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        try process.run(); self.process = process
    }
    func cancel() {
        lock.lock(); cancelled = true
        if let process, process.isRunning { process.terminate() }
        lock.unlock()
    }
}

public enum ProcessService {
    public static func run(_ executable: String, _ arguments: [String], directory: URL? = nil,
                           input: Data? = nil, environment: [String: String] = [:], check: Bool = true, outputURL: URL? = nil) async throws -> CommandResult {
        let running = RunningProcess()
        return try await withTaskCancellationHandler {
            let task = Task.detached(priority: .userInitiated) {
                let process = Process(); process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments; process.currentDirectoryURL = directory
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, value in value }
                let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
                var outputHandle: FileHandle?
                if let outputURL {
                    guard !FileManager.default.fileExists(atPath: outputURL.path), FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CommandFailure("Cannot create subprocess output file.") }
                    outputHandle = try FileHandle(forWritingTo: outputURL); process.standardOutput = outputHandle
                }
                defer { try? outputHandle?.close() }
                if let input {
                    // A file-backed stdin avoids pipe-buffer deadlocks for large batch requests.
                    let path = FileManager.default.temporaryDirectory.appendingPathComponent("MacFiles-stdin-\(UUID().uuidString)")
                    guard FileManager.default.createFile(atPath: path.path, contents: input, attributes: [.posixPermissions: 0o600]) else { throw CommandFailure("Cannot prepare command input.") }
                    let handle = try FileHandle(forReadingFrom: path)
                    try FileManager.default.removeItem(at: path)
                    process.standardInput = handle
                } else { process.standardInput = FileHandle.nullDevice }
                try running.start(process)
                var data = Data(); var truncated = false
                while let chunk = try pipe.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
                    let available = 16 * 1024 * 1024 - data.count
                    if chunk.count > available { truncated = true }
                    data.append(chunk.prefix(available))
                }
                process.waitUntilExit()
                if let handle = process.standardInput as? FileHandle, input != nil { try? handle.close() }
                try Task.checkCancellation()
                guard !truncated else { throw CommandFailure("Command output exceeded 16 MiB; no truncated result was accepted.") }
                let result = CommandResult(status: process.terminationStatus, data: data)
                if check && result.status != 0 { throw CommandFailure(result.output.isEmpty ? "The command failed (\(result.status))." : result.output) }
                return result
            }
            return try await withTaskCancellationHandler { try await task.value } onCancel: { running.cancel(); task.cancel() }
        } onCancel: { running.cancel() }
    }
}
