import Foundation
import Darwin

struct CommandResult {
    var output: String = ""
    var error: String = ""
    var status: Int32 = -1
    var timedOut = false
    var outputTruncated = false
    /// Parsing callers must never consume a partial successful response.
    var succeeded: Bool { status == 0 && !timedOut && !outputTruncated }
}

protocol CommandRunning {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult
}

/// Owns only the direct child. Descendants are not killed; inherited pipe readers
/// are closed after a bounded drain. No background reader can outlive this call.
final class CommandRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 2) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out; process.standardError = err
        defer {
            try? out.fileHandleForReading.close(); try? err.fileHandleForReading.close()
            try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close()
        }
        do { try process.run() } catch { return CommandResult(error: error.localizedDescription) }
        try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close()
        let output = CommandPipeReader(handle: out.fileHandleForReading)
        let errors = CommandPipeReader(handle: err.fileHandleForReading)
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            output.drain(); errors.drain(); Thread.sleep(forTimeInterval: 0.005)
        }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let grace = ProcessInfo.processInfo.systemUptime + 0.15
            while process.isRunning && ProcessInfo.processInfo.systemUptime < grace {
                output.drain(); errors.drain(); Thread.sleep(forTimeInterval: 0.005)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        let drainDeadline = ProcessInfo.processInfo.systemUptime + 0.2
        repeat {
            output.drain(); errors.drain()
            if output.finished && errors.finished { break }
            Thread.sleep(forTimeInterval: 0.005)
        } while ProcessInfo.processInfo.systemUptime < drainDeadline
        return CommandResult(output: output.string, error: errors.string, status: process.terminationStatus,
                             timedOut: timedOut, outputTruncated: output.truncated || errors.truncated || !output.finished || !errors.finished)
    }
}

private final class CommandPipeReader {
    private let descriptor: Int32
    private var data = Data()
    private(set) var finished = false
    private(set) var truncated = false
    init(handle: FileHandle) {
        descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        if flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0 { finished = true; truncated = true }
    }
    func drain() {
        guard !finished else { return }
        var bytes = [UInt8](repeating: 0, count: 16384)
        // Bound each pass so a continuously writing child cannot starve its deadline.
        for _ in 0..<64 {
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count == 0 { finished = true; return }
            if count < 0 {
                if errno == EINTR { continue }
                if errno != EAGAIN && errno != EWOULDBLOCK { truncated = true; finished = true }
                return
            }
            let kept = min(count, max(0, 1_048_576 - data.count))
            data.append(contentsOf: bytes.prefix(kept))
            if kept < count { truncated = true }
        }
    }
    var string: String { String(decoding: data, as: UTF8.self) }
}

enum ExecutableDiscovery {
    static func find(_ name: String, override: String = "", environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if !override.isEmpty {
            let path = NSString(string: override).expandingTildeInPath
            return FileManager.default.isExecutableFile(atPath: path) ? path : nil
        }
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        return directories.map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
