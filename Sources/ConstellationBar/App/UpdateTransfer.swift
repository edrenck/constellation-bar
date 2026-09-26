import Foundation
import CryptoKit

/// Each transfer owns one serial delegate and a bounded sink. URLSession's buffered
/// data/download conveniences cannot enforce a cap while a server is still sending.
final class UpdateTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let destination: URL?
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<Data, Error>?
    private var cancelled = false
    private var completed = false
    private var data = Data()
    private var received = 0
    private var file: FileHandle?

    init(configuration: URLSessionConfiguration, limit: Int, destination: URL? = nil) {
        self.configuration = configuration
        self.limit = limit
        self.destination = destination
    }

    func receive(_ request: URLRequest) async throws -> Data {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                do {
                    if let destination {
                        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                            throw UpdateError(message: "Couldn’t create the temporary update download.")
                        }
                        file = try FileHandle(forWritingTo: destination)
                    }
                    let queue = OperationQueue()
                    queue.maxConcurrentOperationCount = 1
                    configuration.timeoutIntervalForResource = request.timeoutInterval
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                    self.session = session
                    let task = session.dataTask(with: request)
                    self.task = task
                    lock.unlock()
                    task.resume()
                } catch {
                    lock.unlock()
                    finish(error)
                }
            }
        }, onCancel: { self.cancel() })
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        finish(CancellationError())
    }

    private func finish(_ error: Error? = nil) {
        lock.lock()
        guard !completed, let continuation else { lock.unlock(); return }
        completed = true
        self.continuation = nil
        let task = task
        let session = session
        self.task = nil
        self.session = nil
        var finalError = error
        do { try file?.close() } catch { if finalError == nil { finalError = error } }
        file = nil
        if finalError != nil, let destination { try? FileManager.default.removeItem(at: destination) }
        let result = data
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        if let finalError { continuation.resume(throwing: finalError) }
        else { continuation.resume(returning: result) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            completionHandler(.cancel)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            finish(UpdateError(message: code == 403 || code == 429 ? "GitHub’s rate limit was reached. Try again later." : "GitHub request failed (HTTP \(code))."))
            return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel)
            finish(UpdateError(message: "GitHub declared an unexpectedly large response."))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else {
            completionHandler(nil)
            finish(UpdateError(message: "GitHub redirected the download to an insecure URL."))
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        guard bytes.count <= limit - received else {
            lock.unlock()
            finish(UpdateError(message: "GitHub returned an unexpectedly large response."))
            return
        }
        received += bytes.count
        do {
            if let file { try file.write(contentsOf: bytes) }
            else { data.append(bytes) }
            lock.unlock()
        } catch {
            lock.unlock()
            finish(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish(error) }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
