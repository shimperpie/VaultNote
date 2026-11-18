import SwiftUI
import AppKit

// MARK: - Editor Actions

/// 编辑器支持的格式化操作
enum EditorAction: String {
    case toggleChecklist
    case increaseFontSize
    case decreaseFontSize
}

extension Notification.Name {
    static let vaultNoteEditorAction = Notification.Name("VaultNoteEditorAction")
}

/// 富文本编辑器 — 封装 NSTextView，支持图文混编
struct RichTextEditor: NSViewRepresentable {

    @Binding var attributedString: NSAttributedString
    var onTextChange: (NSAttributedString) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // --- 基础设置 ---
        textView.allowsUndo = true
        textView.isRichText = true
        textView.isEditable = true

        // --- 图片支持 ---
        textView.importsGraphics = true
        textView.allowsImageEditing = true

        // --- 布局 ---
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        // --- 字体 ---
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor

        // --- 关键：必须显式设置 typingAttributes ---
        // textView.font = 只设默认字体，打字时实际用的是 typingAttributes
        // 不设的话可能从 RTFD 加载继承加粗属性
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ]

        // --- 代理 ---
        textView.delegate = context.coordinator

        // --- 存储 textView 引用供 Coordinator 使用 ---
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // 中文输入法正在组合拼音/候选字时，禁止重置文本，否则输入法被打断
        if textView.hasMarkedText() { return }
        if textView.attributedString() != attributedString {
            textView.textStorage?.setAttributedString(attributedString)
            // 加载新内容后重置 typingAttributes，防止残留格式
            textView.typingAttributes = [
                .font: textView.font ?? NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ]
        }
        // 更新存储的引用（NavigationSplitView 可能复用 scrollView）
        context.coordinator.textView = textView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?

        init(_ parent: RichTextEditor) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAction(_:)),
                name: .vaultNoteEditorAction,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newValue = NSAttributedString(attributedString: textView.attributedString())
            parent.attributedString = newValue
            parent.onTextChange(newValue)
        }

        // MARK: - Action Handling

        @objc private func handleAction(_ notification: Notification) {
            guard let actionString = notification.object as? String,
                  let action = EditorAction(rawValue: actionString),
                  let textView = self.textView else {
                return
            }

            switch action {
            case .toggleChecklist:
                toggleChecklist(in: textView)
            case .increaseFontSize:
                adjustFontSize(delta: 2, in: textView)
            case .decreaseFontSize:
                adjustFontSize(delta: -2, in: textView)
            }
        }

        // MARK: - Checklist

        /// 切换当前段落的清单状态：无标记 → 添加 ○\t，有标记 → 移除
        private func toggleChecklist(in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let selectedRange = textView.selectedRange()
            let nsString = textStorage.string as NSString
            let paragraphRange = nsString.paragraphRange(for: selectedRange)

            let checklistMarker = "○\t"

            let paragraphText = nsString.substring(with: paragraphRange)

            if paragraphText.hasPrefix(checklistMarker) {
                // 已是清单 → 移除标记
                let markerLength = (checklistMarker as NSString).length
                let removeRange = NSRange(location: paragraphRange.location, length: markerLength)
                textStorage.deleteCharacters(in: removeRange)
            } else {
                // 不是清单 → 添加标记
                let bodyFont = textView.font ?? NSFont.systemFont(ofSize: 14)
                let circleFont = NSFont.systemFont(ofSize: bodyFont.pointSize + 4)

                let marker = NSMutableAttributedString()
                marker.append(NSAttributedString(
                    string: "○",
                    attributes: [
                        .font: circleFont,
                        .foregroundColor: NSColor.textColor
                    ]
                ))
                marker.append(NSAttributedString(
                    string: "\t",
                    attributes: [
                        .font: bodyFont,
                        .foregroundColor: NSColor.textColor
                    ]
                ))
                textStorage.insert(marker, at: paragraphRange.location)
            }

            // 触发保存
            textView.delegate?.textDidChange?(
                Notification(name: NSText.didChangeNotification, object: textView)
            )
        }

        // MARK: - Font Size

        /// 调整选中文本或当前输入位置的字号
        /// - Parameter delta: 正数放大，负数缩小
        private func adjustFontSize(delta: CGFloat, in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let selectedRange = textView.selectedRange()

            // 确定当前字号
            var currentSize: CGFloat = 14
            if textStorage.length > 0 {
                let checkPos = min(selectedRange.location, textStorage.length - 1)
                if let font = textStorage.attribute(.font, at: checkPos, effectiveRange: nil) as? NSFont {
                    currentSize = font.pointSize
                }
            } else if let font = textView.typingAttributes[.font] as? NSFont {
                currentSize = font.pointSize
            }

            let newSize = max(8, min(72, currentSize + delta))
            if newSize == currentSize { return }

            let newFont = NSFont.systemFont(ofSize: newSize)

            if selectedRange.length > 0 {
                // 收集每个显式字体范围的调整后字体（保留粗体/斜体等特征）
                var adjustments: [(NSRange, NSFont)] = []
                textStorage.enumerateAttribute(.font, in: selectedRange, options: []) { value, range, _ in
                    if let font = value as? NSFont {
                        let adjustedSize = max(8, min(72, font.pointSize + delta))
                        if adjustedSize != font.pointSize {
                            let adjustedFont = NSFont(descriptor: font.fontDescriptor, size: adjustedSize)
                                ?? NSFont.systemFont(ofSize: adjustedSize)
                            adjustments.append((range, adjustedFont))
                        }
                    }
                }

                // 整个选区设为基础字号
                textStorage.addAttribute(.font, value: newFont, range: selectedRange)

                // 恢复各范围的字体特征（粗体/斜体等）
                for (range, font) in adjustments {
                    textStorage.addAttribute(.font, value: font, range: range)
                }
            }

            // 更新 typingAttributes 供后续输入使用
            textView.typingAttributes[.font] = newFont

            // 触发保存
            textView.delegate?.textDidChange?(
                Notification(name: NSText.didChangeNotification, object: textView)
            )
        }
    }
}

// MARK: - NSAttributedString <> RTFD Data

extension NSAttributedString {

    /// 将富文本导出为 RTFD 格式（含图片）
    func toRTFDData() throws -> Data {
        let range = NSRange(location: 0, length: length)
        let docAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtfd
        ]
        return try data(from: range, documentAttributes: docAttributes)
    }

    /// 从 RTFD 数据恢复富文本
    static func fromRTFDData(_ data: Data) throws -> NSAttributedString {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtfd
        ]
        return try NSAttributedString(data: data, options: options, documentAttributes: nil)
    }
}
