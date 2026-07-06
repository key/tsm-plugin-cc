#!/usr/bin/env bash
# main リポジトリのトップを解決する。
#
# linked worktree の中から呼ばれても main を指す（tsm の知識ベース .tsm は
# main リポジトリのトップに置かれるため）。解決の優先順位:
#   1. git の common-dir の親 … git 管理下なら最優先（worktree -> main）
#   2. $CLAUDE_PROJECT_DIR    … 非 git だが Claude Code の env がある場合
#   3. $PWD                   … 最終フォールバック
#
# Claude Code はフックを対象プロジェクト外の cwd で起動するため、git 判定は
# `$PWD` ではなく `${CLAUDE_PROJECT_DIR:-$PWD}` を `-C` で明示的にアンカーする。
# アンカーせず素の `git rev-parse` に頼ると、フックの cwd がそもそも git 管理下に
# ないため判定 1 が常に失敗し、判定 2 の $CLAUDE_PROJECT_DIR（linked worktree の
# パス）がそのまま返ってしまう。worktree には `.tsm` が無いため、以降の
# `tsm` 呼び出しが "Database not initialized" で失敗する。
resolve_root() {
  local project common
  project="${CLAUDE_PROJECT_DIR:-$PWD}"
  if common=$(git -C "$project" rev-parse --git-common-dir 2>/dev/null) && [ -n "$common" ]; then
    (cd "$project" && cd "$(dirname "$common")" && pwd) && return
  fi
  printf '%s\n' "$project"
}
