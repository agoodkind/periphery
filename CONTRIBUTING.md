# Contributing

This fork keeps Periphery building and working with current Xcode/Swift toolchains. There is no functional roadmap: bug reports (with a minimal project) and pull requests are welcome, feature requests should come as a PR.

## Build

```
swift build -c release --product periphery
.build/release/periphery version
```

## Test

The full suite is long. Run the tests relevant to your change:

```
swift test --filter <TestCaseName>
```

## Commits

Conventional Commits with a scope, in English: `fix(indexer): ...`, `build: ...`, `docs: ...`, `chore(fork): ...`. One logical change per commit.
