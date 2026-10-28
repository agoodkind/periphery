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

## Fork process

- One issue = one PR = one patch version.
- The PR body must contain `Closes #N`, otherwise the issue stays open after the merge.
- Never edit `CHANGELOG.md` in a fix PR (it conflicts on every merge). Only the release commit fills it.
- Release commit `chore(release): X.Y.Z`: move the `## master` section into `## X.Y.Z (date)` and leave an empty `## master` (same template as the previous release); bump `MODULE.bazel` version with `Version.swift`.
- Release steps: merge, tag `X.Y.Z`, `gh release create`, update the formula in the `tiny-earth-moon/homebrew-tap` tap (tag tarball url + sha256), then update the HomeBank and Blendies Brewfiles.
- External contributions: cherry-pick keeping the original author, add a `Co-authored-by` trailer, and thank the contributor on the original PR.
- CI (`.github/workflows/test.yml`): macOS job (build, full tests, swiftformat, swiftlint) and a Bazel build job; both must be green before merging.
