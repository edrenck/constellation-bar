import AppKit
import Foundation

struct UpdateReceipt: Codable {
    enum State: String, Codable { case prepared, replacing, awaitingStartup, succeeded, rolledBack, recoveryRequired }
    let token: String
    let destination: URL
    let stagedApp: URL
    let version: String
    let parentPID: Int32
    var state: State = .prepared
    var launchedPID: Int32?
    var installerPID: Int32?
    var error: String?

    var directory: URL { stagedApp.deletingLastPathComponent() }
    var backup: URL { directory.appendingPathComponent("previous.app") }
    var failedApp: URL { directory.appendingPathComponent("failed.app") }
    var receiptURL: URL { directory.appendingPathComponent("receipt.json") }
    var acknowledgmentURL: URL { directory.appendingPathComponent("startup.json") }

    func save() throws { try JSONEncoder().encode(self).write(to: receiptURL, options: .atomic) }
    static func load(_ url: URL) throws -> Self {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, (values.fileSize ?? Int.max) < 16_384 else { throw UpdateError(message: "Invalid update receipt.") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 16_384) ?? Data()
        guard data.count < 16_384 else { throw UpdateError(message: "Invalid update receipt size.") }
        let receipt = try JSONDecoder().decode(Self.self, from: data)
        guard receipt.directory.lastPathComponent.hasPrefix(".ConstellationBar-update-"),
              receipt.stagedApp.lastPathComponent == "ConstellationBar.app",
              receipt.destination.pathExtension == "app",
              receipt.directory.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == receipt.destination.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path,
              receipt.receiptURL.standardizedFileURL.resolvingSymlinksInPath().path == url.standardizedFileURL.resolvingSymlinksInPath().path,
              UUID(uuidString: receipt.token) != nil,
              (try receipt.directory.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw UpdateError(message: "Invalid update receipt paths.") }
        return receipt
    }
}

private struct UpdateLaunchUnconfirmed: LocalizedError {
    var errorDescription: String? { "macOS did not confirm whether the app launched. The previous app has been retained for recovery." }
}

struct UpdateStartupAcknowledgment: Codable {
    let token: String
    let pid: Int32
}

/// Replacement is one transaction, owned by the helper until startup is confirmed.
/// Only the app directory and private sibling staging are touched; settings are never involved.
struct UpdateTransaction {
    struct Operations {
        var exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
        var move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
        var remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
        var launch: (URL, [String]) throws -> Int32
        var terminate: (Int32) -> Bool
        var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
        var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    }

    private(set) var receipt: UpdateReceipt
    let operations: Operations
    var acknowledgmentTimeout: TimeInterval = 30

