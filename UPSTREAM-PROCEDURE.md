# Reporting a toolchain bug upstream

Every suspected bug in the Swift toolchain, SwiftPM, swift-format,
swift-syntax, swift-foundation or Xcode is recorded in this repository first.
It stays here until it is certain to be someone else's bug, reduced to a
fixed point, and in the owner's own format. It goes upstream only after
`issue-check` passes and Coen says yes to that filing.

The procedure has three labels, and a tool decides the last two:

| Label | Means | Admitted by |
|---|---|---|
| `upstream-candidate` | Suspected toolchain bug; still being routed, reduced or pinned. | The "Toolchain bug" form, on opening. |
| `upstream-ready` | Complete record; the reproduction fails on the stated toolchain today. | `issue-check --run`, locally and again in CI ([upstream-readiness.yml](.github/workflows/upstream-readiness.yml)), which removes the label and says why if anything is missing. |
| `upstream-filed` | Filed upstream with Coen's recorded yes. | `issue-check --label upstream-filed`. |

The tools are in [Tooling/](Tooling): `issue-reduce` (the reducer) and
`issue-check` (the gate). Build them with
`institute package build --package-path Tooling`.

## 1. Route: whose bug is it?

Decide the owner before reducing anything, because the owner decides what the
reproduction must look like. Work from what failed, not from where it was
noticed:

| The failure | Owner |
|---|---|
| `swift-frontend` crashes, asserts, emits a wrong diagnostic, or miscompiles; a standard-library, runtime or SourceKit defect. | swiftlang/swift |
| `swift build`, `swift test`, `swift package`: resolution, manifest evaluation, build planning, plugins. It must reproduce with the SwiftPM command-line tools, as SwiftPM's template asks. | swiftlang/swift-package-manager |
| `swift-format` formats or lints wrongly, **and** the syntax tree it receives is right. | swiftlang/swift-format |
| The syntax tree itself is wrong: SwiftParser accepts what it should reject or builds the wrong nodes (check with a five-line SwiftParser program). That makes a swift-format symptom a swift-syntax bug. | swiftlang/swift-syntax |
| Foundation behaves wrongly in a type that swift-foundation implements (FoundationEssentials, FoundationInternationalization), **and** it reproduces with swift-foundation itself (Linux, or a package built against its sources). | swiftlang/swift-foundation |
| It reproduces only with Xcode: `xcodebuild`, Xcode's toolchain but not the open-source toolchain of the same version, an Apple SDK framework (SwiftUI, UIKit, the SDK's Foundation), devices, simulators, the Xcode MCP tools, or SDK back-deployment. swiftlang/swift's CONTRIBUTING says such bugs go to Apple. | Feedback Assistant |
| The toolchain is right: the diagnostic is correct, our code has undefined behaviour, a build product was stale, a dependency was wrong. | Our own code: fix it here, never upstream |

Two tests settle most cases:

- **The open-source test.** Run the reproduction on an open-source toolchain
  (installed with swiftly) of the same version as Xcode's. If it reproduces,
  the bug is swiftlang's; if only Xcode's toolchain fails, it is Apple's.
- **The language test.** Before blaming the compiler for a rejection, find
  the rule in the language reference or an Evolution proposal that says the
  code is valid. A confusing diagnostic is not a compiler bug.

Record the rule and its evidence in **Why this owner**.

## 2. Reproduce and take the signature

Reproduce locally from the original sources, never from a quoted log. Then
take the signature, which is what every later step matches against:

```sh
issue-reduce input.swift --signature -- xcrun swiftc -O -wmo -c {} -o /dev/null
```

It prints the innermost pretty-stack phase (`While emitting IR SIL function`),
the assertion text if there is one (without file and line), and the top stack
frames by name, with signal-handler frames and addresses dropped. Paste it
unedited into **Crash signature**. For a wrong-diagnostic bug, add
`--require "<diagnostic text>"`; for a miscompile, reduce by hand with an
executable that exits non-zero on the wrong result, and say so.

Signatures depend on the kind of toolchain. Snapshots are assertions builds, so
they usually stop earlier, at an `Assertion failed:` line. Xcode's and
swift.org's release builds inline differently, so their top frames shift by
one or two. swift.org toolchains print addresses only; the tools name those
frames with `atos`. Take the record's signature on the toolchain in
**Reproduces on**: `issue-check --run` compares against it exactly. The matrix
(step 4) compares across toolchains by phase and shared Swift frames instead.

