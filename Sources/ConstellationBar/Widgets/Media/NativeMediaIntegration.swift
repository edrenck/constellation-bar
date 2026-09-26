import Foundation

/// System-wide metadata through the macOS scripting host. MediaRemote is private API;
/// isolate it in a bounded subprocess so OS changes cannot crash the bar.
final class NativeMediaIntegration: MediaIntegrating {
    let id = "nativeMedia"
    private var artworkKey: [String] = []
    private var cachedArtwork: Data?
    private var lastSession: MediaSession?
    private var lastRead: Date?
    private let runner: CommandRunning
    private let now: () -> Date
    private static var helperPath: String {
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libNativeMediaHelper.dylib")
        return FileManager.default.fileExists(atPath: bundled.path) ? bundled.path : executableDirectory.appendingPathComponent("libNativeMediaHelper.dylib").path
    }
    init(runner: CommandRunning = CommandRunner(), now: @escaping () -> Date = Date.init) { self.runner = runner; self.now = now }

    func sessions() -> (sessions: [MediaSession], status: String) {
        let result = runner.run("/usr/bin/perl", ["-e", Self.snapshotScript, Self.helperPath], timeout: 2)
        guard result.succeeded,
              let data = result.output.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            // A single slow MediaRemote callback should not replace an active
            // track with a setup warning. Expire the fallback so stale tracks
            // cannot remain visible indefinitely after the player closes.
            if let lastSession, let lastRead, now().timeIntervalSince(lastRead) < 10 {
                return ([lastSession], "Reconnecting to macOS Now Playing…")
            }
            let message: String
            if result.timedOut || result.error.contains("timed out") { message = "macOS Now Playing timed out. Playback will be checked again automatically." }
            else if result.error.contains("MediaRemote") { message = "macOS Now Playing is unavailable on this macOS version. Apple Music can provide playback through Automation access." }
            else if result.error.contains("dl_load") || result.error.contains("dlopen") || result.error.contains("Native media helper") {
                message = "The macOS Now Playing helper could not load. Reinstall Constellation Bar to restore it."
            } else { message = "macOS Now Playing is unavailable. Playback will be checked again automatically; no permission is required." }
            return ([], message)
        }
        guard let title = snapshot.title, !title.isEmpty else {
            artworkKey = []; cachedArtwork = nil; lastSession = nil; lastRead = nil
            return ([], "Nothing playing on this Mac.")
        }
        let key = [snapshot.identifier ?? "", title, snapshot.artist ?? "", snapshot.album ?? "", snapshot.source ?? ""]
        if key != artworkKey { artworkKey = key; cachedArtwork = nil }
        if let encoded = snapshot.artwork, let data = Data(base64Encoded: encoded), !data.isEmpty { cachedArtwork = data }
        let duration = Self.nonnegative(snapshot.duration)
        let position = Self.nonnegative(snapshot.position)
        let playback = NowPlayingState(title: title, artist: snapshot.artist ?? "", isPlaying: (snapshot.rate ?? 0) > 0,
                                       source: snapshot.source ?? "macOS", position: duration > 0 ? min(position, duration) : position, duration: duration)
        let session = MediaSession(id: id, providerID: id, playback: playback, canSkip: true,
                                   artwork: cachedArtwork, album: snapshot.album ?? "")
        lastSession = session; lastRead = now()
        return ([session], "Connected")
    }

    func perform(session: String, command: PlaybackCommand?, position: Double?) throws {
        guard session == id, position == nil, let command else {
            throw WidgetActionError(message: "Seeking is not available through macOS Now Playing.")
        }
        let code: Int
        switch command {
        case .playPause: code = 2
        case .next: code = 4
        case .previous: code = 5
        default: throw WidgetActionError(message: "Change shuffle and repeat in your player.")
        }
        let result = runner.run("/usr/bin/perl", ["-e", Self.commandScript, Self.helperPath, String(code)], timeout: 2)
        guard !result.timedOut else { throw WidgetActionError(message: "macOS playback control timed out. Try again or use your player’s controls.") }
        guard result.succeeded, let data = result.output.data(using: .utf8),
              let response = try? JSONDecoder().decode(ControlResult.self, from: data), response.version == 1 else {
            throw WidgetActionError(message: "macOS playback controls are unavailable. Use your player’s controls; Apple Music controls remain available with Automation access.")
        }
        guard response.success else {
            throw WidgetActionError(message: response.message ?? "macOS could not deliver that playback command. Use your player’s controls.")
        }
    }

    private struct ControlResult: Decodable { var version: Int; var success: Bool; var message: String? }
    static let commandScript = #"""
    use strict;
    use warnings;
    use DynaLoader;
    my $path = shift @ARGV or die "Native media helper missing";
    my $command = shift @ARGV;
    die "Invalid playback command" unless defined $command && $command =~ /^(2|4|5)$/;
    $ENV{CONSTELLATION_MEDIA_COMMAND} = $command;
    my $handle = DynaLoader::dl_load_file($path, 0) or die DynaLoader::dl_error();
    my $symbol = DynaLoader::dl_find_symbol($handle, "constellation_media_command") or die "MediaRemote command callback missing";
    DynaLoader::dl_install_xsub("main::command", $symbol);
    command();
    """#

    private static func nonnegative(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }; return max(0, value)
    }
    private struct Snapshot: Decodable {
        var title: String?; var artist: String?; var album: String?; var source: String?
        var identifier: String?
        var rate: Double?; var position: Double?; var duration: Double?; var artwork: String?
    }
    static let snapshotScript = #"""
    use strict;
    use warnings;
    use DynaLoader;
    my $path = shift @ARGV or die "Native media helper missing";
    my $handle = DynaLoader::dl_load_file($path, 0) or die DynaLoader::dl_error();
    my $symbol = DynaLoader::dl_find_symbol($handle, "constellation_media_snapshot") or die "Native media callback missing";
    DynaLoader::dl_install_xsub("main::snapshot", $symbol);
    snapshot();
    """#
}
