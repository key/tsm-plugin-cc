#!/usr/bin/env bats
# the-space-memory フックの「対象外なら何もしない」分岐を検証する。
# tsm バイナリより手前で抜ける分岐だけをテストするので、tsm 不在でも通る。

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPTS="$REPO_ROOT/hooks/scripts"
}

@test "index-file skips non-markdown files" {
  run bash "$SCRIPTS/index-file.sh" <<< '{"tool_input":{"file_path":"/tmp/foo.txt"}}'
  [ "$status" -eq 0 ]
}

@test "search skips too-short queries" {
  run bash "$SCRIPTS/search.sh" <<< '{"prompt":"hi"}'
  [ "$status" -eq 0 ]
}

@test "ingest skips when session_id is missing" {
  run bash "$SCRIPTS/ingest.sh" <<< '{}'
  [ "$status" -eq 0 ]
}

# --- resolve-root.sh ---------------------------------------------------------

@test "resolve_root falls back to PWD outside a git repo" {
  run env -u CLAUDE_PROJECT_DIR bash -c \
    ". '$SCRIPTS/resolve-root.sh'; cd '$BATS_TEST_TMPDIR' && resolve_root"
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR" ]
}

@test "resolve_root uses CLAUDE_PROJECT_DIR outside a git repo" {
  run bash -c \
    "CLAUDE_PROJECT_DIR=/var/tmp; . '$SCRIPTS/resolve-root.sh'; cd '$BATS_TEST_TMPDIR' && resolve_root"
  [ "$status" -eq 0 ]
  [ "$output" = "/var/tmp" ]
}

@test "resolve_root returns the main repo top from inside a linked worktree" {
  main="$BATS_TEST_TMPDIR/main"
  wt="$BATS_TEST_TMPDIR/wt"
  git init -q "$main"
  git -C "$main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$main" worktree add -q "$wt" >/dev/null 2>&1
  # macOS の /private シンボリックリンク差を吸収するため realpath で正規化して比較する。
  run bash -c ". '$SCRIPTS/resolve-root.sh'; cd '$wt' && resolve_root"
  [ "$status" -eq 0 ]
  [ "$(cd "$output" && pwd -P)" = "$(cd "$main" && pwd -P)" ]
}
