#!/bin/bash
# 清理并构建 prod release APK
#
# 编译前校验 .env.local 中必需环境变量的完整性（见 check_required_env），
# 缺失或为空则中止编译。新增环境变量时，需同步更新 REQUIRED_ENV_VARS
# 与 CLAUDE.md「环境变量」清单（保持两处一致）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# prod release 必需的环境变量。
# WORKTREE 仅 dev flavor 使用、QWEATHER_HOST 有默认值，故不列入。
REQUIRED_ENV_VARS=(
  VOLCENGINE_SPEECH_APPID
  VOLCENGINE_SPEECH_TOKEN
  VOLCENGINE_SPEECH_API_KEY
  VOLCENGINE_ARK_ENDPOINT_ID
  VOLCENGINE_ARK_API_KEY
  VOLCENGINE_ACCESS_KEY
  VOLCENGINE_SECRET_KEY
  VOLCENGINE_TOS_ENDPOINT
  VOLCENGINE_TOS_BUCKET
  QWEATHER_TOKEN
)

# 校验给定 env 文件中必需变量是否齐全且非空。
# 用法: check_required_env <env_file>
# 返回: 0 通过；1 文件缺失或变量不全（错误信息输出到 stderr）。
check_required_env() {
  local env_file="$1"
  local missing=()
  local empty=()

  if [ ! -f "${env_file}" ]; then
    echo "✗ 缺少 ${env_file}，请参照 .env.local.example 创建并填写。" >&2
    return 1
  fi

  local var value
  for var in "${REQUIRED_ENV_VARS[@]}"; do
    # 提取 KEY= 后的值（去首尾引号）。grep 无匹配时 value 为空；
    # 命令替换以 || true 兜底，避免 set -e + pipefail 因无匹配而退出。
    value=$(grep -E "^${var}=" "${env_file}" | head -n1 | cut -d'=' -f2- | tr -d '"' | tr -d "'" || true)
    if [ -z "$value" ]; then
      if grep -qE "^${var}=" "${env_file}"; then
        empty+=("$var")
      else
        missing+=("$var")
      fi
    fi
  done

  if [ ${#missing[@]} -gt 0 ] || [ ${#empty[@]} -gt 0 ]; then
    echo "✗ 环境变量不完整，编译中止：" >&2
    if [ ${#missing[@]} -gt 0 ]; then
      echo "  缺失: ${missing[*]}" >&2
    fi
    if [ ${#empty[@]} -gt 0 ]; then
      echo "  为空: ${empty[*]}" >&2
    fi
    echo "  请在 ${env_file} 中补全，模板见 .env.local.example。" >&2
    return 1
  fi

  echo "✓ 环境变量完整（${#REQUIRED_ENV_VARS[@]} 项）"
  return 0
}

# 仅直接执行时进入构建主流程；被 source 时不执行（便于单元测试 check_required_env）。
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  cd "$SCRIPT_DIR/.."
  ENV_FILE="${ENV_FILE:-.env.local}"

  echo "==> 检查环境变量完整性 ($ENV_FILE)..."
  check_required_env "$ENV_FILE"

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
  flutter build apk --flavor prod --release "$@"
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
fi
