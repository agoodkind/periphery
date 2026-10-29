# Minimal Bazel Implementation Plan

> Use `executing-plans` to implement the tasks in order. Track steps with checkbox syntax.

**Goal:** Build the fork and verify a real macOS Swift consumer scan.

**Architecture:** Retain the existing Bazel module and scan integration. Use a small independent consumer with an exact fork override. The consumer compiles real Swift sources and invokes Periphery through its public Bazel mode.

**Tech Stack:** Bazel 9.0.1, the existing rules_swift/rules_apple dependencies, Swift, and the repository's existing test tools.

**Spec:** [Minimal Bazel support](../specs/2026-10-29-bazel-minimal-design.md)

## Global constraints

Apply the constraints in the specification to every task.

## Review focus

- An incomplete index must fail rather than report a successful empty scan.
- A strict scan with unused code must return nonzero and identify the expected declaration.
- A clean fixture must return zero while preserving used declarations.
- Generated scan files and paths must remain usable from the consumer working directory.
- A consumer override must use this fork rather than silently building the upstream registry package.

## Task 1: Establish the fork build

- [ ] Install the pinned Bazel executable through the existing mise installation.
- [ ] Run `mise exec bazel@9.0.1 -- bazel build //:periphery` and record the first failure or successful executable.
- [ ] Fix only demonstrated build metadata, dependency, or API incompatibilities. Keep source version and release files under the versioning owner's control.
- [ ] Rerun the build and execute the resulting Periphery version command.
- [ ] Commit a coherent build repair when one is necessary.

Affected files depend on the demonstrated failure: `MODULE.bazel`, `MODULE.bazel.lock`, `Sources/BUILD.bazel`, and existing Bazel rules. Read each file before editing it.

## Task 2: Verify an independent consumer

- [ ] Create `Tests/BazelTests/Fixture` with a module selecting this fork, a Swift executable, a used declaration, and an unused declaration. Keep the same fixture usable as the setup example.
- [ ] Invoke the public `scan --bazel --strict` path from the consumer root and record the expected unused declaration and nonzero exit status.
- [ ] Remove the unused declaration in a temporary copy and verify a zero exit status. Confirm that the used declaration never appears as unused.
- [ ] Repair only demonstrated integration defects in `BazelProjectDriver` or the existing scan rules.
- [ ] Add the smallest regression runner using the repository's existing Swift test patterns or an explicitly executable shell entry point that runs these real commands. Preserve the original fixture after the clean-case check.
- [ ] Commit the fixture, regression, and any scoped integration repair.

## Task 3: Document and prepare review

- [ ] Add a short setup procedure with the exact fork dependency, pinned version, build command, scan command, and expected result.
- [ ] Run the real regression, relevant existing tests for changed source, formatting, and `git diff --check`.
- [ ] Review every changed file against the spec and confirm that parallel versioning files remain outside this branch.
- [ ] Open one ready PR with the command results and supporting references. Attach it to this chat.
- [ ] Preserve the reviewable branch and classify temporary task artifacts for cleanup. Mark the worktree for later cleanup when removing it would discard the requested open PR checkout.

## Required follow-through

Complete the remaining approved scope in the specification after the first milestone.
