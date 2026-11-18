import SwiftUI

/// 首次设置 — 创建主密码
struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSettingUp = false
    @State private var errorMessage: String?
    @State private var showPassword = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("欢迎使用 VaultNote")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("首次使用，请设置主密码")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                HStack(spacing: 4) {
                    if showPassword {
                        TextField("主密码 (至少 6 位)", text: $password)
                    } else {
                        SecureField("主密码 (至少 6 位)", text: $password)
                    }
                }
                HStack(spacing: 4) {
                    if showPassword {
                        TextField("确认密码", text: $confirmPassword)
                    } else {
                        SecureField("确认密码", text: $confirmPassword)
                    }
                }
                HStack {
                    Spacer()
                    Button(action: { showPassword.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: showPassword ? "eye.fill" : "eye.slash.fill")
                            Text(showPassword ? "隐藏密码" : "显示密码")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 300)
            }
            .textFieldStyle(.roundedBorder)
            .disabled(isSettingUp)

            // 提示
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("密码丢失无法找回，请务必牢记")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("数据仅存储在本机，不会上传到任何服务器")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 错误提示
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // 创建按钮
            Button(action: setup) {
                if isSettingUp {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("创建并开始使用")
                        .frame(width: 220)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(password.isEmpty || confirmPassword.isEmpty || isSettingUp)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setup() {
        errorMessage = nil

        // 验证密码
        guard password.count >= 6 else {
            errorMessage = "密码至少需要 6 位"
            return
        }
        guard password == confirmPassword else {
            errorMessage = "两次输入密码不一致"
            return
        }

        isSettingUp = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try appState.setupMasterPassword(password)
            } catch {
                DispatchQueue.main.async {
                    isSettingUp = false
                    errorMessage = "初始化失败: \(error.localizedDescription)"
                }
            }
        }
    }
}
