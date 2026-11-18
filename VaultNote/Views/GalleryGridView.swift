import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - Keyboard Handler (reference type, survives struct re-creation)

/// 图库键盘事件处理器 — 必须是 class，NSEvent 闭包才能读到最新状态
private class GalleryKeyHandler: ObservableObject {
    @Published var isSelecting = false
    @Published var selectedIDs: Set<UUID> = []

    var onImport: (() -> Void)?
    var onDeleteSelected: (() -> Void)?
    var onExitSelection: (() -> Void)?

    private var monitor: Any?

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow?.sheets.isEmpty ?? true else { return event }

            let cmd = event.modifierFlags.contains(.command)
            if cmd && event.keyCode == 34 { // ⌘I
                self.onImport?()
                return nil
            }

            // 焦点在文本输入框（field editor）时不拦截，避免吞掉输入框的 Delete/Esc
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                return event
            }

            if event.keyCode == 51 { // Delete
                if self.isSelecting && !self.selectedIDs.isEmpty {
                    self.onDeleteSelected?()
                }
                return nil
            }
            if event.keyCode == 53 { // Escape
                if self.isSelecting {
                    self.onExitSelection?()
                    return nil
                }
            }
            return event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}

// MARK: - Gallery Grid View

/// 图库媒体网格视图
struct GalleryGridView: View {
    @EnvironmentObject var appState: AppState

    let category: String  // 仅用于初始显示，实际数据源走 appState.selectedCategory
    let galleryManager = GalleryManager()

    @State private var mediaItems: [MediaItem] = []
    @State private var favorites: Set<String> = []
    @State private var showViewer = false
    @State private var selectedItem: MediaItem?
    @State private var showDeleteAlert = false
    @State private var showOrphanBGMAlert = false
    @State private var orphanBGMs: [String] = []

    @StateObject private var keyHandler = GalleryKeyHandler()
    @State private var showDownloadSheet = false

    /// 真正的当前分类 — 绕过 NavigationSplitView 传参复用问题
    private var activeCategory: String { appState.selectedCategory ?? category }

