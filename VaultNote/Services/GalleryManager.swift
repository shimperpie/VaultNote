import Foundation
import AppKit
import CryptoKit
import AVFoundation

/// 图库文件管理：扫描、分类、缩略图、导入导出
class GalleryManager {

    static let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"])
    static let videoExtensions = Set(["mp4", "mov", "m4v", "avi", "mkv", "webm"])
    static let supportedExtensions = imageExtensions.union(videoExtensions)

    // MARK: - Directory

    private func ensureGalleryDirectory() throws {
        let fm = FileManager.default
        let dir = Constants.galleryDirectory
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: Constants.vaultPermissions)
        }
    }

    // MARK: - Categories

    /// 分类顺序文件（用户拖拽排序后持久化）
    private var categoryOrderFile: URL {
        Constants.galleryDirectory.appendingPathComponent(".category_order.json")
    }

    /// 读取用户自定义的分类顺序（数组）
    private func loadCategoryOrder() -> [String] {
        guard let data = try? Data(contentsOf: categoryOrderFile),
              let order = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return order
    }

    /// 保存用户自定义的分类顺序
    func saveCategoryOrder(_ order: [String]) {
        try? ensureGalleryDirectory()
        if let data = try? JSONSerialization.data(withJSONObject: order, options: [.prettyPrinted]) {
            try? data.write(to: categoryOrderFile, options: .atomic)
        }
    }

    /// 列出所有分类（子文件夹名）
    func listCategories() throws -> [String] {
        try ensureGalleryDirectory()
        let contents = try FileManager.default.contentsOfDirectory(
            at: Constants.galleryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        let sorted = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }
            .sorted()

        // 应用用户拖拽后的顺序：自定义顺序在前，新增分类按字母排在后面
        let order = loadCategoryOrder()
        var result = order.filter { sorted.contains($0) }
        for category in sorted where !result.contains(category) {
            result.append(category)
        }
        return result
    }

    /// 新建分类（创建子文件夹）
    func createCategory(name: String) throws {
        try ensureGalleryDirectory()
        let dir = Constants.galleryDirectory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: dir.path) else {
            throw GalleryError.categoryAlreadyExists
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: Constants.vaultPermissions)
    }

    /// 重命名分类
    func renameCategory(from oldName: String, to newName: String) throws {
        let oldDir = Constants.galleryDirectory.appendingPathComponent(oldName)
        let newDir = Constants.galleryDirectory.appendingPathComponent(newName)
        guard FileManager.default.fileExists(atPath: oldDir.path) else {
            throw GalleryError.categoryNotFound
        }
        guard !FileManager.default.fileExists(atPath: newDir.path) else {
            throw GalleryError.categoryAlreadyExists
        }
        try FileManager.default.moveItem(at: oldDir, to: newDir)

        // 同步更新顺序文件里的名字
        var order = loadCategoryOrder()
        if let idx = order.firstIndex(of: oldName) {
            order[idx] = newName
            saveCategoryOrder(order)
        }
    }

    /// 删除分类及其中所有文件
    func deleteCategory(name: String) throws {
        let dir = Constants.galleryDirectory.appendingPathComponent(name)
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: - Media Items

    /// 列出某个分类下的所有媒体文件
    func listMedia(in category: String) throws -> [MediaItem] {
        let categoryDir = Constants.galleryDirectory.appendingPathComponent(category)
        guard FileManager.default.fileExists(atPath: categoryDir.path) else { return [] }

        let contents = try FileManager.default.contentsOfDirectory(
            at: categoryDir,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        return contents
            .filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map { MediaItem(fileName: $0.lastPathComponent, category: category, fileURL: $0) }
            .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    /// 导入文件到指定分类（复制，重名自动加编号）
    @discardableResult
    func importFile(from sourceURL: URL, to category: String) throws -> MediaItem {
        try ensureGalleryDirectory()
        let categoryDir = Constants.galleryDirectory.appendingPathComponent(category)
        let destURL = categoryDir.appendingPathComponent(sourceURL.lastPathComponent)

        var finalURL = destURL
        let fm = FileManager.default
        var counter = 1
        let baseName = destURL.deletingPathExtension().lastPathComponent
        let ext = destURL.pathExtension
        while fm.fileExists(atPath: finalURL.path) {
            finalURL = categoryDir.appendingPathComponent("\(baseName) \(counter).\(ext)")
            counter += 1
        }

        try fm.copyItem(at: sourceURL, to: finalURL)
        return MediaItem(fileName: finalURL.lastPathComponent, category: category, fileURL: finalURL)
    }

    /// 删除媒体文件
    func deleteMedia(_ item: MediaItem) throws {
        try FileManager.default.removeItem(at: item.fileURL)
        // 顺手清理因此不再被引用的 BGM（合集共享的 BGM 会保留）
        removeOrphanBGMs(in: item.category)
    }

    // MARK: - Move

    /// 把媒体文件从一个分类移动到另一个分类
    /// - 目标目录已有同名文件时自动改名（在扩展名前加 " (1)"），绝不覆盖
    /// - 收藏状态跟随文件迁移（源分类移除、目标分类加入）
    /// - 返回目标目录中的最终文件名
    @discardableResult
    func moveMedia(fileName: String, from source: String, to destination: String) throws -> String {
        guard source != destination else { return fileName }

        let fm = FileManager.default
        let srcURL = Constants.galleryDirectory
            .appendingPathComponent(source)
            .appendingPathComponent(fileName)
        guard fm.fileExists(atPath: srcURL.path) else {
            throw GalleryError.fileNotFound
        }

        let destDir = Constants.galleryDirectory.appendingPathComponent(destination)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: Constants.vaultPermissions)

        let destURL = uniqueDestinationURL(in: destDir, fileName: fileName)
        try fm.moveItem(at: srcURL, to: destURL)

        // 收藏跟随迁移
        var srcFavorites = loadFavorites(in: source)
        var destFavorites = loadFavorites(in: destination)
        if srcFavorites.remove(fileName) != nil {
            destFavorites.insert(destURL.lastPathComponent)
            try? saveFavorites(srcFavorites, in: source)
            try? saveFavorites(destFavorites, in: destination)
        }

        return destURL.lastPathComponent
    }

    /// 目标目录里不冲突的文件名（同名时加 " (n)"）
    private func uniqueDestinationURL(in dir: URL, fileName: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var n = 1
        while true {
            candidate = dir.appendingPathComponent("\(base) (\(n)).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    // MARK: - BGM Cleanup

    /// 计算一个媒体文件会引用的 BGM 文件名（与预览 findBGM 同规则：精确 + 合集 _N 回退）
    private func referencedBGMFileNames(for fileName: String) -> Set<String> {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext),
              !fileName.lowercased().hasSuffix("_bgm.mp3") else {
            return []
        }
        let base = (fileName as NSString).deletingPathExtension
        var result: Set<String> = [base + "_bgm.mp3"]
        if let range = base.range(of: #"_\d+$"#, options: .regularExpression) {
            result.insert(String(base[..<range.lowerBound]) + "_bgm.mp3")
        }
        return result
    }

    /// 扫描分类中的孤儿 BGM（没有任何媒体文件引用的 *_bgm.mp3）
    func scanOrphanBGMs(in category: String) -> [String] {
        let dir = Constants.galleryDirectory.appendingPathComponent(category)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }
        let bgmFiles = names.filter { $0.lowercased().hasSuffix("_bgm.mp3") }
        guard !bgmFiles.isEmpty else { return [] }

        var referenced: Set<String> = []
        for name in names where !name.lowercased().hasSuffix("_bgm.mp3") {
            referenced.formUnion(referencedBGMFileNames(for: name))
        }
        return bgmFiles.filter { !referenced.contains($0) }.sorted()
    }

    /// 删除分类中的孤儿 BGM，返回删除的文件名
    @discardableResult
    func removeOrphanBGMs(in category: String) -> [String] {
        let dir = Constants.galleryDirectory.appendingPathComponent(category)
        let orphans = scanOrphanBGMs(in: category)
        for name in orphans {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        return orphans
    }

    // MARK: - Favorites

    private func favoritesFile(in category: String) -> URL {
        Constants.galleryDirectory
            .appendingPathComponent(category)
            .appendingPathComponent(".favorites.json")
    }

    /// 读取分类的收藏列表（文件名集合）
    func loadFavorites(in category: String) -> Set<String> {
        let file = favoritesFile(in: category)
        guard let data = try? Data(contentsOf: file),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return Set(raw)
    }

    /// 保存分类的收藏列表
    func saveFavorites(_ favorites: Set<String>, in category: String) throws {
        let file = favoritesFile(in: category)
        let data = try JSONSerialization.data(
            withJSONObject: Array(favorites).sorted(),
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: file, options: .atomic)
    }

    // MARK: - Thumbnails

    /// 异步生成缩略图（缓存优先）
    func generateThumbnail(for item: MediaItem, size: CGSize = CGSize(width: 200, height: 200)) async -> NSImage? {
        if let cached = loadThumbnailFromCache(for: item) {
            return cached
        }

        let thumbnail: NSImage?
        if item.isVideo {
            thumbnail = await generateVideoThumbnail(for: item, size: size)
        } else {
            thumbnail = generateImageThumbnail(for: item, size: size)
        }

        if let thumb = thumbnail {
            saveThumbnailToCache(thumb, for: item)
        }

        return thumbnail
    }

    /// 图片缩略图 — 用 CGImageSource 不解码全图
    private func generateImageThumbnail(for item: MediaItem, size: CGSize) -> NSImage? {
        let maxDimension = max(size.width, size.height) * 2
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let src = CGImageSourceCreateWithURL(item.fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize.zero)
    }

    /// 视频缩略图 — AVAssetImageGenerator 取首帧
    private func generateVideoThumbnail(for item: MediaItem, size: CGSize) async -> NSImage? {
        return await generateVideoThumbnailAV(item: item, size: size)
    }

    /// AVFoundation 回退方案 — 取第 0 秒帧
    private func generateVideoThumbnailAV(item: MediaItem, size: CGSize) async -> NSImage? {
        let asset = AVURLAsset(url: item.fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        return await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
                if let cgImage = cgImage {
                    continuation.resume(returning: NSImage(cgImage: cgImage, size: NSSize.zero))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Cache

    private var cacheDir: URL {
        Constants.thumbnailCacheDir
    }

    private func cacheKey(for item: MediaItem) -> String {
        let input = item.fileURL.path
        return SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func loadThumbnailFromCache(for item: MediaItem) -> NSImage? {
        let file = cacheDir.appendingPathComponent(cacheKey(for: item))
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return NSImage(contentsOf: file)
    }

    private func saveThumbnailToCache(_ image: NSImage, for item: MediaItem) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cacheDir.path) {
            try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        let file = cacheDir.appendingPathComponent(cacheKey(for: item))
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: file)
    }
}

// MARK: - Errors

enum GalleryError: LocalizedError {
    case categoryAlreadyExists
    case categoryNotFound
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .categoryAlreadyExists: return "分类已存在"
        case .categoryNotFound: return "分类不存在"
        case .fileNotFound: return "文件不存在"
        }
    }
}
