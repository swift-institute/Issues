/// Minimal reproduction case for Swift compiler crash on Windows
/// when mangling existential type for debug info.
///
/// The crash occurs during IRGen when the compiler attempts to mangle
/// `any HTML.View` for DWARF debug information.
///
/// Key: The HTML namespace is defined in a DIFFERENT PACKAGE (BaseModule)
/// and the View protocol is added via extension here. This cross-package
/// extension pattern combined with existential types triggers the bug.

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
