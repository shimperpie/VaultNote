import SwiftUI

/// 主容器 — 根据 AppPhase 切换界面
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.phase {
            case .setup:
                SetupView()
            case .locked:
                LockView()
            case .unlocked:
                unlockedView
            }
        }
        .frame(
            minWidth: Constants.minWindowWidth,
            minHeight: Constants.minWindowHeight
        )
        .alert("确认删除", isPresented: $appState.showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                appState.confirmDeleteNote()
            }
        } message: {
            Text("删除后无法恢复，确定要删除这条笔记吗？")
        }
    }

    // MARK: - Unlocked View

    private var unlockedView: some View {
        NavigationSplitView {
            NoteListView()
                .navigationSplitViewColumnWidth(min: 180, ideal: Constants.sidebarWidth)
        } detail: {
            if appState.currentMode == .gallery {
                galleryDetail
            } else {
                notesDetail
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar {
            // 格式按钮仅在笔记模式下显示
            if appState.currentMode == .notes {
                // 使用 principal + HStack 而非 ToolbarItemGroup（macOS 上 ToolbarItemGroup 有 bug）
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                    Button(action: { postAction(.toggleChecklist) }) {
                        Image(systemName: "checklist")
                    }
                    .help("切换清单 ⌘⇧L")
                    .disabled(appState.selectedNoteId == nil)

                    Divider()
                        .frame(height: 16)

                    Button(action: { postAction(.decreaseFontSize) }) {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .help("缩小字体 ⌘-")
                    .disabled(appState.selectedNoteId == nil)

                    Button(action: { postAction(.increaseFontSize) }) {
                        Image(systemName: "textformat.size.larger")
                    }
                    .help("放大字体 ⌘+")
                    .disabled(appState.selectedNoteId == nil)
                }
            }
            }  // end if notes mode
        }
    }

    private var emptyEditorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("选择或创建一条笔记")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("⌘N 新建笔记")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Notes Detail

    private var notesDetail: some View {
        Group {
            if let selectedId = appState.selectedNoteId,
               let note = appState.notes.first(where: { $0.id == selectedId }) {
                NoteEditorView(note: note)
                    .id(note.id)
            } else {
                emptyEditorView
            }
        }
    }

    // MARK: - Gallery Detail

    private var galleryDetail: some View {
        Group {
            if let category = appState.selectedCategory {
                GalleryGridView(category: category)
            } else {
                galleryEmptyView
            }
        }
    }

    private var galleryEmptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("选择或创建一个分类")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// 向当前编辑器发送格式化操作
    private func postAction(_ action: EditorAction) {
        NotificationCenter.default.post(
            name: .vaultNoteEditorAction,
            object: action.rawValue
        )
    }
}
