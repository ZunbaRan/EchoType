import AppKit

enum EchoStyle {
    static let accent = NSColor.systemBlue
    static let windowBackground = NSColor(calibratedWhite: 0.135, alpha: 1)
    static let sidebarBackground = NSColor(calibratedWhite: 0.08, alpha: 0.62)
    static let panelBackground = NSColor(calibratedWhite: 1, alpha: 0.035)
    static let cardBackground = NSColor(calibratedWhite: 0.11, alpha: 1)
    static let separator = NSColor(calibratedWhite: 1, alpha: 0.08)
    static let textPrimary = NSColor(calibratedWhite: 1, alpha: 0.92)
    static let textSecondary = NSColor(calibratedWhite: 1, alpha: 0.56)
    static let textTertiary = NSColor(calibratedWhite: 1, alpha: 0.34)

    static func label(
        _ text: String = "",
        size: CGFloat = 13,
        weight: NSFont.Weight = .regular,
        color: NSColor = textPrimary,
        lines: Int = 1
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.maximumNumberOfLines = lines
        field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        if lines != 1 {
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.cell?.usesSingleLineMode = false
        }
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    static func selectableLabel(_ text: String = "", size: CGFloat = 13, color: NSColor = textPrimary) -> NSTextField {
        let field = label(text, size: size, color: color)
        field.isSelectable = true
        field.isEditable = false
        return field
    }

    static func button(
        _ title: String = "",
        symbol: String? = nil,
        target: AnyObject? = nil,
        action: Selector? = nil,
        primary: Bool = false
    ) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = primary ? .rounded : .recessed
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: primary ? .semibold : .medium)
        if let symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) }
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.translatesAutoresizingMaskIntoConstraints = false
        if primary { button.keyEquivalent = "\r" }
        return button
    }

    static func iconButton(_ symbol: String, help: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = button("", symbol: symbol, target: target, action: action)
        button.toolTip = help
        button.isBordered = false
        button.contentTintColor = textSecondary
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }
}

extension NSView {
    func pinEdges(to other: NSView, insets: NSEdgeInsets = .init()) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
        ])
    }

    func removeAllSubviews() {
        subviews.forEach { $0.removeFromSuperview() }
    }
}
