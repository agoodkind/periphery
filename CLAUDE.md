# CLAUDE.md

Fork of Periphery kept working with current Xcode/Swift toolchains. Process (issue/PR/version, CHANGELOG, release, tap, external contributions): `CONTRIBUTING.md` § Fork process.

- Commits and PRs in English, Conventional Commits with a scope; conversation with the owner in French.
- Work in a worktree under `.worktrees/`, never push to `master` directly.
- Never touch `CHANGELOG.md` in a fix PR; only the release commit does.
- Tests: `swift test --filter <TestCase>`; the full suite runs under the shared build lock (`~/dev/HomeBank/Tools/with_heavy_lock.py`).
- Lint: `swiftformat --lint .` and `swiftlint lint --strict` (versions pinned in `.mise.toml`).
