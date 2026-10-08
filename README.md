# EchoType

EchoType 是一款原生 macOS 工具：悬浮窗贴在任意应用的输入框旁，把用户输入的中文实时翻译成英文，并提供一键复制（只复制英文译文）。

## 工作原理

- **感知输入**：通过辅助功能 API（AXUIElement）读取系统聚焦元素的角色、文本与坐标，判定"用户可以输入的地方"。
- **触发翻译**：只在输入框内容实际变化（输入/粘贴/删除）后启动，停顿 1.2 秒（可调）翻译最后一行；聚焦或阅读文档不会误弹。⌃⌥T 可手动立即翻译当前输入框内容（含已有文本）。
- **流式回显**：译文通过 SSE 流式接收，按固定节奏逐字揭示并显示流式光标；窗口大小保持稳定，长译文滚动显示。
- **紧凑工具栏**：复制英文仅保留顶部左侧图标，复制和生成状态也在顶部显示；底部不再保留按钮行，译文滚动区域延伸至底部。窄窗口中的长状态文字会省略，悬停可查看全文。
- **明暗自适应**：悬浮窗可见时约每 1.5 秒检测背后区域的平均亮度，亮背景使用深色文字、暗背景使用浅色文字，不需要悬停。检测异步进行，隐藏后停止；需要屏幕录制授权，采样图像不保存或发送（macOS 26+）。
- **AI 翻译**：OpenAI 兼容接口（`/chat/completions`），返回英文译文。
- **悬浮窗**：非激活式 `NSPanel`，贴在输入框下/上方，可拖动位置和拖拽边缘调整宽高。悬停边缘时在窗口内显示方向提示，移开后消失；悬停不会获取键盘焦点，指针可能仍是普通箭头。手动尺寸默认持久化，关闭重开和重启应用后恢复；输出长度不改变宽高。初始 400×180 点，最小 260×140 点，上限为当前屏幕可用区域。交互结束后继续在原输入框打字；Esc 关闭；复制按钮只写入英文。macOS 26 及以上使用 Liquid Glass（`NSGlassEffectView`）材质，更低版本回退为半透明圆角卡片。
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

**做法**：在 `SnapPanel`（NSPanel 子类）里用同名 `@objc` selector 覆盖 `_hasActiveAppearance`（及 `…IgnoringKeyFocus` 变体），玻璃路径下返回 `true`，其余路径转发给 `NSWindow` 的真实实现。这只是渲染提示，不改变窗口真实身份。面板显示时不激活应用；原生缩放允许临时持有 key，鼠标交互结束后归还，译文视图不接受键盘焦点。

**踩过的坑**（留存备忘）：

- 覆盖 `isKeyWindow` 返回 `true` 无效——材质管线不读它；
- `makeKey() → makeMain() → resignKey()` 能让窗口保留 main 身份获得液态渲染，但实现复杂且 main 身份会被本应用其他窗口的开关键走（状态/设置窗口），需要持续防守；
- KVC/`objc_msgSend` 写 `_setHasActiveAppearance:` 会被系统重新计算覆盖，存不住；
- 私有方法若在未来 macOS 被改名/移除，覆盖自然失效、回退磨砂，不会崩溃；
- `.clear` 风格、18 点圆角和 12% 黑色着色与 easydict-lite 对齐。玻璃材质使用固定调色；背景不透明度设置仅用于旧 macOS 的普通卡片。
- `BackdropSampler` 使用 ScreenCaptureKit 异步检测窗口背后的内容，排除 EchoType 自身，图像最长边仅 64 像素。`SnapPanel` 仅在面板可见时每 1.5 秒更新；移动/缩放后也刷新。关闭会取消任务，过期位置或旧显示周期的结果不会覆盖当前状态。
- 亮背景 → `aqua` 和深色文字，暗背景 → `darkAqua` 和浅色文字；保留复制成功、错误提示的专用颜色。40%/60% 的明暗切换阈值避免混合背景闪烁。检测失败保留最近颜色，未授权时沿用应用外观；定时检测不会主动请求权限。
- 流式回显：服务端 SSE chunk 粒度不可控，`ResultView` 用缓冲 + 固定节奏揭示实现稳定逐字回显。译文放在透明 `NSScrollView` 内，文本宽度跟随用户选择的窗口宽度换行，高度仅增加滚动内容；流式、完成和错误路径均不按内容缩放窗口。

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
