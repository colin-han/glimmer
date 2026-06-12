#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

ADB="$HOME/Library/Android/sdk/platform-tools/adb"
APK="build/app/outputs/flutter-apk/app-prod-release.apk"

# ─── 解析当前版本号 ───────────────────────────────────────────
CURRENT=$(grep '^version:' pubspec.yaml | awk '{print $2}')
CURRENT_VER="${CURRENT%%+*}"   # 1.1.1
CURRENT_BUILD="${CURRENT##*+}" # 5

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VER"

# ─── 解析参数，计算新版本号 ─────────────────────────────────────
BUMP="${1:-patch}"

if [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  # 指定版本号格式 #.#.#
  NEW_VER="$BUMP"
  NEW_BUILD=$((CURRENT_BUILD + 1))
elif [[ "$BUMP" == "major" ]]; then
  NEW_VER="$((MAJOR + 1)).0.0"
  NEW_BUILD=$((CURRENT_BUILD + 1))
elif [[ "$BUMP" == "minor" ]]; then
  NEW_VER="$MAJOR.$((MINOR + 1)).0"
  NEW_BUILD=$((CURRENT_BUILD + 1))
elif [[ "$BUMP" == "patch" ]]; then
  NEW_VER="$MAJOR.$MINOR.$((PATCH + 1))"
  NEW_BUILD=$((CURRENT_BUILD + 1))
else
  echo "用法: $0 [major|minor|patch|<#.#.#>]"
  echo "  不带参数默认 patch"
  exit 1
fi

NEW_VERSION="${NEW_VER}+${NEW_BUILD}"
TAG="v${NEW_VER}"

echo "==> 版本变更: ${CURRENT} → ${NEW_VERSION}"
echo ""

# ─── 检查分支 ─────────────────────────────────────────────────
BRANCH=$(git branch --show-current)
if [[ "$BRANCH" != "main" ]]; then
  echo "❌ 仅支持在 main 分支上发布，当前分支: $BRANCH"
  exit 1
fi

# ─── 检查工作区是否干净 ─────────────────────────────────────────
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "❌ 工作区有未提交的变更，请先提交或暂存"
  git status --short
  exit 1
fi

# ─── 拉取最新代码 ─────────────────────────────────────────────
echo "==> 拉取最新代码..."
git pull --rebase origin "$(git branch --show-current)"
echo ""

# ─── 修改版本号 ───────────────────────────────────────────────
echo "==> 更新版本号..."
sed -i '' "s/^version: .*/version: ${NEW_VERSION}/" pubspec.yaml

# 同步 local.properties（Flutter build 会自动更新，但保持一致性）
sed -i '' "s/flutter.versionName=.*/flutter.versionName=${NEW_VER}/" android/local.properties
sed -i '' "s/flutter.versionCode=.*/flutter.versionCode=${NEW_BUILD}/" android/local.properties

# ─── 提交 + 打 tag ─────────────────────────────────────────────
echo "==> 提交版本变更..."
git add pubspec.yaml
git add -f android/local.properties
git commit -m "release: ${TAG}"
git tag "$TAG"
echo ""

# ─── 推送 ─────────────────────────────────────────────────────
echo "==> 推送提交和标签..."
git push origin "$(git branch --show-current)"
git push origin "$TAG"
echo ""

# ─── 清理并编译 ───────────────────────────────────────────────
echo "==> 清理构建缓存..."
flutter clean

echo "==> 编译 prod release APK..."
flutter build apk --flavor prod --release
echo ""

echo "==> 编译完成: $APK"
ls -lh "$APK"
echo ""

# ─── 安装到设备 ───────────────────────────────────────────────
echo "==> 安装到设备（保留数据）..."
"$ADB" install -r "$APK"
echo "==> ${TAG} 发布完成 ✓"
