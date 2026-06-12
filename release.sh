#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

ADB="$HOME/Library/Android/sdk/platform-tools/adb"
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
APK="build/app/outputs/flutter-apk/app-prod-release.apk"

echo "==> 准备发布 v${VERSION%%+*} (build ${VERSION##*+})"
echo ""

# 清理并编译
echo "==> 清理构建缓存..."
flutter clean

echo "==> 编译 prod release APK..."
flutter build apk --flavor prod --release "$@"
echo ""

echo "==> 编译完成: $APK"
ls -lh "$APK"
echo ""

# 安装到设备
echo "==> 安装到设备（保留数据）..."
"$ADB" install -r "$APK"
echo "==> 安装完成 ✓"
