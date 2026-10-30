/// Base module that defines the HTML namespace.
/// This is in a separate PACKAGE to trigger the cross-package bug.
///
/// Mimics the pattern in swift-whatwg-html where WHATWG_HTML is defined
/// and then aliased to HTML in downstream packages.

/// The internal namespace enum - matches WHATWG_HTML pattern
public enum WHATWG_HTML {}

/// Context type used by the View protocol
extension WHATWG_HTML {
    public struct Context: Sendable {
        public init() {}
    }
}

/// Public typealias for downstream packages
/// This matches the pattern: `public typealias HTML = WHATWG_HTML_Shared.WHATWG_HTML`
public typealias HTML = WHATWG_HTML
