#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
APK="build/app/outputs/flutter-apk/app-prod-release.apk"

echo "==> 准备发布 v${VERSION%%+*} (build ${VERSION##*+})"
echo ""

# 编译
echo "==> 编译 prod release APK..."
flutter build apk --flavor prod --release

echo ""
echo "==> 编译完成: $APK"
ls -lh "$APK"
echo ""

# 确认安装
read -rp "是否安装到已连接的设备？[y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "==> 安装到设备..."
    flutter install --flavor prod
    echo "==> 安装完成"
else
    echo "已跳过安装"
fi
