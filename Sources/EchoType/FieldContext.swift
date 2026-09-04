import AppKit
import ApplicationServices

/// 对系统当前聚焦 UI 元素的只读快照。
struct FieldContext {
    let element: AXUIElement
    let role: String
    let subrole: String
    let value: String
    /// AX 返回的坐标为屏幕左上原点；cocoaFrame 转为 AppKit 左下原点。
    let frameTopLeft: CGRect
    let appName: String

    private static let inputRoles: Set<String> = [
        kAXTextFieldRole,     // "AXTextField"
        kAXTextAreaRole,      // "AXTextArea"
        kAXComboBoxRole,      // "AXComboBox"
        "AXTextView",
    ]

    var isTextInput: Bool {
        if Self.inputRoles.contains(role) { return true }
        if subrole == kAXSearchFieldSubrole { return true }
        return false
    }

    var cocoaFrame: CGRect {
        let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? frameTopLeft.maxY
        return NSRect(
            x: frameTopLeft.minX,
            y: maxY - frameTopLeft.maxY,
            width: frameTopLeft.width,
            height: frameTopLeft.height
        )
    }

    /// 是否包含中文字符（基本区 + 扩展 A 区）。
    var containsCJK: Bool {
        value.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
    }

    /// 取最后一行输入；若该行过长则只取最后一个句子片段，控制翻译成本与延迟。
    var lastInputSegment: String? {
        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard var line = lines.last, !line.isEmpty else { return nil }
        if line.count > 160 {
            let sentenceSeparators: Set<Character> = ["。", "！", "？", "；", "，", ".", "!", "?", ";", ","]
            if let index = line.lastIndex(where: { sentenceSeparators.contains($0) }),
               index < line.endIndex {
                let tail = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
                if !tail.isEmpty { line = String(tail) }
            }
        }
        return line
    }

    init?(element: AXUIElement, appName: String) {
        self.element = element
        self.appName = appName
        role = Self.stringAttribute(element, kAXRoleAttribute) ?? ""
        subrole = Self.stringAttribute(element, kAXSubroleAttribute) ?? ""
        value = Self.stringAttribute(element, kAXValueAttribute) ?? ""
        frameTopLeft = Self.frame(of: element) ?? .zero
        if role.isEmpty { return nil }
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var raw: CFTypeRef?
        // 注意：本 SDK 导入的 AXUIElementCopyAttributeValue 为 3 参数（无 CFError 出参）。
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success,
              let value = raw as? String else { return nil }
        return value
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = axValue(element, kAXPositionAttribute),
              let size = axValue(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero
        var cgSize = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(size, .cgSize, &cgSize) else { return nil }
        return CGRect(origin: point, size: cgSize)
    }

    private static func axValue(_ element: AXUIElement, _ name: String) -> AXValue? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success,
              let value = raw else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }
}
