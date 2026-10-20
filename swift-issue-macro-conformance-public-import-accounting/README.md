# Swift: macro-generated public conformance doesn't count toward `public import` accounting

**Classification:** access-level import diagnostics. A correct module fails to compile
under `treatAllWarnings(as: .error)`, with no import spelling that satisfies both checks.

An attached extension macro adds a public conformance whose witness names a type from a
second module. The client cannot import that module either way:

- `public import Lib`: the expansion's use is not counted, so the import is reported unused:

  ```
  error: public import of 'Lib' was not used in public declarations or inlinable code [UnusedImportAccess]
  ```

- `import Lib` (internal under `InternalImportsByDefault`): the expansion does need it public:

  ```
  macro expansion @Marked:2:22: error: type alias cannot be declared public because its underlying type uses an internal type
  note: module 'Lib' imported as 'internal' from 'Lib' here
  ```

Writing the same extension by hand with `public import Lib` compiles cleanly.

## Reproducer

One package, staged by [`Sources/Reproducer/main.swift`](Sources/Reproducer/main.swift)
from [`Sources/Reproducer/Fixture`](Sources/Reproducer/Fixture) (it fetches swift-syntax):

- `Lib`: `public struct Wrapper`.
- `Marker`: `protocol Marked { associatedtype Storage }` and `@Marked(_:)`, an extension
  macro from `MarkerMacros` that expands to `extension T: Marker.Marked { public typealias Storage = <argument> }`.
- `Client`: `@Marked(Lib.Wrapper.self) public struct Paper {}`, built with
  `InternalImportsByDefault`, `MemberImportVisibility` and `treatAllWarnings(as: .error)`.

```sh
swift run swift-issue-macro-conformance-public-import-accounting-Repro
```

Expected: `public import Lib` builds, since the public conformance uses `Lib.Wrapper`.
Observed on Apple Swift 6.4 (swiftlang-6.4.0.34.1, arm64 macOS 27): both errors above.

## Where it was found

swift-sql's `@Table` with `@Column(as: SQLite::JSONRepresentation<[String]>.self)` from
swift-sqlite: `public import SQLite` is reported unused, while `import SQLite` fails in the
`@Table` expansion ("cannot use conformance of 'JSONRepresentation<QueryOutput>' to
'QueryBindable' in a property declaration marked public ...; 'SQLite' was not imported publicly").
The same accounting gap shows up in two places:

- `@Table` structs need an explicit `: SQL::Table` conformance written in source so that
  `public import SQL` counts as used (swift-questionnaires, swift-rulings,
  reminders-architecture).
- nl-legislation-pipeline changed `Document.data` from `Data` to `[Byte]` because swift-sql's
  "SQL Foundation Integration" hit the same error, and replaced the JSON `signed` column
  with a signers table.

## Variant: the conformed protocol is the only cross-module use (20 Oct 2026)

The gap does not need a witness type. An extension macro whose declaration is
`@attached(extension, conformances: Marker)` (in a module that `public import`s the
protocol's module `Proto`, as swift-sql's `SQL_Macros` does with `SQL`) expands to
`extension Thing: Proto.Marker {}` on `@MarkedDot public struct Thing {}`:

- `public import Proto` in the client: `warning: public import of 'Proto' was not used in
  public declarations or inlinable code`. The same warning appears when the expansion spells
  the protocol with a module selector, `Proto::Marker`, which is the form `@Table` emits.
- `import Proto` (control): `macro expansion @MarkedDot:1:24: error: cannot use protocol
  'Marker' in a public or '@usableFromInline' conformance; 'Proto' was not imported publicly`.

Apple Swift 6.4 (swiftlang-6.4.0.34.1), arm64 macOS 27.2, `InternalImportsByDefault`.
This variant explains every `public import of 'SQL' was not used` on a `@Table` type
(44 in Mapje's PersonalData, 6 in swift-sqlite's CloudKit tables, swift-sql's Public Draft
Tests): the import is needed and the diagnostic is wrong. Under
`treatAllWarnings(as: .error)` such a target cannot build, which is why swift-sql and
swift-sqlite do not yet adopt the canonical settings tail.

## Workaround

Keep every cross-module type a macro puts into public declarations also visible in the
source's own public declarations (an explicit conformance, a public property type), or
avoid such types in macro-generated public members.
