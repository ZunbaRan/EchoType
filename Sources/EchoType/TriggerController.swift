import Foundation
import Carbon.HIToolbox

/// 触发策略：文本变化后防抖等待，静默期结束才发起 AI 翻译；
/// 手动快捷键（⌃⌥T）可跳过防抖立即触发。
final class TriggerController {
    var onTranslate: ((String, FieldContext) -> Void)?

    private var pending: DispatchWorkItem?

    func textChanged(_ field: FieldContext) {
        guard AppSettings.shared.autoTranslate,
              let segment = translatableSegment(of: field) else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onTranslate?(segment, field)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + AppSettings.shared.debounceInterval, execute: item)
    }

    func triggerNow(_ field: FieldContext) {
        pending?.cancel()
        guard let segment = translatableSegment(of: field) else { return }
        onTranslate?(segment, field)
    }

    func cancel() {
        pending?.cancel()
    }

    private func translatableSegment(of field: FieldContext) -> String? {
        guard field.containsCJK,
              let segment = field.lastInputSegment,
              !segment.isEmpty else { return nil }
        return segment
    }
}

/// 全局快捷键（⌃⌥T）：在任意应用内立即翻译当前输入框内容。
enum GlobalHotKey {
    static var handler: (() -> Void)?

    private static var hotKeyRef: EventHotKeyRef?
    private static var installed = false

    static func register() {
        guard !installed else { return }
        installed = true
        let hotKeyID = EventHotKeyID(signature: OSType(0x45544B59) /* "ETKY" */, id: 1)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        hotKeyRef = ref

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async { GlobalHotKey.handler?() }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }
}
