#!/bin/bash
# 构建 release APK 并安装到手机

set -e

APK="build/app/outputs/flutter-apk/app-prod-release.apk"

echo "正在构建 release APK..."
flutter build apk --release --flavor prod "$@"

echo "正在安装到设备..."
flutter install --flavor prod

echo "安装完成 ✓"
