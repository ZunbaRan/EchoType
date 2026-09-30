#!/bin/bash
# 运行单元测试。
#
# 未安装 Xcode 时（xcode-select 指向 CommandLineTools），SwiftPM 不会自动解析
# swift-testing 所需的宏插件，裸 `swift test` 会报：
#   external macro implementation type 'TestingMacros.ExpectMacro' could not be found
# 这里按当前 developer 目录推导 libTestingMacros.dylib 并显式加载；
# 装有 Xcode 的机器上 SwiftPM 能自行解析，直接走裸 swift test。
#
# 注意：不使用 `set -u`——macOS 自带的 bash 3.2 在 `set -u` 下展开空的 "$@" 会报错。
set -eo pipefail
cd "$(dirname "$0")/.."

DEVELOPER_DIR="$(xcode-select -p)"
TESTING_MACROS="$DEVELOPER_DIR/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

if [[ "$DEVELOPER_DIR" == *CommandLineTools* && -f "$TESTING_MACROS" ]]; then
    exec swift test -Xswiftc -load-plugin-library -Xswiftc "$TESTING_MACROS" "$@"
fi

exec swift test "$@"
