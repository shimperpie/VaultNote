import Foundation

// MARK: - Models

/// 抖音媒体项（单张图片或单个视频）
struct DouyinMediaItem {
    enum MediaType: String { case video, image }
    let url: URL
    let type: MediaType
    let quality: String  // 如 "2560p", "原图"
    let previewURL: URL?  // 动图/视频的封面图（用于下载弹窗预览）

    init(url: URL, type: MediaType, quality: String, previewURL: URL? = nil) {
        self.url = url
        self.type = type
        self.quality = quality
        self.previewURL = previewURL
    }
}

/// 抖音 BGM 音乐信息
struct DouyinMusicInfo {
    let title: String
    let author: String
    let url: URL
    let coverURL: URL?
}

/// 抖音解析结果
struct DouyinVideoInfo {
    let videoID: String
    let title: String
    let coverURL: URL?
    let isAlbum: Bool          // true = 合集（多图/多视频）
    let mediaItems: [DouyinMediaItem]  // 至少 1 个
    let music: DouyinMusicInfo?  // BGM 音乐（单视频才有，合集通常没有）

    /// 向后兼容：主下载链接（单视频或合集第一项）
    var downloadURL: URL { mediaItems.first!.url }
    /// 向后兼容：画质描述
    var quality: String { mediaItems.first!.quality }
    /// 合集项数
    var itemCount: Int { mediaItems.count }
    /// 合集描述
    var albumDescription: String {
        let videoCount = mediaItems.filter { $0.type == .video }.count
        let imageCount = mediaItems.filter { $0.type == .image }.count
        if videoCount > 0 && imageCount > 0 {
            return "共 \(itemCount) 项 · \(videoCount) 动图 + \(imageCount) 图片"
        } else if videoCount > 0 {
            return "共 \(itemCount) 项 · 动图"
        } else {
            return "共 \(itemCount) 项 · 图集"
        }
    }
}

// MARK: - Errors

enum DouyinError: LocalizedError {
    case invalidURL
    case parseFailed(String)
    case networkError(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:     return "无效的抖音链接"
        case .parseFailed(let s): return "解析失败: \(s)"
        case .networkError(let s): return "网络错误: \(s)"
        case .apiError(let s): return "API 错误: \(s)"
        }
    }
}

// MARK: - Parser

/// 抖音/小红书分享链接解析器 — 通过第三方 API 获取无水印视频/图片
final class DouyinParser {

    private let endpoints = [
        "https://api.bugpk.com/api/short_videos",
        "https://api.bugpk.com/api/svparse/",
    ]

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    /// 从抖音分享链接解析视频/图集信息
    func parse(shareURL: String) async throws -> DouyinVideoInfo {
        guard let url = normalizeURL(shareURL) else {
            throw DouyinError.invalidURL
        }

        var lastError: Error?
        for endpoint in endpoints {
            do {
                return try await tryParseAPI(endpoint: endpoint, shareURL: url)
            } catch {
                lastError = error
            }
        }

        let msg = lastError.map { "\($0.localizedDescription)" } ?? "所有解析服务暂不可用"
        throw DouyinError.parseFailed(msg)
    }

    // MARK: - Private

    private func normalizeURL(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        for token in trimmed.components(separatedBy: .whitespacesAndNewlines) {
            if let url = URL(string: token),
               let host = url.host,
               host.contains("douyin.com") || host.contains("iesdouyin.com")
                || host.contains("xiaohongshu.com") || host.contains("xhslink.com") {
                return url
            }
        }

        if let match = try? NSRegularExpression(
            pattern: #"https?://[^\s]*(?:douyin\.com|iesdouyin\.com|xiaohongshu\.com|xhslink\.com)[^\s]+"#
        )
            .firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range, in: trimmed),
           let url = URL(string: String(trimmed[range])) {
            return url
        }