    mutating func run() throws {
        var movedPrevious = false
        var movedReplacement = false
        do {
            guard operations.exists(receipt.destination), operations.exists(receipt.stagedApp), !operations.exists(receipt.backup) else {
                throw UpdateError(message: "The app or update staging changed before installation.")
            }
            receipt.state = .replacing
            try receipt.save()
            try operations.move(receipt.destination, receipt.backup)
            movedPrevious = true
            try operations.move(receipt.stagedApp, receipt.destination)
            movedReplacement = true
            receipt.state = .awaitingStartup
            try receipt.save()
            let pid = try operations.launch(receipt.destination, ["--update-receipt", receipt.receiptURL.path, "--update-token", receipt.token])
            receipt.launchedPID = pid
            try receipt.save()
            let deadline = operations.now() + acknowledgmentTimeout
            var confirmed = false
            while operations.now() < deadline {
                if let data = Self.readAcknowledgment(receipt.acknowledgmentURL),
                   let acknowledgment = try? JSONDecoder().decode(UpdateStartupAcknowledgment.self, from: data),
                   acknowledgment.token == receipt.token, acknowledgment.pid == pid {
                    confirmed = true
                    break
                }
                operations.sleep(0.1)
            }
            guard confirmed else { throw UpdateError(message: "The updated app did not confirm startup within \(Int(acknowledgmentTimeout)) seconds.") }
            receipt.state = .succeeded
            try receipt.save()
            // Startup has been confirmed. Delete old binaries, retaining only the receipt/log.
            try operations.remove(receipt.backup)
            for name in ["update.zip", "startup.json", "__MACOSX"] {
                let file = receipt.directory.appendingPathComponent(name)
                if operations.exists(file) { try operations.remove(file) }
            }
            log("Update initialized successfully; previous app removed.")
            Self.pruneReceipts(beside: receipt.destination, preserving: receipt.directory)
        } catch {
            let failure = error
            log("Update failed: \(failure.localizedDescription)")
            // A confirmed update must never be rolled back because cleanup failed.
            if receipt.state == .succeeded {
                receipt.error = "Update succeeded; cleanup failed: \(failure.localizedDescription)"
                try? receipt.save()
                return
            }
            do {
                if failure is UpdateLaunchUnconfirmed { throw failure }
                if let pid = receipt.launchedPID, !operations.terminate(pid) {
                    throw UpdateError(message: "The replacement app could not be stopped safely. The previous app remains at \(receipt.backup.path).")
                }
                if movedReplacement { try operations.move(receipt.destination, receipt.failedApp) }
                if movedPrevious { try operations.move(receipt.backup, receipt.destination) }
                receipt.state = .rolledBack
                receipt.error = failure.localizedDescription
                try receipt.save()
                if movedReplacement { try? operations.remove(receipt.failedApp) }
                if operations.exists(receipt.stagedApp) { try? operations.remove(receipt.stagedApp) }
                let zip = receipt.directory.appendingPathComponent("update.zip")
                if operations.exists(zip) { try? operations.remove(zip) }
                _ = try operations.launch(receipt.destination, ["--update-receipt", receipt.receiptURL.path, "--update-token", receipt.token])
                log("Previous app restored and relaunched.")
            } catch {
                receipt.state = .recoveryRequired
                receipt.error = "\(failure.localizedDescription) Recovery: \(error.localizedDescription)"
                try? receipt.save()
                log(receipt.error!)
            }
            throw failure
        }
    }

