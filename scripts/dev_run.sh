#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.build/DerivedData"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug/SalaryDance.app"

xcodebuild \
  -project "$ROOT_DIR/SalaryDance.xcodeproj" \
  -scheme SalaryDance \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

# 关闭已运行的同 Bundle ID 实例，避免 open 只激活旧进程而不加载刚构建的新版本。
osascript -e 'tell application id "com.salarydance.app" to quit' >/dev/null 2>&1 || true
sleep 0.3

open "$APP_PATH"
