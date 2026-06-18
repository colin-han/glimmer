#!/bin/bash
# 备份真机上指定版本 app 的数据目录到目标路径并打包为 tar.gz。
#
# 用法: ./scripts/backup.sh <version> <target_dir>
#   version    : main | w1 | w2 | ...（对应包名后缀）
#     main → info.colinhan.glimmer              （prod）
#     其他 → info.colinhan.glimmer.dev.<version>（dev worktree）
#   target_dir : 备份归档的存放目录（不存在则创建）
#
# 实现：通过 `adb exec-out run-as <pkg> tar` 流式拉取 app 私有数据目录
#   /data/data/<pkg>/ 的全部内容，并排除临时缓存与可由重装重建的 Flutter 资源：
#     ./cache                        — 系统临时缓存
#     ./code_cache                   — 代码缓存
#     ./app_flutter/flutter_assets   — Flutter 框架资源（图标/字体/kernel_blob，重装即有）
#   如需完整备份（含上述目录），删除下方对应的 --exclude 行即可。
#
# 要求目标 app 为 debuggable——run-as 仅对可调试 app 生效：
#   - dev flavor（run_dev.sh 装的）：默认 debug 构建，可调试 ✓
#   - prod flavor：run_prod.sh 装的是 debug 构建，可调试 ✓；
#     install.sh 装的是 release APK，非可调试 ✗
#
# 安全：脚本只读，不会修改或删除设备上的任何数据。

set -euo pipefail

# ---- 用法 ----
usage() {
  cat >&2 <<EOF
用法: $0 <version> <target_dir>
  version    : main | w1 | w2 | ...（对应包名后缀）
  target_dir : 备份归档的存放目录
EOF
}

if [ $# -ne 2 ]; then
  usage
  exit 1
fi

VERSION="$1"
TARGET_DIR="$2"

# ---- 版本 → 包名 ----
if [ "$VERSION" = "main" ]; then
  PKG="info.colinhan.glimmer"
else
  PKG="info.colinhan.glimmer.dev.${VERSION}"
fi

# ---- 发现 adb（PATH 优先，回退到 Android Studio 默认安装位置）----
ADB=""
if command -v adb >/dev/null 2>&1; then
  ADB="adb"
elif [ -x "${HOME}/Library/Android/sdk/platform-tools/adb" ]; then
  ADB="${HOME}/Library/Android/sdk/platform-tools/adb"
else
  echo "✗ 未找到 adb，请确认 Android platform-tools 已安装并加入 PATH。" >&2
  exit 1
fi

# ---- 前置检查：已连接设备 ----
if ! "$ADB" get-state >/dev/null 2>&1; then
  echo "✗ 未检测到 adb 设备，请连接真机并开启 USB 调试。" >&2
  exit 1
fi

# ---- 前置检查：目标包已安装 ----
# pm path 输出包的 APK 路径（已装）或空行（未装），用输出是否为空判断更可靠。
if [ -z "$("$ADB" shell pm path "$PKG" 2>/dev/null | tr -d '\r')" ]; then
  echo "✗ 设备上未安装包: $PKG（version=${VERSION}）" >&2
  echo "  设备上已安装的 glimmer 包：" >&2
  "$ADB" shell pm list packages 2>/dev/null | tr -d '\r' | grep 'info.colinhan.glimmer' | sed 's/^/    /' >&2 || true
  exit 1
fi

# ---- 前置检查：run-as 可用（app 必须 debuggable）----
# run-as 成功时 `id` 输出形如 `uid=10xxx(...)`；非 debuggable 时输出错误信息。
if ! "$ADB" shell run-as "$PKG" id 2>&1 | tr -d '\r' | grep -q '^uid='; then
  echo "✗ 无法 run-as $PKG：app 非 debuggable。" >&2
  echo "  run-as 仅对可调试 app 生效。可选：" >&2
  echo "    1) 用 ./scripts/run_prod.sh 安装 prod 的 debug 版本（debuggable）后再备份" >&2
  echo "    2) 在已 root 的设备上直接访问 /data/data/${PKG}" >&2
  exit 1
fi

# ---- 目标目录与归档名 ----
mkdir -p "$TARGET_DIR"
TS=$(date +%Y%m%d_%H%M%S)
OUT="$TARGET_DIR/glimmer-${VERSION}-${TS}.tar.gz"

# stderr 临时文件，结束时清理。
ERR_FILE=$(mktemp)
trap 'rm -f "$ERR_FILE"' EXIT

# ---- 流式备份 ----
# adb exec-out 二进制安全流式输出 gzip；-C 切到 app 数据目录后打包全部（.），
# --exclude 跳过临时缓存与 Flutter 框架资源。中途 adb 断连会致归档截断，故完成后校验完整性。
echo "==> 备份 $PKG → $OUT"
echo "    （排除 ./cache ./code_cache ./app_flutter/flutter_assets）"

set +e
"$ADB" exec-out run-as "$PKG" tar -czf - \
  -C "/data/data/${PKG}" \
  --exclude='./cache' \
  --exclude='./code_cache' \
  --exclude='./app_flutter/flutter_assets' \
  . >"$OUT" 2>"$ERR_FILE"
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
  echo "✗ 备份命令失败（退出码 $RC）。" >&2
  tr -d '\r' < "$ERR_FILE" | head -10 >&2
  rm -f "$OUT"
  exit 1
fi

# ---- 完整性校验：gzip 未截断 ----
if ! gzip -t "$OUT" 2>/dev/null; then
  echo "✗ 归档损坏（可能 adb 中途断连），已删除: $OUT" >&2
  rm -f "$OUT"
  exit 1
fi

SIZE=$(ls -lh "$OUT" | awk '{print $5}')
ENTRIES=$(tar -tzf "$OUT" 2>/dev/null | wc -l | tr -d ' ')
echo "✓ 备份完成: $OUT"
echo "    大小: $SIZE / 条目: $ENTRIES"
