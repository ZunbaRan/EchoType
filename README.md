# EchoType

EchoType 是一款原生 macOS 工具：悬浮窗贴在任意应用的输入框旁，把用户输入的中文实时翻译成英文，并提供词/短语释义与一键复制（只复制英文译文）。

## 工作原理

- **感知输入**：通过辅助功能 API（AXUIElement）读取系统聚焦元素的角色、文本与坐标，判定"用户可以输入的地方"。
- **触发翻译**：输入停顿（默认 1.2 秒，可在设置中调节）后自动翻译最后一行；也可用全局快捷键 ⌃⌥T 立即触发。
- **AI 翻译**：OpenAI 兼容接口（`/chat/completions`），返回英文译文 + 最多 2 个备选译法 + 词/短语级释义（音标、中文释义、英文例句）。
- **悬浮窗**：非激活式 `NSPanel`，贴在输入框下/上方，可拖动，不夺走输入焦点；Esc 关闭；复制按钮只写入英文。
- **缓存**：按"原文 + 模型"哈希缓存翻译结果，避免重复请求。

## 构建

需要 macOS 13+ 与 Swift 6 工具链。

```bash
cd EchoType
swift build
swift run EchoType        # 直接运行（首次需在 系统设置 → 隐私与安全性 → 辅助功能 中授权）
Scripts/package-app.sh release
open dist/EchoType.app
```

## 首次启动

1. 应用会引导开启「辅助功能」权限（读取其他应用输入框所必需）。
2. 在 设置 → 翻译服务 中填写 API Base URL、模型名称与 API Key。

## 本地数据

```
~/Library/Application Support/EchoType/
├── credentials.json          # API Key（明文，权限 600，勿提交/分享）
└── translation-cache.json    # 翻译缓存
```

## 隐私

输入框文本仅发送给你配置的翻译服务；除此外不经过任何服务器，无遥测。
