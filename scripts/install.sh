#!/bin/bash
# 安装 prod release APK 到已连接的设备（保留数据）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

ADB="$HOME/Library/Android/sdk/platform-tools/adb"
APK="build/app/outputs/flutter-apk/app-prod-release.apk"

if [ ! -f "$APK" ]; then
  echo "❌ 未找到 APK: $APK，请先执行 build.sh"
  exit 1
fi

echo "==> 安装到设备（保留数据）..."
"$ADB" install -r "$APK"
echo "==> 安装完成 ✓"
