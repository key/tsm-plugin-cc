#!/usr/bin/env bash
set -euo pipefail

FILE=$(jq -r '.tool_input.file_path // empty') || exit 0
[[ -z "$FILE" || "$FILE" == "null" ]] && exit 0

# .md ファイルのみ対象
[[ "$FILE" != *.md ]] && exit 0

# Prefer system-installed tsm over plugin-bundled one
if command -v tsm >/dev/null 2>&1; then
  TSM="tsm"
elif [ -x "${CLAUDE_PLUGIN_ROOT:-}/bin/tsm" ]; then
  TSM="${CLAUDE_PLUGIN_ROOT:-}/bin/tsm"
else
  exit 0
fi

# shellcheck source=hooks/scripts/resolve-root.sh
# shellcheck disable=SC1091
. "$(dirname "$0")/resolve-root.sh"
ROOT=$(resolve_root)
cd "$ROOT"

# tsm の index_root（tsm.toml、通常は main の絶対パス）からの相対パスに変換する。
# ここでは ROOT（resolve_root = main）が index_root と一致する前提で前置を剥がす。
REL_PATH="${FILE#"$ROOT"/}"

# ROOT 配下に変換できなかった場合（プロジェクト外のパス）はスキップ。
#
# 既知の制約（linked worktree）: tsm は index_root 基準でファイルを読み・格納する。
# main 配下にネストした worktree（例: .claude/worktrees/...）の編集は
# その長いネストパスで索引され、main 側の同名 doc とは別エントリになる。
# main 外の worktree は index_root の外なのでここで skip され索引されない。
# worktree パスの索引除外は tsm 本体（index_root / fs-watcher）側の課題。
[ "$REL_PATH" = "$FILE" ] && exit 0

echo "$REL_PATH" | "$TSM" index --files-from-stdin >/dev/null 2>&1
