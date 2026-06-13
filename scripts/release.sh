#!/bin/bash
# 发布流程：更新版本号 → 构建 → 安装
# 用法: ./scripts/release.sh [major|minor|patch|<#.#.#>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/update_version.sh" "$@"
bash "$SCRIPT_DIR/build.sh"
bash "$SCRIPT_DIR/install.sh"

echo ""
echo "==> 发布完成 ✓"
