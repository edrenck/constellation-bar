import Foundation
import Darwin

/// System-wide metadata through the macOS scripting host. MediaRemote is private API;
/// isolate it in a bounded subprocess so OS changes cannot crash the bar.
final class NativeMediaIntegration: MediaIntegrating {
    let id = "nativeMedia"
    private var artworkKey: [String] = []
    private var cachedArtwork: Data?
    private let runner: CommandRunning
    private static var helperPath: String {
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libNativeMediaHelper.dylib")
        return FileManager.default.fileExists(atPath: bundled.path) ? bundled.path : executableDirectory.appendingPathComponent("libNativeMediaHelper.dylib").path
    }
    init(runner: CommandRunning = CommandRunner()) { self.runner = runner }

    func sessions() -> (sessions: [MediaSession], status: String) {
        let result = runner.run("/usr/bin/perl", ["-e", Self.snapshotScript, Self.helperPath], timeout: 2)
        guard result.succeeded,
              let data = result.output.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return ([], "macOS Now Playing is unavailable. Try starting playback in your player.")
        }
        guard let title = snapshot.title, !title.isEmpty else {
            artworkKey = []; cachedArtwork = nil
            return ([], "Nothing playing on this Mac.")
        }
        let key = [snapshot.identifier ?? "", title, snapshot.artist ?? "", snapshot.album ?? "", snapshot.source ?? ""]
        if key != artworkKey { artworkKey = key; cachedArtwork = nil }
        if let encoded = snapshot.artwork, let data = Data(base64Encoded: encoded), !data.isEmpty { cachedArtwork = data }
        let duration = Self.nonnegative(snapshot.duration)
        let position = Self.nonnegative(snapshot.position)
        let playback = NowPlayingState(title: title, artist: snapshot.artist ?? "", isPlaying: (snapshot.rate ?? 0) > 0,
                                       source: snapshot.source ?? "macOS", position: duration > 0 ? min(position, duration) : position, duration: duration)
        return ([MediaSession(id: id, providerID: id, playback: playback, canSkip: true,
                              artwork: cachedArtwork, album: snapshot.album ?? "")], "Connected")
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
        guard let framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else {
            throw WidgetActionError(message: "macOS playback controls are unavailable.")
        }
        defer { dlclose(framework) }
        typealias SendCommand = @convention(c) (Int, CFDictionary?) -> Bool
        guard let symbol = dlsym(framework, "MRMediaRemoteSendCommand"),
              unsafeBitCast(symbol, to: SendCommand.self)(code, nil) else {
            throw WidgetActionError(message: "macOS could not deliver that playback command.")
        }
    }

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
