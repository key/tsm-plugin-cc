# the-space-memory

ワークスペース横断のナレッジ検索エンジン。ハイブリッド検索（FTS5 +
ベクトル）で過去のメモ・調査・セッションログを検索し、プロンプトに
自動で文脈を注入する。

検索・索引付けの実体は別配布の **`tsm` CLI**
（[the-space-memory](https://github.com/key/the-space-memory)）。
このプラグインは `tsm` を呼び出すフック／スキル／エージェントの薄い
ラッパー。

## インストール

このリポジトリ単体がマーケットプレイスを兼ねる。

```bash
/plugin marketplace add key/tsm-plugin-cc
/plugin install the-space-memory@tsm-plugin-cc
```

別途 `tsm` CLI のインストールが必要（下記）。

## 必要ツール

- [`tsm`](https://github.com/key/the-space-memory) CLI（**別途インストールが必要**。
  未導入ならフックは無言でスキップ）
- `jq`

`tsm` が `PATH` 上にあればそれを使う。無ければ
`${CLAUDE_PLUGIN_ROOT}/bin/tsm` にフォールバックする（このリポジトリには
バイナリを同梱していないので、通常は `PATH` 上の `tsm` を使う）。

## 挙動

3 つのフックで動く。いずれもプロジェクトルート（= `tsm.toml` を置く
ディレクトリ）を `resolve-root.sh` で解決する。解決順は
git の common-dir の親（linked worktree からでも main を指す）→
`CLAUDE_PROJECT_DIR` → `$PWD`。プロジェクト外のパスや空クエリはスキップする。

- **`UserPromptSubmit`** — クエリで `tsm search` し、ヒットを
  `<knowledge_search>` として context に注入（`search.sh`）
- **`PostToolUse` (`Edit`/`Write`)** — 対象が `*.md` かつプロジェクト内なら
  `tsm index` で索引付け（`index-file.sh`）
- **`Stop`** — そのセッションの JSONL を `tsm ingest-session` で取り込む
  （`ingest.sh`）

## 制約

- linked worktree 内の `*.md` 編集の索引: tsm はプロジェクトルート（`tsm.toml`
  の場所、通常は main の絶対パス）基準でファイルを読み・格納する。このため main 配下に
  ネストした worktree の編集はネストパスで索引され main 側の同名 doc とは別
  エントリになり、main 外の worktree は索引対象外になる。worktree パスの除外は
  tsm 本体（プロジェクトルート解決 / fs-watcher）側の課題として未対応。
  なお `doctor` / `search` / `ingest` は worktree からでも main の DB を正しく参照する。

## スキル / エージェント

- `the-space-memory:search` — 手動でナレッジ検索する（`tsm search`）
- `the-space-memory:doctor` — デーモン・埋め込み器・DB の健全性チェック
- `the-space-memory:dict-update` — `tsm` ユーザー辞書のキュレーション（`tsm dict update` 候補の
  ADD/REJECT 判定・reject 同期・synonym 追加/インポート。`--apply` 前に承認）
- `deep-research` エージェント — 複数クエリ + 全文読みで深掘り調査する

## セットアップ

1. `tsm` CLI をインストールして `PATH` を通す
2. プロジェクトルートで `tsm init` を実行する（`tsm.toml` と `.tsm/` を生成。
   索引対象を絞るなら `content_dirs` を設定）
3. デーモンを起動: `tsm start`（フック経由でも自動起動される）
4. 動作確認: `tsm doctor -f json` または `/the-space-memory:doctor`

## 環境変数

| 変数 | 既定 | 意味 |
|---|---|---|
| `TSM_SNIPPET_BUDGET` | `1000` | 検索スニペットの合計文字数の上限 |
| `TSM_HOOK_DEBUG` | （未設定） | セット時のみデバッグログを出力（後述） |

`TSM_HOOK_DEBUG` をセットすると `search.sh` が
`${TMPDIR:-/tmp}/tsm-hook-search.<uid>.log`（0600）に記録する。
生のプロンプトを含むため既定では無効。

## トラブルシューティング

`tsm doctor`（または `/the-space-memory:doctor`）で確認する。

| 症状 | 対処 |
|---|---|
| 検索が空振りする | `tsm doctor` で確認し `tsm vector-fill` で再生成 |
| 索引されない | `resolve-root.sh` が想定のルートを返すか確認（git 管理下なら main を指す） |
| デーモンが落ちている | `tsm start` |
