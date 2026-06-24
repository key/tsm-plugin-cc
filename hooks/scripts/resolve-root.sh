#!/usr/bin/env bash
# main リポジトリのトップを解決する。
#
# linked worktree の中から呼ばれても main を指す（tsm の知識ベース .tsm は
# main リポジトリのトップに置かれるため）。解決の優先順位:
#   1. git の common-dir の親 … git 管理下なら最優先（worktree -> main）
#   2. $CLAUDE_PROJECT_DIR    … 非 git だが Claude Code の env がある場合
#   3. $PWD                   … 最終フォールバック
resolve_root() {
  local common
  if common=$(git rev-parse --git-common-dir 2>/dev/null) && [ -n "$common" ]; then
    (cd "$(dirname "$common")" && pwd) && return
  fi
  printf '%s\n' "${CLAUDE_PROJECT_DIR:-$PWD}"
}
