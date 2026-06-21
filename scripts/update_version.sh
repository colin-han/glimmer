#!/bin/bash
# 计算并更新版本号：写入 pubspec.yaml、提交、打 tag、推送
# 用法: ./scripts/update_version.sh [--skip-version] [major|minor|patch|<#.#.#>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# ─── 解析参数 ──────────────────────────────────────────────────
SKIP_VERSION=false
BUMP="patch"

for arg in "$@"; do
  case "$arg" in
    --skip-version) SKIP_VERSION=true ;;
    major|minor|patch) BUMP="$arg" ;;
    [0-9]*.[0-9]*.[0-9]*) BUMP="$arg" ;;
    *)
      echo "未知参数: $arg"
      echo "用法: $0 [--skip-version] [major|minor|patch|<#.#.#>]"
      exit 1
      ;;
  esac
done

# ─── 解析当前版本号 ───────────────────────────────────────────
CURRENT=$(grep '^version:' pubspec.yaml | awk '{print $2}')
CURRENT_VER="${CURRENT%%+*}"   # 1.1.1
CURRENT_BUILD="${CURRENT##*+}" # 5

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VER"

# ─── 检查自当前版本 tag 以来是否有新的提交 ───────────────────────
CURRENT_TAG="v${CURRENT_VER}"
if git rev-parse --verify --quiet "$CURRENT_TAG" >/dev/null; then
  COMMITS=$(git rev-list --count "$CURRENT_TAG"..HEAD)
  if [[ "$COMMITS" -eq 0 ]]; then
    echo "⚠️  自 ${CURRENT_TAG} 以来没有任何新的 git 提交，代码未发生变化。"
    echo ""
    read -r -p "是否跳过版本更新及后续 tag/推送流程？[Y/n] " response
    if [[ "$response" =~ ^[Nn]$ ]]; then
      echo "==> 继续执行版本更新流程"
      echo ""
    else
      echo "==> 已跳过版本更新（未做任何改动）"
      exit 0
    fi
  fi
else
  echo "⚠️  未找到当前版本 tag ${CURRENT_TAG}，跳过提交检查"
fi

if [[ "$SKIP_VERSION" == false ]]; then
  # ─── 计算新版本号 ─────────────────────────────────────────────
  if [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
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

  # ─── 提交 + 打 tag ─────────────────────────────────────────────
  echo "==> 提交版本变更..."
  git add pubspec.yaml
  git commit -m "release: ${TAG}"
  git tag "$TAG"
  echo ""

  # ─── 推送 ─────────────────────────────────────────────────────
  echo "==> 推送提交和标签..."
  git push origin "$(git branch --show-current)"
  git push origin "$TAG"
  echo ""
else
  echo "==> 跳过版本变更 (--skip-version)"
  TAG="v${CURRENT_VER}"
  echo ""
fi

echo "==> ${TAG} 版本已更新"
