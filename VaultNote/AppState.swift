import SwiftUI
import CryptoKit
import Combine
import LocalAuthentication

extension Notification.Name {
    /// 图库数据发生变化（如媒体文件被移动），网格视图据此刷新
    static let vaultGalleryDidChange = Notification.Name("vaultGalleryDidChange")
}

/// 应用全局状态
class AppState: ObservableObject {

    // MARK: - Published State

    @Published var phase: AppPhase = .setup
    @Published var notes: [Note] = []
    @Published var selectedNoteId: UUID?
    @Published var searchText = ""
    @Published var showDeleteConfirmation = false
    @Published var currentMode: AppMode = .notes
    @Published var galleryCategories: [String] = []
    @Published var selectedCategory: String?

    // MARK: - Internal

    private let noteManager = NoteManager()
    private let galleryManager = GalleryManager()
    private var cryptoService: CryptoServiceProxy?
    private var autoLockTimer: Timer?
    private var autoLockTimeout: TimeInterval = Constants.defaultAutoLockInterval
    private var noteToDelete: Note?
    private var eventMonitor: Any?

    // MARK: - Init

    init() {
        if FileManager.default.fileExists(atPath: Constants.saltFile.path) {
            phase = .locked
        } else {
            phase = .setup
        }
    }

    // MARK: - Setup

    func setupMasterPassword(_ password: String) throws {
        let salt = try CryptoService.generateSalt()

        // 创建 vault 目录
        try ensureDirectories()

        // 保存盐值
        try salt.write(to: Constants.saltFile, options: .atomic)

        // 派生密钥 + 保存验证数据
        let key = CryptoService.deriveKey(password: password, salt: salt)
        let verificationPlaintext = Constants.verificationPlaintext.data(using: .utf8)!
        let encryptedVerification = try CryptoService.encrypt(data: verificationPlaintext, key: key)
        try KeychainManager.saveVerificationData(encryptedVerification)

        // 初始化为解锁状态 — 必须在主线程
        cryptoService = CryptoServiceProxy(key: key)
        saveBiometricKeyIfAvailable(key)
        DispatchQueue.main.async {
            self.notes = []
            self.startAutoLockTimer()
            self.phase = .unlocked
        }
    }

    // MARK: - Unlock

    func unlock(_ password: String) throws -> Bool {
        let salt = try Data(contentsOf: Constants.saltFile)
        let key = CryptoService.deriveKey(password: password, salt: salt)

        guard let verificationData = try KeychainManager.getVerificationData() else {
            throw CryptoError.keychainError
        }

        let decrypted: Data
        do {
            decrypted = try CryptoService.decrypt(data: verificationData, key: key)
        } catch {
            return false
        }

        guard String(data: decrypted, encoding: .utf8) == Constants.verificationPlaintext else {
            return false
        }

        cryptoService = CryptoServiceProxy(key: key)
        saveBiometricKeyIfAvailable(key)
        let loadedNotes = (try? noteManager.loadAllNotes(crypto: cryptoService!)) ?? []

        // 所有 @Published 变更必须在主线程，否则 SwiftUI 不会可靠刷新
        DispatchQueue.main.async {
            self.notes = loadedNotes
            self.startAutoLockTimer()
            self.phase = .unlocked
        }
        return true
    }

    // MARK: - Biometric Unlock

    /// 是否可以显示 Touch ID 解锁按钮（设备有生物识别 + 钥匙串里已有密钥）
    func canUseBiometricUnlock() -> Bool {
        let context = LAContext()
        var error: NSError?
        let ok = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let hasKey = KeychainManager.hasBiometricKey()
        logBiometric("canUseBiometricUnlock: canEvaluate=\(ok) hasKey=\(hasKey) err=\(error?.localizedDescription ?? "nil")")
        // 按钮以设备能力为准；密钥未存时按了会给明确提示（避免按钮莫名不出现）
        return ok
    }

