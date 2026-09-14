import AppKit

/// A user-selected, read-only security-scoped bookmark. No broad disk permission
/// or path-based attempt to bypass macOS's protection of Outlook data.
enum OutlookCacheAccess {
    private static let key = "outlookCalendarCacheBookmark"
    static var configured: Bool { UserDefaults.standard.data(forKey: key) != nil }

    static func chooseFolder(completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose Outlook data folder"
        panel.message = "Select Outlook’s local data folder. ConstellationBar reads Outlook’s cache locally to find calendar records and never changes its files."
        panel.prompt = "Use read-only"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/UBF8T346G9.Office/Outlook")
        panel.begin { result in
            guard result == .OK, let url = panel.url else { completion(nil); return }
            do {
                guard url.lastPathComponent == "Outlook" else {
                    completion("Select the Outlook folder inside Library → Group Containers → UBF8T346G9.Office."); return
                }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: key)
                completion(nil)
            } catch { completion("Could not save access to the selected Outlook folder. Please choose it again.") }
        }
    }

    static func disconnect() { UserDefaults.standard.removeObject(forKey: key) }

    static func withFolder<T>(_ read: (URL) throws -> T) throws -> T {
        guard let bookmark = UserDefaults.standard.data(forKey: key) else {
            throw OutlookCacheError.message("Choose Outlook’s local data folder to read its synced calendars.")
        }
        var stale = false
        let url: URL
        do { url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) }
        catch { throw OutlookCacheError.message("Outlook folder access has expired. Choose the folder again.") }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if stale {
            let renewed = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(renewed, forKey: key)
        }
        return try read(url)
    }
}

enum OutlookCacheError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
