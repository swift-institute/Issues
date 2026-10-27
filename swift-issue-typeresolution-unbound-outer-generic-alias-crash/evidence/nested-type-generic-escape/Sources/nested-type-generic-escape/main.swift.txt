// MARK: - Nested-type generic escape
// Purpose: Test whether Swift 6.3 allows accessing a nested type of a
//          generic outer struct WITHOUT specifying the outer's generic
//          parameter, when the nested type does not reference it.
//
//          If YES, we can have `Ownership.Box<V>` (CoW, generic) AND
//          `Ownership.Box.Unique<U: ~Copyable>` (nested, independent generic)
//          coexist without forcing users to write a phantom `Ownership.Box<SomePhantom>.Unique<U>`.
//
//          If NO, hoisting is the only way to avoid the phantom.
//
// Hypotheses:
//   H1 — `Foo.Bar = Int` nested typealias, accessible as `Foo.Bar` (no generic)
//   H2 — `Foo.Bar<U>` nested struct, accessible as `Foo.Bar<X>` (no outer generic)
//   H3 — `Foo<V: ~Copyable>.Bar<U: ~Copyable>`, accessible as `Foo.Bar<H>` where H: ~Copyable
//   H4 — default generic parameter trick: `struct Foo<V = Void>`
//   H5 — hoisted pattern: top-level `struct __FooBar<U>` + nested `typealias Bar<U> = __FooBar<U>`
//
// Toolchain: swift-6.3.1 (2026-04-17)
// Platform: macOS 26 (arm64)
// Date: 2026-04-24
// Result: See per-variant results below.
// Revalidated: Swift 6.3.1 (2026-04-30) — PASSES

// ============================================================================
// MARK: - H1 — Nested typealias, no outer generic at access
// ============================================================================

struct H1_Foo<V> {
    typealias Bar = Int  // Doesn't reference V
}

func h1_test() {
    let h1_x: H1_Foo<String>.Bar = 42  // Explicit V = String
    print("H1: H1_Foo<String>.Bar = \(h1_x) — works with explicit outer generic")
    print("H1: H1_Foo.Bar without outer generic — see h1_short_test() below")
}

func h1_short_test() {
    let h1_y: H1_Foo.Bar = 42
    print("H1 short: \(h1_y)")
}

// ============================================================================
// MARK: - H2 — Nested struct with own generic, accessed without outer's generic
// ============================================================================

struct H2_Foo<V> {
    struct Bar<U> {
        let value: U
    }
}

func h2_test() {
    // Full form: H2_Foo<Int>.Bar<String>
    let h2_full: H2_Foo<Int>.Bar<String> = H2_Foo<Int>.Bar(value: "hi")
    print("H2: H2_Foo<Int>.Bar<String>(value:) = \(h2_full.value) — works explicit")
    print("H2: H2_Foo.Bar<String> without outer V — see H2_short_test() below")
}

// H2 short: REFUTED on Swift 6.3.1.
// Diagnostic:
//   error: generic parameter 'V' could not be inferred
//   note: explicitly specify the generic arguments to fix this issue
// Command:
//   let h2_short: H2_Foo.Bar<String> = H2_Foo.Bar(value: "hi")
//
// Swift requires the outer generic to be specified when accessing a
// nested struct that has its own generic parameter. The outer V cannot
// be inferred from the inner type arguments.
// func h2_short_test() {
//     let h2_short: H2_Foo.Bar<String> = H2_Foo.Bar(value: "hi")
//     print("H2 short: \(h2_short.value)")
// }

// ============================================================================
// MARK: - H3 — ~Copyable nested struct inside generic outer
// ============================================================================

struct H3_Foo<V: ~Copyable>: ~Copyable {
    struct Bar<U: ~Copyable>: ~Copyable {
        let value: U
        init(_ value: consuming U) { self.value = value }
    }
}

struct H3_Handle: ~Copyable {
    let id: Int
    init(_ id: Int) { self.id = id }
}

func h3_test() {
    // Full form: H3_Foo<Int>.Bar<H3_Handle>
    let h3_full: H3_Foo<Int>.Bar<H3_Handle> = H3_Foo<Int>.Bar(H3_Handle(42))
    print("H3: H3_Foo<Int>.Bar<Handle>(id:42) — works explicit; .id = \(h3_full.value.id)")
}

