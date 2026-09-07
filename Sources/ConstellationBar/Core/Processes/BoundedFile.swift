import Foundation
import Darwin

/// Reads regular files without following a final symlink or allocating beyond the byte limit.
/// Nonblocking open ensures a FIFO cannot hang a sampling queue before fstat rejects it.
enum BoundedFile {
    static func read(_ url: URL, maximumBytes: Int) -> Data? {
        guard maximumBytes >= 0, maximumBytes < Int.max else { return nil }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= maximumBytes else { return nil }
        var result = Data()
        do {
            while let chunk = try handle.read(upToCount: min(8192, maximumBytes + 1 - result.count)), !chunk.isEmpty {
                result.append(chunk)
                guard result.count <= maximumBytes else { return nil }
            }
        } catch { return nil }
        return result
    }
}