        return nil
    }

    private func tryParseAPI(endpoint: String, shareURL: URL) async throws -> DouyinVideoInfo {
        guard let apiURL = URL(string: endpoint) else {
            throw DouyinError.invalidURL
        }

        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "url", value: shareURL.absoluteString)]

        guard let requestURL = components?.url else {
            throw DouyinError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(desktopUA, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200...299).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8)?.prefix(300) ?? "<无法解码>"
            throw DouyinError.apiError("HTTP \(statusCode) — \(body)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let preview = String(data: data, encoding: .utf8)?.prefix(500) ?? "<无法解码>"
            throw DouyinError.parseFailed("返回非JSON: \(preview)")
        }

        return try extractVideoInfo(from: json, shareURL: shareURL.absoluteString)
    }

    /// 从 API JSON 提取视频/图集信息
    private func extractVideoInfo(from json: [String: Any], shareURL: String) throws -> DouyinVideoInfo {
        if let code = json["code"] as? Int, code != 200 {
            let msg = json["msg"] as? String ?? "未知错误"
            throw DouyinError.apiError("code=\(code), msg=\(msg)")
        }

        guard let data = json["data"] as? [String: Any] else {
            throw DouyinError.parseFailed("JSON 中未找到 data 字段")
        }

        let isXHS = shareURL.lowercased().contains("xiaohongshu")
            || shareURL.lowercased().contains("xhslink")
        let title = (data["title"] as? String) ?? (isXHS ? "小红书笔记" : "抖音视频")
        let coverStr = data["cover"] as? String
        let contentType = data["type"] as? String ?? "video"
        let videoID = extractVideoID(from: shareURL) ?? UUID().uuidString

        // ── 图集/合集：多图（可能含 live_photo 动图）──
        let images = data["images"] as? [String] ?? []
        let livePhotos = data["live_photo"] as? [[String: Any]] ?? []

        if !images.isEmpty {
            var items: [DouyinMediaItem] = []

            if isXHS {
                // 小红书实况图：优先取动态视频（动图 MP4），个别无视频时回退静态图
                for lp in livePhotos {
                    if let videoURLStr = lp["video"] as? String,
                       let url = URL(string: videoURLStr) {
                        let coverURL = (lp["image"] as? String).flatMap { URL(string: $0) }
                        items.append(DouyinMediaItem(url: url, type: .video, quality: "动图", previewURL: coverURL))
                    } else if let imageURLStr = lp["image"] as? String,
                       let url = URL(string: imageURLStr) {
                        items.append(DouyinMediaItem(url: url, type: .image, quality: "原图"))
                    }
                }
                let liveCount = items.count
                for i in liveCount..<images.count {
                    if let url = URL(string: images[i]) {
                        items.append(DouyinMediaItem(url: url, type: .image, quality: "原图"))
                    }
                }
            } else {
                // 抖音：先处理 live_photo — 这些是动图（无声音短视频）
                for lp in livePhotos {
                    if let videoURLStr = lp["video"] as? String,
                       let url = URL(string: videoURLStr) {
                        let coverURL = (lp["image"] as? String).flatMap { URL(string: $0) }
                        items.append(DouyinMediaItem(url: url, type: .video, quality: "动图", previewURL: coverURL))
                    }
                }
                let animatedCount = items.count
                for i in animatedCount..<images.count {
                    if let url = URL(string: images[i]) {
                        items.append(DouyinMediaItem(url: url, type: .image, quality: "原图"))
                    }
                }
            }

            if !items.isEmpty {
                return DouyinVideoInfo(
                    videoID: videoID,
                    title: title,
                    coverURL: coverStr.flatMap { URL(string: $0) },
                    isAlbum: true,
                    mediaItems: items,
                    music: extractMusic(from: data)
                )
            }
        }

        // ── 单视频 ──
        let (videoURL, quality) = extractBestQuality(from: data)
        guard let downloadURL = videoURL else {
            throw DouyinError.parseFailed("未找到视频或图片下载地址")
        }

        let music = extractMusic(from: data)
        let item = DouyinMediaItem(url: downloadURL, type: .video, quality: quality)
        return DouyinVideoInfo(
            videoID: videoID,
            title: title,
            coverURL: coverStr.flatMap { URL(string: $0) },
            isAlbum: false,
            mediaItems: [item],
            music: music
        )
    }

    /// 从 data JSON 中选最高画质的视频链接
    private func extractBestQuality(from data: [String: Any]) -> (URL?, String) {
        if let backups = data["video_backup"] as? [[String: Any]], !backups.isEmpty {
            var best: [String: Any]?
            var bestBitrate: Int = 0

            for entry in backups {
                guard let urlStr = entry["url"] as? String,
                      URL(string: urlStr) != nil else { continue }
                let bitrate = entry["bit_rate"] as? Int ?? 0
                if bitrate > bestBitrate {
                    bestBitrate = bitrate
                    best = entry
                }
            }

            if let best = best,
               let urlStr = best["url"] as? String,
               let url = URL(string: urlStr) {
                let quality = best["quality"] as? String ?? "高清"
                return (url, quality)
            }
        }

        if let urlStr = data["url"] as? String,
           let url = URL(string: urlStr) {
            let quality = data["quality"] as? String ?? "高清"
            return (url, quality)
        }

        return (nil, "未知")
    }

    /// 从 data JSON 提取 BGM 音乐信息
    private func extractMusic(from data: [String: Any]) -> DouyinMusicInfo? {
        guard let music = data["music"] as? [String: Any],
              let urlStr = music["url"] as? String,
              let url = URL(string: urlStr) else {
            return nil
        }
        return DouyinMusicInfo(
            title: (music["title"] as? String) ?? "未知音乐",
            author: (music["author"] as? String) ?? "未知作者",
            url: url,
            coverURL: (music["cover"] as? String).flatMap { URL(string: $0) }
        )
    }

    private func extractVideoID(from urlString: String) -> String? {
        for pattern in [#"/video/(\d+)"#, #"/note/(\d+)"#, #"video/(\d+)"#,
                        #"aweme_id=(\d+)"#, #"item_id=(\d+)"#, #"modal_id=(\d+)"#] {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
               let range = Range(match.range(at: 1), in: urlString) {
                return String(urlString[range])
            }
        }
        return nil
    }

    private let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
}
