# Swift Compiler Crash: Windows Existential Type Mangling

**Bug Report:** https://github.com/swiftlang/swift/issues/86202

Minimal reproduction case for a Swift compiler crash on Windows when mangling existential types for debug info.

## Bug Summary

The Swift compiler crashes on Windows (x86_64-unknown-windows-msvc) during IR generation when mangling an existential type (`any Protocol`) for DWARF debug information. The crash occurs only on Windows; macOS and Linux compile successfully with the same code and Swift version.

**Crash assertion:**
```
Assertion failed: isActuallyCanonicalOrNull() && "Forming a CanType out of a non-canonical type!"
```

## Reproduction

```bash
# On Windows with Swift 6.0+
git clone https://github.com/coenttb/swift-issue-windows-existential-crash.git
cd swift-issue-windows-existential-crash
swift build -c debug
```

The crash occurs during debug build. Release builds (`-c release`) are not affected.

## Environment

- **Swift version:** 6.0+ (tested with 6.0.3)
- **Platform:** Windows (x86_64-unknown-windows-msvc)
- **Works on:** macOS, Linux (same Swift version)

## Minimal Code

This reproduction uses two minimal packages with specific Swift 6 features enabled.

### Package 1: [swift-issue-windows-existential-crash-other-package](https://github.com/coenttb/swift-issue-windows-existential-crash-other-package)

**Sources/BaseModule/BaseModule.swift:**
```swift
/// The internal namespace enum
public enum WHATWG_HTML {}

extension WHATWG_HTML {
    public struct Context: Sendable {
        public init() {}
    }
}

/// Public typealias - this pattern is required to trigger the bug
public typealias HTML = WHATWG_HTML
```

**Package.swift:**
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BaseModule",
    products: [
        .library(name: "BaseModule", targets: ["BaseModule"]),
    ],
    targets: [
        .target(name: "BaseModule")
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]
}
```

### Package 2: This package (ExistentialCrash)

**Sources/ExistentialCrash/Crash.swift:**
```swift
public import BaseModule

// MARK: - Renderable Protocol

public protocol Renderable {
    associatedtype Content
    associatedtype Context
    associatedtype Output
    var body: Content { get }

    static func _render<Buffer: RangeReplaceableCollection>(
        _ markup: Self,
        into buffer: inout Buffer,
        context: inout Context
    ) where Buffer.Element == Output
}

extension Renderable where Content: Renderable, Content.Context == Context, Content.Output == Output {
    @inlinable
    public static func _render<Buffer: RangeReplaceableCollection>(
        _ markup: Self,
        into buffer: inout Buffer,
        context: inout Context
    ) where Buffer.Element == Output {
        Content._render(markup.body, into: &buffer, context: &context)
    }
}

// MARK: - HTML.View Protocol (extends HTML from other package)

extension HTML {
    public protocol View: Renderable
    where Content: HTML.View, Context == HTML.Context, Output == UInt8 {
        @HTML.Builder var body: Content { get }
    }
}

extension HTML.View {
    @inlinable
    public static func _render<Buffer: RangeReplaceableCollection>(
        _ html: Self,
        into buffer: inout Buffer,
        context: inout HTML.Context
    ) where Buffer.Element == UInt8 {
        Content._render(html.body, into: &buffer, context: &context)
    }
}

// MARK: - HTML Builder

extension HTML {
    @resultBuilder
    public struct Builder {
        public static func buildBlock<Content: HTML.View>(_ content: Content) -> Content {
            content
        }
    }
}

// MARK: - Never conformance

extension Never: HTML.View {
    public var body: Never { fatalError() }
}

// MARK: - HTML.AnyView (THIS TRIGGERS THE CRASH)

extension HTML {
    public struct AnyView: HTML.View, @unchecked Sendable {
        /// The existential type that causes the crash during debug info mangling
        public let base: any HTML.View

