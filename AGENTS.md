# EchoType 维护速查

## 常用命令

- **构建**：`swift build`
- **测试**：`Scripts/run-tests.sh`
- **运行**：`swift run EchoType`（首次需在 系统设置 → 隐私与安全性 → 辅助功能 中授权）
- **打包**：`Scripts/package-app.sh release` → `dist/EchoType.app`

## 测试环境注意

- 在 CLT-only 环境（未安装 Xcode）下，裸 `swift test` 会因 `TestingMacros` 宏插件未被 SwiftPM 解析而失败，请走 `Scripts/run-tests.sh`（脚本按 xcode-select 动态推导插件路径）；装有 Xcode 的机器两种方式都行。
- CLT 不提供 `XCTest.framework`，测试框架只能用 swift-testing（`import Testing` / `@Test` / `#expect`）。

## 测试范围约定

测试只覆盖纯逻辑：`InputRoleGate` / `InputSegmenter` / `ScreenCoordinates` / `SnapPositionSolver` / `StreamingJSONExtractor` / `ThinkingModePolicy` / `TranslationCache.cacheKey`。**不要在测试里碰 `TranslationCache.shared`**——它会读写真实的 `~/Library/Application Support/EchoType/`。

## Liquid Glass 构建注意

- macOS 按二进制 `LC_BUILD_VERSION` 的 **sdk 字段**门控 `NSGlassEffectView` 的实际渲染：sdk 写成 13.0 时玻璃被静默降级为普通视图（类仍存在，弱链接，无崩溃——只是没有玻璃效果）。
- 裸 `swift build` 产物的 sdk 字段可能被写成部署目标 13.0（debug 必现，release 视构建缓存而定），所以**开发构建不保证有玻璃效果**；`Scripts/package-app.sh` 已显式传 `-platform_version macos 13.0 <真实SDK版本>`（SDK 版本由 `xcrun --show-sdk-version` 动态获取），要验证玻璃效果必须走打包脚本，并用 `otool -l <二进制> | grep -A5 LC_BUILD_VERSION` 确认 `sdk` 字段 ≥ 26.0。

## 运行前提

- 需要「辅助功能」权限，否则读不到其他应用的输入框。
- `Scripts/package-app.sh` 用固定 designated requirement 做 ad-hoc 签名，目的是让 TCC 授权在重新构建后依然有效；**改签名逻辑时务必保留这一点**。
