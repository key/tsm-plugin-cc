#!/usr/bin/env bash
set -eu

# stdin から JSON を読む
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)

[ -z "$SESSION_ID" ] && exit 0

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

# セッション JSONL の格納先（このセッションのプロジェクトパスで符号化される）を
# tsm の知識ベース .tsm がある main とは別に解決する。worktree 内では両者は
# 食い違う（DB は main、セッションは worktree のトップ）ため。
# cd で main に移る前に、現在地（worktree）基準で確定させる。
# セッション側は Claude が設定する CLAUDE_PROJECT_DIR が最も正確なので優先する。
SESSION_PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$(resolve_root)"

# セッション JSONL ファイルを探す。
# Claude はプロジェクトの絶対パスの "/" と "." を "-" に置換した名前で
# ~/.claude/projects/ 配下にセッションを格納する。
ENCODED=$(printf '%s' "$SESSION_PROJECT" | sed 's/[/.]/-/g')
SESSIONS_DIR="$HOME/.claude/projects/$ENCODED"
JSONL_FILE="$SESSIONS_DIR/$SESSION_ID.jsonl"

[ ! -f "$JSONL_FILE" ] && exit 0

"$TSM" ingest-session "$JSONL_FILE" >/dev/null 2>&1