    private static func readAcknowledgment(_ url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink != true,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1024), data.count < 1024 else { return nil }
        return data
    }

    private func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = receipt.directory.appendingPathComponent("installer.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    /// Keep five completed receipts. Never delete unfinished recovery directories or backups.
    static func pruneReceipts(beside app: URL, preserving current: URL) {
        let manager = FileManager.default
        guard let directories = try? manager.contentsOfDirectory(at: app.deletingLastPathComponent(), includingPropertiesForKeys: [.isSymbolicLinkKey, .contentModificationDateKey]) else { return }
        let completed = directories.filter { directory in
            guard directory.lastPathComponent.hasPrefix(".ConstellationBar-update-"),
                  (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  let receipt = try? UpdateReceipt.load(directory.appendingPathComponent("receipt.json")),
                  receipt.destination.standardizedFileURL.resolvingSymlinksInPath().path == app.standardizedFileURL.resolvingSymlinksInPath().path, [.succeeded, .rolledBack].contains(receipt.state),
                  !manager.fileExists(atPath: receipt.backup.path) else { return false }
            return true
        }.sorted { left, right in
            let l = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
        let retained = Set([current.standardizedFileURL.resolvingSymlinksInPath().path] + completed.filter { $0.standardizedFileURL.resolvingSymlinksInPath().path != current.standardizedFileURL.resolvingSymlinksInPath().path }.prefix(4).map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        for directory in completed where !retained.contains(directory.standardizedFileURL.resolvingSymlinksInPath().path) { try? manager.removeItem(at: directory) }
    }

    /// The installer has the same bundle ID as the app. Its process must not make
    /// normal single-instance protection reject the replacement or recovered app.
    static func installerPIDForStartup(arguments: [String], bundle: Bundle = .main) -> Int32? {
        guard let index = arguments.firstIndex(of: "--update-receipt"), arguments.indices.contains(index + 1),
              let tokenIndex = arguments.firstIndex(of: "--update-token"), arguments.indices.contains(tokenIndex + 1),
              let receipt = try? UpdateReceipt.load(URL(fileURLWithPath: arguments[index + 1])),
              receipt.token == arguments[tokenIndex + 1],
              receipt.destination.standardizedFileURL.resolvingSymlinksInPath().path == bundle.bundleURL.standardizedFileURL.resolvingSymlinksInPath().path,
              [.awaitingStartup, .rolledBack].contains(receipt.state) else { return nil }
        return receipt.installerPID
    }

    static func acknowledgeStartup(arguments: [String], bundle: Bundle = .main) {
        guard let index = arguments.firstIndex(of: "--update-receipt"), arguments.indices.contains(index + 1),
              let tokenIndex = arguments.firstIndex(of: "--update-token"), arguments.indices.contains(tokenIndex + 1),
              let receipt = try? UpdateReceipt.load(URL(fileURLWithPath: arguments[index + 1])),
              receipt.state == .awaitingStartup, receipt.token == arguments[tokenIndex + 1],
              receipt.destination.standardizedFileURL.resolvingSymlinksInPath().path == bundle.bundleURL.standardizedFileURL.resolvingSymlinksInPath().path,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              AppVersion(version) == AppVersion(receipt.version) else { return }
        let acknowledgment = UpdateStartupAcknowledgment(token: receipt.token, pid: ProcessInfo.processInfo.processIdentifier)
        try? JSONEncoder().encode(acknowledgment).write(to: receipt.acknowledgmentURL, options: .atomic)
    }

    static func runHelper(receiptURL: URL) throws {
        var receipt = try UpdateReceipt.load(receiptURL)
        guard receipt.state == .prepared else { throw UpdateError(message: "The update transaction has already started.") }
        receipt.installerPID = ProcessInfo.processInfo.processIdentifier
        try receipt.save()
        do { try AppUpdater.verifyPreparedApplication(receipt.stagedApp, replacing: receipt.destination, version: receipt.version) }
        catch {
            receipt.error = "Installer verification failed: \(error.localizedDescription)"
            try? receipt.save()
            throw error
        }
        guard receipt.parentPID > 1, receipt.parentPID != ProcessInfo.processInfo.processIdentifier else {
            throw UpdateError(message: "Invalid installer parent process.")
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 60
        while kill(receipt.parentPID, 0) == 0 {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                receipt.error = "The running app did not quit; installation was cancelled."
                try? receipt.save()
                throw UpdateError(message: receipt.error!)
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let operations = Operations(launch: { app, arguments in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.arguments = arguments
            var result: Result<NSRunningApplication, Error>?
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { application, error in
                DispatchQueue.main.async {
                    if let application { result = .success(application) }
                    else { result = .failure(error ?? UpdateError(message: "macOS could not launch the updated app.")) }
                }
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while result == nil && ProcessInfo.processInfo.systemUptime < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
            guard let result else { throw UpdateLaunchUnconfirmed() }
            return try result.get().processIdentifier
        }, terminate: { pid in
            // This PID was returned by Launch Services for this transaction, never a broad kill.
            guard let application = NSRunningApplication(processIdentifier: pid) else { return true }
            guard application.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == receipt.destination.standardizedFileURL.resolvingSymlinksInPath().path else { return false }
            application.terminate()
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            while !application.isTerminated && ProcessInfo.processInfo.systemUptime < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
            if !application.isTerminated { application.forceTerminate() }
            let forcedDeadline = ProcessInfo.processInfo.systemUptime + 2
            while !application.isTerminated && ProcessInfo.processInfo.systemUptime < forcedDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
            return application.isTerminated
        })
        var transaction = UpdateTransaction(receipt: receipt, operations: operations)
        try transaction.run()
    }
}
