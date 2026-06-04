#!/bin/bash
# 构建 release APK 并安装到手机

set -e

ADB="$HOME/Library/Android/sdk/platform-tools/adb"

echo "正在构建 release APK..."
flutter build apk --release --flavor prod "$@"

echo "正在安装到设备（保留数据）..."
"$ADB" install -r build/app/outputs/flutter-apk/app-prod-release.apk

echo "安装完成 ✓"
