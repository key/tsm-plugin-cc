#!/usr/bin/env bash
set -eu

# デバッグログはデフォルト無効。TSM_HOOK_DEBUG をセットしたときだけ、
# ユーザー専用のテンポラリ（0600）に出力する。
# 生のプロンプトを含むため、共有 /tmp への常時書き込みはしない。
if [ -n "${TSM_HOOK_DEBUG:-}" ]; then
  LOG="${TMPDIR:-/tmp}/tsm-hook-search.$(id -u).log"
  ( umask 077; : >> "$LOG" )
  log() { echo "[$(date -Iseconds)] $*" >> "$LOG"; }
else
  LOG="/dev/null"
  log() { :; }
fi

# stdin から JSON を読む
INPUT=$(cat)
log "RAW_INPUT='${INPUT:0:300}'"
QUERY=$(echo "$INPUT" | jq -r '.prompt // .user_prompt // empty' 2>/dev/null || true)

log "query='${QUERY:0:80}' PLUGIN_ROOT='${CLAUDE_PLUGIN_ROOT:-}' PROJECT_DIR='${CLAUDE_PROJECT_DIR:-}'"

# クエリが短すぎる場合はスキップ
if [ ${#QUERY} -lt 3 ]; then
  log "SKIP: query too short (${#QUERY} chars)"
  exit 0
fi

# Prefer system-installed tsm over plugin-bundled one
# (bundled binary may have hardcoded paths from Docker build)
if command -v tsm >/dev/null 2>&1; then
  TSM="tsm"
elif [ -x "${CLAUDE_PLUGIN_ROOT:-}/bin/tsm" ]; then
  TSM="${CLAUDE_PLUGIN_ROOT:-}/bin/tsm"
else
  log "SKIP: tsm not found"
  exit 0
fi

# shellcheck source=hooks/scripts/resolve-root.sh
# shellcheck disable=SC1091
. "$(dirname "$0")/resolve-root.sh"
cd "$(resolve_root)"

# 検索タイムアウト（秒）。プロンプト投入ごとに走るフックなので、遅い検索が
# 入力の体感を損なわないよう既定 3 秒で打ち切る。TSM_SEARCH_TIMEOUT で上書き可
# （0 または非数値で無効化）。timeout(1) は macOS 標準に無く、perl/python 等の
# ランタイムも環境依存で当てにできないため、POSIX の sleep/kill だけで実装する。
SEARCH_TIMEOUT="${TSM_SEARCH_TIMEOUT:-3}"

# ハード上限 10 秒。hooks.json のフック機構 timeout と同値で、それを超える設定は
# 無意味（機構側が SIGTERM で強制打ち切りし graceful 経路を通らない）ため、内部
# ウォッチドッグ側で 10 秒に丸める。これで env の値に関わらず最大 10 秒を保証する。
SEARCH_TIMEOUT_MAX=10
if [ "$SEARCH_TIMEOUT" -gt "$SEARCH_TIMEOUT_MAX" ] 2>/dev/null; then
  SEARCH_TIMEOUT="$SEARCH_TIMEOUT_MAX"
fi

# 検索実行（tsmd が未起動なら自動起動される）。stderr は $LOG（TSM_HOOK_DEBUG
# 未設定なら /dev/null）と自スクリプトの stderr の双方へ tee する。フック失敗は
# non-blocking なので、TSM_HOOK_DEBUG 抜きでもログで診断できるよう表面化させる。
if [ "$SEARCH_TIMEOUT" -gt 0 ] 2>/dev/null; then
  # tsm を背景実行し、監視プロセスが SEARCH_TIMEOUT 秒後に TERM する。時間内に
  # 終われば監視役を止める。結果は一時ファイル経由で受け取り、背景プロセスが
  # コマンド置換のパイプを掴んで置換完了を遅延させないようにする。
  # mktemp 失敗（書き込み不可な TMPDIR 等）でも他の失敗経路と同じく graceful に
  # exit 0 する。set -eu 下の bare 代入は失敗時にスクリプトを異常終了させるため。
  SEARCH_OUT=$(mktemp "${TMPDIR:-/tmp}/tsm-search.XXXXXX") || {
    log "FAIL: mktemp failed"
    exit 0
  }
  # 監視役が発火した事実はセンチネルファイルで記録する。SEARCH_RC>=128 での判定は
  # SIGSEGV(139)/OOM kill(137) 等あらゆるシグナル死を打ち切りと誤認し、クラッシュを
  # TIMEOUT と誤記録してデバッグを誤誘導するため使わない。
  TIMED_OUT="$SEARCH_OUT.timedout"
  # 一時ファイルは通常終了・内部 exit 経路で EXIT trap が掃除する。フック機構が
  # 上限超過を SIGTERM で打ち切る場合にも備え TERM/INT を捕捉し、進行中の検索と
  # 監視役も停止してから exit 0 で抜ける（SIGKILL は捕捉不可）。exit 0 なのは、
  # 非0がフックを失敗扱いにさせ best-effort・non-blocking の契約を破るため。子を
  # 止めるのは、打ち切り後に tsm search が孤児として走り続けたり、監視役が終了済み
  # PID を遅延 kill するのを防ぐため（PID 未設定の窓に備え空初期化して参照を守る）。
  SEARCH_PID=
  WATCH_PID=
  _on_signal() {
    if [ -n "$SEARCH_PID" ]; then kill -TERM "$SEARCH_PID" 2>/dev/null || true; fi
    if [ -n "$WATCH_PID" ]; then kill -TERM "$WATCH_PID" 2>/dev/null || true; fi
    rm -f "$SEARCH_OUT" "$TIMED_OUT"
    exit 0
  }
  trap 'rm -f "$SEARCH_OUT" "$TIMED_OUT"' EXIT
  trap _on_signal TERM INT
  "$TSM" search --query "$QUERY" --format json >"$SEARCH_OUT" 2> >(tee -a "$LOG" >&2) &
  SEARCH_PID=$!
  # 監視役はセンチネルを立ててから TERM を送る（flag→TERM の順で、TERM 後に wait が
  # 返る時点で必ず flag が見える）。tsm search は TERM に素直に応じる協調クライアント
  # なので KILL エスカレートはしない（猶予 sleep は打ち切りごとに遅延を上乗せするうえ、
  # 既に終了した PID への遅延 KILL は PID 再利用の的になる）。ハングの最終上限は
  # フック機構側の 10 秒が担う。
  ( sleep "$SEARCH_TIMEOUT"; : >"$TIMED_OUT"; kill -TERM "$SEARCH_PID" 2>/dev/null ) >/dev/null 2>&1 &
  WATCH_PID=$!
  if wait "$SEARCH_PID" 2>/dev/null; then SEARCH_RC=0; else SEARCH_RC=$?; fi
  kill -TERM "$WATCH_PID" 2>/dev/null || true
  wait "$WATCH_PID" 2>/dev/null || true
  # cat 失敗は「本当に空」と区別してログに残す（診断性）。結果は空として続行。
  if ! RESULT=$(cat "$SEARCH_OUT"); then
    log "FAIL: could not read search output"
    RESULT=""
  fi
  if [ "$SEARCH_RC" -ne 0 ]; then
    if [ -e "$TIMED_OUT" ]; then
      log "TIMEOUT: tsm search exceeded ${SEARCH_TIMEOUT}s"
    elif [ "$SEARCH_RC" -ge 128 ]; then
      log "FAIL: tsm search terminated by signal $((SEARCH_RC - 128))"
    else
      log "FAIL: tsm search exited with $SEARCH_RC"
    fi
    exit 0
  fi
else
  RESULT=$("$TSM" search --query "$QUERY" --format json 2> >(tee -a "$LOG" >&2)) || {
    log "FAIL: tsm search exited with $?"
    exit 0
  }
fi

# 結果が空なら何も出力しない
if [ -z "$RESULT" ] || [ "$RESULT" = "null" ]; then
  log "EMPTY: no results"
  exit 0
fi

COUNT=$(echo "$RESULT" | jq '.results | length' 2>/dev/null || echo "0")
TOTAL_HITS=$(echo "$RESULT" | jq '.total_hits // 0' 2>/dev/null || echo "0")
log "OK: $COUNT results (total_hits: $TOTAL_HITS)"

if [ "$COUNT" = "0" ]; then
  exit 0
fi

BUDGET="${TSM_SNIPPET_BUDGET:-1000}"

# Build XML output following Anthropic prompting best practices.
XML=$(echo "$RESULT" | jq -r --arg query "$QUERY" --argjson budget "$BUDGET" --argjson total_hits "$TOTAL_HITS" '
  .results | length as $count |
  reduce to_entries[] as $entry (
    {xml: "", used: 0};
    $entry.value as $item |
    ($entry.key + 1) as $idx |
    ($item.snippet | length) as $slen |

    # snippet budget check
    (if (.used + $slen) <= $budget then true else false end) as $ok |

    # source attributes
    (if $item.status != null and $item.status != ""
     then " status=\"\($item.status)\""
     else "" end) as $st |

    # related element (omit when empty)
    (if ($item.related_docs // [] | length) > 0
     then "<related>" + ($item.related_docs | map(.file_path) | join(", ")) + "</related>\n"
     else "" end) as $rel |

    # snippet element (self-closing when over budget)
    (if $ok
     then "<snippet>\n\($item.snippet)\n</snippet>\n"
     else "<snippet/>\n" end) as $snip |

    # score: truncate to 3 decimal places
    ($item.score | tostring | split(".") |
     .[0] + "." + ((.[1] // "000") | .[0:3])) as $score |

    {
      xml: (.xml
        + "<result index=\"\($idx)\" score=\"\($score)\">\n"
        + "<source type=\"\($item.source_type // "unknown")\"\($st)>\($item.source_file)</source>\n"
        + "<section>\($item.section_path)</section>\n"
        + $snip + $rel
        + "</result>\n"),
      used: (if $ok then .used + $slen else .used end)
    }
  ) |
  "<knowledge_search query=\"\($query | gsub("\""; "&quot;") | gsub("&"; "&amp;") | gsub("<"; "&lt;"))\" count=\"\($count)\" total=\"\($total_hits)\">\n\(.xml)</knowledge_search>"
')

# additionalContext 形式で出力
jq -n --arg context "$XML" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $context
  }
}'
