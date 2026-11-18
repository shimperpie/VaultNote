import CryptoKit
import Foundation
import Security

/// 加密服务：AES-256-GCM 文件加密 + PBKDF2 密钥派生
enum CryptoService {

    // MARK: - Key Derivation

    /// 使用 PBKDF2-HMAC-SHA256 从密码派生 AES-256 密钥
    /// - Parameters:
    ///   - password: 用户输入的密码
    ///   - salt: 随机盐值 (推荐 32 字节)
    ///   - iterations: 迭代次数，默认 600,000 (OWASP 推荐)
    /// - Returns: 32 字节的 AES-256 对称密钥
    static func deriveKey(
        password: String,
        salt: Data,
        iterations: Int = 600_000
    ) -> SymmetricKey {
        let passwordKey = SymmetricKey(data: password.data(using: .utf8)!)
        let hashLength = SHA256.Digest.byteCount  // 32 bytes
        let blockCount = 1  // AES-256 正好 32 字节，一个 block 就够了
        var derivedKey = Data()

        for blockIndex in 1...blockCount {
            var input = Data()
            input.append(salt)
            var beBlock = UInt32(blockIndex).bigEndian
            input.append(Data(bytes: &beBlock, count: 4))

            var u = Data(HMAC<SHA256>.authenticationCode(for: input, using: passwordKey))
            var t = u

            for _ in 1..<iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: passwordKey))
                for i in 0..<hashLength {
                    t[i] ^= u[i]
                }
            }

            derivedKey.append(t)
        }

        return SymmetricKey(data: derivedKey.prefix(32))
    }

    /// 生成随机盐值
    static func generateSalt() throws -> Data {
        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            guard let address = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, bytes.count, address)
        }
        guard status == errSecSuccess else { throw CryptoError.randomnessUnavailable }
        return salt
    }

    // MARK: - Encrypt / Decrypt

    /// AES-256-GCM 加密
    /// - Returns: combined data (nonce + ciphertext + tag)，适合直接写入文件
    static func encrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }
        return combined
    }

    /// AES-256-GCM 解密
    static func decrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Note File Format

    /// 将笔记内容编码为存储格式 (JSON: id + title + dates + RTFD base64)
    static func encodeNotePayload(note: Note, rtfdData: Data) throws -> Data {
        let payload: [String: Any] = [
            "id": note.id.uuidString,
            "title": note.title,
            "createdAt": note.createdAt.timeIntervalSince1970,
            "updatedAt": note.updatedAt.timeIntervalSince1970,
            "rtfdBase64": rtfdData.base64EncodedString()
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// 从存储格式解码笔记
    static func decodeNotePayload(_ data: Data) throws -> (Note, Data) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idString = json["id"] as? String,
              let id = UUID(uuidString: idString),
              let title = json["title"] as? String,
              let createdInterval = json["createdAt"] as? TimeInterval,
              let updatedInterval = json["updatedAt"] as? TimeInterval,
              let rtfdBase64 = json["rtfdBase64"] as? String,
              let rtfdData = Data(base64Encoded: rtfdBase64)
        else {
            throw CryptoError.invalidPayloadFormat
        }

        let note = Note(
            id: id,
            title: title,
            createdAt: Date(timeIntervalSince1970: createdInterval),
            updatedAt: Date(timeIntervalSince1970: updatedInterval)
        )
        return (note, rtfdData)
    }
}

// MARK: - Errors

enum CryptoError: LocalizedError {
    case randomnessUnavailable
    case encryptionFailed
    case decryptionFailed
    case invalidPayloadFormat
    case keychainError

    var errorDescription: String? {
        switch self {
        case .randomnessUnavailable: return "无法生成安全随机数据，请重试"
        case .encryptionFailed: return "加密失败"
        case .decryptionFailed: return "解密失败 — 密码可能不正确"
        case .invalidPayloadFormat: return "数据格式损坏"
        case .keychainError: return "钥匙串访问失败"
        }
    }
}
