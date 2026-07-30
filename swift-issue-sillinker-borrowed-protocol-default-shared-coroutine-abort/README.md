# `MandatorySILLinker` aborts on a bodiless shared `.read` coroutine from a defaulted `@_borrowed` requirement

Upstream: [swiftlang/swift#90406](https://github.com/swiftlang/swift/issues/90406) — open,
`crash` / `triage needed`, filed 2026-07-05. **Not ours; do not file a duplicate.**

## Symptom

`swift-frontend` aborts (signal 6) compiling a module that adds its own conformance
to a protocol imported from another module:

```
Assertion failed: ((!hasSharedVisibility(F->getLinkage()) || F->hasForeignBody())
  && "cannot deserialize shared function"),
  function deserializeAndPushToWorklist at Linker.cpp:88.

While evaluating request ExecuteSILPipelineRequest(Run pipelines
  { Mandatory Diagnostic Passes + Enabling Optimization Passes } on SIL for Consumer)
While running pass #66 SILModuleTransform "MandatorySILLinker".
```

On an assertions-enabled toolchain the same malformed function is caught earlier,
during `ASTLoweringRequest`, and the message names it outright:

```
SIL verification failed: public/package/shared function must have a body:
  F->isDefinition() || F->hasForeignBody()
In function:
// MyVector.subscript.read
sil shared [serialized] @$s4LibA8MyVectorPAAEy7ElementQzSicir
  : $@yield_once @convention(method) <τ_0_0 where τ_0_0 : MyVector>
    (Int, @in_guaranteed τ_0_0) -> @yields @in_guaranteed τ_0_0.Element
```

That is the mechanism in one line: the `.read` **coroutine** for the protocol
extension's default implementation is emitted `sil shared [serialized]` with **no
body**, and the importing module's mandatory SIL linker cannot deserialize it.

## Trigger

Three ingredients in the **defining** module, plus a conformance in the importing
module. Each is load-bearing — removing any one compiles clean:

1. a **coroutine-accessor** requirement on the protocol: `@_borrowed` written
   directly, **or** inherited by refining a stdlib protocol whose requirement is
   already `@_borrowed` (`Collection.subscript(position:)`) — no `@_borrowed`
   appears in that variant's source at all;
2. a **protocol extension in the defining module** supplying that requirement's
   default implementation;
3. **at least one conforming type in the defining module**;
4. and, in the importing module, **its own conformance** to the protocol.

The defining module always compiles. Only the importing module aborts.

`Sources/Reproducer/LibA.swift.txt` + `Sources/Reproducer/Consumer.swift.txt` are the
`@_borrowed` form. The `Collection`-refining form is recorded in the upstream issue and
was A/B-confirmed here on 6.3.3 aarch64 Linux (crashes; and clean once ingredient 3
is removed).

## What is *not* required

Worth stating explicitly, because this signature was first observed in a
release + `-O` + `-enable-default-cmo` + whole-module CI configuration and that
framing is misleading:

- **not** optimization-dependent — fires at `-Onone`, plain `swiftc -c`;
- **not** cross-module-optimization dependent — no `-enable-default-cmo` anywhere;
- **not** whole-module dependent — fires with `-primary-file`;
- **not** architecture-dependent — see the matrix;
- **not** SwiftPM-dependent — two bare `swiftc` invocations.

It *is* inherently **cross-module**: two frontend invocations, the second importing
the first's `.swiftmodule`. That is why the harness drives `swiftc` out of process.

## Toolchain × architecture matrix

Every row `swift --version`-confirmed. `abort` = signal 6.

| Toolchain | Host | Result |
|---|---|---|
| 6.3.3-RELEASE (swiftly) | macOS arm64 | **abort** — `MandatorySILLinker`, `Linker.cpp:88` |
| 6.3.3-RELEASE (`swift:6.3.3` container) | Linux aarch64 | **abort** — `MandatorySILLinker`, `Linker.cpp:88` |
| 6.3.3-RELEASE (`swift:6.3.3` container) | Linux x86_64 | **abort** — `MandatorySILLinker`, `Linker.cpp:88` |
| Apple Swift 6.4 (Xcode) | macOS arm64 | **abort** — `MandatorySILLinker`, `Linker.cpp:88` |
| 6.4.x-snapshot-2026-07-23 (+assertions) | macOS arm64 | **abort** — earlier, SIL verifier |
| main-snapshot-2026-07-11 (+assertions) | macOS arm64 | **abort** — earlier, SIL verifier |

**Not fixed on any tested toolchain, including 6.5-dev `main`.** Both assertions-enabled
snapshots reject it during SIL lowering rather than at link time — an earlier and
clearer diagnosis of the same defect, not a fix. Architecture is not a variable:
aarch64 and x86_64 Linux, and arm64 macOS, all abort identically (upstream #90406 also
reports Windows and WSL).

## Reproducing by hand

```sh
cd Sources/Reproducer
mkdir -p /tmp/repro && cp LibA.swift.txt /tmp/repro/LibA.swift \
                    && cp Consumer.swift.txt /tmp/repro/Consumer.swift
cd /tmp/repro
swiftc -emit-module -emit-library -module-name LibA LibA.swift   # exit 0, always
swiftc -c -I . Consumer.swift                                    # abort, signal 6
```

## Harness

Two targets, per the repository convention:

- `…-Tests` wraps the out-of-process probe in
  `withKnownIssue("swiftlang/swift#90406", …)` with `when: { true }`. Green while the
  bug fires; **red the moment the importing module compiles cleanly** — that flip is
  the fix-detection signal.
- `…-Repro` is the same probe standalone: exit `1` = fires, `0` = fixed, `2` =
  inconclusive.

Both treat the **defining** module's clean build as the probe's positive control: if
that invocation fails, the environment is at fault and the result is inconclusive
rather than negative.

Verified in a mirror package on 6.3.3 (macOS arm64): `swift test` → *passed with 1
known issue*; standalone probe → exit 1. Flip semantics verified by deleting
ingredient 3 from `LibA.swift.txt`, which makes the probe report `false` and the test
go red with *"Known issue was not recorded"*.

## Institute exposure

Found while characterizing the fourth crash signature on
swift-institute/Issues#58 — a `Products_Live` (`swift-foundations/swift-products`) abort
with this exact assertion, first seen under release + `-O` + `-enable-default-cmo` +
whole-module on Linux x86_64.

That production instance was reproduced at canonical `main` in the `swift:6.3.3`
container on Linux **aarch64**, with the identical assertion, the identical pass
(`MandatorySILLinker`, pass #309) and the identical pipeline stage. Re-running that exact
failing frontend invocation with `-enable-default-cmo` removed, with `-Onone` instead of
`-O`, and with both removed **aborts identically in all four variants** — so the
consuming module's optimization and cross-module-optimization flags are not part of the
trigger. The malformed `sil shared [serialized]` function is already present in a
dependency's `.swiftmodule` before the consuming module is compiled at all, which is
exactly the situation this reduction models.

The same production target also aborts identically when built from the commit *before*
the source change that Issues#58 could not rule out, so the abort is not source-change
induced.

The ecosystem-relevant reading is ingredient 1's second form: **any** protocol that
refines a stdlib collection protocol, defaults the inherited subscript in an
extension of its own module, has a conformer in that module, and is conformed to
again by an importing module, hits this — with no `@_borrowed` in sight.
