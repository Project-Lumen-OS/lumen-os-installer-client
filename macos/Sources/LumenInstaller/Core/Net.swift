import Foundation

enum Net {
    static func json(_ url: String) async throws -> Any {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("lumen-installer", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppError(L("GitHub ответил %@", "\((resp as? HTTPURLResponse)?.statusCode ?? 0)"))
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Downloads to dest (skipped when a file of the expected size is already there), reporting progress.
    static func download(_ url: String, to dest: String, size: Int64? = nil, progress: @escaping (Int64, Int64) -> Void) async throws {
        if let size, FileManager.default.size(dest) == size { progress(size, size); return }
        try FileManager.default.createDirectory(atPath: dest.parentPath, withIntermediateDirectories: true)
        let d = Downloader(progress: progress)
        let tmp = try await d.fetch(URL(string: url)!)
        try? FileManager.default.removeItem(atPath: dest)
        try FileManager.default.moveItem(at: tmp, to: URL(fileURLWithPath: dest))
        if let size, FileManager.default.size(dest) != size { throw AppError(L("файл %@ скачан не полностью", "\(dest.lastPath)")) }
    }
}

private final class Downloader: NSObject, URLSessionDownloadDelegate {
    let progress: (Int64, Int64) -> Void
    var cont: CheckedContinuation<URL, Error>?
    init(progress: @escaping (Int64, Int64) -> Void) { self.progress = progress }

    func fetch(_ url: URL) async throws -> URL {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { c in
                cont = c
                session.downloadTask(with: url).resume()
            }
        } onCancel: { session.invalidateAndCancel() }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite t: Int64) {
        progress(w, t)
    }
    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { cont?.resume(throwing: AppError("HTTP \(code)")); cont = nil; return }
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try FileManager.default.moveItem(at: location, to: keep); cont?.resume(returning: keep) }
        catch { cont?.resume(throwing: error) }
        cont = nil
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { cont?.resume(throwing: error); cont = nil }
    }
}
