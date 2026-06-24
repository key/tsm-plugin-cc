# Changelog

## 0.14.0 (2026-06-24)


### Features

* **dict-update:** document the top-level `tsm synonym` commands (`add` / `import`),
  replacing the removed `tsm dict synonym sync`. Requires tsm >= 0.7.0, where the
  `tsm synonym` split lands ([the-space-memory#247](https://github.com/key/the-space-memory/pull/247)).

## [0.13.0](https://github.com/key/claude-code-plugins/compare/the-space-memory-v0.12.2...the-space-memory-v0.13.0) (2026-06-22)


### Features

* **the-space-memory:** add dict-update skill for dictionary curation ([#34](https://github.com/key/claude-code-plugins/issues/34)) ([924ef08](https://github.com/key/claude-code-plugins/commit/924ef08e59086aac01f9e1f46e0aa2d1c8f44979))

## [0.12.2](https://github.com/key/claude-code-plugins/compare/the-space-memory-v0.12.1...the-space-memory-v0.12.2) (2026-06-17)


### Bug Fixes

* **the-space-memory:** resolve tsm root from git for worktree support ([#29](https://github.com/key/claude-code-plugins/issues/29)) ([22c4574](https://github.com/key/claude-code-plugins/commit/22c4574f9ca151a2174d2f857e8f260cfed39d37))

## [0.12.1](https://github.com/key/claude-code-plugins/compare/the-space-memory-v0.12.0...the-space-memory-v0.12.1) (2026-06-17)


### Bug Fixes

* quote ${CLAUDE_PLUGIN_ROOT} in hook commands ([#17](https://github.com/key/claude-code-plugins/issues/17)) ([c7f47c4](https://github.com/key/claude-code-plugins/commit/c7f47c4ed659338136411ec9a3b4b4753f3cdf97))
* **the-space-memory:** make hook paths portable and stop logging raw prompts ([#14](https://github.com/key/claude-code-plugins/issues/14)) ([926d59e](https://github.com/key/claude-code-plugins/commit/926d59e72b2b5adf9406b345957a81843faed1ed))

## [0.12.0](https://github.com/key/claude-code-plugins/compare/the-space-memory-v0.11.0...the-space-memory-v0.12.0) (2026-04-30)


### ⚠ BREAKING CHANGES

* /the-space-memory:setup no longer exists.

### Features

* scaffold marketplace with the-space-memory and current-datetime plugins ([#1](https://github.com/key/claude-code-plugins/issues/1)) ([15d7aff](https://github.com/key/claude-code-plugins/commit/15d7afff22717016452e3b2ae66d072cf18d662d))
