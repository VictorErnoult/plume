import CryptoKit
import Foundation

/// Downloads one file into `<destination>.partial`, resuming with an HTTP range, then checks
/// its size and SHA-256 before renaming it.
struct ModelFileDownloader {
    let configuration: URLSessionConfiguration

    func fetch(from url: URL, to destination: URL, expected: ModelDownload, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { return }
        let partial = destination.appendingPathExtension("partial")
        if !fm.fileExists(atPath: partial.path) { fm.createFile(atPath: partial.path, contents: nil) }
        let offset = Int64((try? fm.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value ?? 0)
        var request = URLRequest(url: url)
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        try await RangeDownload(file: partial, offset: offset, progress: progress).run(request, configuration: configuration)
        guard try Self.size(of: partial) == expected.bytes, try Self.sha256(of: partial) == expected.sha256 else {
            try? fm.removeItem(at: partial)
            throw ReadAloudError.checksumMismatch
        }
        try fm.moveItem(at: partial, to: destination)
    }

    static func size(of url: URL) throws -> Int64 {
        Int64((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? -1)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// A data task appending to a file: `206` continues the partial file, `200` (the server
/// ignored the range) starts it over.
final class RangeDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let file: URL
    private var written: Int64
    private let progress: @Sendable (Int64) -> Void
    private var handle: FileHandle?
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    init(file: URL, offset: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.file = file
        self.written = offset
        self.progress = progress
    }

    func run(_ request: URLRequest, configuration: URLSessionConfiguration) async throws {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    self.continuation = continuation
                    let task = session.dataTask(with: request)
                    self.task = task
                    task.resume()
                    // A Cancel that came before the task existed had nothing to stop.
                    if cancelled { task.cancel() }
                }
            }
        } onCancel: {
            lock.withLock { () -> URLSessionDataTask? in
                cancelled = true
                return task
            }?.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            switch status {
            case 206:
                handle = try FileHandle(forWritingTo: file)
                try handle?.seekToEnd()
            case 200:
                handle = try FileHandle(forWritingTo: file)
                try handle?.truncate(atOffset: 0)
                written = 0
            default:
                throw ReadAloudError.httpStatus(status)
            }
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle?.write(contentsOf: data)
            written += Int64(data.count)
            progress(written)
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        if let failure = failure ?? error { continuation?.resume(throwing: failure) } else { continuation?.resume() }
    }
}
