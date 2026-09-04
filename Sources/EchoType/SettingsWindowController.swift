import AppKit

/// 设置窗口：复刻 EchoSub 的侧栏 + 表单风格，四个标签页。
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private enum Tab: Int, CaseIterable {
        case translation
        case trigger
        case appearance
        case data

        var title: String {
            switch self {
            case .translation: return "翻译服务"
            case .trigger: return "触发方式"
            case .appearance: return "悬浮窗外观"
            case .data: return "数据与隐私"
            }
        }

        var symbol: String {
            switch self {
            case .translation: return "character.bubble"
            case .trigger: return "bolt"
            case .appearance: return "paintbrush"
            case .data: return "key"
            }
        }
    }

    private let settings = AppSettings.shared
    private let table = NSTableView()
    private let content = NSView()
    private var selectedTab: Tab = .translation
    private var baseURLField: NSTextField?
    private var modelField: NSTextField?
    private var keyField: NSSecureTextField?
    private var connectionLabel: NSTextField?
    private var pinCheckbox: NSButton?
    private var autoCopyCheckbox: NSButton?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "EchoType 设置"
        window.backgroundColor = EchoStyle.windowBackground
        window.setFrameAutosaveName("EchoType.settings")
        super.init(window: window)
        window.delegate = self
        buildInterface()
        showTab(.translation)

        // 悬浮窗 Pin 按钮与设置开关共享同一状态，变化时同步刷新
        NotificationCenter.default.addObserver(forName: .echoSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.pinCheckbox?.state = AppSettings.shared.pinPanel ? .on : .off
            self?.autoCopyCheckbox?.state = AppSettings.shared.autoCopyTranslation ? .on : .off
        }
    }

    required init?(coder: NSCoder) { nil }

    private func buildInterface() {
        guard let root = window?.contentView else { return }
        root.wantsLayer = true
        root.layer?.backgroundColor = EchoStyle.windowBackground.cgColor
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(split)
        split.pinEdges(to: root)

        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = EchoStyle.sidebarBackground.cgColor
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("settings-tab"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 34
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(scroll)
        scroll.pinEdges(to: sidebar, insets: NSEdgeInsets(top: 16, left: 8, bottom: 12, right: 8))

        content.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(content)
        sidebar.widthAnchor.constraint(equalToConstant: 172).isActive = true
        content.widthAnchor.constraint(greaterThanOrEqualToConstant: 460).isActive = true
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { Tab.allCases.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tab = Tab(rawValue: row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("settings-tab-cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let label = EchoStyle.label("", size: 12, weight: .medium)
            cell.textField = label
            cell.addSubview(label)
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 28).isActive = true
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
            let image = NSImageView()
            image.identifier = NSUserInterfaceItemIdentifier("tab-icon")
            image.translatesAutoresizingMaskIntoConstraints = false
            image.contentTintColor = EchoStyle.accent
            cell.addSubview(image)
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 14),
                image.heightAnchor.constraint(equalToConstant: 14),
            ])
        }
        cell.textField?.stringValue = tab.title
        (cell.subviews.first(where: { $0.identifier?.rawValue == "tab-icon" }) as? NSImageView)?
            .image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tab = Tab(rawValue: table.selectedRow) else { return }
        showTab(tab)
    }

    private func showTab(_ tab: Tab) {
        if selectedTab == .translation { saveTranslationFields() }
        selectedTab = tab
        content.removeAllSubviews()
        let title = EchoStyle.label(tab.title, size: 16, weight: .bold)
        let body: NSView
        switch tab {
        case .translation: body = makeTranslationSettings()
        case .trigger: body = makeTriggerSettings()
        case .appearance: body = makeAppearanceSettings()
        case .data: body = makeDataSettings()
        }
        let stack = NSStackView(views: [title, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
        ])
    }

    // MARK: - 翻译服务

    private func makeTranslationSettings() -> NSView {
        let provider = NSPopUpButton()
        provider.addItems(withTitles: ["OpenAI 兼容接口"])
        let base = NSTextField(string: settings.translationBaseURL)
        base.placeholderString = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        styleInput(base)
        baseURLField = base
        let model = NSTextField(string: settings.translationModel)
        model.placeholderString = "qwen3.7-plus"
        styleInput(model)
        modelField = model
        let key = NSSecureTextField(string: PlaintextCredentialStore.shared.loadTranslationAPIKey())
        key.placeholderString = "sk-…"
        styleInput(key)
        keyField = key
        let test = EchoStyle.button("测试连接", target: self, action: #selector(testTranslation))
        let status = EchoStyle.label("", size: 11, color: EchoStyle.textTertiary)
        connectionLabel = status
        let keyStack = NSStackView(views: [key, test])
        keyStack.orientation = .horizontal
        keyStack.spacing = 8
        return form([
            row("翻译服务", detail: "使用你自己的 API Key", control: provider),
            row("API Base URL", detail: "可指向兼容接口或代理服务", control: base),
            row("模型名称", control: model),
            row("API Key", detail: "本机明文 credentials.json", control: keyStack),
            row("连接状态", control: status),
            note("输入框中的中文文本会发送给你配置的翻译服务；翻译结果按原文缓存，相同内容不会重复请求。"),
        ])
    }

    private func saveTranslationFields() {
        if let value = baseURLField?.stringValue, !value.isEmpty { settings.translationBaseURL = value }
        if let value = modelField?.stringValue, !value.isEmpty { settings.translationModel = value }
        if let value = keyField?.stringValue { PlaintextCredentialStore.shared.saveTranslationAPIKey(value) }
    }

    @objc private func testTranslation() {
        saveTranslationFields()
        connectionLabel?.stringValue = "正在测试…"
        connectionLabel?.textColor = EchoStyle.textSecondary
        TranslationService().testConnection(configuration: settings.translationConfiguration) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.connectionLabel?.stringValue = "● 连接成功"
                    self?.connectionLabel?.textColor = .systemGreen
                case .failure(let error):
                    self?.connectionLabel?.stringValue = error.localizedDescription
                    self?.connectionLabel?.textColor = .systemRed
                }
            }
        }
    }

    // MARK: - 触发方式

    private func makeTriggerSettings() -> NSView {
        let auto = NSButton(checkboxWithTitle: "输入停顿后自动翻译", target: self, action: #selector(autoTranslateChanged(_:)))
        auto.state = settings.autoTranslate ? .on : .off
        let debounce = NSSlider(value: settings.debounceInterval, minValue: 0.3, maxValue: 3, target: self, action: #selector(debounceChanged(_:)))
        debounce.numberOfTickMarks = 0
        debounce.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let debounceLabel = EchoStyle.label(String(format: "%.1f 秒", settings.debounceInterval), size: 10.5, color: EchoStyle.textSecondary)
        debounce.identifier = NSUserInterfaceItemIdentifier("debounce-slider")
        debounceStack = (debounce, debounceLabel)
        let stack = NSStackView(views: [debounce, debounceLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        let autoCopy = NSButton(checkboxWithTitle: "翻译完成后自动复制到剪贴板", target: self, action: #selector(autoCopyChanged(_:)))
        autoCopy.state = settings.autoCopyTranslation ? .on : .off
        autoCopyCheckbox = autoCopy
        return form([
            row("自动翻译", detail: "关闭后仍可用快捷键 ⌃⌥T 手动触发", control: auto),
            row("自动复制", detail: "译文生成后立即写入剪贴板，直接粘贴即可", control: autoCopy),
            row("输入停顿阈值", detail: "停止打字多久后触发翻译", control: stack),
            row("手动翻译快捷键", detail: "在任意应用内立即翻译当前输入", control: EchoStyle.label("⌃⌥T", size: 12)),
            note("翻译只针对输入框最后一行（过长时截取最后一个句子片段），控制延迟与 API 成本。"),
        ])
    }

    @objc private func autoCopyChanged(_ sender: NSButton) {
        settings.autoCopyTranslation = sender.state == .on
    }

    private var debounceStack: (slider: NSSlider, label: NSTextField)?

    @objc private func autoTranslateChanged(_ sender: NSButton) {
        settings.autoTranslate = sender.state == .on
    }

    @objc private func debounceChanged(_ sender: NSSlider) {
        settings.debounceInterval = sender.doubleValue
        debounceStack?.label.stringValue = String(format: "%.1f 秒", sender.doubleValue)
    }

    // MARK: - 悬浮窗外观

    private func makeAppearanceSettings() -> NSView {
        let font = NSSlider(value: settings.panelFontSize, minValue: 11, maxValue: 28, target: self, action: #selector(fontSizeChanged(_:)))
        font.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let opacity = NSSlider(value: settings.backgroundOpacity, minValue: 0, maxValue: 1, target: self, action: #selector(opacityChanged(_:)))
        opacity.isContinuous = true
        opacity.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let edge = NSPopUpButton()
        edge.addItems(withTitles: ["输入框下方", "输入框上方"])
        edge.selectItem(at: settings.snapEdge.rawValue)
        edge.target = self
        edge.action = #selector(edgeChanged(_:))
        let spaces = NSButton(checkboxWithTitle: "在所有桌面空间显示", target: self, action: #selector(spacesChanged(_:)))
        spaces.state = settings.showsOnAllSpaces ? .on : .off
        let pin = NSButton(checkboxWithTitle: "悬浮窗常驻", target: self, action: #selector(pinPanelChanged(_:)))
        pin.state = settings.pinPanel ? .on : .off
        pinCheckbox = pin
        return form([
            row("译文字号", control: font),
            row("背景不透明度", detail: "最左为完全透明", control: opacity),
            row("默认贴边位置", detail: "空间不足时会自动翻转", control: edge),
            row("跨桌面显示", control: spaces),
            row("悬浮窗常驻", detail: "关闭后焦点离开输入框即隐藏", control: pin),
            note("悬浮窗可拖动；按 Esc 关闭；译文流式实时显示；点击复制只会复制英文译文。"),
        ])
    }

    @objc private func fontSizeChanged(_ sender: NSSlider) { settings.panelFontSize = sender.doubleValue }
    @objc private func opacityChanged(_ sender: NSSlider) { settings.backgroundOpacity = sender.doubleValue }
    @objc private func edgeChanged(_ sender: NSPopUpButton) { settings.snapEdge = SnapEdge(rawValue: sender.indexOfSelectedItem) ?? .below }
    @objc private func spacesChanged(_ sender: NSButton) { settings.showsOnAllSpaces = sender.state == .on }
    @objc private func pinPanelChanged(_ sender: NSButton) { settings.pinPanel = sender.state == .on }

    // MARK: - 数据与隐私

    private func makeDataSettings() -> NSView {
        let clearCache = EchoStyle.button("清除翻译缓存", target: self, action: #selector(clearCache))
        let reset = EchoStyle.button("恢复默认设置…", target: self, action: #selector(resetSettings))
        let countLabel = EchoStyle.label("当前缓存 \(TranslationCache.shared.count) 条", size: 11, color: EchoStyle.textTertiary)
        return form([
            row("翻译缓存", detail: "按原文与模型缓存，避免重复请求", control: clearCache),
            row("缓存条数", control: countLabel),
            row("恢复默认设置", control: reset),
            note("EchoType 需要辅助功能权限读取任意应用中的输入框内容，该内容仅用于生成翻译，只发送给你配置的翻译服务，不会经过任何其他服务器。API Key 以明文保存在 Application Support/EchoType/credentials.json，与缓存在同一文件夹，请勿分享。"),
        ])
    }

    @objc private func clearCache() {
        confirm(title: "清除翻译缓存？", message: "全部已缓存的翻译结果将被删除。") { TranslationCache.shared.clear() }
    }

    @objc private func resetSettings() {
        confirm(title: "恢复默认设置？", message: "触发方式与外观偏好将恢复默认值。") { self.settings.reset() }
    }

    private func confirm(title: String, message: String, action: @escaping () -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { action() } }
    }

    func windowWillClose(_ notification: Notification) {
        saveTranslationFields()
    }

    // MARK: - 表单构造（与 EchoSub 相同的行样式）

    private func form(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 412).isActive = true
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 9
        stack.layer?.borderWidth = 0.5
        stack.layer?.borderColor = EchoStyle.separator.cgColor
        stack.layer?.backgroundColor = EchoStyle.panelBackground.cgColor
        return stack
    }

    private func row(_ title: String, detail: String? = nil, control: NSView) -> NSView {
        let titleLabel = EchoStyle.label(title, size: 12.5, weight: .medium)
        var labels = [titleLabel]
        if let detail { labels.append(EchoStyle.label(detail, size: 10.5, color: EchoStyle.textTertiary, lines: 2)) }
        let labelStack = NSStackView(views: labels)
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2
        let spacer = NSView()
        let stack = NSStackView(views: [labelStack, spacer, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 412).isActive = true
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: detail == nil ? 42 : 52).isActive = true
        return stack
    }

    private func styleInput(_ field: NSTextField, width: CGFloat = 235) {
        field.controlSize = .regular
        field.font = .systemFont(ofSize: 12.5)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.72)
        field.textColor = EchoStyle.textPrimary
        field.focusRingType = .exterior
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        field.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func note(_ text: String) -> NSView {
        let label = EchoStyle.label(text, size: 10.5, color: EchoStyle.textTertiary, lines: 6)
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.widthAnchor.constraint(equalToConstant: 412),
        ])
        return container
    }
}
