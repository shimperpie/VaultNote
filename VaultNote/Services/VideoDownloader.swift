import Foundation

// MARK: - Delegate Protocol

/// 用于 URLSession 委托回调的代理对象
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    let onComplete: (URL) -> Void
    let onError: (Error) -> Void

    // 用于保存下载完成的临时文件（避免被系统自动清理）
    private var savedTempURL: URL?

    init(onProgress: @escaping (Double) -> Void,
         onComplete: @escaping (URL) -> Void,
         onError: @escaping (Error) -> Void) {
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [weak self] in
            self?.onProgress(progress)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // 立即把临时文件复制到安全位置 — 必须在 delegate 回调内同步完成
        // URLSession 会在回调返回后清理临时文件
        let fm = FileManager.default
        let destDir = fm.temporaryDirectory.appendingPathComponent("VaultNoteDownloads")
        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destURL = destDir.appendingPathComponent(UUID().uuidString + ".mp4")
        try? fm.removeItem(at: destURL) // 移除旧文件（不太可能但安全）

        do {
            try fm.copyItem(at: location, to: destURL)
            savedTempURL = destURL
        } catch {
            // 复制失败，仍传原始 location（尽力而为）
            savedTempURL = location
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let url = self.savedTempURL else { return }
            self.onComplete(url)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return // 取消不报错
            }
            DispatchQueue.main.async { [weak self] in
                self?.onError(error)
            }
        }
    }
}

// MARK: - Downloader

/// 视频下载器 — 带进度回调、支持取消
final class VideoDownloader {

    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var delegate: DownloadDelegate?

    /// 下载视频文件
    func download(
        url: URL,
        filename: String,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (URL) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        cancel()

        let dlDelegate = DownloadDelegate(
            onProgress: onProgress,
            onComplete: onComplete,
            onError: onError
        )
        self.delegate = dlDelegate

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600

        let dlSession = URLSession(
            configuration: config,
            delegate: dlDelegate,
            delegateQueue: nil
        )
        self.session = dlSession

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        task = dlSession.downloadTask(with: request)
        task?.resume()
    }

    /// 取消当前下载
    func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        delegate = nil
    }
}