    /// 用 Touch ID 解锁：系统验证 → 读取密钥 → 校验验证数据 → 加载数据
    func unlockWithBiometrics() async -> Bool {
        let context = LAContext()
        var error: NSError?
        // .deviceOwnerAuthentication = Touch ID 优先，弹窗里的"输入密码"会真正弹出登录密码输入框
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            logBiometric("unlockWithBiometrics: canEvaluate 失败 err=\(error?.localizedDescription ?? "nil")")
            return false
        }

        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "使用 Touch ID 解锁 Vault"
            )
            guard ok else { return false }
        } catch {
            logBiometric("unlockWithBiometrics: evaluatePolicy 失败 \(error.localizedDescription)")
            return false
        }

        guard let keyData = KeychainManager.loadBiometricKey(with: context) else {
            logBiometric("unlockWithBiometrics: 钥匙串中无密钥（可能尚未用密码解锁过，或存储失败）")
            return false
        }
        let key = SymmetricKey(data: keyData)

        guard let verificationData = try? KeychainManager.getVerificationData(),
              let decrypted = try? CryptoService.decrypt(data: verificationData, key: key),
              String(data: decrypted, encoding: .utf8) == Constants.verificationPlaintext else {
            return false
        }

        cryptoService = CryptoServiceProxy(key: key)
        let loadedNotes = (try? noteManager.loadAllNotes(crypto: cryptoService!)) ?? []
        await MainActor.run {
            self.notes = loadedNotes
            self.startAutoLockTimer()
            self.phase = .unlocked
        }
        return true
    }

    /// 设备支持生物识别时，把派生密钥存入受保护的 Keychain（失败静默，不影响密码流程）
    private func saveBiometricKeyIfAvailable(_ key: SymmetricKey) {
        let context = LAContext()
        var err: NSError?
        let ok = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        logBiometric("saveBiometricKeyIfAvailable: canEvaluate=\(ok) err=\(err?.localizedDescription ?? "nil")")
        guard ok else {
            return
        }
        let keyData = key.withUnsafeBytes { Data($0) }
        do {
            try KeychainManager.saveBiometricKey(keyData)
            logBiometric("saveBiometricKeyIfAvailable: 密钥已存入")
        } catch {
            logBiometric("saveBiometricKeyIfAvailable: 存储失败 \(error.localizedDescription)")
        }
    }

    /// 生物识别诊断日志（写入缓存目录，方便排查）
    private func logBiometric(_ msg: String) {
        let dir = Constants.thumbnailCacheDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("biometric_diag.log")
        let line = "[\(Date())] \(msg)\n"
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: file)
        }
    }

    // MARK: - Lock

    func lock() {
        cryptoService = nil
        notes = []
        selectedNoteId = nil
        searchText = ""
        autoLockTimer?.invalidate()
        stopEventMonitoring()
        phase = .locked
    }

    // MARK: - Note CRUD

    func createNewNote() {
        guard let crypto = cryptoService else { return }
        let note = Note(title: "")

        do {
            try noteManager.saveNote(note, rtfdData: Data(), key: crypto.key)
            self.notes.insert(note, at: 0)
            self.selectedNoteId = note.id
        } catch {
            print("创建笔记失败: \(error)")
        }
    }

    func updateNote(_ note: Note, rtfdData: Data) {
        guard let crypto = cryptoService else { return }
        do {
            try noteManager.saveNote(note, rtfdData: rtfdData, key: crypto.key)
            DispatchQueue.main.async {
                if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                    self.notes[index] = note
                }
            }
        } catch {
            print("保存笔记失败: \(error)")
        }
    }

    func requestDeleteNote(_ note: Note) {
        noteToDelete = note
        showDeleteConfirmation = true
    }

    func confirmDeleteNote() {
        guard let note = noteToDelete, let crypto = cryptoService else { return }
        do {
            try noteManager.deleteNote(id: note.id)
            notes.removeAll { $0.id == note.id }
            if selectedNoteId == note.id {
                selectedNoteId = notes.first?.id
            }
        } catch {
            print("删除笔记失败: \(error)")
        }
        noteToDelete = nil
    }

    func loadRTFD(for noteId: UUID) -> Data? {
        guard let crypto = cryptoService else { return nil }
        let fileURL = Constants.notesDirectory.appendingPathComponent("\(noteId.uuidString).enc")
        if let (_, rtfdData) = try? noteManager.loadNoteContent(at: fileURL, key: crypto.key) {
            return rtfdData
        }
        return nil
    }

    func filteredNotes() -> [Note] {
        if searchText.isEmpty { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Gallery

    func loadGalleryCategories() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let categories = (try? self?.galleryManager.listCategories()) ?? []
            DispatchQueue.main.async {
                self?.galleryCategories = categories
                if self?.selectedCategory == nil || !categories.contains(self?.selectedCategory ?? "") {
                    self?.selectedCategory = categories.first
                }
            }
        }
    }

    func createGalleryCategory(name: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.galleryManager.createCategory(name: name)
                DispatchQueue.main.async {
                    self?.loadGalleryCategories()
                }
            } catch {
                print("创建分类失败: \(error)")
            }
        }
    }

    func deleteGalleryCategory(name: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.galleryManager.deleteCategory(name: name)
                DispatchQueue.main.async {
                    self?.loadGalleryCategories()
                }
            } catch {
                print("删除分类失败: \(error)")
            }
        }
    }

    func renameGalleryCategory(from oldName: String, to newName: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.galleryManager.renameCategory(from: oldName, to: newName)
                DispatchQueue.main.async {
                    if self?.selectedCategory == oldName {
                        self?.selectedCategory = newName
                    }
                    self?.loadGalleryCategories()
                }
            } catch {
                print("重命名分类失败: \(error)")
            }
        }
    }

    /// 拖拽调整分类顺序（同步持久化）
    func moveGalleryCategory(fromOffsets source: IndexSet, toOffset destination: Int) {
        var categories = galleryCategories
        categories.move(fromOffsets: source, toOffset: destination)
        galleryCategories = categories
        galleryManager.saveCategoryOrder(categories)
    }

    /// 把媒体文件移动到另一个分类（成功返回 true）
    @discardableResult
    func moveMedia(fileName: String, from source: String, to destination: String) -> Bool {
        do {
            try galleryManager.moveMedia(fileName: fileName, from: source, to: destination)
            loadGalleryCategories()
            NotificationCenter.default.post(name: .vaultGalleryDidChange, object: nil)
            return true
        } catch {
            print("移动文件失败: \(error)")
            return false
        }
    }

    // MARK: - Auto-Lock

    func windowDidResignActive() {
        // 窗口失去焦点时立即开始倒计时（不管之前有没有操作）
        restartAutoLockTimer()
    }

    private func startAutoLockTimer() {
        restartAutoLockTimer()
        startEventMonitoring()
    }

    private func restartAutoLockTimer() {
        autoLockTimer?.invalidate()
        autoLockTimer = Timer.scheduledTimer(
            withTimeInterval: autoLockTimeout,
            repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.lock()
            }
        }
    }

    /// 监听所有用户输入事件（键盘、鼠标、滚轮），任何操作都重置计时器
    private func startEventMonitoring() {
        stopEventMonitoring()
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved, .flagsChanged]
        ) { [weak self] event in
            // 有操作 → 重置计时器
            self?.restartAutoLockTimer()
            return event
        }
    }

    private func stopEventMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Helpers

    private func ensureDirectories() throws {
        let fm = FileManager.default
        let vaultDir = Constants.vaultDirectory
        let notesDir = Constants.notesDirectory

        if !fm.fileExists(atPath: vaultDir.path) {
            try fm.createDirectory(at: vaultDir, withIntermediateDirectories: true, attributes: Constants.vaultPermissions)
        }
        if !fm.fileExists(atPath: notesDir.path) {
            try fm.createDirectory(at: notesDir, withIntermediateDirectories: true, attributes: Constants.vaultPermissions)
        }
    }
}

// MARK: - App Phase

enum AppPhase {
    case setup    // 首次启动，需设置主密码
    case locked   // 已锁定，需输入密码
    case unlocked // 已解锁，正常使用
}

// MARK: - App Mode

/// 侧边栏模式：笔记编辑 / 图库浏览
enum AppMode: String, CaseIterable {
    case notes = "笔记"
    case gallery = "图库"
}
