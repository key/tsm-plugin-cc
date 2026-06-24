---
name: the-space-memory:doctor
description: Run health checks on The Space Memory daemon, embedder, and database.
user-invocable: true
---

# Doctor — Health Check

Run `tsm doctor` to check daemon, embedder, database, and vector integrity.

## Usage

```bash
# main リポジトリのトップに移動してから実行する（worktree からでも main を指す）。
ROOT=$(git rev-parse --git-common-dir 2>/dev/null) && ROOT=$(cd "$(dirname "$ROOT")" && pwd) || ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$ROOT" && tsm doctor -f json
```

## What it checks

- Daemon process status (tsmd)
- Embedder child process status
- Database integrity (FTS5 + vector tables)
- Vector backfill queue status
- Socket connectivity (daemon.sock, embedder.sock)

## Output Format

Parse the JSON and present like this:

```text
### The Space Memory — Doctor

✔ Version: v0.6.0 (built 2026-06-24)
✔ Daemon: running (pid 1234)
✔ Embedder: running (pid 5678)
✔ Database: 1,234 chunks, 1,200 vectors
⚠ Backfill: 34 chunks pending (hint: run `tsm vector-fill`)
✘ Socket: embedder.sock not found (hint: restart embedder)

All good. / N issue(s) found.
```

- status "ok" → ✔
- status "warning" → ⚠ (show hint)
- status "error" → ✘ (show hint)
- The `Build` section (`Version` / `Built`) identifies the running binary —
  surface it so a stale `tsm` is obvious (requires tsm ≥ the release adding it;
  older binaries simply omit the section)

## Troubleshooting

| Symptom | Action |
|---|---|
| Daemon not running | `tsm start` |
| Embedder down | Check logs in `{state_dir}/logs/` |
| Vectors stale | `tsm vector-fill` to re-queue |
| DB corrupt | `tsm rebuild --apply` |
