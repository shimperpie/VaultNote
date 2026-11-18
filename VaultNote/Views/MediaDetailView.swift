import SwiftUI
import AVKit
import AVFoundation

/// 媒体全屏预览器 — 支持图片缩放和视频播放
/// 双播放器架构：videoPlayer 循环播画面，audioPlayer 持续播 BGM
struct MediaDetailView: View {
    let item: MediaItem
    let items: [MediaItem]
    let favorites: Set<String>
    let onToggleFavorite: (MediaItem) -> Void

    @Binding var isPresented: Bool

    @State private var currentIndex: Int
    @State private var favSet: Set<String>
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    @State private var videoPlayer: AVPlayer?
    @State private var audioPlayer: AVPlayer?
    @State private var currentBGMURL: URL?
    @State private var loopObserver: Any?
    @State private var keyMonitor: Any?
    @State private var isMuted = false
    @State private var isPlaying = true
    @State private var controlsVisible = true
    @State private var videoProgress: Double = 0
    @State private var timeObserver: Any?

    init(
        item: MediaItem,
        items: [MediaItem],
        isPresented: Binding<Bool>,
        favorites: Set<String>,
        onToggleFavorite: @escaping (MediaItem) -> Void
    ) {
        self.item = item
        self.items = items
        self.favorites = favorites
        self.onToggleFavorite = onToggleFavorite
        self._isPresented = isPresented
        self._currentIndex = State(initialValue: items.firstIndex(of: item) ?? 0)
        self._favSet = State(initialValue: favorites)
    }

