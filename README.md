# EchoType

EchoType 是一款原生 macOS 工具：悬浮窗贴在任意应用的输入框旁，把用户输入的中文实时翻译成英文，并提供一键复制（只复制英文译文）。

## 工作原理

- **感知输入**：通过辅助功能 API（AXUIElement）读取系统聚焦元素的角色、文本与坐标，判定"用户可以输入的地方"。
- **触发翻译**：输入停顿（默认 1.2 秒，可在设置中调节）后自动翻译最后一行；也可用全局快捷键 ⌃⌥T 立即触发。
- **AI 翻译**：OpenAI 兼容接口（`/chat/completions`），返回英文译文。
- **悬浮窗**：非激活式 `NSPanel`，贴在输入框下/上方，可拖动，不夺走输入焦点；Esc 关闭；复制按钮只写入英文。macOS 26 及以上使用 Liquid Glass（`NSGlassEffectView`）材质，更低版本回退为半透明圆角卡片。
- **缓存**：按"原文 + 模型"哈希缓存翻译结果，避免重复请求。

## 构建

需要 macOS 13+ 与 Swift 6 工具链。

```bash
cd EchoType
swift build
Scripts/run-tests.sh      # 单元测试（纯逻辑：角色判定、分段、坐标换算、贴边定位、流式解析、缓存 key）
swift run EchoType        # 直接运行（首次需在 系统设置 → 隐私与安全性 → 辅助功能 中授权）
Scripts/package-app.sh release
open dist/EchoType.app
```

未安装 Xcode 时（仅有 Command Line Tools），裸 `swift test` 会因 swift-testing 宏插件未被解析而失败，用 `Scripts/run-tests.sh` 即可；装有 Xcode 的机器两种方式都行。

## Liquid Glass 实现笔记（macOS 26+ 悬浮窗）

`NSGlassEffectView` 没有公开的「强制活跃渲染」开关（不像 `NSVisualEffectView.state`）。实测发现：液态/磨砂渲染跟随窗口的**私有查询 `_hasActiveAppearance`**，而不是公开的 `isKeyWindow` / `isMainWindow`。悬浮窗是非激活面板，天然没有活跃身份，默认会被系统降级为磨砂。

**做法**：在 `SnapPanel`（NSPanel 子类）里用同名 `@objc` selector 覆盖 `_hasActiveAppearance`（及 `…IgnoringKeyFocus` 变体），玻璃路径下返回 `true`，其余路径转发给 `NSWindow` 的真实实现。这只是渲染提示，不改变窗口真实身份，因此键盘输入仍属于前台应用；面板同时设置 `canBecomeKey = false`，从结构上杜绝抢焦点（按钮点击、拖拽不受影响，Esc 由全局键盘监听兜底）。

**踩过的坑**（留存备忘）：

- 覆盖 `isKeyWindow` 返回 `true` 无效——材质管线不读它；
- `makeKey() → makeMain() → resignKey()` 能让窗口保留 main 身份获得液态渲染，但实现复杂且 main 身份会被本应用其他窗口的开关键走（状态/设置窗口），需要持续防守；
- KVC/`objc_msgSend` 写 `_setHasActiveAppearance:` 会被系统重新计算覆盖，存不住；
- 私有方法若在未来 macOS 被改名/移除，覆盖自然失效、回退磨砂，不会崩溃；
- `.clear` 风格透射最强；全局 `darkAqua` + 深色 `tintColor` 会把白底压成死灰——面板单独用 `aqua` 外观、文字用语义色（`labelColor`）、着色用低透明度白色雾化。

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

输入框文本仅发送给你配置的翻译服务；除此外不经过任何服务器，无遥测。密码等安全输入框（AXSecureTextField）被显式排除，不会被读取或翻译。
