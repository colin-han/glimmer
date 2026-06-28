#!/bin/bash
# 清理并构建 prod release APK
# 用法: ./scripts/build.sh [--skip-env-check] [其余 flutter build 参数]
#   --skip-env-check  跳过环境变量检查（release 脚本已统一检查时使用）
#
# 编译前校验 .env.local 中必需环境变量的完整性（见 check_env.sh），
# 缺失或为空则中止编译。新增环境变量时，需同步更新 check_env.sh 的
# REQUIRED_ENV_VARS 与 CLAUDE.md「环境变量」清单（保持两处一致）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# ─── 解析参数 ──────────────────────────────────────────────────
SKIP_ENV_CHECK=false
BUILD_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --skip-env-check) SKIP_ENV_CHECK=true ;;
    *) BUILD_ARGS+=("$arg") ;;
  esac
done

# ─── 环境变量检查 ─────────────────────────────────────────────
if [[ "$SKIP_ENV_CHECK" == false ]]; then
  bash "$SCRIPT_DIR/check_env.sh"
else
  echo "==> 跳过环境变量检查 (--skip-env-check)"
  echo ""
fi

APK="build/app/outputs/flutter-apk/app-prod-release.apk"

# 走本机 Clash 代理：flutter clean 后 sqlite3 包需从 GitHub 下载预编译原生库，
# 直连 github.com 经常超时，导致构建在 compileFlutterBuild 阶段失败。
export HTTP_PROXY="http://127.0.0.1:7890"
export HTTPS_PROXY="http://127.0.0.1:7890"

echo "==> 清理构建缓存..."
flutter clean

echo "==> 编译 prod release APK..."
# release buildType 开启了 isDebuggable=true（见 android/app/build.gradle.kts，
# 为支持 scripts/backup.sh 的 run-as 备份 prod 数据）。Flutter 的 gradle plugin
# 用 buildModeFor() 判断构建模式时只看 isDebuggable 标志、不看 buildType 名字
# （FlutterPluginUtils.kt: isDebuggable → "debug"），于是把 release 产出的 APK
# 错误重命名为 app-prod-debug.apk，导致 flutter-apk/app-prod-release.apk 缺失、
# flutter build 以非零退出码报 "failed to produce an .apk file"。
# 这是 Flutter 对 release+debuggable 的既定行为（master 仍未改，issue #54126
# 追踪至今 open），不会随版本修复，故此处不依赖 set -e 立即失败，改为构建后
# 从 gradle 真实输出路径 outputs/apk/prod/release/ 补齐正确命名的 APK。
set +e
flutter build apk --flavor prod --release "${BUILD_ARGS[@]}"
build_rc=$?
set -e
echo ""

# flutter-apk/ 下没有正确命名的 release APK 时，从 gradle 实际输出路径补齐，
# 确保后续 install.sh 可用（Flutter 会把该 APK 错命名成 app-prod-debug.apk）。
if [ ! -f "$APK" ]; then
  GRADLE_APK="build/app/outputs/apk/prod/release/app-prod-release.apk"
  if [ -f "$GRADLE_APK" ]; then
    echo "==> 从 gradle 输出路径补齐 release APK: $GRADLE_APK"
    cp "$GRADLE_APK" "$APK"
  fi
fi

if [ ! -f "$APK" ]; then
  echo "✗ 构建失败：未找到 $APK（flutter build 退出码 $build_rc）" >&2
  exit 1
fi

echo "==> 编译完成: $APK"
ls -lh "$APK"
