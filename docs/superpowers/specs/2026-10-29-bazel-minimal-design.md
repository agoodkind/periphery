# Minimal Bazel support

Build the Periphery fork with Bazel and scan a real Swift executable on macOS. A consumer selects a published fork release. The scan does not report declarations the executable uses. It reports a deliberately unused declaration and returns a failure status under `--strict`. It returns success when that declaration is removed.

## Approach

Reuse the existing module, build targets, project driver, and scan rule. Fix only failures demonstrated by the build and consumer scan. A separate integration fixture supplies the regression and the setup example.

The user approved restoring the existing integration and then requested a bounded first milestone. Replacing it with a separate rules package would require another maintained project. The first milestone proves the build and scan before the CI and publication changes.

## Constraints

- Work in branch `bazel-minimal` and its separate checkout.
- Use Bazel `9.0.1`, already pinned by the repository, unless a demonstrated compatibility failure requires a version change.
- Coordinate shared dependency/module versions with the parallel release-versioning owner. Preserve its release scripts, release workflows, test workflow, version stamping, and published tags.
- Preserve the current module name and version for local commit-based selection.
- Use the public `periphery scan --bazel` entry point and real compiler index records. Do not replace scanning with fixture-only output checks or mock compiler data.
- Keep internal SwiftPM/Xcode behavior outside the change unless the Bazel path proves a shared defect.

## First milestone

Record the compiler and Bazel versions, successful fork build, exact consumer commands, findings, and exit statuses. Keep an automated regression that exercises the real scan and unused-code control. Provide a short reproducible setup example and one focused PR. The PR remains available for review; this goal does not require merge or release.

## Full approved scope

After the first milestone, verify Swift targets on Linux and macOS and Apple application targets on macOS. Add repeatable CI checks and publish tested fork versions to Bazel's package catalog. These remain required outcomes of the approved setup. Coordinate release and module metadata with the parallel versioning owner before publication changes.
