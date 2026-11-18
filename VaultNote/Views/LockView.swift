import SwiftUI

/// 解锁界面
struct LockView: View {
    @EnvironmentObject var appState: AppState
    @State private var password = ""
    @State private var isVerifying = false
    @State private var shake = false
    @State private var errorMessage: String?
    @State private var showPassword = false
    @State private var showBiometricButton = false
    @State private var isBiometricVerifying = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // 图标
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            // 标题
            Text("VaultNote")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("输入密码解锁")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // 密码输入
            HStack(spacing: 4) {
                if showPassword {
                    TextField("主密码", text: $password)
                } else {
                    SecureField("主密码", text: $password)
                }
                Button(action: { showPassword.toggle() }) {
                    Image(systemName: showPassword ? "eye.fill" : "eye.slash.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 300)
            .disabled(isVerifying)
            .onSubmit { unlock() }
            .modifier(ShakeEffect(shakes: shake ? 2 : 0))
            .animation(shake ? Animation.default.repeatCount(2).speed(2) : .default, value: shake)

            // 错误提示
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // 解锁按钮
            Button(action: unlock) {
                if isVerifying {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("解锁")
                        .frame(width: 200)
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
            .disabled(password.isEmpty || isVerifying)

            // Touch ID 解锁（设备有生物识别且已存密钥时显示）
            if showBiometricButton {
                Button(action: { unlockWithBiometrics() }) {
                    Label(
                        isBiometricVerifying ? "正在验证…" : "Touch ID 解锁",
                        systemImage: "touchid"
                    )
                    .frame(width: 200)
                }
                .buttonStyle(.bordered)
                .disabled(isBiometricVerifying || isVerifying)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            showBiometricButton = appState.canUseBiometricUnlock()
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        isVerifying = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let success = try appState.unlock(password)
                DispatchQueue.main.async {
                    isVerifying = false
                    if !success {
                        errorMessage = "密码错误，请重试"
                        password = ""
                        shake = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            shake = false
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isVerifying = false
                    errorMessage = "解锁失败: \(error.localizedDescription)"
                    password = ""
                }
            }
        }
    }

    private func unlockWithBiometrics() {
        isBiometricVerifying = true
        errorMessage = nil
        Task {
            let success = await appState.unlockWithBiometrics()
            await MainActor.run {
                isBiometricVerifying = false
                if !success {
                    errorMessage = "Touch ID 解锁失败，请重试或输入密码（如从未用过指纹，请先用密码解锁一次）"
                }
            }
        }
    }
}

// MARK: - Shake Effect

struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(shakes * .pi * 2) * 8, y: 0))
    }
}