        private let renderFunction: (inout ContiguousArray<UInt8>, inout HTML.Context) -> Void

        public init<T: HTML.View>(_ base: T) {
            self.base = base
            self.renderFunction = { buffer, context in
                T._render(base, into: &buffer, context: &context)
            }
        }

        /// This initializer triggers the crash on Windows.
        public init(_ base: any HTML.View) {
            if let anyView = base as? HTML.AnyView {
                self = anyView
            } else {
                self.base = base
                self.renderFunction = { buffer, context in
                    func render<T: HTML.View>(_ html: T) {
                        T._render(html, into: &buffer, context: &context)
                    }
                    render(base)
                }
            }
        }

        public static func _render<Buffer: RangeReplaceableCollection>(
            _ html: HTML.AnyView,
            into buffer: inout Buffer,
            context: inout HTML.Context
        ) where Buffer.Element == UInt8 {
            var contiguousBuffer = ContiguousArray<UInt8>()
            html.renderFunction(&contiguousBuffer, &context)
            buffer.append(contentsOf: contiguousBuffer)
        }

        public var body: Never { fatalError() }
    }
}
```

**Package.swift:**
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ExistentialCrash",
    products: [
        .library(name: "ExistentialCrash", targets: ["ExistentialCrash"]),
    ],
    dependencies: [
        .package(url: "https://github.com/coenttb/swift-issue-windows-existential-crash-other-package", from: "0.2.0"),
    ],
    targets: [
        .target(
            name: "ExistentialCrash",
            dependencies: [
                .product(name: "BaseModule", package: "swift-issue-windows-existential-crash-other-package"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]
}
```

## Key Findings

The bug requires the following combination:

1. **Cross-package protocol extensions** - Protocol defined by extending a type from another package
2. **Typealias pattern** - `public typealias HTML = WHATWG_HTML` in the base package
3. **Swift 6 features** - `ExistentialAny` and `InternalImportsByDefault` enabled
4. **Existential type** - `any HTML.View` used as a stored property or parameter

**Cross-module vs Cross-package:**
- ✅ Cross-module (same package, different targets): Works on Windows
- ❌ Cross-package (different packages): Crashes on Windows

## Full Stack Trace

From CI run: https://github.com/coenttb/swift-issue-windows-existential-crash/actions/runs/20483301014

