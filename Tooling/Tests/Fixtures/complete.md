### Owner

swiftlang/swift (compiler, standard library, runtime, SourceKit)

### Why this owner

`swift-frontend` crashes during IRGen (`While emitting IR SIL function`), on the open-source swift.org toolchains (6.3.3, 6.4.1, the 6.4.x and main snapshots) as well as Xcode's, with a 2-line file that imports nothing: the compiler rule, not Feedback Assistant (it is not Xcode-only), and not our code (the source is valid Swift; swift-issue-reporting compiles at `-Onone`). Observed 2026-10-22.

### Upstream action

Cherry-pick request on the fixing pull request

### Crash signature

```text
crashed: yes
assertion: (arg->getType().isObject())
phase: While emitting IR SIL function
frame 0: emitApplyArgument
frame 1: IRGenSILFunction::visitFullApplySite
frame 2: IRGenSILFunction::visitSILBasicBlock
frame 3: IRGenSILFunction::emitSILFunction
```

Taken on 6.4.x-snapshot-2026-10-20, an assertions build, with `issue-reduce repro.swift --frames 4 --signature -- swiftly run swiftc -O {} +6.4.x-snapshot-2026-10-20`. The pretty-stack function is `@main`. Release builds, which have no assertions, crash later on the same path: Xcode 27.2 in `llvm::MDAttachments::insert ← Value::setMetadata ← IRBuilderBase::CreateCast ← irgen::reemitAsUnsubstituted ← emitApplyArgument`, and 6.4.1 in `CastInst::Create ← CreateCast ← reemitAsUnsubstituted ← emitApplyArgument`.

### Toolchain matrix

| Toolchain | `swiftc --version` | Result |
|---|---|---|
| xcode-27.2 | Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1) | reproduces |
| 6.4.1 | Apple Swift version 6.4.1 (swift-6.4.1-RELEASE) | reproduces |
| 6.3.3 | Apple Swift version 6.3.3 (swift-6.3.3-RELEASE) | reproduces |
| 6.4.x-snapshot-2026-10-20 | Apple Swift version 6.4.4-dev (LLVM a52029da5113665, Swift 90b3468f3de7d1f) | reproduces (asserts: (arg->getType().isObject())) |
| main-snapshot-2026-07-11 | Apple Swift version 6.5-dev (LLVM 6f2057ffeafd4c6, Swift 83c32e02f71e4bb) | reproduces (asserts: (arg->getType().isObject())) |
| main-snapshot-2026-10-17 | Apple Swift version 6.5-dev (LLVM 9b3700c0bd7ce7a, Swift f62414fd1d17227) | does not reproduce |

Observed 2026-10-22 on macOS 27.2 arm64 with `issue-reduce repro.swift --matrix 6.4.x-snapshot-2026-10-20,xcode-27.2,6.4.1,6.3.3,main-snapshot-2026-07-11,main-snapshot-2026-10-17 -- swiftc -O {}`. main-snapshot-2026-10-17 compiles it (exit 0).

### Regression range

Not a regression within 6.4: 6.3.3 crashes too, and swiftlang/swift#91794 reported it on 6.3.3. Fixed on main by swiftlang/swift#93047 (commit d87ff8a5d062c9e996d9539a24aa00c209a3ab9d, merged 2026-10-08). Observed with `gh api repos/swiftlang/swift/compare/d87ff8a5…<revision>`: the commit is an ancestor of main-snapshot-2026-10-17's Swift revision f62414fd1d17227 (status `ahead`), and is not in 6.4.x-snapshot-2026-10-20's revision 90b3468f3de7d1f (status `diverged`). No bisection was needed, because the fix commit is known and its containment was checked directly. `gh api "repos/swiftlang/swift/commits?sha=release/6.4.x&path=lib/IRGen/LoadableByAddress.cpp&since=2026-09-01T00:00:00Z"` returns nothing. As a control, the same query from 2026-01-01 lists the 2026-08-06 commit 967232150f first, so release/6.4.x has no cherry-pick of the fix under any SHA.

