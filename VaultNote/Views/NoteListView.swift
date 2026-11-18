import SwiftUI
import UniformTypeIdentifiers

/// 待确认的媒体移动操作
private struct PendingMove: Identifiable {
    let id = UUID()
    let fileName: String
    let from: String
    let to: String
}

/// 左侧边栏 — 模式切换 + 笔记列表 / 图库分类
struct NoteListView: View {
    @EnvironmentObject var appState: AppState

    @State private var newCategoryName = ""
    @State private var showNewCategoryAlert = false
    @State private var editingCategory: String?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool
    @State private var pendingMove: PendingMove?
    @State private var highlightedDropCategory: String?
    @State private var showMoveError = false
    @State private var moveErrorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // 模式切换
            Picker("模式", selection: $appState.currentMode) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .onChange(of: appState.currentMode) { newMode in
                if newMode == .gallery {
                    appState.loadGalleryCategories()
                }
            }

            Divider()

            // 内容区 — 根据模式切换
            if appState.currentMode == .gallery {
                galleryContent
            } else {
                notesContent
            }

            // 底部操作栏
            Divider()
            bottomBar
        }
        .frame(width: Constants.sidebarWidth)
        .alert(item: $pendingMove) { move in
            Alert(
                title: Text("移动文件"),
                message: Text("把「\(move.fileName)」移动到「\(move.to)」分类？"),
                primaryButton: .default(Text("移动")) { confirmMove(move) },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert("移动失败", isPresented: $showMoveError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(moveErrorMessage)
        }
    }

    // MARK: - Notes Mode

    private var notesContent: some View {
        VStack(spacing: 0) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索笔记...", text: $appState.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color(.controlBackgroundColor))

            Divider()

            // 笔记列表
            if appState.filteredNotes().isEmpty {
                emptyNotesView
            } else {
                ScrollViewReader { proxy in
                    List(selection: $appState.selectedNoteId) {
                        ForEach(appState.filteredNotes()) { note in
                            NoteRow(note: note)
                                .tag(note.id)
                                .contextMenu {
                                    Button("删除笔记") {
                                        appState.requestDeleteNote(note)
                                    }
                                }
                        }
                    }
                    .listStyle(.sidebar)
                    .onChange(of: appState.selectedNoteId) { newId in
                        guard let id = newId else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private var emptyNotesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(appState.searchText.isEmpty ? "还没有笔记" : "没有匹配结果")
                .font(.headline)
                .foregroundColor(.secondary)
            if appState.searchText.isEmpty {
                Text("点击下方 + 创建第一个笔记")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Gallery Mode

    private var galleryContent: some View {
        Group {
            if appState.galleryCategories.isEmpty {
                emptyGalleryView
            } else {
                List(selection: Binding(
                    get: { appState.selectedCategory },
                    set: {
                        appState.selectedCategory = $0
                        editingCategory = nil
                    }
                )) {
                    ForEach(appState.galleryCategories, id: \.self) { category in
                        categoryRow(category)
                            .tag(category)
                            .listRowBackground(
                                highlightedDropCategory == category
                                    ? Color.accentColor.opacity(0.15)
                                    : nil
                            )
                            .onDrop(
                                of: [UTType.fileURL],
                                isTargeted: dropTargetBinding(for: category)
                            ) { providers in
                                handleMediaDrop(providers, to: category)
                            }
                            .contextMenu {
                                Button("在 Finder 中显示") {
                                    let url = Constants.galleryDirectory.appendingPathComponent(category)
                                    NSWorkspace.shared.open(url)
                                }
                                Divider()
                                Button("删除", role: .destructive) {
                                    appState.deleteGalleryCategory(name: category)
                                }
                            }
                    }
                    .onMove { appState.moveGalleryCategory(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.sidebar)
                .contextMenu {
                    Button(action: { showNewCategoryAlert = true }) {
                        Label("新建文件夹", systemImage: "folder.badge.plus")
                    }
                }
            }
        }
    }

    /// 分类行：双击进入重命名；编辑时显示输入框
    @ViewBuilder
    private func categoryRow(_ category: String) -> some View {
        if editingCategory == category {
            TextField("分类名", text: $renameText)
                .textFieldStyle(.plain)
                .focused($renameFieldFocused)
                .onSubmit { commitRename(from: category) }
                .onExitCommand { editingCategory = nil }
                .onAppear {
                    renameFieldFocused = true
                }
        } else {
            Label(category, systemImage: "folder")
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    editingCategory = category
                    renameText = category
                })
                .help("双击重命名，拖拽调整顺序")
        }
    }

    private func commitRename(from oldName: String) {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty,
           newName != oldName,
           !appState.galleryCategories.contains(where: { $0 != oldName && $0 == newName }) {
            appState.renameGalleryCategory(from: oldName, to: newName)
        }
        editingCategory = nil
    }

    // MARK: - Media Drop

    /// 拖拽悬停高亮绑定
    private func dropTargetBinding(for category: String) -> Binding<Bool> {
        Binding(
            get: { highlightedDropCategory == category },
            set: { newValue in
                if newValue {
                    highlightedDropCategory = category
                } else if highlightedDropCategory == category {
                    highlightedDropCategory = nil
                }
            }
        )
    }

    /// 接收图库拖来的媒体文件，弹确认框
    private func handleMediaDrop(_ providers: [NSItemProvider], to category: String) -> Bool {
        guard let from = appState.selectedCategory else { return false }
        guard let provider = providers.first else { return false }
        // 拖到当前分类：接受但什么都不做（不复制、不弹窗）
        if from == category {
            return true
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                pendingMove = PendingMove(fileName: url.lastPathComponent, from: from, to: category)
            }
        }
        return true
    }

    private func confirmMove(_ move: PendingMove) {
        let ok = appState.moveMedia(fileName: move.fileName, from: move.from, to: move.to)
        if !ok {
            moveErrorMessage = "移动失败：「\(move.fileName)」未移动"
            showMoveError = true
        }
    }

    private var emptyGalleryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("还没有分类")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("点击下方 + 创建第一个分类")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("然后将图片/视频拖入图库区域")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            Button(action: { showNewCategoryAlert = true }) {
                Label("新建文件夹", systemImage: "folder.badge.plus")
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button(action: {
                if appState.currentMode == .gallery {
                    showNewCategoryAlert = true
                } else {
                    appState.createNewNote()
                }
            }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(appState.currentMode == .gallery ? "新建分类" : "新建笔记 (⌘N)")

            Spacer()

            Button(action: { appState.lock() }) {
                Image(systemName: "lock.fill")
            }
            .buttonStyle(.borderless)
            .help("锁定 (⌘L)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .alert("新建分类", isPresented: $showNewCategoryAlert) {
            TextField("分类名称", text: $newCategoryName)
            Button("取消", role: .cancel) {
                newCategoryName = ""
            }
            Button("创建") {
                let name = newCategoryName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    appState.createGalleryCategory(name: name)
                }
                newCategoryName = ""
            }
        } message: {
            Text("输入分类名称，会在图库文件夹中创建对应的子文件夹")
        }
    }
}

// MARK: - Note Row

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title.isEmpty ? "无标题笔记" : note.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Text(formattedDate(note.updatedAt))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "今天 \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "昨天 \(formatter.string(from: date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm"
            return formatter.string(from: date)
        }
    }
}
