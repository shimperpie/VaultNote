import CryptoKit
import Foundation

/// 笔记持久化管理：加密存储 / 解密读取 / 删除
class NoteManager {

    // MARK: - CRUD

    /// 加载所有笔记（解密并解析）
    func loadAllNotes(crypto: CryptoServiceProxy) throws -> [Note] {
        let notesDir = Constants.notesDirectory
        guard FileManager.default.fileExists(atPath: notesDir.path) else {
            return []
        }

        let files = try FileManager.default.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil)
        let encFiles = files.filter { $0.pathExtension == "enc" }

        var notes: [Note] = []
        for file in encFiles {
            if let (note, _) = try? loadNoteContent(at: file, key: crypto.key) {
                notes.append(note)
            }
        }

        return notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 保存笔记（加密后写入磁盘）
    func saveNote(_ note: Note, rtfdData: Data, key: SymmetricKey) throws {
        // 确保目录存在
        try ensureVaultDirectories()

        // 编码
        let payload = try CryptoService.encodeNotePayload(note: note, rtfdData: rtfdData)

        // 加密
        let encrypted = try CryptoService.encrypt(data: payload, key: key)

        // 写入文件
        let fileURL = noteFileURL(for: note.id)
        try encrypted.write(to: fileURL, options: .atomic)
    }

    /// 删除笔记
    func deleteNote(id: UUID) throws {
        let fileURL = noteFileURL(for: id)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// 加载单条笔记的 RTFD 内容
    func loadNoteContent(at url: URL, key: SymmetricKey) throws -> (Note, Data) {
        let encrypted = try Data(contentsOf: url)
        let payload = try CryptoService.decrypt(data: encrypted, key: key)
        return try CryptoService.decodeNotePayload(payload)
    }

    /// 导出解密后的笔记（纯文本 + 图片另存）
    func exportNote(id: UUID, key: SymmetricKey, to directory: URL) throws {
        let fileURL = noteFileURL(for: id)
        let (note, rtfdData) = try loadNoteContent(at: fileURL, key: key)

        // 写入 .rtfd 文件
        let exportURL = directory.appendingPathComponent("\(note.title.sanitizedFileName).rtfd")
        let wrapper = FileWrapper(regularFileWithContents: rtfdData)
        try wrapper.write(to: exportURL, options: .atomic, originalContentsURL: nil)
    }

    // MARK: - Helpers

    private func noteFileURL(for id: UUID) -> URL {
        Constants.notesDirectory.appendingPathComponent("\(id.uuidString).enc")
    }

    private func ensureVaultDirectories() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Constants.vaultDirectory.path) {
            try fm.createDirectory(
                at: Constants.vaultDirectory,
                withIntermediateDirectories: true,
                attributes: Constants.vaultPermissions
            )
        }
        if !fm.fileExists(atPath: Constants.notesDirectory.path) {
            try fm.createDirectory(
                at: Constants.notesDirectory,
                withIntermediateDirectories: true,
                attributes: Constants.vaultPermissions
            )
        }
    }
}

// MARK: - CryptoService Proxy (封装密钥)

struct CryptoServiceProxy {
    let key: SymmetricKey
}

// MARK: - String Extension

extension String {
    /// 移除文件名不安全字符
    var sanitizedFileName: String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return self.components(separatedBy: invalidChars).joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
    }
}
