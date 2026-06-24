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

`tsm dict update --apply` adds **every** current candidate at once —
there is no per-word add flag. You shape the result *before* applying,
by adjusting `--threshold` and the reject list. Therefore:

> **Reject the noise first, verify the survivors, then apply.** Never
> `--apply` a list you have not reviewed.

## Workflow

1. **Dry run** — list candidates (unknown tokens at or above the frequency threshold):

   ```bash
   cd "$CLAUDE_PROJECT_DIR" && tsm dict update
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
   from recent chats), not durable vocabulary — lean REJECT on those.

2. **Classify** every candidate as ADD / REJECT / LEAVE using the criteria below.

3. **Reject the noise** — append rejected words (one per line) to the
   reject list, then sync:

   ```bash
   # append rejected words to .tsm/reject_words.txt (one word per line)
   tsm dict reject --apply
   ```

   `reject --apply` is **additive and case-insensitive**: it adds the
   file's words to the DB reject list (rejecting `the` also catches
   `The`). It does **not** prune — an empty file is a no-op, and removing
   a word from the file does not un-reject it. There is no CLI un-reject;
   clearing the list requires `tsm rebuild`.

   **Reject ≠ unsearchable.** Rejecting only drops a word from the
   user-dictionary candidate pipeline (frequency stops accumulating). It does
   **not** remove the term from the FTS index — ASCII acronyms like `CAN`,
   `API`, `JST` stay searchable via the default tokenizer even when rejected.
   So rejecting their lowercase forms is safe for recall; don't skip a
   stopword reject for fear of "losing" the uppercase domain term.

   **Rejected words reappearing as candidates?** If the dry run still lists
   words that are already in `reject_words.txt` (e.g. `the`, `https`), the list
   is not synced to the DB. `tsm rebuild --apply` **resets the DB reject list**,
   so the file is the source of truth but must be re-applied. Confirm with
   `tsm dict reject --all` (or the rejected count in `tsm doctor`): if it is
   empty/small while `reject_words.txt` is large, re-run `tsm dict reject
   --apply` to re-sync — that alone can cut thousands of stale candidates.

4. **Re-run the dry run** and confirm only the ADD words remain:

   ```bash
   tsm dict update
   ```

5. **Confirm with the user, then apply** — this rebuilds the FTS index:

   ```bash
   tsm dict update --apply
   ```

6. **Synonyms (optional)** — map variants/abbreviations to a canonical
   term. Add pairs directly:

   ```bash
   tsm synonym add <variant> <canonical>
   ```

   or edit `.tsm/synonyms.csv` and import it (mirrors the user subset):

   ```bash
   tsm synonym import --file .tsm/synonyms.csv
   ```

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

Plan: reject the 6 noise words, then apply the 7 to the dictionary (rebuilds FTS).
Proceed?
```

## Quick reference

| Command | Effect |
|---|---|
| `tsm dict update` | Dry run — list candidates (read-only) |
| `tsm dict update --threshold <N>` | Dry run at a different frequency cutoff (default 5) |
| `tsm dict update --apply` | Add all current candidates + rebuild FTS — **confirm first** |
| `tsm dict reject --apply` | Add `.tsm/reject_words.txt` words to the DB reject list (additive, case-insensitive; empty file = no-op; no un-reject) |
| `tsm dict reject --all` | Show all currently rejected words |
| `tsm synonym add <a> <b>` | Add a synonym pair to the DB |
| `tsm synonym import --file <PATH>` | Import synonym pairs from a CSV file (mirrors the user subset) |

## Common mistakes

| Mistake | Fix |
|---|---|
| Running `--apply` on the raw candidate list | Reject noise first; `--apply` adds *everything* shown |
| Adding stopwords (`こと`, `の`-led tokens) | These hurt FTS precision — always reject |
| Rejecting encoding variants without mapping them | Add a `synonyms.csv` entry to canonical form to keep recall |
| Applying without telling the user | `--apply` rebuilds the FTS index — confirm first |
