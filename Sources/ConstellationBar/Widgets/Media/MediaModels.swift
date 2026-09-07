import Foundation
import AppKit


struct NowPlayingState: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var source: String
    var position: Double = 0
    var duration: Double = 0

    static let empty = NowPlayingState(title: "Nothing playing", artist: "", isPlaying: false, source: "")
}

struct MediaSession: Equatable {
    var id: String
    var providerID: String
    var playback: NowPlayingState
    var canSeek = false
    var canSkip = false
    var artwork: Data? = nil
    var album: String = ""
    var shuffle: Bool? = nil
    var repeatMode: MediaRepeatMode? = nil
}

enum MediaRepeatMode: String { case off, one, all
    var next: MediaRepeatMode { self == .off ? .all : self == .all ? .one : .off }
}

protocol MediaIntegrating: AnyObject {
    var id: String { get }
    func sessions() -> (sessions: [MediaSession], status: String)
    func perform(session: String, command: PlaybackCommand?, position: Double?) throws
}
