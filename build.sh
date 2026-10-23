#!/bin/bash
# 构建 DeepSeek 账单.app（macOS 13+ / arm64）
set -euo pipefail
cd "$(dirname "$0")"

# 优先用本机可用的 13.x SDK；找不到就退回当前命令行工具 SDK
SDK="${SDK_PATH:-}"
if [ -z "$SDK" ]; then
  for candidate in \
    /Library/Developer/CommandLineTools/SDKs/MacOSX13.1.sdk \
    "$(xcrun --show-sdk-path 2>/dev/null || true)"; do
    if [ -n "${candidate:-}" ] && [ -d "$candidate" ]; then
      SDK="$candidate"
      break
    fi
  done
fi
if [ -z "$SDK" ]; then
  echo "找不到 macOS SDK，请安装 Xcode Command Line Tools：xcode-select --install" >&2
  exit 1
fi

mkdir -p .modulecache
export CLANG_MODULE_CACHE_PATH="$PWD/.modulecache"
export SWIFT_MODULE_CACHE_PATH="$PWD/.modulecache"

swiftc -sdk "$SDK" -module-cache-path "$PWD/.modulecache" \
  -Xcc -fmodules-cache-path="$PWD/.modulecache" \
  -O -target arm64-apple-macos13.0 \
  -o DeepSeekBill \
  main.swift Config.swift API.swift Model.swift Views.swift AppDelegate.swift \
  -framework AppKit -framework SwiftUI -framework Combine -framework QuartzCore

rm -rf DeepSeekBill.app
mkdir -p DeepSeekBill.app/Contents/MacOS
cp DeepSeekBill DeepSeekBill.app/Contents/MacOS/
cp Info.plist DeepSeekBill.app/Contents/Info.plist
codesign --force -s - DeepSeekBill.app

echo "构建完成：$PWD/DeepSeekBill.app"
