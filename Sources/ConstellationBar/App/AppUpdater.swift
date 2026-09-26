import AppKit
import Foundation
import Security

/// Numeric tags are compared as versions, so v0.10.0 sorts after v0.9.0.
struct AppVersion: Comparable, Equatable {
    let numbers: [Int]
    let prerelease: [String]

    init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        guard !value.isEmpty else { return nil }
        let core = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = core.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let components = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3, components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(components[0]), let minor = Int(components[1]), let patch = Int(components[2]) else { return nil }
        guard components.allSatisfy({ $0.count == 1 || $0.first != "0" }) else { return nil }
        numbers = [major, minor, patch]
        prerelease = parts.count == 2 ? parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        if parts.count == 2 && (prerelease.isEmpty || prerelease.contains("") || prerelease.contains(where: { $0.contains(where: { !$0.isASCII || !($0.isLetter || $0.isNumber || $0 == "-") }) || ($0.allSatisfy(\.isNumber) && $0.count > 1 && $0.first == "0") })) { return nil }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            if let l = Int(left), let r = Int(right) { return l < r }
            if Int(left) != nil { return true }
            if Int(right) != nil { return false }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct GitHubUpdateRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let size: Int
    }
    let tag_name: String
    let html_url: URL
    let draft: Bool
    let assets: [Asset]

    func archive(for tag: String) -> Asset? {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return assets.first { $0.name == "ConstellationBar-\(version)-universal.zip" }
    }
}

struct UpdateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Updates only published archives signed by the installed app's Developer ID team.
/// Checking never installs anything; replacement requires the Install and Relaunch action.
final class AppUpdater {
    static let shared = AppUpdater()
    static let changed = Notification.Name("ConstellationBar.updaterChanged")
    static let repository = "edrenck/constellation-bar"
    private(set) var isBusy = false
    private(set) var statusText = "Check GitHub for a newer version."
    private let session: URLSession
    private let installedVersion: String?
    private var automaticCheckStarted = false

    init(session: URLSession = URLSession(configuration: .ephemeral),
         installedVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) {
        self.session = session
        self.installedVersion = installedVersion
    }

    func startAutomaticCheck() {
        guard !automaticCheckStarted else { return }
        automaticCheckStarted = true
        checkForUpdates(interactive: false)
    }

    func checkForUpdates(interactive: Bool = true) {
        guard !isBusy else { return }
        setStatus("Checking GitHub…", busy: true)
        Task {
            do {
                guard let installed = installedVersion, let current = AppVersion(installed) else {
                    throw UpdateError(message: "This development build has no version to compare. Use a packaged ConstellationBar.app to check for updates.")
                }
                struct Tag: Decodable { let name: String }
                var tags: [Tag] = []
                // GitHub orders tags independently of semantic versions. Read all pages,
                // bounded to 1,000 tags, and choose the greatest numeric release tag.
                for page in 1...10 {
                    let data = try await fetch(URL(string: "https://api.github.com/repos/\(Self.repository)/tags?per_page=100&page=\(page)")!, limit: 2_000_000)
                    let batch = try JSONDecoder().decode([Tag].self, from: data)
                    tags += batch
                    if batch.count < 100 { break }
                }
                guard let newest = tags.compactMap({ tag -> (String, AppVersion)? in
                    guard let version = AppVersion(tag.name), version.prerelease.isEmpty else { return nil }
                    return (tag.name, version)
                }).max(by: { $0.1 < $1.1 }) else { throw UpdateError(message: "GitHub has no release version tags.") }
                if newest.1 <= current {
                    await MainActor.run {
                        self.setStatus("ConstellationBar \(installed) is up to date.", busy: false)
                        if interactive { self.showMessage("You’re Up to Date", self.statusText) }
                    }
                    return
                }
                let encoded = newest.0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
                let data: Data
                do { data = try await fetch(URL(string: "https://api.github.com/repos/\(Self.repository)/releases/tags/\(encoded)")!, limit: 2_000_000) }
                catch {
                    throw UpdateError(message: "\(newest.0) is newer, but its installable GitHub release is not available yet. Try again after the release is published.")
                }
                let release = try JSONDecoder().decode(GitHubUpdateRelease.self, from: data)
                guard release.html_url.scheme == "https", release.html_url.host == "github.com", release.html_url.path.hasPrefix("/\(Self.repository)/releases/"),
                      !release.draft, release.tag_name == newest.0, release.archive(for: newest.0) != nil,
                      release.assets.contains(where: { $0.name == "SHA256SUMS" }) else {
                    throw UpdateError(message: "\(newest.0) is newer, but its universal app archive and SHA256SUMS are not published yet.")
                }
                await MainActor.run {
                    self.setStatus("Update available: \(release.tag_name)", busy: false)
                    if interactive { self.offer(release) }
                }
            } catch {
                await MainActor.run {
                    self.setStatus(error.localizedDescription, busy: false)
                    if interactive { self.showMessage("Couldn’t Check for Updates", error.localizedDescription) }
                }
            }
        }
    }

