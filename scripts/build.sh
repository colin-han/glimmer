#!/bin/bash
# 清理并构建 prod release APK

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

APK="build/app/outputs/flutter-apk/app-prod-release.apk"

echo "==> 清理构建缓存..."
flutter clean

echo "==> 编译 prod release APK..."
flutter build apk --flavor prod --release "$@"
echo ""

echo "==> 编译完成: $APK"
ls -lh "$APK"
