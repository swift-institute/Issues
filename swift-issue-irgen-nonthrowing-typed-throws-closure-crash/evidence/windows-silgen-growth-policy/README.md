# Windows assertions compiler: SILGen abort on a non-throwing closure converted to nested typed throws

Observed 2026-10-20 in swift-molecules/swift-memory-allocation, commit `21a907ea`, CI run 39416803412, job "Build · Windows · release". The build enables every package trait, which brings in swift-atoms/swift-growth. The same commit built green on the same leg without the traits (run of 07:31 UTC).

## Trigger site

`swift-growth/Sources/Growth/Growth.Policy.swift:67`, in `extension Growth.Policy where Element: ~Copyable`:

```swift
@inlinable
public static var exact: Self {
    Self { $0 }
}
```

The initializer takes a function of type `(Count) throws(Error) -> Count`, where `Error` is nested in the generic `Growth.Policy`. The closure `{ $0 }` is non-throwing. This is the shape of this entry: a non-throwing closure converted to a typed-throws function whose error type is nested in a generic container, here inside an extension constrained with `~Copyable`.

## Failure

```text
Assertion failed: !getErrorResult().getInterfaceType()->hasArchetype() && "interface type of result should not contain context archetypes", file ...\swift\lib\AST\ASTContext.cpp, line 5537
While evaluating request ASTLoweringRequest(Lowering AST to SIL for module Growth)
While silgen visitDecl extension of Growth.Policy (at ...\Growth.Policy.swift:39:1)
While silgen emitFunction SIL function "@$s6GrowthAAO6PolicyVAARi_zrlE5exactADy_xGvgZ".
 for getter for exact (at ...\Growth.Policy.swift:67:23)
Exception Code: 0xC000001D
```

Toolchain: Swift 6.4.1 (swift-6.4.1-RELEASE) Windows with assertions. Exit: `error: emit-module command failed due to exception 29`.

## Relation to this entry

Same source shape as the entries above, but a different assertion in a different phase: here SILGen asserts that the error-result interface type contains no context archetypes, where the retained captures abort in IRGen on `hasErrorResult()`. Swift 6.4.1 does not have swiftlang/swift#90789. The reduction below shows that the reduced shapes compile on a main nightly that has it (Linux 6.5-dev, Swift f62414fd1d17227). The ASTContext assertion of the full swift-growth package was not rerun on that nightly.

## Reduction (21 Oct)

Reduced on the private repository `swift-institute/windows-exception-29-reproducer`, branch `main`. The `v/` files last changed at `99e4ab2f89890e764ab43f195cfd04ad7b8fddc8` and the `v2/` files at `fc11f3e10fcd3e0fd0eb2a6bd3f62df6af0e869f`; both are copied here unchanged from `main` at `7ad41ef5b24d08db52ede2c97b4fccdc3753dc04`, with `run.sh` (the Linux nightly driver) and `win-nightly.yml.txt` (the Windows snapshot attempt). Command, as in `run.sh`:

```console
swiftc -parse-as-library -module-name M -package-name p -swift-version 6 -Onone -enable-experimental-feature Lifetimes -c <file> -o out.o
```

On Windows 6.4.1 with assertions the reduced files do not stop at the ASTContext assertion. They fail in the SIL verifier run by SILGen, on the stray `$error` debug value that swiftlang/swift#90789 removes and now verifies:

```text
SIL verification failed: Operand is of an ArchetypeType that does not exist in the Caller's generic param list.: isArchetypeValidInFunction(A, F)
Verifying instruction:
   undef<$Policy<Element>.Error>
->   debug_value undef : $Policy<Element>.Error, var, name "$error", argno 2
```

Exit `-1073741795` (0xC000001D), at `-Onone` and `-O`, with and without the fleet's upcoming-feature flags.

