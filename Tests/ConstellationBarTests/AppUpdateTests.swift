import XCTest
import Foundation
import ServiceManagement
@testable import ConstellationBar

final class AppUpdateTests: XCTestCase {
    func testVersionComparisonUsesNumericTagsAndPrereleaseOrdering() throws {
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("v0.10.0")), try XCTUnwrap(AppVersion("0.9.9")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.0.0-rc.2")), try XCTUnwrap(AppVersion("1.0.0-rc.10")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.0.0-rc.10")), try XCTUnwrap(AppVersion("1.0.0")))
        XCTAssertEqual(AppVersion("v1.2.3"), AppVersion("1.2.3+build.42"))
        for invalid in ["", "+build", "latest", "1.2", "1.2.3.4", "1.two.3", "1.2.3-", "1.2.3-alpha..2", "01.2.3", "1.2.3-alpha.01"] {
            XCTAssertNil(AppVersion(invalid), invalid)
        }
    }

    func testChecksumMustMatchExactArchiveName() {
        let digest = String(repeating: "a", count: 64)
        XCTAssertEqual(AppUpdater.checksum(for: "ConstellationBar-1.0.0-universal.zip", in: "\(digest.uppercased())  ConstellationBar-1.0.0-universal.zip\n"), digest)
        XCTAssertNil(AppUpdater.checksum(for: "ConstellationBar-1.0.0-universal.zip", in: "\(digest)  malicious.zip"))
        XCTAssertNil(AppUpdater.checksum(for: "archive.zip", in: "invalid  archive.zip"))
    }

    func testArchivePathsCannotEscapeStagingOrReplaceOtherApps() {
        XCTAssertTrue(AppUpdater.safeArchiveEntries("ConstellationBar.app/\nConstellationBar.app/Contents/MacOS/ConstellationBar\n__MACOSX/._ConstellationBar.app"))
        for unsafe in ["", "/Applications/Other.app/file", "ConstellationBar.app/../../file", "Other.app/file", "ConstellationBar.app\\..\\file"] {
            XCTAssertFalse(AppUpdater.safeArchiveEntries(unsafe), unsafe)
        }
    }

    func testArchiveExpansionIsBoundedBeforeExtraction() {
        XCTAssertTrue(AppUpdater.safeArchiveSize("42 files, 20000000 bytes uncompressed, 4000000 bytes compressed: 80.0%"))
        XCTAssertFalse(AppUpdater.safeArchiveSize("2 files, 999999999999 bytes uncompressed, 1000 bytes compressed"))
        XCTAssertFalse(AppUpdater.safeArchiveSize("unrecognized archive"))
    }

    func testReleaseArchiveMustMatchTagAndUniversalPackaging() throws {
        let release = try JSONDecoder().decode(GitHubUpdateRelease.self, from: Data("""
        {"tag_name":"v1.0.0","html_url":"https://github.com/edrenck/constellation-bar/releases/tag/v1.0.0","draft":false,"assets":[{"name":"ConstellationBar-1.0.0-universal.zip","size":100,"browser_download_url":"https://github.com/edrenck/constellation-bar/releases/download/v1.0.0/ConstellationBar-1.0.0-universal.zip"}]}
        """.utf8))
        XCTAssertNotNil(release.archive(for: "v1.0.0"))
        XCTAssertNil(release.archive(for: "v1.1.0"))
    }

    func testVerificationToolsFailClosedOnTimeoutTruncationAndFailure() throws {
        XCTAssertEqual(try AppUpdater.verifiedCommandOutput(CommandResult(output: "verified", status: 0)), "verified")
        XCTAssertThrowsError(try AppUpdater.verifiedCommandOutput(CommandResult(status: 0, timedOut: true)))
        XCTAssertThrowsError(try AppUpdater.verifiedCommandOutput(CommandResult(output: String(repeating: "a", count: 1_048_576), status: 0)))
        XCTAssertThrowsError(try AppUpdater.verifiedCommandOutput(CommandResult(error: "invalid signature", status: 1)))
    }

    func testLiveCheckUsesGreatestNumericTagAndOffersPublishedUpdate() async {
        let updater = await check(version: "0.9.0") { request in
            if request.url!.path.hasSuffix("/tags") {
                return (200, Data("[{\"name\":\"v0.9.0\"},{\"name\":\"v0.10.0\"},{\"name\":\"v2.0.0-rc.1\"}]".utf8))
            }
            XCTAssertTrue(request.url!.path.hasSuffix("/v0.10.0"))
            return (200, Self.releaseData(tag: "v0.10.0"))
        }
        XCTAssertEqual(updater.statusText, "Update available: v0.10.0")
    }

    func testLiveCheckTreatsCurrentAndOlderTagsAsUpToDate() async {
        for tag in ["v0.7.1", "v0.7.0"] {
            let updater = await check(version: "0.7.1") { request in
                XCTAssertTrue(request.url!.path.hasSuffix("/tags"), "A current build does not fetch an older release")
                return (200, Data("[{\"name\":\"\(tag)\"}]".utf8))
            }
            XCTAssertEqual(updater.statusText, "ConstellationBar 0.7.1 is up to date.")
        }
    }

    func testLiveCheckExplainsUnpublishedAssetsAndHTTPFailure() async {
        let missing = await check(version: "0.7.0") { request in
            if request.url!.path.hasSuffix("/tags") { return (200, Data("[{\"name\":\"v0.7.1\"}]".utf8)) }
            return (200, Self.releaseData(tag: "v0.7.1", assets: false))
        }
        XCTAssertTrue(missing.statusText.contains("archive and SHA256SUMS are not published"), missing.statusText)
        let failed = await check(version: "0.7.0") { _ in (503, Data()) }
        XCTAssertTrue(failed.statusText.contains("HTTP 503"), failed.statusText)
        let limited = await check(version: "0.7.0") { _ in (403, Data()) }
        XCTAssertTrue(limited.statusText.contains("rate limit"), limited.statusText)
    }

    func testRepeatedChecksFetchFreshTagsInsteadOfUsingCachedRelease() async {
        let lock = NSLock()
        var tagRequests = 0
        UpdateURLProtocol.setResponder { request in
            lock.lock(); defer { lock.unlock() }
            if request.url!.path.hasSuffix("/tags") {
                tagRequests += 1
                return (200, Data("[{\"name\":\"\(tagRequests == 1 ? "v0.9.0" : "v0.10.0")\"}]".utf8))
            }
            return (200, Self.releaseData(tag: tagRequests == 1 ? "v0.9.0" : "v0.10.0"))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let updater = AppUpdater(session: session, installedVersion: "0.7.1")
        for expected in ["v0.9.0", "v0.10.0"] {
            let complete = expectation(description: "Fresh check completed")
            let observer = NotificationCenter.default.addObserver(forName: AppUpdater.changed, object: updater, queue: nil) { _ in
                if !updater.isBusy { complete.fulfill() }
            }
            updater.checkForUpdates(interactive: false)
            await fulfillment(of: [complete], timeout: 5)
            NotificationCenter.default.removeObserver(observer)
            XCTAssertEqual(updater.statusText, "Update available: \(expected)")
        }
    }

    func testUnknownDevelopmentVersionDoesNotClaimAnAvailableUpdateOrCallGitHub() async {
        let updater = await check(version: nil) { _ in
            XCTFail("Unknown development versions must not request GitHub")
            return (200, Data("[{\"name\":\"v0.7.1\"}]".utf8))
        }
        XCTAssertTrue(updater.statusText.contains("no version to compare"), updater.statusText)
    }

    private func check(version: String?, responder: @escaping (URLRequest) -> (Int, Data)) async -> AppUpdater {
        UpdateURLProtocol.setResponder(responder)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let updater = AppUpdater(session: session, installedVersion: version)
        let complete = expectation(description: "GitHub update check completed")
        let observer = NotificationCenter.default.addObserver(forName: AppUpdater.changed, object: updater, queue: nil) { _ in
            if !updater.isBusy { complete.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        updater.checkForUpdates(interactive: false)
        await fulfillment(of: [complete], timeout: 5)
        XCTAssertFalse(updater.isBusy)
        return updater
    }

    private static func releaseData(tag: String, assets: Bool = true) -> Data {
        let version = String(tag.dropFirst())
        let artifact: [[String: Any]] = assets ? [
            ["name": "ConstellationBar-\(version)-universal.zip", "size": 100, "browser_download_url": "https://github.com/edrenck/constellation-bar/releases/download/\(tag)/ConstellationBar-\(version)-universal.zip"],
            ["name": "SHA256SUMS", "size": 100, "browser_download_url": "https://github.com/edrenck/constellation-bar/releases/download/\(tag)/SHA256SUMS"]
        ] : []
        return try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": "https://github.com/edrenck/constellation-bar/releases/tag/\(tag)", "draft": false, "prerelease": true, "assets": artifact])
    }

    func testLoginStartupRepairFollowsRequestedStateAndBundleMove() {
        let path = "/Applications/ConstellationBar.app"
        XCTAssertTrue(LaunchAtLogin.shouldReconcile(requested: true, status: .enabled, registeredPath: "/Downloads/ConstellationBar.app", currentPath: path))
        XCTAssertTrue(LaunchAtLogin.shouldReconcile(requested: true, status: .notFound, registeredPath: path, currentPath: path))
        XCTAssertTrue(LaunchAtLogin.shouldReconcile(requested: true, status: .notRegistered, registeredPath: path, currentPath: path))
        XCTAssertFalse(LaunchAtLogin.shouldReconcile(requested: true, status: .enabled, registeredPath: path, currentPath: path))
        XCTAssertFalse(LaunchAtLogin.shouldReconcile(requested: true, status: .requiresApproval, registeredPath: nil, currentPath: path))
        XCTAssertFalse(LaunchAtLogin.shouldReconcile(requested: false, status: .notRegistered, registeredPath: nil, currentPath: path))
    }
}

private final class UpdateURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responder: ((URLRequest) -> (Int, Data))?

    static func setResponder(_ response: @escaping (URLRequest) -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }
        responder = response
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let respond = Self.responder
        Self.lock.unlock()
        guard let respond else { return }
        let (status, data) = respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
