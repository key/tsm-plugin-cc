---
name: the-space-memory:dict-update
description: |
  Curate The Space Memory's user dictionary: review tokenizer candidates and decide add vs reject, then manage synonyms.
  Use when: user wants to improve Japanese full-text search quality, fix bad tokenization, or maintain the dictionary.
  Examples: "辞書を更新して", "the-space-memory の辞書メンテして", "検索の分かち書きを直したい",
  "辞書の候補を見せて", "シノニムを追加して", "update the knowledge dictionary", "review dict candidates".
user-invocable: true
---

# Dictionary Update

Curate the `tsm` user dictionary so the FTS5 tokenizer treats domain
terms as single tokens. The hard part is **judgment**: which candidate
words to ADD vs REJECT. The commands are mechanical.

## Core principle

There is no bulk "apply all candidates" command. `tsm dict update` is a
**read-only** discovery view; every verdict is set one word at a time
with `tsm dict add <word>` or `tsm dict reject <word>`. The hard part
is the per-word ADD/REJECT/LEAVE judgment — the commands themselves
are mechanical and safe by default (nothing changes until you name a
word).

`user_dict.simpledic` and `reject_words.txt` are a portable,
git-tracked mirror of the DB's verdicts: `tsm dict export` writes
DB → files, `tsm dict import` writes files → DB (insert-only — it
never removes a verdict).

## Workflow

1. **Dry run** — list candidates (unknown tokens at or above the
   frequency threshold). The candidate rows print to **stderr**, so
   capture both streams:

   ```bash
   cd "$CLAUDE_PROJECT_DIR" && tsm dict update 2>&1
   ```

   Each row is `<word>  <N> hits  (first: <date>, last: <date>)`:

   ```text
   ハンドロード    42 hits  (first: 2025-03-01, last: 2026-06-20)
   LoRa            38 hits  (first: 2025-01-15, last: 2026-05-02)
   commit           5 hits  (first: 2026-06-22, last: 2026-06-22)
   パス             5 hits  (first: 2026-06-22, last: 2026-06-22)
   ```

   The `first`/`last` dates are a judgment signal: a burst of words all
   dated today is usually session-ingest noise (generic English/JA terms
   from recent chats), not durable vocabulary — lean REJECT on those. This
   is common in agent-orchestration session transcripts too: boilerplate
   like "teammate", "idleReason", "orchestrator"/"オーケストレーター" floods
   candidates in the ingestion window — lean REJECT there as well.

2. **Classify** every candidate as ADD / REJECT / LEAVE using the criteria below.

3. **Record REJECT verdicts** — one word at a time, matching the exact
   surface form shown by `tsm dict update` (no Unicode normalization is
   applied, so a halfwidth/fullwidth or NFC/NFD variant is a distinct word):

   ```bash
   tsm dict reject <word>
   ```

   For a large batch, append the words (one per line) to
   `.tsm/reject_words.txt` and sync them in one pass:

   ```bash
   tsm dict import
   ```

   `import` is **insert-only**: it upserts the verdicts named in the
   file and leaves every other word's verdict untouched — it does not
   prune anything.

   **Reject ≠ unsearchable.** Rejecting only stops a word from
   accumulating frequency in the candidate pipeline. It does **not**
   remove the term from the FTS index — ASCII acronyms like `CAN`,
   `API`, `JST` stay searchable via the default tokenizer even when
   rejected. So rejecting their lowercase forms is safe for recall;
   don't skip a stopword reject for fear of "losing" the uppercase
   domain term.

   **To undo a verdict**, reset the word to pending: `tsm dict rm <word>`.

4. **Re-run the dry run** and confirm only the ADD words remain:

   ```bash
   tsm dict update 2>&1
   ```

5. **Confirm with the user, then add** each ADD word — one at a time:

   ```bash
   tsm dict add <word> [<reading>]
   ```

   Omit `<reading>` for an all-kana word (the surface is its own
   reading). `add` always changes the accepted set, so it regenerates
   `user_dict.simpledic` and reloads the tokenizer right away — there is
   no separate "apply" step. (`reject`/`rm`/`import` only trigger the
   same reload when they change an *accepted* word's status — rejecting
   a plain pending candidate does not touch the accepted set and re-indexes
   nothing.) See **Concurrency** below before running `add` while a
   reindex may already be in flight.

