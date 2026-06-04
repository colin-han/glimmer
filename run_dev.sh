#!/bin/bash
# 开发版运行脚本，自动使用 dev flavor

# 从 .env.local 读取 WORKTREE
WORKTREE=""
ENV_FILE="$(dirname "$0")/.env.local"
if [ -f "$ENV_FILE" ]; then
  WORKTREE=$(grep '^WORKTREE=' "$ENV_FILE" | head -1 | cut -d'=' -f2 | tr -d '"' | tr -d "'")
fi

flutter run --flavor dev --dart-define=dev=true ${WORKTREE:+--dart-define=worktree="$WORKTREE"} "$@"
