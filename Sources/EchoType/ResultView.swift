import AppKit

/// 只读译文不成为第一响应者，滚动或拖动面板不会开始文本编辑。
private final class PanelTextView: NSTextView {
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Window-local hints never intercept a native resize gesture or change keyboard focus.
private final class PanelResizeHintView: NSView {
    var edgeMask = 0 {
        didSet { if oldValue != edgeMask { needsDisplay = true } }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard edgeMask != 0 else { return }
        let width = bounds.width
        let height = bounds.height
        if edgeMask & 1 != 0 { drawHint("↔", in: NSRect(x: 1, y: height / 2 - 12, width: 16, height: 24)) }
        if edgeMask & 2 != 0 { drawHint("↔", in: NSRect(x: width - 17, y: height / 2 - 12, width: 16, height: 24)) }
        if edgeMask & 4 != 0 { drawHint("↕", in: NSRect(x: width / 2 - 12, y: height - 19, width: 24, height: 18)) }
        if edgeMask & 8 != 0 { drawHint("↕", in: NSRect(x: width / 2 - 12, y: 1, width: 24, height: 18)) }
    }

    private func drawHint(_ direction: String, in rect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.white]
        let text = direction as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }
}

/// 悬浮窗内容：英文译文、复制按钮。
final class ResultView: NSView {
    var onCopy: ((String) -> Void)?

    private var currentResult: TranslationResult?

    // MARK: 流式逐字揭示
    // 服务端 SSE chunk 粒度不一（一次可能吐几个词甚至整句），
    // 这里缓冲目标文本、按固定节奏揭示，保证"逐字回显"的观感 + 流式光标。
    private var streamTarget = ""
    private var revealedCount = 0
    private var revealTimer: Timer?
    private static let streamCaret = "▍"

