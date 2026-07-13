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

# 検索実行（tsmd が未起動なら自動起動される）。stderr は $LOG（TSM_HOOK_DEBUG
# 未設定なら /dev/null）と自スクリプトの stderr の双方へ tee する。フック失敗は
# non-blocking なので、TSM_HOOK_DEBUG 抜きでもログで診断できるよう表面化させる。
if [ "$SEARCH_TIMEOUT" -gt 0 ] 2>/dev/null; then
  # tsm を背景実行し、監視プロセスが SEARCH_TIMEOUT 秒後に TERM する。時間内に
  # 終われば監視役を止める。結果は一時ファイル経由で受け取り、背景プロセスが
  # コマンド置換のパイプを掴んで置換完了を遅延させないようにする。
  SEARCH_OUT=$(mktemp "${TMPDIR:-/tmp}/tsm-search.XXXXXX")
  "$TSM" search --query "$QUERY" --format json >"$SEARCH_OUT" 2> >(tee -a "$LOG" >&2) &
  SEARCH_PID=$!
  ( sleep "$SEARCH_TIMEOUT"; kill -TERM "$SEARCH_PID" 2>/dev/null ) >/dev/null 2>&1 &
  WATCH_PID=$!
  if wait "$SEARCH_PID" 2>/dev/null; then SEARCH_RC=0; else SEARCH_RC=$?; fi
  kill -TERM "$WATCH_PID" 2>/dev/null || true
  wait "$WATCH_PID" 2>/dev/null || true
  RESULT=$(cat "$SEARCH_OUT")
  rm -f "$SEARCH_OUT"
  if [ "$SEARCH_RC" -ne 0 ]; then
    # 128+ は監視役の TERM（＝打ち切り）。それ以外は tsm 自体の失敗。
    if [ "$SEARCH_RC" -ge 128 ]; then
      log "TIMEOUT: tsm search exceeded ${SEARCH_TIMEOUT}s"
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
