import SwiftUI

@main
struct VaultNoteApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                    appState.windowDidResignActive()
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            // 自定义菜单栏
            CommandGroup(replacing: .newItem) {
                Button("新建笔记") {
                    appState.createNewNote()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("安全") {
                Button("锁定") {
                    appState.lock()
                }
                .keyboardShortcut("l", modifiers: .command)
            }

            CommandMenu("格式") {
                Button("切换清单") {
                    NotificationCenter.default.post(
                        name: .vaultNoteEditorAction,
                        object: EditorAction.toggleChecklist.rawValue
                    )
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("放大字体") {
                    NotificationCenter.default.post(
                        name: .vaultNoteEditorAction,
                        object: EditorAction.increaseFontSize.rawValue
                    )
                }
                .keyboardShortcut("=", modifiers: [.command, .shift])

                Button("缩小字体") {
                    NotificationCenter.default.post(
                        name: .vaultNoteEditorAction,
                        object: EditorAction.decreaseFontSize.rawValue
                    )
                }
                .keyboardShortcut("-", modifiers: .command)
            }
        }
    }
}