    private let kindLabel = EchoStyle.label("", size: 10.5, weight: .semibold, color: .systemTeal)
    private let translationField: NSTextView = {
        let field = PanelTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
        field.font = .systemFont(ofSize: 15)
        field.textColor = EchoStyle.textPrimary
        field.isEditable = false
        field.isSelectable = false
        field.isRichText = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isVerticallyResizable = true
        field.isHorizontallyResizable = false
        field.minSize = .zero
        field.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        field.autoresizingMask = [.width]
        field.textContainerInset = .zero
        field.textContainer?.lineFragmentPadding = 0
        field.textContainer?.containerSize = NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        field.textContainer?.widthTracksTextView = true
        return field
    }()
    private let translationScrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        return scrollView
    }()
    private let statusLabel = EchoStyle.label("", size: 10.5, color: EchoStyle.textTertiary, lines: 2)
    private let spinner: NSProgressIndicator = {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isIndeterminate = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let card: NSView = ResultView.makeCard()
    private let contents = NSView()
    private let header = NSStackView()
    private let footer = NSStackView()
    private let resizeHints = PanelResizeHintView()
    private var edgeTracking: NSTrackingArea?

    /// macOS 26+ 悬浮窗用 Liquid Glass；更低版本保持半透明圆角卡片。
    /// SnapPanel 据此决定是否覆盖全局 darkAqua 外观。
    static var usesLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    private var usesGlass: Bool {
        if #available(macOS 26.0, *) { return card is NSGlassEffectView }
        return false
    }

    private static func makeCard() -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 12
            glass.style = .clear
            return glass
        }
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = EchoStyle.separator.cgColor
        return view
    }

    private var copyButton: NSButton!
    private var pinButton: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildInterface()
        applyBackground()
    }

    required init?(coder: NSCoder) { nil }

    private func buildInterface() {
        addSubview(card)
        // No constraints connect the content to the window's frame. Its width and height belong to the user.
        card.frame = bounds
        card.autoresizingMask = [.width, .height]
        contents.frame = card.bounds
        contents.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *), let glass = card as? NSGlassEffectView {
            glass.contentView = contents
        } else {
            card.addSubview(contents)
        }
        translationScrollView.documentView = translationField

        copyButton = EchoStyle.button("复制英文", symbol: "doc.on.doc", target: self, action: #selector(copyTranslation), primary: true)
        copyButton.isEnabled = false

        pinButton = EchoStyle.iconButton("pin.fill", help: "常驻：失去焦点时不自动隐藏", target: self, action: #selector(togglePin))
        pinButton.contentTintColor = secondaryTextColor
        if !AppSettings.shared.pinPanel {
            pinButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "常驻")
        }
        statusLabel.textColor = tertiaryTextColor
        translationField.textColor = primaryTextColor

        [kindLabel, pinButton!, NSView(), spinner].forEach { header.addArrangedSubview($0) }
        header.orientation = .horizontal
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = true
        header.autoresizingMask = [.width, .minYMargin]

        [copyButton!, NSView(), statusLabel].forEach { footer.addArrangedSubview($0) }
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = true
        footer.autoresizingMask = [.width, .maxYMargin]
        translationScrollView.autoresizingMask = [.width, .height]
        [header, translationScrollView, footer].forEach { contents.addSubview($0) }
        contents.addSubview(resizeHints)
        resizeHints.autoresizingMask = [.width, .height]
        spinner.isHidden = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        card.frame = bounds
        contents.frame = card.bounds
        let area = contents.bounds
        resizeHints.frame = area
        let width = max(0, area.width - 36)
        header.frame = NSRect(x: 18, y: max(12, area.height - 36), width: width, height: 24)
        footer.frame = NSRect(x: 18, y: 12, width: width, height: 28)
        let textBottom = footer.frame.maxY + 8
        translationScrollView.frame = NSRect(x: 18, y: textBottom, width: width, height: max(0, header.frame.minY - 8 - textBottom))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    // Nonactivating panels still need edge hints while the input application keeps keyboard focus.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { updateTrackingAreas() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let edgeTracking { removeTrackingArea(edgeTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking)
        edgeTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) { updateResizeHint(with: event) }
    override func mouseMoved(with event: NSEvent) { updateResizeHint(with: event) }
    override func mouseExited(with event: NSEvent) {
        clearResizeHint()
    }

    /// Clear only a hint owned by this view when the panel is hidden.
    func clearResizeHint() {
        resizeHints.edgeMask = 0
    }

    private func updateResizeHint(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let margin: CGFloat = 6
        let left = bounds.contains(point) && point.x <= bounds.minX + margin
        let right = bounds.contains(point) && point.x >= bounds.maxX - margin
        let bottom = bounds.contains(point) && point.y <= bounds.minY + margin
        let top = bounds.contains(point) && point.y >= bounds.maxY - margin
        guard left || right || top || bottom else {
            clearResizeHint()
            return
        }
        resizeHints.edgeMask = (left ? 1 : (right ? 2 : 0)) | (top ? 4 : (bottom ? 8 : 0))
    }

    /// 玻璃雾化系数：把 0–1 的「背景不透明度」设置压缩到 0–0.15 的白色雾化强度。
    /// 液态玻璃本体不加着色（参考 macOS 26 小组件的近中性透射），
    /// 雾化层只作为滑块微调——系数过大会把玻璃糊成磨砂灰块。
    private static let glassTintFactor = 0.15

    /// 玻璃路径下，把「背景不透明度」设置映射为白色雾化层强度
    /// （提高不透明度 = 更不透明，白色雾化保持亮色材质而不会退回灰块）。
    static func glassTint(forOpacity opacity: Double, factor: Double) -> NSColor? {
        let strength = opacity * factor
        guard strength > 0.02 else { return nil }
        return NSColor(calibratedWhite: 1, alpha: strength)
    }

    /// 玻璃路径下用语义色——靠材质 vibrancy 随背景明暗自动反转；
    /// 旧卡片路径维持写死的亮色（卡片本身是深色的）。
    private var primaryTextColor: NSColor { usesGlass ? .labelColor : EchoStyle.textPrimary }
    private var secondaryTextColor: NSColor { usesGlass ? .secondaryLabelColor : EchoStyle.textSecondary }
    private var tertiaryTextColor: NSColor { usesGlass ? .tertiaryLabelColor : EchoStyle.textTertiary }

    private func applyBackground() {
        let opacity = AppSettings.shared.backgroundOpacity
        if #available(macOS 26.0, *), let glass = card as? NSGlassEffectView {
            glass.style = .clear
            glass.tintColor = Self.glassTint(forOpacity: opacity, factor: Self.glassTintFactor)
        } else {
            card.layer?.backgroundColor = EchoStyle.cardBackground.withAlphaComponent(opacity).cgColor
        }
    }

    func applySettings() {
        applyBackground()
        // 与设置页的"悬浮窗常驻"共享同一状态
        pinButton.image = NSImage(
            systemSymbolName: AppSettings.shared.pinPanel ? "pin.fill" : "pin",
            accessibilityDescription: "常驻"
        )
        if let result = currentResult { render(result) }
    }

    // MARK: 状态

    func setLoading(_ source: String) {
        currentResult = nil
        stopStreaming()
        spinner.startAnimation(nil)
        spinner.isHidden = false
        kindLabel.stringValue = "翻译中"
        translationField.font = .systemFont(ofSize: AppSettings.shared.panelFontSize, weight: .regular)
        translationField.textColor = secondaryTextColor
        translationField.string = source
        translationField.scrollRangeToVisible(NSRange(location: 0, length: 0))
        clearTransientViews()
        statusLabel.stringValue = ""
        copyButton.isEnabled = false
    }

    func show(_ result: TranslationResult) {
        stopStreaming()
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        render(result)
    }

    func showError(_ message: String) {
        stopStreaming()
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        kindLabel.stringValue = "翻译失败"
        statusLabel.stringValue = message
        statusLabel.textColor = .systemRed
        copyButton.isEnabled = false
    }

    private func clearTransientViews() {
        statusLabel.stringValue = ""
        statusLabel.textColor = tertiaryTextColor
    }

    private func render(_ result: TranslationResult) {
        currentResult = result
        clearTransientViews()
        kindLabel.stringValue = "译文"
        translationField.font = .systemFont(ofSize: AppSettings.shared.panelFontSize, weight: .semibold)
        translationField.textColor = primaryTextColor
        translationField.string = result.translation
        copyButton.isEnabled = true
    }

    @objc private func togglePin() {
        AppSettings.shared.pinPanel.toggle()
        pinButton.image = NSImage(
            systemSymbolName: AppSettings.shared.pinPanel ? "pin.fill" : "pin",
            accessibilityDescription: "常驻"
        )
    }

    /// 翻译完成后自动复制成功的提示。
    func showAutoCopied() {
        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = "已自动复制到剪贴板"
    }

    /// 流式输出：译文进缓冲区，由揭示定时器逐字显示（尚未完成时禁用复制）。
    func updatePartial(_ partial: String) {
        guard currentResult == nil else { return }
        if partial.count < revealedCount { revealedCount = 0 } // 防御：目标文本变短
        streamTarget = partial
        translationField.textColor = primaryTextColor
        copyButton.isEnabled = false
        statusLabel.stringValue = "生成中…"
        statusLabel.textColor = tertiaryTextColor
        startRevealTimer()
    }

    private func startRevealTimer() {
        guard revealTimer == nil else { return }
        let timer = Timer(timeInterval: 0.024, repeats: true) { [weak self] _ in
            self?.revealTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        revealTimer = timer
    }

    private func revealTick() {
        let target = streamTarget
        if revealedCount < target.count {
            // 积压越多每拍揭示越多（追赶），至少 1 字
            let backlog = target.count - revealedCount
            revealedCount = min(target.count, revealedCount + max(1, backlog / 6))
        }
        translationField.string = String(target.prefix(revealedCount)) + Self.streamCaret
    }

    private func stopStreaming() {
        revealTimer?.invalidate()
        revealTimer = nil
        streamTarget = ""
        revealedCount = 0
    }

    @objc private func copyTranslation() {
        guard let result = currentResult else { return }
        onCopy?(result.translation)
        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = "已复制英文"
    }
}
