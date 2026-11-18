import SwiftUI
import AppKit

/// 右侧笔记编辑器
struct NoteEditorView: View {
    @EnvironmentObject var appState: AppState

    let note: Note

    @State private var attributedText: NSAttributedString = NSAttributedString(string: "")
    @State private var title: String = ""
    @State private var isDirty = false
    @State private var hasSaved = false
    @State private var saveTimer: Timer?

    // 用于跟踪是否正在从 model 加载（避免触发 save）
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                TextField("无标题笔记", text: $title)
                    .font(.system(size: 18, weight: .semibold))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .onChange(of: title) { _ in
                        if !isLoading { scheduleSave() }
                    }

                // 保存状态指示
                if isDirty {
                    Text("未保存")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if hasSaved {
                    Text("已保存")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .background(Color(.controlBackgroundColor))

            Divider()

            // 富文本编辑器
            RichTextEditor(attributedString: $attributedText) { newText in
                if !isLoading { scheduleSave() }
            }
        }
        .onAppear { loadContent() }
        .onChange(of: note.id) { _ in loadContent() }
    }

    // MARK: - Content Loading

    private func loadContent() {
        saveTimer?.invalidate()
        isLoading = true
        title = note.title

        // 从磁盘加载 RTFD
        DispatchQueue.global(qos: .userInitiated).async {
            if let rtfdData = appState.loadRTFD(for: note.id) {
                if let attrString = try? NSAttributedString.fromRTFDData(rtfdData) {
                    DispatchQueue.main.async {
                        attributedText = attrString
                        isLoading = false
                        isDirty = false
                    }
                    return
                }
            }
            DispatchQueue.main.async {
                attributedText = NSAttributedString(string: "")
                isLoading = false
                isDirty = false
            }
        }
    }

    // MARK: - Save

    private func scheduleSave() {
        saveTimer?.invalidate()
        isDirty = true
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            performSave()
        }
    }

    private func performSave() {
        guard !isLoading else { return }
        guard appState.selectedNoteId == note.id else { return }

        do {
            let rtfdData = try attributedText.toRTFDData()
            let savedTitle = title.trimmingCharacters(in: .whitespaces).isEmpty
                ? "无标题笔记" : title
            appState.updateNote(
                Note(
                    id: note.id,
                    title: savedTitle,
                    createdAt: note.createdAt,
                    updatedAt: Date()
                ),
                rtfdData: rtfdData
            )
            DispatchQueue.main.async {
                isDirty = false
                hasSaved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    hasSaved = false
                }
            }
        } catch {
            print("保存失败: \(error)")
        }
    }
}
