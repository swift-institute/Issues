# Reporting a toolchain bug upstream

A suspected bug in the Swift toolchain, SwiftPM, swift-format, swift-syntax, swift-foundation or Xcode is opened here first, with the "Toolchain bug" form, which applies `upstream-candidate`. `issue-check` alone grants `upstream-ready` and `upstream-filed`, and each filing also needs Coen's explicit yes. This page covers only what the tool can't judge. For everything else, run the tool: each finding says what is missing and how to supply it.

```sh
swift build --package-path Tooling        # builds issue-reduce and issue-check
issue-check <N>                           # every field the next label demands
issue-check <N> --run                     # the same, then runs the reproduction
```

## 1. Route: whose bug is it?

Decide the owner first, from what failed rather than where it was noticed. Record the rule and its evidence in **Why this owner**.

| The failure | Owner |
|---|---|
| `swift-frontend` crashes, asserts, gives a wrong diagnostic or miscompiles; a standard-library, runtime or SourceKit defect | swiftlang/swift |
| `swift build`, `swift test` or `swift package` (resolution, manifests, planning, plugins), reproduced with the SwiftPM command-line tools | swiftlang/swift-package-manager |
| swift-format is wrong although the syntax tree it receives is right | swiftlang/swift-format |
| The syntax tree itself is wrong (check with a five-line SwiftParser program) | swiftlang/swift-syntax |
| A FoundationEssentials or FoundationInternationalization type is wrong, and it reproduces with swift-foundation itself | swiftlang/swift-foundation |
| It reproduces only with Xcode: `xcodebuild`, Xcode's toolchain but not the open-source one of the same version, an Apple SDK framework, devices, simulators, SDK back-deployment | Feedback Assistant |
| The toolchain is right: a correct diagnostic, undefined behaviour in our code, a stale build product | Our own code: fix it here |

Two tests settle most cases:

- **Open source.** Run it on the swiftly toolchain of Xcode's version. If it reproduces there, the bug is swiftlang's. If only Xcode's toolchain fails, it is Apple's.
- **Language.** Before calling a rejection a compiler bug, find the rule in the language reference or an Evolution proposal that makes the code valid.

## 2. Signature, reduction, matrix

```sh
issue-reduce in.swift --signature -- xcrun swiftc -O -wmo -c {} -o /dev/null
issue-reduce all.swift --frames 5 -o reduced.swift -- xcrun swiftc -module-name M -parse-as-library -O -wmo -c {} -o /dev/null
gh workflow run toolchain-matrix.yml -R swift-institute/Issues -f issue=<N> -f toolchains=<release>,<6.x.x-snapshot-…>,<main-snapshot-…>
```

- Reproduce from the original sources, never from a quoted log. Vary one build setting at a time and keep only those the failure needs.
- Take the signature on the toolchain you name in **Reproduces on**. A wrong-diagnostic bug adds `--require "<text>"`. A miscompile is reduced by hand with an executable that exits non-zero on the wrong result. A Windows signature has no frame names, so it always adds a `--require`.
- The reducer only deletes and simplifies. Finish by hand: move bodies to top level, replace parameters with literals, rename everything to short neutral names, and re-run the reducer after each change. Record an A/B result for every ingredient that's left.
- The matrix that counts comes from the workflow, not from a local `--matrix` run. Windows rows come only from CI. If the bug passes on main, bisect between main snapshots to find the fix, and then the most you can file is a cherry-pick request. If an older release passes, bisect the regression the same way.

## 3. Duplicates and draft

Search the owner's repository, open and closed, for issues and pull requests: use the failing function, the phase, the assertion text and the API. An open duplicate turns the filing into a comment that adds what it lacks. A closed one sends you back to the matrix. If the latest main snapshot still fails (a fix that was reverted, or one that missed this case), the filing is a request to reopen that issue: one comment with the matrix, the minimal reproduction and what shows the fix is not on main. The draft uses the owner's own template headings and stands alone: no machine-local paths, no "available on request", no Institute context.

## 4. Independent review

Give a fresh agent only the draft. It must reproduce the bug in an empty directory on the stated toolchain, then try to make it smaller. If it succeeds, take the smaller version, re-run the matrix and give the new draft to a new reviewer. Stop when a reviewer can't remove any *ingredient*: a declaration, field, call, attribute, cast, argument or flag. A respelling that removes nothing is adopted if it's shorter, but needs no further round.

## 5. Gate, then Coen

Add `upstream-ready`, and CI re-runs `issue-check --run --enforce` on a clean runner. Ask Coen about one filing at a time, with the draft and where it will go. File it exactly as drafted after his explicit yes, record the yes and the link in **Filing record**, then add `upstream-filed`.

## Workarounds in someone else's package

Treat a pull request to a third-party package the same as a filing: it needs the record and Coen's yes for that one pull request. It also qualifies only if the maintainers would want it without our compiler bug, because it is clearer, safer, faster or more correct. Show their test suite passing on every platform they support, from a fork (forking also needs Coen's yes). Use their pull-request template, and search their history for earlier discussion of the code. If it doesn't qualify, record the workaround on our issue and post nothing.

## What the gate can't check

The gate can't tell whether the routing argument is sound, whether the duplicate verdict is right, or whether the reviewer was really independent. Those rest on the record being honest, so every claim in it says whether it was observed (with the command) or inferred (and from what).