Find the build settings that matter first. Xcode's Debug configuration adds
`-DDEBUG`, `-enable-testing` and `-g`; a release build drops them. Vary one at
a time, and keep only those whose removal makes the failure go away.

## 3. Reduce mechanically

Make one file. For a single module, concatenate its sources (with
`-wmo`, a module compiled as one file behaves as one compiled as many). Then
run the reducer:

```sh
issue-reduce all.swift --frames 5 -o reduced.swift -- \
  xcrun swiftc -module-name M -parse-as-library -O -wmo -DDEBUG -c {} -o /dev/null
```

It strips comments, then repeatedly proposes the largest remaining
deletion or simplification — a statement, member, `#if` clause, attribute,
modifier, conformance, generic parameter, `where` clause, parameter, default
value, argument, `throws`/`async`, a body replaced by `{}` or
`{ fatalError() }` — and keeps it only if the command still fails with the
same signature. It then tries dropping each command argument. It stops at a
fixed point: a full pass in which no step was kept. Every run is in a fresh
directory, so no build cache can fake a reduction.

The reducer only deletes and simplifies. It cannot restructure: it cannot move
a function body to top-level code, replace a parameter with a literal, or swap
a generic wrapper for the call it wraps. On #150 it reached 64 lines, and
hand restructuring then reached 4. The independent reviewer reached 2, by
inlining the function into a top-level expression.

Then finish by hand, and re-run the reducer after each change:

- Rename what is left to short neutral names (`f`, `S`, `P`). Nothing that
  names an Institute or third-party package may remain.
- For each remaining ingredient, record an A/B result in **Reduction record**:
  A contains it and fails, B drops only it and passes.
- The result is one file and one command, with no imports beyond the
  toolchain's own. `issue-check` rejects anything else (SwiftPM bugs excepted,
  which need a package).

## 4. Pin the toolchain matrix

Run the minimal reproduction on the current release (`xcode-27.2` and the
open-source `6.4.1`), the latest release-branch snapshot and the latest main
snapshot:

```sh
swiftly list-available main-snapshot | head -3      # latest main snapshot
swiftly list-available 6.4.x-snapshot | head -3     # latest release-branch snapshot
swiftly install main-snapshot-YYYY-MM-DD
issue-reduce repro.swift --matrix 6.4.x-snapshot-YYYY-MM-DD,xcode-27.2,6.4.1,main-snapshot-YYYY-MM-DD -- swiftc -O {}
```

`--matrix` runs each toolchain (`xcode-…` through the selected Xcode, the rest
through `swiftly run … +<name>`). It takes the first toolchain's signature as
the reference and prints a table ready for **Toolchain matrix**: `reproduces`
when a toolchain crashes in the same phase with a shared Swift frame,
`different crash`, or `does not reproduce`. `issue-check` requires a main
snapshot from the last month.

A local `--matrix` run is for iterating only. The Institute treats CI as
evidence, so the table in the record comes from the
[toolchain-matrix](.github/workflows/toolchain-matrix.yml) workflow. It runs
the record's own reproduction on a hosted macOS runner and posts the table on
the issue:

```sh
gh workflow run toolchain-matrix.yml -R swift-institute/Issues \
  -f issue=150 -f toolchains=6.4.x-snapshot-2026-10-20,xcode-27.2,6.4.1,main-snapshot-2026-10-17
```

- **Fails on main:** a new issue (or a comment on an open duplicate).
- **Passes on main:** do not file a new issue. Bisect between main snapshots
  (`swiftly list-available main-snapshot`, binary search, one install each)
  to the first passing snapshot, then find the fix: `gh search prs` with the
  failing function or pass name, or `git log` of swiftlang/swift between the
  two snapshots' revisions. If the fix is on main but not on the release
  branch, the most that applies is a **Cherry-pick request on the fixing pull
  request**. Otherwise, **Do not file**.
- **Regressed:** if an older release passes, bisect the same way and record
  the range in **Regression range**.

## 5. Search for duplicates

Before drafting, search the owner's repository, open and closed issues and
pull requests (`gh search` covers both states by default), with the failing
function, the phase, the assertion text, and the affected API or package:

```sh
gh search issues "reemitAsUnsubstituted" --repo swiftlang/swift --limit 30
gh search prs    "reemitAsUnsubstituted" --repo swiftlang/swift --limit 30
gh pr list --repo swiftlang/swift --search "<issue number> in:body" --state all
```