### Duplicate search

Run 2026-10-22 against swiftlang/swift (gh search covers open and closed):

```sh
gh search issues "reemitAsUnsubstituted" --repo swiftlang/swift --limit 15
gh search issues "MDAttachments::insert" --repo swiftlang/swift --limit 15
gh search issues "setMetadata CreateCast" --repo swiftlang/swift --limit 15
gh search issues "emitApplyArgument crash" --repo swiftlang/swift --limit 15
gh search issues "withExpectedIssue crash" --repo swiftlang/swift --limit 15
gh search issues "_withKnownIssue IRGen" --repo swiftlang/swift --limit 15
gh search prs "reemitAsUnsubstituted" --repo swiftlang/swift --limit 15
gh search prs "LoadableByAddress bit casts" --repo swiftlang/swift
gh pr list --repo swiftlang/swift --search "91794 in:body" --state all
gh pr list --repo swiftlang/swift --search "LoadableByAddress" --state all --limit 30
gh pr list --repo swiftlang/swift --base release/6.4.x --search "LoadableByAddress" --state all
```

- swiftlang/swift#91794 (closed, completed 2026-10-08): "IRGen crash (reemitAsUnsubstituted → llvm::CastInst::Create) compiling swift-issue-reporting's _recordIssue under -O -enable-testing -D DEBUG", on 6.3.3. The same bug: same package, same flags, same frames.
- swiftlang/swift#93047 (merged to main 2026-10-08): "Fix LoadableByAddress for bit casts to function types taking large loadable types". Its body says "Fixes https://github.com/swiftlang/swift/issues/91794", and its title describes the reduced trigger exactly.
- No pull request against release/6.4.x carries #93047. The three [6.4] LoadableByAddress pull requests found (#91289, #90579, #88941) are other fixes.
- The other hits (#88901, #57539, #93244, #50234, #75577, #49862, #49955) are unrelated crashes that share only common frame names.

Verdict: a duplicate of #91794, already fixed on main by #93047, and not on release/6.4.x. Do not file a new issue. Ask on #93047 for a cherry-pick to release/6.4.x.

### Minimal reproduction

```swift
struct L { var a = (0, 0, 0, 0, 0) }
unsafeBitCast(0, to: (@convention(thin) (L) -> ()).self)(L())
```

```sh
swiftc -O repro.swift
```

### Reproduces on

6.4.x-snapshot-2026-10-20

### Reduction record

- **Mechanical.** The 23 files of swift-issue-reporting b23bb44's IssueReporting target were concatenated into one 89,799-byte file. It reproduces with `xcrun swiftc -module-name IssueReporting -package-name P -parse-as-library -swift-version 6 -O -wmo -DDEBUG -c {} -o /dev/null`. `issue-reduce all.swift --frames 5` took it to 1,643 bytes (64 lines) in 175 steps, 1,010 runs and 3 passes, ending at a fixed point (the last pass kept nothing) after 683 s. It also reduced the command to `xcrun swiftc -O`: removing the `#if DEBUG` clauses made `-DDEBUG` unnecessary.
- **By hand.** The `dlsym` lookup, the generic `unsafeBitCast` wrapper and the `String` fields were each replaced by the smallest equivalent, and the reducer was re-run after each change. `issue-reduce repro.swift --frames 5` on the 4-line result kept nothing more from the source (2 passes, fixed point) and only dropped `-c -o /dev/null`.
- **A/B results, each observed on Xcode 27.2 with only the named change:**
  - `-Onone` instead of `-O`: compiles. `-Osize`: crashes.
  - Four `Int` fields instead of five (32 bytes instead of 40): compiles. Five `Int`s, or three `String`s, crash; two `String`s compile. Inferred: the trigger is a struct above LoadableByAddress's large-loadable threshold.
  - Thick `(L) -> Void` instead of `@convention(thin)`: compiles.
  - Taking the cast without calling it: compiles.
  - A tuple of five `Int`s instead of the struct: compiles.
  - `Int` instead of `UnsafeRawPointer` as the source: crashes. The pointer is kept because it is the real-world shape.
  - Returning `L` from a thin `() -> L` instead of passing it: crashes, but with a different signature, so it is not this bug.
- **Independent review, three rounds**, each by a new agent given only the draft, in an empty directory:
  - Round 1, on the 4-line draft: reproduced on Xcode 27.2, 6.4.1, 6.4.x-snapshot-2026-10-20 and main-snapshot-2026-10-17 (compiles), plus 6.3.3 and main-snapshot-2026-07-11, all as in the matrix. Removed an ingredient: the function, by inlining the call into one top-level expression (2 lines). Asked for a link to the package code, the signal per row, and a note that swift.org stacks are unsymbolized.
  - Round 2, on the 2-line draft: reproduced on the four named toolchains. Found only a respelling: five fields → one tuple-typed field with a default, `L()` → 99 bytes from 126. Asked that the cherry-pick check cover other SHAs, that the swift-issue-reporting claim be shown, and that frame omissions and the source revision of the line numbers be stated. All adopted. `issue-reduce` on the respelled file keeps nothing (fixed point).
  - Independent review: reproduced (round 3, a new agent given only the final draft, in an empty directory) on all six matrix toolchains, each as stated, including the -Onone, four-element and thick controls and the large-result variant. Nothing left to remove: no ingredient can go (the struct, the call, the argument, `@convention(thin)` or `-O` each make it compile), and only respellings remain (five fields, a memberwise init, `.init()`). It found that a direct `@convention(thin)` reference without the cast crashes elsewhere (`LoadableByAddress::recreateSingleApply`), still on main: a separate candidate. Its notes (merge commit cc997ce, the `-enable-testing` per-file mode, the library's real parameter list, the Xcode build number) were adopted.

### Upstream draft

Comment on swiftlang/swift#93047 (Fix LoadableByAddress for bit casts to function types taking large loadable types):

---

Could this be cherry-picked to `release/6.4.x`? The crash it fixes (#91794) is still present in Swift 6.4.2 as shipped in Xcode 27.2, and in the latest 6.4.x snapshot. `release/6.4.x` has had no commit to `lib/IRGen/LoadableByAddress.cpp` since 2026-08-06.

It breaks optimised builds that define `DEBUG` of anything that depends on swift-issue-reporting, which swift-dependencies and TCA do. That module's `DEBUG`-only Swift Testing shims bit-cast a `dlsym` result to a thin function whose parameters include its own `SourceLocation`, a struct of two `String`s and two `Int`s that mirrors Swift Testing's, for example `(Any?, Any, SourceLocation) -> Issue` ([SwiftTesting.swift#L32-L38](https://github.com/pointfreeco/swift-issue-reporting/blob/b23bb4493c439d3e05152bc167014235ba3d47fc/Sources/IssueReporting/Internal/SwiftTesting.swift#L32-L38)). At b23bb44, its IssueReporting target crashes with `-O -wmo -DDEBUG`, and per file with `-O -enable-testing -DDEBUG` as in #91794. It compiles with `-O -wmo` alone.

#### Reproduction

```swift
struct L { var a = (0, 0, 0, 0, 0) }
unsafeBitCast(0, to: (@convention(thin) (L) -> ()).self)(L())
```

```sh
swiftc -O repro.swift
```

It compiles at `-Onone`, with a four-element tuple instead of five, and with a thick function type instead of `@convention(thin)`.

#### Matrix

| Toolchain | `swiftc --version` | Result |
|---|---|---|
| Xcode 27.2 (27B48) | Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1) | crashes, signal 11 |
| 6.4.1 release | Apple Swift version 6.4.1 (swift-6.4.1-RELEASE) | crashes, signal 11 |
| 6.3.3 release | Apple Swift version 6.3.3 (swift-6.3.3-RELEASE) | crashes, signal 11 |
| 6.4.x-snapshot-2026-10-20 | Apple Swift version 6.4.4-dev (LLVM a52029da5113665, Swift 90b3468f3de7d1f) | assertion, signal 6 |
| main-snapshot-2026-07-11 | Apple Swift version 6.5-dev (LLVM 6f2057ffeafd4c6, Swift 83c32e02f71e4bb) | assertion, signal 6 |
| main-snapshot-2026-10-17 | Apple Swift version 6.5-dev (LLVM 9b3700c0bd7ce7a, Swift f62414fd1d17227) | compiles |

The 2026-10-17 main snapshot's revision f62414fd descends from this PR (commit d87ff8a5, merged as cc997ce0).

A large result through a thin function crashes too:

```swift
let l = unsafeBitCast(0, to: (@convention(thin) () -> L).self)()
```

On Xcode 27.2 it gets signal 11 in `emitCastToSubstSchema` ← `CallEmission::emitToExplosion`. On the 6.4.x snapshot it fails `origConv.getNumSILArguments() == args.size()` in `visitFullApplySite`. It compiles on the 2026-10-17 main snapshot, so the same cherry-pick may cover it; we have not bisected it separately.

#### Stack dump

Frame numbers are as printed on this machine.

6.4.x-snapshot-2026-10-20 (revision 90b3468f). swift.org toolchains print addresses only, so these frames were symbolized with `atos`. Omitted: frames 0–7 (the signal handler, `abort` and the assertion) and frames 13 and up (the request evaluator and `main`).

```text
Assertion failed: (arg->getType().isObject()), function emitApplyArgument, file IRGenSIL.cpp, line 3473.
3.	While evaluating request IRGenRequest(IR Generation for file "repro.swift")
4.	While emitting IR SIL function "@main".
#8  emitApplyArgument((anonymous namespace)::IRGenSILFunction&, swift::SILValue, swift::SILType, swift::irgen::Explosion&, swift::SILInstruction*, unsigned int, bool)
#9  (anonymous namespace)::IRGenSILFunction::visitFullApplySite(swift::FullApplySite)
#10 (anonymous namespace)::IRGenSILFunction::visitSILBasicBlock(swift::SILBasicBlock*)
#11 (anonymous namespace)::IRGenSILFunction::emitSILFunction()
#12 swift::irgen::IRGenModule::emitSILFunction(swift::SILFunction*)
```

Xcode 27.2 (Swift 6.4.2). Omitted: frames 0–3 (the signal handler), 5 (a repeat of 4), and 11 and up:

```text
4.	While emitting IR SIL function "@main".
4  llvm::MDAttachments::insert(unsigned int, llvm::MDNode&)
6  llvm::Value::setMetadata(unsigned int, llvm::MDNode*)
7  llvm::IRBuilderBase::CreateCast(llvm::Instruction::CastOps, llvm::Value*, llvm::Type*, llvm::Twine const&, llvm::MDNode*, llvm::FMFSource)
8  swift::irgen::reemitAsUnsubstituted(swift::irgen::IRGenFunction&, swift::SILType, swift::SILType, swift::irgen::Explosion&, swift::irgen::Explosion&)
9  emitApplyArgument((anonymous namespace)::IRGenSILFunction&, swift::SILValue, swift::SILType, swift::irgen::Explosion&, swift::SILInstruction*, unsigned int, bool)
10 (anonymous namespace)::IRGenSILFunction::visitFullApplySite(swift::FullApplySite)
```

#### Environment

macOS 27.2 on arm64 (Apple silicon), with the toolchains in the matrix.

### Readiness

- [X] The reproduction is one file and one command, and uses no Institute code or third-party package.
- [X] The matrix was run with the minimal reproduction, on toolchains installed from swift.org or the stated Xcode.
- [X] The duplicate search covered open and closed issues and pull requests in the owner's repository.
- [X] An independent reviewer reproduced it from the draft alone and found nothing left to remove.

### Filing record

_No response_
