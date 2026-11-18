import Foundation

/// 图库媒体项数据模型
struct MediaItem: Identifiable, Equatable {
    let id: UUID
    var fileName: String
    var category: String
    var fileURL: URL
    var isVideo: Bool
    var fileSize: Int64
    var isFavorite: Bool

    init(id: UUID = UUID(), fileName: String, category: String, fileURL: URL, isFavorite: Bool = false) {
        self.id = id
        self.fileName = fileName
        self.category = category
        self.fileURL = fileURL
        self.isVideo = GalleryManager.videoExtensions.contains(fileURL.pathExtension.lowercased())
        self.isFavorite = isFavorite
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        self.fileSize = Int64(size)
    }

    /// 合集分组键：文件名匹配「标题_N.扩展名」时返回标题，否则 nil（单件）
    var albumKey: String? {
        let base = (fileName as NSString).deletingPathExtension
        if let regex = try? NSRegularExpression(pattern: #"^(.+)_\d+$"#),
           let match = regex.firstMatch(in: base, range: NSRange(base.startIndex..., in: base)),
           let range = Range(match.range(at: 1), in: base) {
            return String(base[range])
        }
        return nil
    }
}

extension String {
    /// 去掉抖音标题里的话题标签（#xxx），用于文件名生成和预览标题显示
    func strippingHashtags() -> String {
        // 先分离我们自己加的序号后缀（如 _1.jpg / _2.mp4），只清洗标题部分
        var title = self
        var suffix = ""
        if let regex = try? NSRegularExpression(pattern: #"_\d+\.(jpg|jpeg|png|mp4|mov|m4v)$"#),
           let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
           let range = Range(match.range(at: 0), in: self) {
            title = String(self[..<range.lowerBound])
            suffix = String(self[range])
        }

        // 去掉话题标签（# 开头的连续非空白片段）
        var result = title
        if let regex = try? NSRegularExpression(pattern: #"#\S+"#) {
            result = regex.stringByReplacingMatches(
                in: title,
                range: NSRange(title.startIndex..., in: title),
                withTemplate: " "
            )
        }

        // 合并多余空格
        let collapsed = result.split(separator: " ").joined(separator: " ")
        var trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)

        // 去掉尾部标点（. 。 、 ， , ； ; ： : ！ ! ？ ? …）
        while let last = trimmed.last, "。、，,.；;：:！!？?…".contains(last) {
            trimmed.removeLast()
        }
        let cleaned = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned + suffix
    }
}
