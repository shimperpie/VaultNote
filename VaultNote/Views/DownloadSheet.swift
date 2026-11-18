import SwiftUI

/// 抖音/小红书视频/图集下载弹窗
struct DownloadSheet: View {
    @Environment(\.dismiss) var dismiss

    let onDownloadComplete: (() -> Void)?

    @State private var linkText = ""
    @State private var videoInfo: DouyinVideoInfo?
    @State private var downloadProgress: Double = 0
    @State private var statusMessage = ""
    @State private var isError = false
    @State private var isParsing = false
    @State private var isDownloading = false
    @State private var downloadComplete = false
    @State private var downloadedCount = 0

    // 合集预览选择
    @State private var selectedIndices: Set<Int> = []
    @State private var includeBGM = true
    @State private var platform = "抖音"

    private let parser = DouyinParser()
    private let downloader = VideoDownloader()
    private let galleryManager = GalleryManager()

    /// 当前平台对应的图库分类
    private var activeCategory: String { platform }

    private let gridColumns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 8)]

    var body: some View {
        VStack(spacing: 16) {
            // 标题栏
            HStack {
                Text("下载\(platform)内容")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { cancelAndDismiss() }) {
                    Label("关闭", systemImage: "xmark")
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            // 链接输入
            VStack(alignment: .leading, spacing: 6) {
                Text("\(platform)分享链接").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    TextField("粘贴\(platform)链接...", text: $linkText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isDownloading)

                    if !linkText.isEmpty {
                        Button(action: { linkText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDownloading)
                    }

                    Button(action: parseLink) {
                        Text("解析")
                    }
                    .disabled(linkText.trimmingCharacters(in: .whitespaces).isEmpty || isParsing || isDownloading)
                }
            }

            // 状态区域
            VStack(spacing: 12) {
                if isParsing {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在解析链接...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let info = videoInfo {
                    if info.isAlbum {
                        albumPreviewGrid(info)
                    } else {
                        singleVideoCard(info)
                    }
                }

                // 下载进度
                if isDownloading {
                    VStack(spacing: 8) {
                        ProgressView(value: downloadProgress)
                            .frame(maxWidth: .infinity)
                        Text("\(downloadedCount) / \(totalSelectedCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 完成
                if downloadComplete {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("下载完成！已存入「\(platform)」分类")
                            .font(.callout)
                        Button("打开") {
                            dismiss()
                            onDownloadComplete?()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                // 错误
                if isError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(Color(.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            // 下载按钮
            if videoInfo != nil, !isDownloading, !downloadComplete {
                Button(action: startDownload) {
                    if let info = videoInfo, info.isAlbum {
                        Label("下载选中 (\(totalSelectedCount) 项)", systemImage: "arrow.down.to.line")
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("下载最高画质", systemImage: "arrow.down.to.line")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(totalSelectedCount == 0)
            }

            if isDownloading {
                Button(role: .destructive, action: cancelDownload) {
                    Label("取消下载", systemImage: "xmark")
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 400)
        .onDisappear {
            downloader.cancel()
        }
    }

    // MARK: - Total selected count

    private var totalSelectedCount: Int {
        guard let info = videoInfo, info.isAlbum else {
            return videoInfo != nil ? 1 : 0
        }
        var count = selectedIndices.count
        if includeBGM && info.music != nil { count += 1 }
        return count
    }

    // MARK: - Single Video Card

    @ViewBuilder
    private func singleVideoCard(_ info: DouyinVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(info.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let music = info.music {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundColor(.purple)
                        Text("BGM: \(music.title)")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }

                Image(systemName: "film")
                    .font(.caption)
                Text("\(info.quality) · 无水印")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Album Preview Grid

    @ViewBuilder
    private func albumPreviewGrid(_ info: DouyinVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题 + 操作按钮
            HStack {
                Text(info.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("全选") { selectedIndices = Set(0..<info.mediaItems.count) }
                    .font(.caption)
                Button("取消全选") { selectedIndices = [] }
                    .font(.caption)
            }

            // 缩略图网格
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(Array(info.mediaItems.enumerated()), id: \.offset) { index, item in
                        albumItemCell(index: index, item: item)
                            .onTapGesture { toggleSelection(index) }
                    }
                }
            }
            .frame(maxHeight: 300)

            // BGM 行
            if let music = info.music {
                HStack {
                    Button(action: { includeBGM.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: includeBGM ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(includeBGM ? .purple : .secondary)
                            Image(systemName: "music.note")
                                .foregroundColor(.purple)
                            Text("BGM: \(music.title)")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func albumItemCell(index: Int, item: DouyinMediaItem) -> some View {
        let isSelected = selectedIndices.contains(index)

        ZStack(alignment: .topLeading) {
            // 缩略图（动图用封面图预览，没有封面才显示占位符）
            AsyncImage(url: item.previewURL ?? item.url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    placeholderView
                @unknown default:
                    placeholderView
                }
            }
            .frame(height: 120)
            .clipped()

            // 选中框 + 类型标签
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .white.opacity(0.7))
                        .font(.title3)
                        .background(Circle().fill(Color.black.opacity(0.4)).scaleEffect(0.7))
                    Spacer()
                    Text(item.type == .video ? "动图" : "图片")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.type == .video ? Color.purple.opacity(0.8) : Color.green.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .padding(4)
                }
                Spacer()
            }
        }
        .frame(height: 120)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }

    private var placeholderView: some View {
        ZStack {
            Color(.windowBackgroundColor).opacity(0.3)
            Image(systemName: "play.rectangle")
                .font(.title)
                .foregroundColor(.secondary)
        }
    }

    private func toggleSelection(_ index: Int) {
        if selectedIndices.contains(index) {
            selectedIndices.remove(index)
        } else {
            selectedIndices.insert(index)
        }
    }

    /// 从链接文本识别平台
    private func detectPlatform(from rawURL: String) -> String {
        let lower = rawURL.lowercased()
        if lower.contains("xiaohongshu") || lower.contains("xhslink") {
            return "小红书"
        }
        return "抖音"
    }

    // MARK: - Actions

    private func parseLink() {
        let url = linkText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }

        platform = detectPlatform(from: url)
        isError = false
        isParsing = true
        videoInfo = nil
        downloadComplete = false

        Task {
            do {
                let info = try await parser.parse(shareURL: url)
                await MainActor.run {
                    videoInfo = info
                    isParsing = false
                    // 合集默认全选 + BGM 默认选中
                    if info.isAlbum {
                        selectedIndices = Set(0..<info.mediaItems.count)
                        includeBGM = info.music != nil
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    isError = true
                    isParsing = false
                }
            }
        }
    }

    private func startDownload() {
        guard let info = videoInfo else { return }

        isError = false
        isDownloading = true
        downloadProgress = 0
        downloadedCount = 0
        downloadComplete = false

        ensureCategory(activeCategory)

        if info.isAlbum {
            let selected = info.mediaItems.enumerated().filter { selectedIndices.contains($0.offset) }
            downloadAlbum(indexedItems: selected, title: info.title, totalItems: selected.count)
        } else {
            downloadSingle(info: info)
        }
    }

    /// 下载单个视频
    private func downloadSingle(info: DouyinVideoInfo) {
        let cleanTitle = info.title.strippingHashtags()
        let base = cleanTitle.isEmpty ? "\(platform)视频" : cleanTitle
        let safeFilename = sanitizeFilename(base) + ".mp4"

        downloader.download(
            url: info.downloadURL,
            filename: safeFilename,
            onProgress: { [self] p in downloadProgress = p },
            onComplete: { [self] tempURL in
                saveFile(tempURL: tempURL, filename: safeFilename)
                if let music = info.music {
                    downloadBGM(music: music, baseFilename: sanitizeFilename(base))
                }
            },
            onError: { [self] error in handleError(error) }
        )
    }

    /// 后台下载 BGM MP3，失败不阻塞主流程
    private func downloadBGM(music: DouyinMusicInfo, baseFilename: String) {
        let bgmFilename = "\(baseFilename)_bgm.mp3"
        let destDir = Constants.galleryDirectory.appendingPathComponent(activeCategory)
        let destURL = destDir.appendingPathComponent(bgmFilename)

        Task {
            do {
                var request = URLRequest(url: music.url)
                request.setValue(
                    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                    forHTTPHeaderField: "User-Agent"
                )
                let (tempURL, _) = try await URLSession.shared.download(for: request)

                let fm = FileManager.default
                try? fm.removeItem(at: destURL)
                try fm.copyItem(at: tempURL, to: destURL)
                print("[DownloadSheet] BGM 下载完成: \(bgmFilename)")
            } catch {
                print("[DownloadSheet] BGM 下载失败（非致命）: \(error.localizedDescription)")
            }
        }
    }

    /// 逐个下载选中的合集项（保留原始序号命名）
    private func downloadAlbum(indexedItems: [(Int, DouyinMediaItem)], title: String, totalItems: Int) {
        let cleanTitle = title.strippingHashtags()
        let safeBase = sanitizeFilename(cleanTitle.isEmpty ? "\(platform)图集" : cleanTitle)
        let total = totalItems

        Task {
            var completed = 0

            for (origIndex, item) in indexedItems {
                guard isDownloading else { break }

                let ext = item.type == .video ? "mp4" : "jpg"
                let filename = "\(safeBase)_\(origIndex + 1).\(ext)"
                let destDir = Constants.galleryDirectory.appendingPathComponent(activeCategory)
                let destURL = destDir.appendingPathComponent(filename)

                if FileManager.default.fileExists(atPath: destURL.path) {
                    completed += 1
                    await MainActor.run {
                        downloadedCount = completed
                        downloadProgress = Double(completed) / Double(total)
                    }
                    continue
                }

                do {
                    var request = URLRequest(url: item.url)
                    request.setValue(
                        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                        forHTTPHeaderField: "User-Agent"
                    )
                    let (tempURL, _) = try await URLSession.shared.download(for: request)

                    let fm = FileManager.default
                    try? fm.removeItem(at: destURL)
                    try fm.copyItem(at: tempURL, to: destURL)

                    completed += 1
                    await MainActor.run {
                        downloadedCount = completed
                        downloadProgress = Double(completed) / Double(total)
                    }
                } catch {
                    if (error as NSError).code == NSURLErrorCancelled { break }
                    print("[DownloadSheet] 第\(origIndex+1)项下载失败: \(error.localizedDescription)")
                }
            }

            // 下载 BGM（如果选中）
            if includeBGM, let music = videoInfo?.music {
                downloadBGM(music: music, baseFilename: safeBase)
            }

            await MainActor.run {
                if completed > 0 {
                    downloadComplete = true
                    isDownloading = false
                } else if isDownloading {
                    statusMessage = "下载失败，请检查网络"
                    isError = true
                    isDownloading = false
                }
            }
        }
    }

    /// 保存下载文件到图库
    private func saveFile(tempURL: URL, filename: String) {
        do {
            let destDir = Constants.galleryDirectory.appendingPathComponent(activeCategory)
            let destURL = destDir.appendingPathComponent(filename)

            let fm = FileManager.default
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: tempURL, to: destURL)

            downloadComplete = true
            isDownloading = false
        } catch {
            statusMessage = "保存文件失败: \(error.localizedDescription)"
            isError = true
            isDownloading = false
        }
    }

    private func handleError(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        statusMessage = error.localizedDescription
        isError = true
        isDownloading = false
    }

    private func cancelDownload() {
        downloader.cancel()
        isDownloading = false
    }

    private func cancelAndDismiss() {
        downloader.cancel()
        isDownloading = false
        dismiss()
    }

    // MARK: - Helpers

    private func ensureCategory(_ category: String) {
        let catDir = Constants.galleryDirectory.appendingPathComponent(category)
        if !FileManager.default.fileExists(atPath: catDir.path) {
            try? FileManager.default.createDirectory(
                at: catDir,
                withIntermediateDirectories: true,
                attributes: Constants.vaultPermissions
            )
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*:|\"<>")
        let sanitized = name.components(separatedBy: invalid).joined(separator: "_")
        return sanitized.isEmpty ? "douyin_video" : sanitized
    }
}