    var currentItem: MediaItem {
        guard currentIndex >= 0 && currentIndex < items.count else { return item }
        return items[currentIndex]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部工具栏
                HStack {
                    Text(currentItem.fileName.strippingHashtags())
                        .foregroundColor(.white)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text("\(currentIndex + 1) / \(items.count)")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.body)
                        .padding(.trailing, 16)

                    // 收藏星标
                    Button(action: toggleFavorite) {
                        Image(systemName: favSet.contains(currentItem.fileName) ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundColor(favSet.contains(currentItem.fileName) ? .yellow : .white)
                    }
                    .buttonStyle(.plain)
                    .help("收藏")

                    // 静音按钮：视频或照片但有BGM时都显示
                    if currentItem.isVideo || currentBGMURL != nil {
                        Button(action: {
                            isMuted.toggle()
                            videoPlayer?.isMuted = isMuted
                            audioPlayer?.isMuted = isMuted
                        }) {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help(isMuted ? "🔇 静音" : "🔈 有声音")
                    }

                    Button(action: { closeViewer() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.55), .black.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // 媒体内容
                if currentItem.isVideo {
                    videoView
                } else {
                    imageView
                }

                // 底部导航
                HStack(spacing: 32) {
                    Button(action: { navigate(-1) }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title)
                            .foregroundColor(currentIndex > 0 ? .white : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(currentIndex <= 0)

                    Button(action: { closeViewer() }) {
                        Image(systemName: "rectangle.grid.1x2.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("返回图库")

                    Button(action: { navigate(1) }) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title)
                            .foregroundColor(currentIndex < items.count - 1 ? .white : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(currentIndex >= items.count - 1)
                }
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0), .black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onAppear {
            loadMedia()
            startKeyMonitor()
        }
        .onChange(of: currentIndex) { _ in loadMedia() }
        .onDisappear {
            videoPlayer?.pause()
            audioPlayer?.pause()
            stopKeyMonitor()
            clearTimeObserver()
            if let obs = loopObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }
    }

    // MARK: - Image View

    private var imageView: some View {
        GeometryReader { geo in
            if let nsImage = NSImage(contentsOf: currentItem.fileURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(0.5, min(5.0, lastScale * value))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                },
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if scale > 1.0 {
                                scale = 1.0; lastScale = 1.0
                                offset = .zero; lastOffset = .zero
                            } else {
                                scale = 2.0; lastScale = 2.0
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("无法加载图片")
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Video View

    private var videoView: some View {
        ZStack(alignment: .bottom) {
            if let player = videoPlayer {
                GeometryReader { geo in
                    NativeVideoPlayer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { togglePlayPause() }
                        .onContinuousHover { phase in
                            // 所有视频统一：进度线只在鼠标位于视频底部 60pt 区域时显示，
                            // 离开该区域立即隐藏
                            switch phase {
                            case .active(let location):
                                let inBottomZone = location.y >= geo.size.height - 60
                                if controlsVisible != inBottomZone {
                                    controlsVisible = inBottomZone
                                }
                            case .ended:
                                if controlsVisible { controlsVisible = false }
                            }
                        }
                }
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 极简控制：细进度线 + 播放/暂停按钮（鼠标在视频底部时显示）
            if controlsVisible, currentItem.isVideo {
                HStack(spacing: 10) {
                    Button(action: togglePlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    .help(isPlaying ? "暂停" : "播放")

                    videoProgressBar
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
    }

    /// 2px 细进度线（只显示不拖动，避免与独立 BGM 播放错位）
    private var videoProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(2, geo.size.width * videoProgress))
            }
        }
        .frame(height: 2)
    }

    // MARK: - Keyboard

    private func startKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            switch event.keyCode {
            case 123: // left arrow
                if currentIndex > 0 { navigate(-1) }
                return nil
            case 124: // right arrow
                if currentIndex < items.count - 1 { navigate(1) }
                return nil
            default:
                return event
            }
        }
    }

    private func stopKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Media Loading

    private func loadMedia() {
        // 清理旧视频
        clearTimeObserver()
        videoPlayer?.pause()
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
            loopObserver = nil
        }
        videoPlayer = nil

        // 重置图片状态
        scale = 1.0; lastScale = 1.0
        offset = .zero; lastOffset = .zero
        isMuted = false
        videoProgress = 0
        isPlaying = true
        controlsVisible = false

        let bgmURL = findBGM(for: currentItem.fileURL)

        if currentItem.isVideo {
            // ── 视频播放器（只播画面，循环）──
            let videoAsset = AVAsset(url: currentItem.fileURL)
            let videoItem = AVPlayerItem(asset: videoAsset)
            let vp = AVPlayer(playerItem: videoItem)
            videoPlayer = vp
            vp.isMuted = false

            // 进度观察（驱动底部细进度线）
            timeObserver = vp.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                queue: .main
            ) { [self] time in
                guard let duration = self.videoPlayer?.currentItem?.duration,
                      duration.seconds.isFinite,
                      duration.seconds > 0 else { return }
                self.videoProgress = min(1, max(0, time.seconds / duration.seconds))
            }

            // 循环监听
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: videoItem,
                queue: .main
            ) { _ in
                vp.seek(to: .zero)
                vp.play()
                isPlaying = true
            }

            vp.play()

            // ── BGM 切换 ──
            switchBGM(to: bgmURL)
        } else {
            // ── 照片：保持 BGM 继续，不重建 ──
            if let bgmURL = bgmURL {
                if bgmURL != currentBGMURL {
                    switchBGM(to: bgmURL)
                }
                // 相同 BGM → audioPlayer 继续播，啥也不做
            }
        }
    }

    // MARK: - Minimal Controls

    /// 点击画面：整体播放/暂停（视频画面 + BGM 一起）
    private func togglePlayPause() {
        guard currentItem.isVideo else { return }

        if isPlaying {
            videoPlayer?.pause()
            audioPlayer?.pause()
            isPlaying = false
        } else {
            videoPlayer?.play()
            if audioPlayer != nil {
                audioPlayer?.play()
            }
            isPlaying = true
        }
    }

    /// 移除视频进度观察器
    private func clearTimeObserver() {
        if let observer = timeObserver {
            videoPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    /// 切换 BGM：URL 相同则保持播放，不同则切换从头播
    private func switchBGM(to bgmURL: URL?) {
        guard let bgmURL = bgmURL else { return }

        if bgmURL == currentBGMURL {
            // 同一首歌 → 保持继续播（如果暂停了就恢复）
            if audioPlayer?.rate == 0 {
                audioPlayer?.play()
            }
            return
        }

        // 不同 BGM → 切换
        audioPlayer?.pause()
        let audioItem = AVPlayerItem(asset: AVAsset(url: bgmURL))
        audioPlayer = AVPlayer(playerItem: audioItem)
        audioPlayer?.isMuted = isMuted
        audioPlayer?.play()
        currentBGMURL = bgmURL
    }

    /// 查找视频对应的 BGM 文件
    private func findBGM(for videoURL: URL) -> URL? {
        let videoPath = videoURL.path
        let basePath = videoPath.hasSuffix(".mp4")
            ? String(videoPath.dropLast(4))
            : videoURL.deletingPathExtension().path
        let fm = FileManager.default

        let exactPath = basePath + "_bgm.mp3"
        if fm.fileExists(atPath: exactPath) {
            return URL(fileURLWithPath: exactPath)
        }

        if let range = basePath.range(of: #"_\d+$"#, options: .regularExpression) {
            let albumBase = String(basePath[..<range.lowerBound])
            let albumPath = albumBase + "_bgm.mp3"
            if fm.fileExists(atPath: albumPath) {
                return URL(fileURLWithPath: albumPath)
            }
        }

        return nil
    }

    // MARK: - Navigation

    private func navigate(_ delta: Int) {
        let newIndex = currentIndex + delta
        guard newIndex >= 0, newIndex < items.count else { return }
        currentIndex = newIndex
    }

    private func toggleFavorite() {
        let name = currentItem.fileName
        if favSet.contains(name) {
            favSet.remove(name)
        } else {
            favSet.insert(name)
        }
        onToggleFavorite(currentItem)
    }

    private func closeViewer() {
        videoPlayer?.pause()
        audioPlayer?.pause()
        isPresented = false
    }
}

// MARK: - Native Video Player (avoids _AVKit_SwiftUI crash on macOS 26)

struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        // 无痕播放：系统控制条全部隐藏，用自绘极简进度线
        view.controlsStyle = .none
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
