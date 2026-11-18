import Foundation

/// 应用全局常量
enum Constants {

    /// 应用名称
    static let appName = "VaultNote"

    /// 数据存储目录
    static let vaultDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".vaultnote")
    }()

    /// 加密笔记存储子目录
    static let notesDirectory: URL = {
        vaultDirectory.appendingPathComponent("notes")
    }()

    /// 图库媒体存储目录（不加密，仅 0o700 权限保护）
    static let galleryDirectory: URL = {
        vaultDirectory.appendingPathComponent("gallery")
    }()

    /// 缩略图缓存目录
    static let thumbnailCacheDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("VaultNote/thumbnails")
    }()

    /// 盐值文件
    static let saltFile: URL = {
        vaultDirectory.appendingPathComponent("salt")
    }()

    /// 密码验证明文
    static let verificationPlaintext = "VAULTNOTE_VERIFY"

    /// 目录权限 (仅 owner 可读写)
    static let vaultPermissions: [FileAttributeKey: Any] = [
        .posixPermissions: 0o700
    ]

    /// 自动锁定时间 (秒)
    static let defaultAutoLockInterval: TimeInterval = 60  // 1 分钟无操作自动锁定

    /// PBKDF2 迭代次数
    static let pbkdf2Iterations = 600_000

    /// 窗口最小尺寸
    static let minWindowWidth: CGFloat = 800
    static let minWindowHeight: CGFloat = 600

    /// 侧边栏宽度
    static let sidebarWidth: CGFloat = 260
}