// H3 short: REFUTED on Swift 6.3.1 (same shape as H2; ~Copyable doesn't change it).
// Diagnostic:
//   error: generic parameter 'V' could not be inferred
// Command:
//   let h3_short: H3_Foo.Bar<H3_Handle> = H3_Foo.Bar(H3_Handle(43))
// func h3_short_test() {
//     let h3_short: H3_Foo.Bar<H3_Handle> = H3_Foo.Bar(H3_Handle(43))
//     print("H3 short: \(h3_short.value.id)")
// }

// ============================================================================
// MARK: - H4 — Default generic parameter
// ============================================================================
// Try: `struct Foo<V = Void>` — does Swift 6.3 accept default generic args on structs?

struct H4_Foo<V> {  // No default — testing whether default is supported
    // struct Foo<V = Void> — hypothetical; see if this compiles when uncommented
    typealias DefaultBar = Int
}

// Testing via uncommenting:
// struct H4_FooWithDefault<V = Void> {
//     typealias DefaultBar = Int
// }
// let h4_x: H4_FooWithDefault.DefaultBar = 1  // Would this work?

func h4_test() {
    print("H4: default generic parameter — tested via commented H4_FooWithDefault")
}

// ============================================================================
// MARK: - H5 — Hoisted pattern: module-scope struct + nested typealias
// ============================================================================

// Module-scope (hoisted) — ~Copyable struct with its own generic
struct __H5FooBar<U: ~Copyable>: ~Copyable {
    let value: U
    init(_ value: consuming U) { self.value = value }
}

// Outer generic struct with nested typealias to the hoisted type
struct H5_Foo<V> {
    typealias Bar<U: ~Copyable> = __H5FooBar<U>
}

func h5_test() {
    // Attempt: H5_Foo<Int>.Bar<H3_Handle>
    let h5_full: H5_Foo<Int>.Bar<H3_Handle> = H5_Foo<Int>.Bar(H3_Handle(7))
    print("H5: H5_Foo<Int>.Bar<Handle> via hoisted typealias — id = \(h5_full.value.id)")
    print("H5: The hoisted type is __H5FooBar<U>, reached via nested typealias")
    print("H5: Same phantom-V constraint applies at access through H5_Foo<V>")
}

// H5 short: CRASHES Swift 6.3.1 compiler. Stack dump caught:
//
//   9. While evaluating request ResolveTypeRequest(while resolving type ,
//      H5_Foo.Bar<H3_Handle>)
//
// The compiler segfaults in applyUnboundGenericArguments while trying to
// resolve a nested-typealias reference with the outer generic omitted.
// Confirmed crash with:
//   let h5_short: H5_Foo.Bar<H3_Handle> = H5_Foo.Bar(H3_Handle(8))
//
// This means the hoisting-through-nested-typealias pattern does NOT allow
// omitting the outer generic in Swift 6.3.1 — and worse, attempting it
// crashes the compiler.
//
// Left commented out to keep the build green. Status: compiler bug, file
// upstream if the short-form access is desired.

// ============================================================================
// MARK: - H6 — Direct access to hoisted type
// ============================================================================
// Instead of going through the outer generic, users access the hoisted type
// directly. We then add a module-scope typealias that creates a shorter form.

// Already have __H5FooBar<U: ~Copyable> at module scope.
// Add a module-scope typealias:
typealias H5Bar<U: ~Copyable> = __H5FooBar<U>

func h6_test() {
    let h6_x = H5Bar(H3_Handle(99))
    print("H6: module-scope typealias H5Bar<U> = __H5FooBar<U> — id = \(h6_x.value.id)")
    print("H6: But H5Bar is a top-level typealias, not nested under H5_Foo namespace")
    print("H6: Violates Nest.Name — this is the compound-at-module-scope pattern")
}

// ============================================================================
// MARK: - Main
// ============================================================================

print("==================================================")
print("nested-type-generic-escape experiment")
print("==================================================")

print("\n--- H1 ---")
h1_test()
h1_short_test()  // This works — nested typealias to non-generic type allows outer omitted

print("\n--- H2 ---")
h2_test()
// h2_short_test() REFUTED — see comment above

print("\n--- H3 ---")
h3_test()
// h3_short_test() REFUTED — see comment above

print("\n--- H4 ---")
h4_test()

print("\n--- H5 ---")
h5_test()
// h5_short_test() CRASHES the compiler — see comment above

print("\n--- H6 ---")
h6_test()

print("\n==================================================")
print("RESULTS:")
print("  H1 short form (typealias to non-generic):     WORKS")
print("  H2 short form (nested struct with own gen):   REFUTED")
print("  H3 short form (~Copyable variant):            REFUTED")
print("  H5 short form (hoisted via nested typealias): CRASHES compiler")
print("==================================================")
