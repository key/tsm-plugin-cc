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

@test "search exits 0 when killed by SIGTERM mid-search (non-blocking contract)" {
  # フックは best-effort・non-blocking。検索中にフック機構が SIGTERM で打ち切っても
  # 非0を返してはならない（非0はフックを失敗扱いにさせ、内部タイムアウト導入の趣旨
  # である「静かに劣化」を壊す）。TERM trap が exit 0 で抜けることを守る回帰テスト。
  fakebin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$fakebin"
  # `search` でハングする偽 tsm。開始を通知してから待つ（テストの決定性のため）。
  cat > "$fakebin/tsm" <<SH
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/tsm_started"
sleep 5
SH
  chmod +x "$fakebin/tsm"

  repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

  # 内部ウォッチドッグは発火させず（高い timeout・クランプで 10s）、代わりに SIGTERM
  # を送る。fd 3 を閉じて起動するのは、背景の孤児プロセスが bats の出力 fd を掴んで
  # テスト実行をハングさせないため（bats の定石）。
  PATH="$fakebin:$PATH" CLAUDE_PROJECT_DIR="$repo" TSM_SEARCH_TIMEOUT=30 \
    bash "$SCRIPTS/search.sh" >/dev/null 2>&1 3>&- <<< '{"prompt":"regression query for signal handling"}' &
  local pid=$!

  # 偽 tsm が動き出す＝TERM trap 設置済みになるまで待ってから TERM する。
  for _ in $(seq 1 50); do
    [ -e "$BATS_TEST_TMPDIR/tsm_started" ] && break
    sleep 0.1
  done
  kill -TERM "$pid"

  local status=0
  wait "$pid" || status=$?
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

@test "resolve_root anchors on CLAUDE_PROJECT_DIR (a linked worktree) even when the hook's cwd is outside any git repo" {
  # Claude Code invokes hooks with a cwd that is not the project (e.g. it may
  # not be under git management at all). resolve_root must still anchor its
  # git lookup to CLAUDE_PROJECT_DIR (via `git -C`), not to $PWD, or it falls
  # through to returning the worktree path itself — which has no .tsm state.
  main="$BATS_TEST_TMPDIR/main"
  wt="$BATS_TEST_TMPDIR/wt"
  nongit="$BATS_TEST_TMPDIR/nongit"
  mkdir -p "$nongit"
  git init -q "$main"
  git -C "$main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$main" worktree add -q "$wt" >/dev/null 2>&1
  run env CLAUDE_PROJECT_DIR="$wt" bash -c \
    ". '$SCRIPTS/resolve-root.sh'; cd '$nongit' && resolve_root"
  [ "$status" -eq 0 ]
  [ "$(cd "$output" && pwd -P)" = "$(cd "$main" && pwd -P)" ]
}
