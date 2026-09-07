import Foundation

struct CommandResult {
    var output: String = ""
    var error: String = ""
    var status: Int32 = -1
    var timedOut = false
    var succeeded: Bool { status == 0 && !timedOut }
}

protocol CommandRunning {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult
}

/// Drain both pipes while running so a full pipe cannot deadlock the provider.
final class CommandRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 2) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return CommandResult(error: error.localizedDescription) }
        let group = DispatchGroup()
        let output = LockedData(), errors = LockedData()
        for (pipe, buffer) in [(out, output), (err, errors)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    buffer.append(data)
                }
                group.leave()
            }
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let grace = Date().addingTimeInterval(0.15)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        // A child may inherit a pipe; never wait indefinitely for that child.
        _ = group.wait(timeout: .now() + 0.2)
        return CommandResult(output: output.string, error: errors.string, status: process.terminationStatus, timedOut: timedOut)
    }
}

private final class LockedData {
    private let lock = NSLock()
    private var data = Data()
    func append(_ value: Data) { lock.lock(); defer { lock.unlock() }; if data.count < 1_048_576 { data.append(value.prefix(1_048_576 - data.count)) } }
    var string: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
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
