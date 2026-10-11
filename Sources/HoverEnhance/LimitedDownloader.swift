import Foundation
import os

/// Downloads with a size limit. A response that says it's larger than the limit is cancelled as soon
/// as its headers arrive, and one that doesn't say is cancelled once it grows past the limit, so a
/// huge file is never read into memory whole.
final class LimitedDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Outcome: Sendable {
        case data(Data, URLResponse)
        /// Larger than the limit: its size when the server said, nil when it only ran past the limit.
        case tooLarge(bytes: Int64?)
        case failed
    }

    private struct Download {
        let limit: Int64?
        let continuation: CheckedContinuation<Outcome, Never>
        var response: URLResponse?
        var data = Data()
    }

    /// In-flight downloads by task; the session calls back on its own queue.
    private let downloads = OSAllocatedUnfairLock<[Int: Download]>(initialState: [:])
    private var session: URLSession!

    init(configuration: URLSessionConfiguration) {
        super.init()
        // The session keeps its delegate for as long as it lives, which is as long as this does.
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// `limit` is in bytes; nil downloads whatever size it is.
    func data(for request: URLRequest, limit: Int64?) async -> Outcome {
        let task = session.dataTask(with: request)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                downloads.withLock { $0[task.taskIdentifier] = Download(limit: limit, continuation: continuation) }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// Takes the download out of the list and answers its caller. Only the first finish counts.
    private func finish(_ task: URLSessionTask, _ outcome: (Download) -> Outcome) {
        guard let download = downloads.withLock({ $0.removeValue(forKey: task.taskIdentifier) }) else { return }
        download.continuation.resume(returning: outcome(download))
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        // -1 when the server doesn't say.
        let expected = response.expectedContentLength
        let limit = downloads.withLock { downloads -> Int64?? in
            guard downloads[dataTask.taskIdentifier] != nil else { return nil }
            downloads[dataTask.taskIdentifier]?.response = response
            if expected > 0, expected <= Int64(Int.max) { downloads[dataTask.taskIdentifier]?.data.reserveCapacity(Int(expected)) }
            return .some(downloads[dataTask.taskIdentifier]?.limit)
        }
        if let limit = limit ?? nil, expected > limit {
            finish(dataTask) { _ in .tooLarge(bytes: expected) }
            completionHandler(.cancel)
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overLimit = downloads.withLock { downloads -> Bool in
            guard var download = downloads[dataTask.taskIdentifier] else { return false }
            download.data.append(data)
            if let limit = download.limit, Int64(download.data.count) > limit { return true }
            downloads[dataTask.taskIdentifier] = download
            return false
        }
        if overLimit {
            finish(dataTask) { _ in .tooLarge(bytes: nil) }
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        finish(task) { download in
            guard error == nil, let response = download.response else { return .failed }
            return .data(download.data, response)
        }
    }
}
