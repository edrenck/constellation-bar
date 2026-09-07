import Foundation

/// A native-messaging bridge, never a network listener. The extension opts individual tabs in.
struct BrowserSnapshot: Codable {
    var id: String; var title: String; var playing: Bool; var position: Double; var duration: Double
    var canSeek: Bool; var timestamp: Double
    var error: String? = nil
    var acknowledged: String? = nil
    var valid: Bool {
        !id.isEmpty && id.count < 100 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        && title.count <= 1000 && position.isFinite && duration.isFinite && timestamp.isFinite && position >= 0 && duration >= 0
    }
}
struct BrowserCommand: Codable {
    var id: String = UUID().uuidString
    var action: String
    var position: Double?
    var timestamp = Date().timeIntervalSince1970
}
enum BrowserBridge {
    static var directory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ConstellationBar/BrowserMedia") }
    static func prepare() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    static func file(_ id: String, suffix: String) -> URL { directory.appendingPathComponent(id + suffix + ".json") }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func exchange(_ snapshot: BrowserSnapshot, at root: URL = directory) throws -> BrowserCommand? {
        guard snapshot.valid else { throw WidgetActionError(message: "Invalid media snapshot") }
        var current = snapshot; current.timestamp = Date().timeIntervalSince1970
        try write(current, to: root.appendingPathComponent(snapshot.id + "-state.json"))
        let path = root.appendingPathComponent(snapshot.id + "-command.json")
        guard let data = BoundedFile.read(path, maximumBytes: 65536), let command = try? JSONDecoder().decode(BrowserCommand.self, from: data) else { return nil }
        if command.id == snapshot.acknowledged || Date().timeIntervalSince1970 - command.timestamp > 10 {
            try? FileManager.default.removeItem(at: path); return nil
        }
        return command
    }
    static func runHost() {
        // Chrome's native protocol uses a native-endian UInt32 length, followed by JSON.
        let input = FileHandle.standardInput, output = FileHandle.standardOutput
        func readExactly(_ count: Int) -> Data? {
            var data = Data()
            while data.count < count {
                let next = input.readData(ofLength: count - data.count)
                if next.isEmpty { return nil }; data.append(next)
            }
            return data
        }
        while let header = readExactly(4) {
            let count = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            guard count > 0, count <= 65536, let payload = readExactly(Int(count)) else { break }
            let response: Data
            do {
                let snapshot = try JSONDecoder().decode(BrowserSnapshot.self, from: payload)
                let command = try exchange(snapshot)
                response = try JSONEncoder().encode(command)
            } catch { response = Data("null".utf8) }
            var size = UInt32(response.count)
            output.write(Data(bytes: &size, count: 4)); output.write(response)
        }
    }
}
final class BrowserMediaIntegration: MediaIntegrating {
    let id = "browser"
    func sessions() -> (sessions: [MediaSession], status: String) {
        let files = (try? FileManager.default.contentsOfDirectory(at: BrowserBridge.directory, includingPropertiesForKeys: nil)) ?? []
        var sessions: [MediaSession] = []
        for file in files where file.lastPathComponent.hasSuffix("-state.json") {
            guard let data = BoundedFile.read(file, maximumBytes: 65536), let state = try? JSONDecoder().decode(BrowserSnapshot.self, from: data), state.valid else { continue }
            let age = Date().timeIntervalSince1970 - state.timestamp
            if age > 86400 { try? FileManager.default.removeItem(at: file) }
            guard age >= 0 && age < 8 else { continue }
            let playback = NowPlayingState(title: state.title, artist: "", isPlaying: state.playing, source: "Browser", position: state.position, duration: state.duration)
            sessions.append(MediaSession(id: "browser:" + state.id, providerID: id, playback: playback, canSeek: state.canSeek))
        }
        return (sessions.sorted { $0.id < $1.id }, sessions.isEmpty ? "Enable a media tab with the companion extension." : "Connected")
    }
    func perform(session: String, command: PlaybackCommand?, position: Double?) throws {
        guard sessions().sessions.contains(where: { $0.id == session }) else { throw WidgetActionError(message: "That browser media session is no longer available.") }
        let id = String(session.dropFirst("browser:".count))
        guard command == nil || command == .playPause else { throw WidgetActionError(message: "This browser provider supports play/pause and seeking.") }
        if let position, !position.isFinite || position < 0 { throw WidgetActionError(message: "Invalid playback position.") }
        let action = BrowserCommand(action: position == nil ? "playPause" : "seek", position: position)
        try BrowserBridge.write(action, to: BrowserBridge.file(id, suffix: "-command"))
        // Wait off the UI thread for an acknowledgement rather than claiming delivery is success.
        let deadline = Date(timeIntervalSinceNow: 4)
        while Date() < deadline {
            if let data = BoundedFile.read(BrowserBridge.file(id, suffix: "-state"), maximumBytes: 65536), let snapshot = try? JSONDecoder().decode(BrowserSnapshot.self, from: data), snapshot.acknowledged == action.id {
                if let error = snapshot.error { throw WidgetActionError(message: error) }; return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw WidgetActionError(message: "The browser did not respond. Keep the enabled media tab open and try again.")
    }
}