    var body: some View {
        VStack(spacing: 0) {
            galleryToolbar
            Group {
                if mediaItems.isEmpty { emptyView }
                else { gridView }
            }
        }
        .onAppear {
            keyHandler.onImport = { importFiles() }
            keyHandler.onDeleteSelected = { showDeleteAlert = true }
            keyHandler.onExitSelection = { exitSelectionMode() }
            keyHandler.start()
        }
        .onDisappear { keyHandler.stop() }
        .onChange(of: activeCategory) { _ in
            exitSelectionMode()
            loadMedia()
        }
        .onAppear {
            loadMedia()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaultGalleryDidChange)) { _ in
            loadMedia()
        }
        .overlay {
            if showViewer, let item = selectedItem {
                MediaDetailView(
                    item: item,
                    items: viewerItems,
                    isPresented: $showViewer,
                    favorites: favorites,
                    onToggleFavorite: { toggleFavorite($0) }
                )
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showViewer)
        .sheet(isPresented: $showDownloadSheet) {
            DownloadSheet(onDownloadComplete: {
                loadMedia()
            })
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteSelected() }
        } message: {
            Text("确定要删除选中的 \(keyHandler.selectedIDs.count) 个文件吗？删除后无法恢复。")
        }
        .alert("清理孤儿 BGM", isPresented: $showOrphanBGMAlert) {
            if orphanBGMs.isEmpty {
                Button("好的", role: .cancel) {}
            } else {
                Button("取消", role: .cancel) {}
                Button("删除 \(orphanBGMs.count) 个", role: .destructive) {
                    galleryManager.removeOrphanBGMs(in: activeCategory)
                    loadMedia()
                }
            }
        } message: {
            Text(orphanBGMs.isEmpty
                ? "没有找到不再被使用的 BGM 文件。"
                : "将删除以下不再被使用的 BGM：\n"
                    + orphanBGMs.prefix(8).joined(separator: "\n")
                    + (orphanBGMs.count > 8 ? "\n…" : ""))
        }
    }

    // MARK: - Toolbar

    private var galleryToolbar: some View {
        HStack(spacing: 12) {
            Button(action: importFiles) {
                Image(systemName: "square.and.arrow.down")
            }
            .help("导入文件 (⌘I)")

            Button(action: { showDownloadSheet = true }) {
                Image(systemName: "link")
            }
            .help("粘贴抖音链接下载视频")

            if !keyHandler.isSelecting {
                Button(action: scanAndCleanBGM) {
                    Image(systemName: "broom")
                }
                .help("清理孤儿 BGM")
            }

            Spacer()

            if keyHandler.isSelecting {
                Text("已选 \(keyHandler.selectedIDs.count) 项")
                    .font(.body)
                    .foregroundColor(.secondary)

                Button(mediaItems.isEmpty || keyHandler.selectedIDs.count == mediaItems.count ? "取消全选" : "全选") {
                    toggleSelectAll()
                }

                Button("取消") { exitSelectionMode() }

                Button(action: { showDeleteAlert = true }) {
                    Label("删除所选", systemImage: "trash")
                }
                .disabled(keyHandler.selectedIDs.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button("选择") { enterSelectionMode() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Grid

    private var gridView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(sortedGroups) { group in
                    Section {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 140, maximum: 300), spacing: 4)],
                            spacing: 4
                        ) {
                            ForEach(group.items) { item in
                                cell(for: item)
                            }
                        }
                    } header: {
                        if let album = group.album {
                            Text("\(album.strippingHashtags()) · \(group.items.count) 项")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                        }
                    }
                }
            }
            .padding(8)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    /// 单个媒体项的网格单元
    private func cell(for item: MediaItem) -> some View {
        ThumbnailCell(
            item: item,
            galleryManager: galleryManager,
            isSelected: keyHandler.selectedIDs.contains(item.id),
            isSelecting: keyHandler.isSelecting,
            isFavorite: favorites.contains(item.fileName),
            onToggleFavorite: { toggleFavorite(item) }
        )
        .onTapGesture {
            if keyHandler.isSelecting {
                toggleSelection(item)
            } else {
                selectedItem = item
                showViewer = true
            }
        }
        .onDrag {
            NSItemProvider(object: item.fileURL as NSURL)
        }
        .contextMenu {
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
            }
            Button(favorites.contains(item.fileName) ? "取消收藏" : "收藏") {
                toggleFavorite(item)
            }
            Divider()
            Button("删除", role: .destructive) { deleteSingleItem(item) }
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("此分类暂无媒体")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("拖入图片或视频到此处，或按 ⌘I 导入")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Selection

    private func toggleSelection(_ item: MediaItem) {
        if keyHandler.selectedIDs.contains(item.id) {
            keyHandler.selectedIDs.remove(item.id)
        } else {
            keyHandler.selectedIDs.insert(item.id)
        }
    }

    /// 全选 / 取消全选当前分类的全部媒体
    private func toggleSelectAll() {
        let allIDs = Set(mediaItems.map { $0.id })
        if !allIDs.isEmpty && keyHandler.selectedIDs.isSuperset(of: allIDs) {
            keyHandler.selectedIDs = []
        } else {
            keyHandler.selectedIDs = allIDs
        }
    }

    private func enterSelectionMode() {
        keyHandler.isSelecting = true
        keyHandler.selectedIDs = []
    }

    private func exitSelectionMode() {
        keyHandler.isSelecting = false
        keyHandler.selectedIDs = []
    }

    // MARK: - BGM Cleanup

    private func scanAndCleanBGM() {
        orphanBGMs = galleryManager.scanOrphanBGMs(in: activeCategory)
        showOrphanBGMAlert = true
    }

    // MARK: - Import

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .movie, .audiovisualContent]
        panel.message = "选择要导入到「\(activeCategory)」的媒体文件"

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            do {
                try galleryManager.importFile(from: url, to: activeCategory)
            } catch {
                print("导入失败: \(error)")
            }
        }
        loadMedia()
    }

    // MARK: - Delete

    private func deleteSingleItem(_ item: MediaItem) {
        do {
            try galleryManager.deleteMedia(item)
            favorites.remove(item.fileName)
            try? galleryManager.saveFavorites(favorites, in: activeCategory)
            keyHandler.selectedIDs.remove(item.id)
            mediaItems.removeAll { $0.id == item.id }
        } catch {
            print("删除失败: \(error)")
        }
    }

    private func deleteSelected() {
        let toDelete = mediaItems.filter { keyHandler.selectedIDs.contains($0.id) }
        for item in toDelete {
            try? galleryManager.deleteMedia(item)
            favorites.remove(item.fileName)
        }
        try? galleryManager.saveFavorites(favorites, in: activeCategory)
        mediaItems.removeAll { keyHandler.selectedIDs.contains($0.id) }
        exitSelectionMode()
    }

    // MARK: - Data

    private func loadMedia() {
        do {
            let items = try galleryManager.listMedia(in: activeCategory)
            favorites = galleryManager.loadFavorites(in: activeCategory)
            mediaItems = items
            applyFavoritesAndSort()
        } catch {
            print("加载图库失败: \(error)")
            mediaItems = []
        }
    }

    /// 把收藏状态应用到列表并排序：收藏的排最前，其后按文件名
    private func applyFavoritesAndSort() {
        for i in mediaItems.indices {
            mediaItems[i].isFavorite = favorites.contains(mediaItems[i].fileName)
        }
        mediaItems.sort { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            return a.fileName.localizedStandardCompare(b.fileName) == .orderedAscending
        }
    }

    private func toggleFavorite(_ item: MediaItem) {
        if favorites.contains(item.fileName) {
            favorites.remove(item.fileName)
        } else {
            favorites.insert(item.fileName)
        }
        try? galleryManager.saveFavorites(favorites, in: activeCategory)
        applyFavoritesAndSort()
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    // 图库内部文件（已在 ~/.vaultnote/gallery 下）不导入复制，
                    // 避免把图库文件拖回网格时被复制一份
                    if url.path.hasPrefix(Constants.galleryDirectory.path) {
                        return
                    }
                    do {
                        try galleryManager.importFile(from: url, to: activeCategory)
                        loadMedia()
                    } catch {
                        print("导入失败: \(error)")
                    }
                }
            }
        }
        return true
    }

    // MARK: - Grouping

    /// 把媒体列表按合集分组（同名前缀 _N 项归一组），单件各自成组；
    /// 组排序：含收藏的组在前，其余按名称
    private var sortedGroups: [MediaGroup] {
        var map: [String: (album: String?, items: [MediaItem])] = [:]
        var order: [String] = []

        for item in mediaItems {
            if let key = item.albumKey {
                if map[key] == nil { order.append(key) }
                map[key, default: (album: key, items: [])].items.append(item)
            } else {
                let key = "single:\(item.id.uuidString)"
                order.append(key)
                map[key] = (album: nil, items: [item])
            }
        }

        var groups = order.compactMap { key -> MediaGroup? in
            guard let g = map[key] else { return nil }
            // 组内按文件名（序号）排列，保证预览左右键按合集自然顺序走
            let sortedItems = g.items.sorted {
                $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
            }
            return MediaGroup(id: key, album: g.album, items: sortedItems)
        }
        groups.sort { a, b in
            let aFav = a.items.contains(where: \.isFavorite)
            let bFav = b.items.contains(where: \.isFavorite)
            if aFav != bFav { return aFav }
            let aName = a.album ?? a.items.first?.fileName ?? ""
            let bName = b.album ?? b.items.first?.fileName ?? ""
            return aName.localizedStandardCompare(bName) == .orderedAscending
        }
        return groups
    }

    /// 预览用浏览顺序：按分组摊平（合集连在一起、组内按序号），
    /// 保证左右键先在当前合集内切换，组尾才进入下一个合集/单件
    private var viewerItems: [MediaItem] {
        sortedGroups.flatMap { $0.items }
    }
}

/// 图库分组单元：合集（album 非空）或单件（album 为 nil）
private struct MediaGroup: Identifiable {
    let id: String
    let album: String?
    let items: [MediaItem]
}

// MARK: - Thumbnail Cell

struct ThumbnailCell: View {
    let item: MediaItem
    let galleryManager: GalleryManager
    let isSelected: Bool
    let isSelecting: Bool
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .overlay {
                            ProgressView().controlSize(.small)
                        }
                }

                // 选中遮罩
                if isSelecting && isSelected {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                }

                // 选中勾选
                if isSelecting && isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                                .background(Circle().fill(Color.white).frame(width: 18, height: 18))
                                .padding(6)
                        }
                        Spacer()
                    }
                }

                // 视频标记
                if item.isVideo {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill").font(.caption2)
                        Text("视频").font(.caption2)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                    .padding(4)
                }

                // 收藏星标
                if !isSelecting && isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .onTapGesture { onToggleFavorite() }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            isSelecting
                ? RoundedRectangle(cornerRadius: 0)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                : nil
        )
        .task {
            thumbnail = await galleryManager.generateThumbnail(for: item)
        }
    }
}
