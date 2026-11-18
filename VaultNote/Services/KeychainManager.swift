import Foundation
import Security
import LocalAuthentication

/// 验证数据管理器：存储/读取密码验证密文
///
/// 以本地文件为主存储（~/.vaultnote/verify），首次启动时自动从 Keychain 迁移旧数据。
/// 验证密文本身已用 AES-256-GCM 加密，文件存储不会降低安全性，
/// 同时避免了 ad-hoc 签名 app 每次读取 Keychain 时 macOS 弹出的授权提示。
enum KeychainManager {

    /// 验证文件路径
    private static let verifyFile: URL = {
        Constants.vaultDirectory.appendingPathComponent("verify")
    }()

    /// 保存加密后的验证数据（写入本地文件，不再使用 Keychain）
    static func saveVerificationData(_ data: Data) throws {
        try data.write(to: verifyFile, options: .atomic)
    }

    /// 读取加密后的验证数据
    /// - 优先读取本地文件
    /// - 文件不存在时尝试从 Keychain 迁移旧数据
    static func getVerificationData() throws -> Data? {
        // 优先读文件
        if FileManager.default.fileExists(atPath: verifyFile.path) {
            return try Data(contentsOf: verifyFile)
        }

        // 文件不存在 → 尝试从 Keychain 迁移旧数据
        if let keychainData = try readFromKeychain() {
            try keychainData.write(to: verifyFile, options: .atomic)
            try deleteFromKeychain()
            return keychainData
        }

        return nil
    }

    /// 删除验证数据
    static func deleteVerificationData() throws {
        if FileManager.default.fileExists(atPath: verifyFile.path) {
            try FileManager.default.removeItem(at: verifyFile)
        }
        try? deleteFromKeychain()
    }

    // MARK: - Keychain (仅用于迁移旧数据)

    private static let serviceName = "com.vaultnote.app"
    private static let accountName = "master_password_verification"

    private static func readFromKeychain() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func deleteFromKeychain() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Biometric Key（Touch ID 解锁用）

    private static let biometricService = "com.vaultnote.app.biometric"
    private static let biometricAccount = "vault_key"

    /// 把派生密钥存入 Keychain（密码本身不落盘）。
    /// 说明：ad-hoc 签名 App 无法使用 kSecAttrAccessControl（生物识别保护，会报 -34018），
    /// 因此采用"普通存储 + 读取前必须通过系统指纹/登录密码验证"的方案，
    /// 验证门卫由 LAContext.evaluatePolicy 承担。
    static func saveBiometricKey(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: biometricService,
            kSecAttrAccount as String: biometricAccount,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status))
        }
    }

    /// 用已验证的 LAContext 读取密钥（不重复弹 Touch ID）
    static func loadBiometricKey(with context: LAContext) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: biometricService,
            kSecAttrAccount as String: biometricAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    /// 是否已存有生物识别密钥
    static func hasBiometricKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: biometricService,
            kSecAttrAccount as String: biometricAccount
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // 生物识别保护的项目做存在性查询时可能返回"需要交互"而非"成功"，此时同样视为已存在
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}