Paste the commands, the date, the candidates considered and why each is or
is not the same bug, and a closing `Verdict:` line into **Duplicate search**.
An open duplicate turns the action into a comment that adds what it lacks
(usually the minimal reproduction or the matrix); a closed one sends you back
to step 4.

## 6. Draft in the owner's format

Write **Upstream draft** with the owner's own template headings, in their
order. `issue-check` compares them exactly:

| Owner | Template | Headings |
|---|---|---|
| swiftlang/swift, crash | `crash-report.yml` | Description, Reproduction, Stack dump, Expected behavior, Environment, Additional information |
| swiftlang/swift, other | `bug-report.yml` | Description, Reproduction, Expected behavior, Environment, Additional information |
| swiftlang/swift-package-manager | `BUG_REPORT.yml` | Description, Expected behavior, Actual behavior, Steps to reproduce, Swift Package Manager version/commit hash, Swift & OS version |
| swiftlang/swift-syntax | `BUG_REPORT.yml` | Description, Steps to Reproduce |
| swiftlang/swift-foundation | `bug_report.md` | Describe the bug, To Reproduce, Expected behavior, Configuration, Regression information, Additional context |
| swiftlang/swift-format | none | Description, Reproduction, Expected behavior, Actual behavior, Environment |
| Feedback Assistant | its form | Title, Description, Steps to reproduce, Expected results, Actual results, Configuration |

The draft contains the minimal reproduction and its command verbatim, the
stack dump that shows the signature's frames, and the matrix. It contains no
machine-local paths, no "available on request", and no Institute context the
reader would need to follow it. A cherry-pick request or a comment needs no
fixed headings, but must still contain the reproduction and command.

## 7. Independent review

Give a fresh agent, with no other context, only the draft. It must reproduce
the failure in an empty directory on the stated toolchain, and then try to
make the reproduction smaller. Record its verdict as
`Independent review: reproduced on <toolchain>; <what it tried>; nothing left
to remove` in **Reduction record**. If it shrinks the reproduction, take the
smaller one, go back to step 4, and give the new draft to a new reviewer.

The loop stops when a reviewer can remove no *ingredient*: a declaration,
field, call, attribute, cast, argument or flag whose removal still fails the
same way. A respelling that removes nothing (renaming, `Void` for `()`,
another literal) is adopted if shorter, but does not need another round. On
#150 it took three rounds. The first reviewer took 4 lines to 2 by inlining the
function. The second only respelled five fields as one tuple-typed field. The
third found nothing to remove.

## 8. Gate, then Coen

```sh
issue-check 150 --run                      # locally: every field, then the run
gh issue edit 150 --add-label upstream-ready
```

Adding `upstream-ready` (or editing an issue that has it) runs the same check
in CI on a clean macOS runner, with the stated toolchain installed by swiftly.
If anything is missing or the reproduction no longer fails, CI removes the
label and says why.

Only then ask Coen, one filing at a time, with the draft and the target.
After his explicit yes, file it exactly as drafted, then fill **Filing
record** with `Approved by Coen: <date>` and his words, and the upstream link,
and add `upstream-filed`; `issue-check --label upstream-filed` checks both.

## Workarounds in someone else's package

A toolchain bug sometimes has a source-side workaround in a third-party
package. #150's is a one-line change in swift-issue-reporting. The
package's maintainers are not the bug's owner, so a pull request to them goes
through the same record and Coen's per-filing yes. It must also pass one more
test: **it improves their code on its own merits**, not just around our
compiler. It qualifies only if, without the toolchain bug, the maintainers
would still want it, because it is clearer, safer, faster or more correct. A
workaround for a bug already fixed on main, or for a configuration the package
does not support, does not qualify.

If it qualifies, the record also needs:

- the package's own test suite passing with the change, on CI in a fork (a
  fork is a public action, so it needs Coen's yes too);
- every platform the package supports compiling with the change;
- the package's pull-request template, or its CONTRIBUTING order;
- a search of the package's issues and pull requests for earlier discussion
  of the code being changed.

If it does not qualify, record the workaround on the Institute issue, for our
own pins or forks, and post nothing.

## What the gate does not check

`issue-check` checks that each part is present and consistent and that the
reproduction still fails. It cannot tell whether a routing argument is sound,
whether a duplicate verdict is right, or whether a reviewer was really
independent. Those rest on the record being honest, which is why every claim
in it says how it was obtained: observed (run, with the command) or inferred
(and from what).