6. **Synonyms (optional)** — map variants/abbreviations to a canonical
   term. Add pairs directly:

   ```bash
   tsm synonym add <variant> <canonical>
   ```

   or edit `.tsm/synonyms.csv` and import it (mirrors the user subset):

   ```bash
   tsm synonym import --file .tsm/synonyms.csv
   ```

## Concurrency

**Do not run `tsm dict add` (or a `reject`/`rm`/`import` that flips an
already-accepted word) while a `tsm reindex` (`all`/`fts`/`vectors`) is
already running.** The verdict is still recorded in the DB either way,
but the automatic FTS re-index this triggers fails with `reindex
already in progress` if one is already under way, leaving the
tokenizer/search index stale. Before adding words, check `tsm status`
or `tsm doctor` for an in-progress reindex. If one is running, either
wait for it to finish, or afterward run `tsm reindex fts` (or `tsm
restart`) to pick up the pending dictionary changes.

## Classification criteria

| Verdict | What it looks like | Examples |
|---|---|---|
| **ADD** | Domain terms, proper nouns, product/tech names, mixed Latin/JA vocab, compound nouns the tokenizer mis-splits | `ハンドロード`, `弾速`, `形態素解析`, `LoRa`, `marlin`, `9mm` |
| **REJECT** | Truncated mid-word fragments; tokens led by a particle; generic stopwords; bare numbers/dates; mojibake / encoding variants | `キャリブレーシ` (truncated), `の対応` (particle-led), `こと`/`もの`/`ため` (stopwords), `2025` (bare year), `ﾊﾝﾄﾞﾛｰﾄﾞ` (halfwidth), `リロ―ディング` (wrong dash) |
| **LEAVE** | Legitimate but low-value or genuinely ambiguous — skip this pass, revisit if it recurs | one-off jargon, names you can't verify |

**Encoding variants are a normalization symptom, not vocabulary.**
Halfwidth-katakana (`ﾊﾝﾄﾞﾛｰﾄﾞ`) and dash-variant (`―` vs `ー`) duplicates
should be REJECTED — and optionally mapped to their canonical form in
`synonyms.csv` to preserve recall. If they recur often, flag the
indexing pipeline's NFKC normalization as a follow-up rather than
rejecting them one by one.

**Tuning the threshold:** raising `--threshold <N>` is the blunt control
for noise volume; the reject list is the precise one. Use threshold to
cut a flood of low-frequency junk, the reject list for specific
recurring bad tokens.

## Present to the user before applying

Show the classification as a table, then ask for approval:

```text
### Dictionary candidates (threshold ≥ 5)

ADD (7):     ハンドロード, LoRa, 弾速, 山間部, marlin, 9mm, 形態素解析
REJECT (6):  キャリブレーシ, の対応, こと, 2025, ﾊﾝﾄﾞﾛｰﾄﾞ, リロ―ディング
LEAVE (0):   —

Plan: reject the 6 noise words, then add the 7 domain words to the dictionary
(each triggers an FTS re-index). Proceed?
```

## Quick reference

| Command | Effect |
|---|---|
| `tsm dict update [--threshold <N>]` | Dry run — list candidates (read-only; default threshold 5; rows on stderr) |
| `tsm dict add <word> [<reading>]` | Accept one word; always reloads tokenizer + FTS re-index |
| `tsm dict reject <word>` | Reject one word; clears any prior accept (re-indexes only if it *was* accepted) |
| `tsm dict rm <word>` | Reset one word to pending (re-indexes only if it *was* accepted) |
| `tsm dict export` | DB → files, overwriting `user_dict.simpledic` + `reject_words.txt` |
| `tsm dict import` | Files → DB, insert-only; re-indexes only if accepted words changed |
| `tsm synonym add <a> <b>` | Add a synonym pair to the DB |
| `tsm synonym import --file <PATH>` | Import synonym pairs from a CSV file (mirrors the user subset) |

## Common mistakes

| Mistake | Fix |
|---|---|
| Assuming `tsm dict update` writes anything | It's read-only; verdicts need `add`/`reject`/`import` |
| Adding stopwords (`こと`, `の`-led tokens) | These hurt FTS precision — always reject |
| Rejecting encoding variants without mapping them | Add a `synonyms.csv` entry to canonical form to keep recall |
| Hand-editing `reject_words.txt` then running `tsm dict export` | `export` overwrites the files from the DB, silently discarding unsynced file edits — `import` first (or just use `tsm dict reject <word>`) |
| Finalizing verdicts while a `tsm reindex` is running | Check `tsm status`/`tsm doctor` first — see **Concurrency** |
