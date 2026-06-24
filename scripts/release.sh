#!/bin/bash
# 发布流程：更新版本号 → 构建 → 归档到 releases/ → 安装
# 用法: ./scripts/release.sh [major|minor|patch|<#.#.#>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

bash "$SCRIPT_DIR/update_version.sh" "$@"
bash "$SCRIPT_DIR/build.sh"

# ─── 归档 release APK 到 releases/（带版本号，已加入 .gitignore 不入库） ───
APK="build/app/outputs/flutter-apk/app-prod-release.apk"
# 读取 pubspec.yaml 中已更新的版本号（update_version.sh 已写入），去 build 号
VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
VERSION_VER="${VERSION%%+*}"
RELEASES_DIR="releases"
ARCHIVE="$RELEASES_DIR/glimmer-v${VERSION_VER}.apk"

mkdir -p "$RELEASES_DIR"
cp "$APK" "$ARCHIVE"
echo ""
echo "==> 已归档到 $ARCHIVE"
ls -lh "$ARCHIVE"

# 安装在归档之后：即便没有连接设备导致安装失败，APK 也已保存到 releases/
bash "$SCRIPT_DIR/install.sh"

echo ""
echo "==> 发布完成 ✓"
