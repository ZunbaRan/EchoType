import Testing
@testable import EchoType

struct ThinkingModePolicyTests {
    @Test func supportsExplicitThinking() {
        #expect(ThinkingModePolicy.supportsExplicitThinking(model: "qwen3.7-plus"))
        #expect(ThinkingModePolicy.supportsExplicitThinking(model: "qwen-3-max"))
        #expect(ThinkingModePolicy.supportsExplicitThinking(model: "deepseek-v3"))
        #expect(ThinkingModePolicy.supportsExplicitThinking(model: "DeepSeek-R1"))
        #expect(!ThinkingModePolicy.supportsExplicitThinking(model: "qwen-plus"))
        #expect(!ThinkingModePolicy.supportsExplicitThinking(model: "gpt-4o"))
    }

    @Test func applyThinkingModeAddsFlagForSupportedModel() {
        var payload: [String: Any] = ["model": "qwen3.7-plus"]
        ThinkingModePolicy.applyThinkingMode(to: &payload, model: "qwen3.7-plus")
        #expect(payload["enable_thinking"] as? Bool == false)
    }

    @Test func applyThinkingModeLeavesPayloadUntouchedForUnsupportedModel() {
        var payload: [String: Any] = ["model": "gpt-4o", "temperature": 0.3]
        let keysBefore = Set(payload.keys)
        ThinkingModePolicy.applyThinkingMode(to: &payload, model: "gpt-4o")
        #expect(Set(payload.keys) == keysBefore)
    }
}