    private func offer(_ release: GitHubUpdateRelease) {
        let alert = NSAlert()
        alert.messageText = "ConstellationBar \(release.tag_name) Is Available"
        alert.informativeText = "Download the signed update from GitHub. The app will verify it before offering to install and relaunch."
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release Notes")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn { prepare(release) }
        if response == .alertThirdButtonReturn { NSWorkspace.shared.open(release.html_url) }
    }

    private func prepare(_ release: GitHubUpdateRelease) {
        guard !isBusy else { return }
        setStatus("Downloading and verifying \(release.tag_name)…", busy: true)
        Task {
            var staging: URL?
            do {
                let installed = Bundle.main.bundleURL
                guard installed.pathExtension == "app", FileManager.default.isWritableFile(atPath: installed.deletingLastPathComponent().path) else {
                    throw UpdateError(message: "Move ConstellationBar to an Applications folder you can write to, then check again. You can also install the release manually from GitHub.")
                }
                guard try Self.teamIdentifier(at: installed) != nil else {
                    throw UpdateError(message: "In-app installation requires a Developer ID signed app. Download the signed release from GitHub to replace this development build.")
                }
                guard let archive = release.archive(for: release.tag_name), let sums = release.assets.first(where: { $0.name == "SHA256SUMS" }),
                      archive.size > 0, archive.size < 150_000_000 else { throw UpdateError(message: "The release archive is missing or too large.") }
                let directory = installed.deletingLastPathComponent().appendingPathComponent(".ConstellationBar-update-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                staging = directory
                let zip = directory.appendingPathComponent("update.zip")
                try await download(archive.browser_download_url, to: zip, limit: 150_000_000)
                let checksumData = try await fetch(sums.browser_download_url, limit: 65_536, asset: true)
                guard let expected = Self.checksum(for: archive.name, in: String(decoding: checksumData, as: UTF8.self)),
                      try UpdateTransfer.sha256(of: zip) == expected else {
                    throw UpdateError(message: "The update’s SHA-256 checksum does not match. The installed app has not been changed.")
                }
                let names = try Self.run("/usr/bin/zipinfo", ["-1", zip.path])
                let modes = try Self.run("/usr/bin/zipinfo", ["-l", zip.path])
                let totals = try Self.run("/usr/bin/zipinfo", ["-t", zip.path])
                guard Self.safeArchiveSize(totals), Self.safeArchiveEntries(names), !modes.split(separator: "\n").contains(where: { $0.first == "l" }) else {
                    throw UpdateError(message: "The update archive contains unsafe file paths, symbolic links or an excessive extracted size.")
                }
                _ = try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, directory.path], timeout: 60)
                let app = directory.appendingPathComponent("ConstellationBar.app", isDirectory: true)
                try Self.verifyPreparedApplication(app, replacing: installed, version: release.tag_name)
                await MainActor.run {
                    self.setStatus("\(release.tag_name) is verified and ready to install.", busy: false)
                    self.confirmInstall(staging: directory, app: app, installed: installed, release: release)
                }
                staging = nil
            } catch {
                if let staging { try? FileManager.default.removeItem(at: staging) }
                await MainActor.run {
                    self.setStatus(error.localizedDescription, busy: false)
                    self.showMessage("Couldn’t Prepare Update", error.localizedDescription)
                }
            }
        }
    }

    private func confirmInstall(staging: URL, app: URL, installed: URL, release: GitHubUpdateRelease) {
        let alert = NSAlert()
        alert.messageText = "Install \(release.tag_name) and Relaunch?"
        alert.informativeText = "The download passed its checksum, Developer ID signature and macOS security checks. ConstellationBar will briefly quit while it replaces the app. Your configuration is preserved."
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { try? FileManager.default.removeItem(at: staging); return }
        do {
            let receipt = UpdateReceipt(token: UUID().uuidString, destination: installed, stagedApp: app,
                                        version: release.tag_name, parentPID: ProcessInfo.processInfo.processIdentifier)
            try receipt.save()
            guard let executable = Bundle.main.executableURL else { throw UpdateError(message: "Couldn’t locate the installer helper.") }
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--install-update", receipt.receiptURL.path]
            let logURL = staging.appendingPathComponent("helper.log")
            guard FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw UpdateError(message: "Couldn’t create the installer log.")
            }
            let log = try FileHandle(forWritingTo: logURL)
            defer { try? log.close() }
            process.standardOutput = log
            process.standardError = log
            try process.run()
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            setStatus(error.localizedDescription, busy: false)
            showMessage("Couldn’t Install Update", error.localizedDescription)
        }
    }

    private func request(_ url: URL, asset: Bool) throws -> URLRequest {
        let allowedHost = asset ? "github.com" : "api.github.com"
        guard url.scheme == "https", url.host == allowedHost,
              !asset || url.path.hasPrefix("/\(Self.repository)/releases/download/") else { throw UpdateError(message: "GitHub returned an unexpected download URL.") }
        var request = URLRequest(url: url, timeoutInterval: asset ? 120 : 20)
        request.setValue("ConstellationBar-Updater", forHTTPHeaderField: "User-Agent")
        if !asset { request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        return request
    }

    private func fetch(_ url: URL, limit: Int, asset: Bool = false) async throws -> Data {
        let transfer = UpdateTransfer(configuration: session.configuration, limit: limit)
        return try await transfer.receive(request(url, asset: asset))
    }

    private func download(_ url: URL, to file: URL, limit: Int) async throws {
        let transfer = UpdateTransfer(configuration: session.configuration, limit: limit, destination: file)
        _ = try await transfer.receive(request(url, asset: true))
    }

    static func checksum(for filename: String, in contents: String) -> String? {
        for line in contents.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 2, fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == filename,
                  fields[0].count == 64, fields[0].allSatisfy(\.isHexDigit) else { continue }
            return fields[0].lowercased()
        }
        return nil
    }

    static func safeArchiveEntries(_ listing: String) -> Bool {
        let names = listing.split(separator: "\n")
        return !names.isEmpty && names.allSatisfy { name in
            let path = String(name)
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            return !path.hasPrefix("/") && !path.contains("\\") && !components.contains("..") &&
                (path.hasPrefix("ConstellationBar.app/") || path == "ConstellationBar.app" || path.hasPrefix("__MACOSX/"))
        }
    }

    static func safeArchiveSize(_ summary: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: "([0-9]+) bytes uncompressed"),
              let match = expression.firstMatch(in: summary, range: NSRange(summary.startIndex..., in: summary)),
              let range = Range(match.range(at: 1), in: summary), let bytes = Int(summary[range]) else { return false }
        return bytes > 0 && bytes <= 500_000_000
    }

    static func verifyPreparedApplication(_ app: URL, replacing installed: URL, version: String) throws {
        guard (try app.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
              (try installed.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
              let installedBundle = Bundle(url: installed), let bundle = Bundle(url: app),
              let installedID = installedBundle.bundleIdentifier, bundle.bundleIdentifier == installedID,
              let installedTeam = try teamIdentifier(at: installed),
              let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              AppVersion(appVersion) == AppVersion(version),
              try teamIdentifier(at: app) == installedTeam else {
            throw UpdateError(message: "The downloaded app’s identity, signing team or version does not match this update.")
        }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        _ = try run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
    }

    static func teamIdentifier(at app: URL) throws -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { throw UpdateError(message: "Couldn’t read the app’s code signature.") }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else { throw UpdateError(message: "Couldn’t inspect the app’s signing identity.") }
        return values[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) throws -> String {
        let result = CommandRunner().run(executable, arguments, timeout: timeout)
        return try verifiedCommandOutput(result)
    }

    static func verifiedCommandOutput(_ result: CommandResult) throws -> String {
        guard !result.timedOut else { throw UpdateError(message: "Update verification timed out. The installed app has not been changed.") }
        // CommandRunner caps each pipe at 1 MiB. Fail closed if a security listing
        // may have been truncated; never validate only a prefix of an archive.
        guard !result.outputTruncated, result.output.utf8.count < 1_048_576, result.error.utf8.count < 1_048_576 else {
            throw UpdateError(message: "The update verification output exceeded its limit.")
        }
        guard result.succeeded else {
            throw UpdateError(message: "Update verification failed: \(String((result.error.isEmpty ? result.output : result.error).prefix(2000)))")
        }
        return result.output
    }

    private func setStatus(_ text: String, busy: Bool) {
        statusText = text
        isBusy = busy
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    private func showMessage(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
