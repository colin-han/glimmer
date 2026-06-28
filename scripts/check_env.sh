#!/bin/bash
# 校验 .env.local 中必需环境变量是否齐全且非空（缺失或为空则以非零退出）。
# 用法: ./scripts/check_env.sh [env_file]
#   默认 env_file=.env.local
# 退出码: 0 通过；1 文件缺失或变量不全。
#
# 新增环境变量时，需同步更新 REQUIRED_ENV_VARS 与 CLAUDE.md「环境变量」清单
# （保持两处一致）。

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
  AMAP_WEB_KEY
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
    echo "✗ 环境变量不完整，检查中止：" >&2
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

# 仅直接执行时进入校验主流程；被 source 时不执行（便于单元测试 check_required_env）。
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  cd "$SCRIPT_DIR/.."
  ENV_FILE="${1:-.env.local}"

  echo "==> 检查环境变量完整性 ($ENV_FILE)..."
  check_required_env "$ENV_FILE"
fi
