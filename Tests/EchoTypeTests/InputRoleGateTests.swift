import Testing
@testable import EchoType

struct InputRoleGateTests {
    @Test func plainTextField() {
        #expect(InputRoleGate.isTextInput(role: "AXTextField", subrole: ""))
    }

    @Test func textArea() {
        #expect(InputRoleGate.isTextInput(role: "AXTextArea", subrole: ""))
    }

    @Test func comboBox() {
        #expect(InputRoleGate.isTextInput(role: "AXComboBox", subrole: ""))
    }

    @Test func textView() {
        #expect(InputRoleGate.isTextInput(role: "AXTextView", subrole: ""))
    }

    @Test func buttonIsNotTextInput() {
        #expect(!InputRoleGate.isTextInput(role: "AXButton", subrole: ""))
    }

    @Test func emptyRoleIsNotTextInput() {
        #expect(!InputRoleGate.isTextInput(role: "", subrole: ""))
    }

    @Test func searchFieldSubroleOnTextField() {
        #expect(InputRoleGate.isTextInput(role: "AXTextField", subrole: "AXSearchField"))
    }

    /// 文档化既有行为：子角色单独命中也能放行，不依赖角色白名单。
    @Test func searchFieldSubroleAlone() {
        #expect(InputRoleGate.isTextInput(role: "AXGroup", subrole: "AXSearchField"))
    }

    /// 核心回归保护：密码框（role=AXTextField + subrole=AXSecureTextField）必须被排除。
    @Test func secureTextFieldExcluded() {
        #expect(!InputRoleGate.isTextInput(role: "AXTextField", subrole: "AXSecureTextField"))
    }

    /// 安全子角色优先于角色白名单：即使 role 命中也一律排除。
    @Test func secureSubroleOverridesRoleWhitelist() {
        #expect(!InputRoleGate.isTextInput(role: "AXTextArea", subrole: "AXSecureTextField"))
    }
}
