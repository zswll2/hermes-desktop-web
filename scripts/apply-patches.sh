#!/usr/bin/env bash
# 把本仓库 patches/ 里的补丁打到上游仓库的指定基线上。
#
# 用法：
#   bash scripts/apply-patches.sh [目标目录]
#
# 说明：
#   - 补丁基线 = ac0f4104c55d9de19bbe8ac431d2df97836d1865（见 README「如何应用补丁」）
#   - 上游 main 已在此之后前进 1,700+ 个提交，直接打到最新 main 会有冲突；
#     更省事的方式是直接用分支：git clone -b feat/desktop-web https://github.com/zswll2/hermes-agent.git
set -euo pipefail

BASE="${PATCH_BASE:-ac0f4104c55d9de19bbe8ac431d2df97836d1865}"
TARGET="${1:-hermes-desktop-web}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/patches"

[ -d "$PATCH_DIR" ] || { echo "找不到补丁目录: $PATCH_DIR" >&2; exit 1; }
COUNT=$(ls "$PATCH_DIR"/*.patch 2>/dev/null | wc -l)
[ "$COUNT" -gt 0 ] || { echo "补丁目录为空: $PATCH_DIR" >&2; exit 1; }

echo "补丁数: $COUNT    基线: $BASE    目标: $TARGET"

if [ ! -d "$TARGET/.git" ]; then
  echo "== 克隆上游 =="
  git clone https://github.com/NousResearch/hermes-agent.git "$TARGET"
fi

cd "$TARGET"
echo "== 切到基线并建分支 =="
git checkout -b feat/desktop-web "$BASE"

echo "== 应用补丁 =="
git am "$PATCH_DIR"/*.patch

echo "== 完成 =="
echo "下一步："
echo "  cd $TARGET/apps/desktop && npm ci && npm run build:web"
echo "  然后按 README「部署」一节用 HERMES_WEB_APP_DIST 指向 dist-web"