```
Assertion failed: isActuallyCanonicalOrNull() && "Forming a CanType out of a non-canonical type!",
file C:\Users\swift-ci\jenkins\workspace\swift-6.0-windows-toolchain\swift\include\swift/AST/Type.h, line 448

Please submit a bug report (https://swift.org/contributing/#reporting-bugs) and include the crash backtrace.

Stack dump:
0.  Program arguments: C:\\Users\\runneradmin\\AppData\\Local\\Programs\\Swift\\Toolchains\\6.0.3+Asserts\\usr\\bin\\swift-frontend.exe -frontend -c -primary-file D:\\a\\swift-issue-windows-existential-crash\\swift-issue-windows-existential-crash\\Sources\\ExistentialCrash\\Crash.swift ... -enable-upcoming-feature ExistentialAny -enable-upcoming-feature InternalImportsByDefault ... -g -debug-info-format=dwarf -dwarf-version=4 ...
1.  Swift version 6.0.3 (swift-6.0.3-RELEASE)
2.  Compiling with the current language version
3.  While evaluating request IRGenRequest(IR Generation for file "D:\a\swift-issue-windows-existential-crash\swift-issue-windows-existential-crash\Sources\ExistentialCrash\Crash.swift")
4.  While emitting IR SIL function "@$s10BaseModule11WHATWG_HTMLO16ExistentialCrashE7AnyViewVyAfcDE0H0_pcfC".
    for 'init(_:)' (at D:\a\swift-issue-windows-existential-crash\swift-issue-windows-existential-crash\Sources\ExistentialCrash\Crash.swift:93:16)
5.  While mangling type for debugger type 'any HTML.View'

Exception Code: 0x80000003

 #0 0x00007ff743e24e15 (swift-frontend.exe+0x6074e15)
 #1 0x00007ff9db801989 (ucrtbase.dll+0xc1989)
 #2 0x00007ff9db7e4ab1 (ucrtbase.dll+0xa4ab1)
 #3 0x00007ff9db802986 (ucrtbase.dll+0xc2986)
 #4 0x00007ff9db802b61 (ucrtbase.dll+0xc2b61)
 #5 0x00007ff73fb2bc31 (swift-frontend.exe+0x1d7bc31)
 #6 0x00007ff73fb34a4b (swift-frontend.exe+0x1d84a4b)
 #7 0x00007ff73e57d143 (swift-frontend.exe+0x7cd143)
 #8 0x00007ff73e57fd5b (swift-frontend.exe+0x7cfd5b)
 #9 0x00007ff73e57b215 (swift-frontend.exe+0x7cb215)
#10 0x00007ff73e57ae07 (swift-frontend.exe+0x7cae07)
#11 0x00007ff73e6ac4f6 (swift-frontend.exe+0x8fc4f6)
#12 0x00007ff73e6a3173 (swift-frontend.exe+0x8f3173)
#13 0x00007ff73e6ba4d0 (swift-frontend.exe+0x90a4d0)
#14 0x00007ff73e693603 (swift-frontend.exe+0x8e3603)
#15 0x00007ff73e692574 (swift-frontend.exe+0x8e2574)
#16 0x00007ff73e4e5e48 (swift-frontend.exe+0x735e48)
#17 0x00007ff73e46d631 (swift-frontend.exe+0x6bd631)
#18 0x00007ff73e476036 (swift-frontend.exe+0x6c6036)
#19 0x00007ff73e46541b (swift-frontend.exe+0x6b541b)
#20 0x00007ff73e470bca (swift-frontend.exe+0x6c0bca)
#21 0x00007ff73e11af6c (swift-frontend.exe+0x36af6c)
#22 0x00007ff73e11bb10 (swift-frontend.exe+0x36bb10)
#23 0x00007ff73e11a358 (swift-frontend.exe+0x36a358)
#24 0x00007ff73e11a8ce (swift-frontend.exe+0x36a8ce)
#25 0x00007ff73e11cb76 (swift-frontend.exe+0x36cb76)
#26 0x00007ff73df7850b (swift-frontend.exe+0x1c850b)
#27 0x00007ff73df780dc (swift-frontend.exe+0x1c80dc)
#28 0x00007ff743e83b38 (swift-frontend.exe+0x60d3b38)
#29 0x00007ff9dd88e8d7 (KERNEL32.DLL+0x2e8d7)
#30 0x00007ff9dddac53c (ntdll.dll+0x8c53c)
```

## Expected Behavior

The compiler should successfully compile the code with debug info enabled.

## Actual Behavior

The compiler crashes with an assertion failure when attempting to mangle the existential type `any HTML.View` for debug info generation. The crash occurs in IRGen during DWARF debug info emission.

## CI Status

| Platform | Status |
|----------|--------|
| macOS | ✅ Works |
| Linux | ✅ Works |
| Windows | ❌ Crashes |

**CI:** https://github.com/coenttb/swift-issue-windows-existential-crash/actions

**Failing run:** https://github.com/coenttb/swift-issue-windows-existential-crash/actions/runs/20483301014

## Workaround

Disable debug info generation on Windows:
```bash
swift build -c debug -Xswiftc -gnone
```

## Original Discovery

This bug was discovered in [coenttb/swift-html-rendering](https://github.com/coenttb/swift-html-rendering) CI when building on Windows with Swift 6.0.

## Suggested Labels

`bug`, `crash`, `compiler`, `IRGen`, `Windows`, `existentials`, `debug info`, `mangling`
