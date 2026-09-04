import AppKit

/// 悬浮窗内容：英文译文（可选中）、备选译法、词/短语释义卡片、复制按钮。
final class ResultView: NSView {
    var onCopy: ((String) -> Void)?

    private var currentResult: TranslationResult?

    private let kindLabel = EchoStyle.label("", size: 10.5, weight: .semibold, color: .systemTeal)
    private let translationField = EchoStyle.selectableLabel("", size: 15)
    private let alternativesStack = NSStackView()
    private let glossStack = NSStackView()
    private let statusLabel = EchoStyle.label("", size: 10.5, color: EchoStyle.textTertiary, lines: 2)
    private let spinner: NSProgressIndicator = {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isIndeterminate = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let container: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = EchoStyle.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var copyButton: NSButton!
    private var pinButton: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildInterface()
        applyBackground()
    }

    required init?(coder: NSCoder) { nil }

    private func buildInterface() {
        addSubview(container)
        container.pinEdges(to: self, insets: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))

        translationField.lineBreakMode = .byWordWrapping
        translationField.maximumNumberOfLines = 0
        translationField.cell?.wraps = true
        translationField.cell?.isScrollable = false

        copyButton = EchoStyle.button("复制英文", symbol: "doc.on.doc", target: self, action: #selector(copyTranslation), primary: true)
        copyButton.isEnabled = false

        alternativesStack.orientation = .vertical
        alternativesStack.alignment = .leading
        alternativesStack.spacing = 3

        glossStack.orientation = .vertical
        glossStack.alignment = .leading
        glossStack.spacing = 4

        pinButton = EchoStyle.iconButton("pin.fill", help: "常驻：失去焦点时不自动隐藏", target: self, action: #selector(togglePin))
        if !AppSettings.shared.pinPanel {
            pinButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "常驻")
        }

        let header = NSStackView(views: [kindLabel, pinButton, NSView(), spinner])
        header.orientation = .horizontal
        header.alignment = .centerY

        let footer = NSStackView(views: [copyButton, NSView(), statusLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let stack = NSStackView(views: [header, translationField, alternativesStack, glossStack, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: SnapPanel.preferredWidth - 16),
        ])
        spinner.isHidden = true
    }

    private func applyBackground() {
        let opacity = AppSettings.shared.backgroundOpacity
        container.layer?.backgroundColor = EchoStyle.cardBackground.withAlphaComponent(opacity).cgColor
    }

    func applySettings() {
        applyBackground()
        if let result = currentResult { render(result) }
    }

    // MARK: 状态

    func setLoading(_ source: String) {
        currentResult = nil
        spinner.startAnimation(nil)
        spinner.isHidden = false
        kindLabel.stringValue = "翻译中"
        translationField.font = .systemFont(ofSize: AppSettings.shared.panelFontSize, weight: .regular)
        translationField.textColor = EchoStyle.textSecondary
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
        alternativesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        glossStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statusLabel.stringValue = ""
        statusLabel.textColor = EchoStyle.textTertiary
    }

    private func render(_ result: TranslationResult) {
        currentResult = result
        clearTransientViews()
        kindLabel.stringValue = "译文"
        translationField.font = .systemFont(ofSize: AppSettings.shared.panelFontSize, weight: .semibold)
        translationField.textColor = EchoStyle.textPrimary
        translationField.stringValue = result.translation
        copyButton.isEnabled = true

        if !result.alternatives.isEmpty {
            for alternative in result.alternatives.prefix(2) {
                let row = EchoStyle.label("· \(alternative)", size: 11.5, color: EchoStyle.textSecondary, lines: 2)
                alternativesStack.addArrangedSubview(row)
            }
        }

        if !result.phonetic.isEmpty || !result.meaning.isEmpty {
            glossStack.addArrangedSubview(makeSeparator())
            if !result.phonetic.isEmpty {
                glossStack.addArrangedSubview(
                    EchoStyle.label("\(result.phonetic)", size: 11, color: EchoStyle.textTertiary)
                )
            }
            if !result.meaning.isEmpty {
                glossStack.addArrangedSubview(
                    EchoStyle.label(result.meaning, size: 11.5, color: EchoStyle.textSecondary, lines: 2)
                )
            }
            for example in result.examples.prefix(2) {
                glossStack.addArrangedSubview(
                    EchoStyle.label("e.g. \(example)", size: 10.5, color: EchoStyle.textTertiary, lines: 2)
                )
            }
        }
    }

    private func makeSeparator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = EchoStyle.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        view.widthAnchor.constraint(equalToConstant: SnapPanel.preferredWidth - 44).isActive = true
        return view
    }

    @objc private func togglePin() {
        AppSettings.shared.pinPanel.toggle()
        pinButton.image = NSImage(
            systemSymbolName: AppSettings.shared.pinPanel ? "pin.fill" : "pin",
            accessibilityDescription: "常驻"
        )
    }

    /// 流式输出：实时刷新译文（尚未完成时禁用复制）。
    func updatePartial(_ partial: String) {
        guard currentResult == nil else { return }
        translationField.textColor = EchoStyle.textPrimary
        translationField.stringValue = partial
        copyButton.isEnabled = false
        statusLabel.stringValue = "生成中…"
        statusLabel.textColor = EchoStyle.textTertiary
    }

    @objc private func copyTranslation() {
        guard let result = currentResult else { return }
        onCopy?(result.translation)
        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = "已复制英文"
    }
}
