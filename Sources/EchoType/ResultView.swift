import AppKit

/// 拒绝成为第一响应者的文本标签：悬浮窗在 key/main 身份切换中
/// 若让文本框持有焦点，会画出选中高亮/首响应者白底。
private final class PanelTextField: NSTextField {
    override var acceptsFirstResponder: Bool { false }
}

/// 悬浮窗内容：英文译文、复制按钮。
final class ResultView: NSView {
    var onCopy: ((String) -> Void)?

    private var currentResult: TranslationResult?

    private let kindLabel = EchoStyle.label("", size: 10.5, weight: .semibold, color: .systemTeal)
    private let translationField: NSTextField = {
        let field = PanelTextField(labelWithString: "")
        field.font = .systemFont(ofSize: 15)
        field.textColor = EchoStyle.textPrimary
        field.isEditable = false
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
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
            glass.translatesAutoresizingMaskIntoConstraints = false
            return glass
        }
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = EchoStyle.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
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
        card.pinEdges(to: self, insets: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))

        translationField.lineBreakMode = .byWordWrapping
        translationField.maximumNumberOfLines = 0
        translationField.cell?.wraps = true
        translationField.cell?.isScrollable = false

        copyButton = EchoStyle.button("复制英文", symbol: "doc.on.doc", target: self, action: #selector(copyTranslation), primary: true)
        copyButton.isEnabled = false

        pinButton = EchoStyle.iconButton("pin.fill", help: "常驻：失去焦点时不自动隐藏", target: self, action: #selector(togglePin))
        pinButton.contentTintColor = secondaryTextColor
        if !AppSettings.shared.pinPanel {
            pinButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "常驻")
        }
        statusLabel.textColor = tertiaryTextColor
        translationField.textColor = primaryTextColor

        let header = NSStackView(views: [kindLabel, pinButton, NSView(), spinner])
        header.orientation = .horizontal
        header.alignment = .centerY

        let footer = NSStackView(views: [copyButton, NSView(), statusLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let stack = NSStackView(views: [header, translationField, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 26.0, *), let glass = card as? NSGlassEffectView {
            // AppKit 会自动把 contentView 四边约束到玻璃视图边缘，无需再手动 pin；
            // 玻璃高度随内容自适应，fittingSize 照常向上传播给 resizeToFitContent()。
            glass.contentView = stack
        } else {
            card.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                stack.topAnchor.constraint(equalTo: card.topAnchor),
                stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: SnapPanel.preferredWidth - 16),
            // 译文换行宽度 = 面板宽 - 容器左右边距(16) - 栈左右内边距(36)
            translationField.widthAnchor.constraint(equalToConstant: SnapPanel.preferredWidth - 16 - 36),
        ])
        spinner.isHidden = true
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
        spinner.startAnimation(nil)
        spinner.isHidden = false
        kindLabel.stringValue = "翻译中"
        translationField.font = .systemFont(ofSize: AppSettings.shared.panelFontSize, weight: .regular)
        translationField.textColor = secondaryTextColor
        translationField.stringValue = source
        clearTransientViews()
        statusLabel.stringValue = ""
        copyButton.isEnabled = false
    }

    func show(_ result: TranslationResult) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        render(result)
    }

    func showError(_ message: String) {
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
        translationField.stringValue = result.translation
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

    /// 流式输出：实时刷新译文（尚未完成时禁用复制）。
    func updatePartial(_ partial: String) {
        guard currentResult == nil else { return }
        translationField.textColor = primaryTextColor
        translationField.stringValue = partial
        copyButton.isEnabled = false
        statusLabel.stringValue = "生成中…"
        statusLabel.textColor = tertiaryTextColor
    }

    @objc private func copyTranslation() {
        guard let result = currentResult else { return }
        onCopy?(result.translation)
        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = "已复制英文"
    }
}