| File | Change from `a_full.swift` | Windows 6.4.1 +assertions | Linux nightly 6.5-dev +assertions | Xcode 6.4.2 + `-sil-verify-all` (local) |
|---|---|---|---|---|
| `v/a_full.swift` | the swift-growth shape: `Policy<Element: ~Copyable>`, `Error` in an extension, `@Sendable`, `static var exact: Self { Self { $0 } }` | fails | compiles | fails |
| `v/b_copyable.swift` | plain `Element` | fails | compiles | fails |
| `v/c_explicit.swift` | closure annotated `{ x throws(Error) in x }` | compiles | compiles | compiles |
| `v/d_label.swift` | `Self(apply: { $0 })` | fails | compiles | fails |
| `v/e_errorinbody.swift` | `Error` in the struct body | fails | compiles | fails |
| `v/f_nosendable.swift` | no `@Sendable` | fails | compiles | fails |
| `v/g_func.swift` | a static func | fails | compiles | fails |
| `v/h_throwing.swift` | a closure that throws | compiles | compiles | compiles |
| `v/i_untyped.swift` | untyped `throws` | compiles | compiles | compiles |
| `v2/j_nongeneric.swift` | outer type not generic | compiles | compiles | compiles |
| `v2/k_generic_toplevel_error.swift` | `Error` at top level | compiles | compiles | compiles |
| `v2/l_generic_nested_error_freefunc.swift` | closures passed to a generic free function | type error: the variant is ill-formed (`Element` cannot be inferred) | type error | type error |
| `v2/m_generic_nested_error_local.swift` | plain generic struct, no `~Copyable`, `static var exact` | fails | compiles | fails |
| `v2/n_minimal_nonstatic.swift` | minimal: `init() { _apply = { $0 } }` | fails | compiles | fails |
| `v2/o_fix_annotated.swift` | `n` with the annotated closure | compiles | compiles | compiles |
| `v2/p_fix_ignoring_param.swift` | `n` with `{ (x: Int) throws(Error) -> Int in x }` | compiles | compiles | compiles |

Sources: CI runs 39611649862 (round 1, `v/`), 39617426261 and 39618299796 (round 2, `v2/`), 39643341814 (Linux nightly and Windows 6.4.1, both rounds); excerpts in `ci/`. The local column is this port's run on Xcode's Swift 6.4.2 (swiftlang-6.4.2.1.9, macOS arm64, no assertions) in `local-macos-6.4.2.txt`. Without `-Xfrontend -sil-verify-all` every file but `l` compiles there; with it, Xcode 6.4.2 fails on exactly the files Windows fails on, with the same verifier message, and `n_minimal_nonstatic.swift` needs no other flag. So the defect is present in Xcode 6.4.2 too, and a release toolchain can show it.

Windows main snapshot: not measured. `swift-DEVELOPMENT-SNAPSHOT-2026-10-17-a` installs on `windows-latest` (as `0.0.0+Asserts`), but `swift.exe`, `swiftc.exe` and `swift-frontend.exe` fail to start ("An error occurred trying to start process"), with and without the runtime directories on PATH; through setup-swift the install fails with `spawn UNKNOWN`. Runs 39644966448, 39645727164, 39648674520, 39649352927, 39649775973, 39650197861 and 39650672635 (`ci/win-nightly-attempts.txt`; the last one ran `win-nightly.yml.txt` as kept here).

## Workaround

Annotate the closure with its thrown type (`{ current throws(Error) in current }`, rows `c`, `o`, `p`). This landed on swift-atoms/swift-growth `main` at `c707a1a2c7579492ac22f571f434c3eaf40a8ea3` on 21 Oct (run 39620941964, Windows leg green) and was applied to swift-slab, swift-buffer-slab, swift-memory-allocation and swift-calendar-gregorian the same day (Issues#113). Coen decided not to ask for a backport of swiftlang/swift#90789; the annotations stay until the fleet moves to Swift 6.5.

## Impact

Any package whose trait-enabled graph included swift-growth failed its Windows leg (first seen: swift-memory-allocation) until the annotation landed.

## Files

- `v/`, `v2/`: the variants above.
- `run.sh`: the Linux nightly driver (it also runs `v3/`, which belongs to `swift-issue-silgen-term-verification-primary-associated-type-noncopyable`).
- `win-nightly.yml.txt`: the Windows snapshot workflow at `7ad41ef5b24d08db52ede2c97b4fccdc3753dc04`.
- `ci/`: result lines and the verifier line from the runs named above, timestamps stripped.
- `local-macos-6.4.2.txt`: this port's local run.

The Swift sources kept here verbatim are stored as `.swift.txt`, so the repository formatter and linter never rewrite them: `v/h_throwing.swift.txt`. Scripts and notes in this folder name them by their original `.swift` names; rename a file back to rerun it.
