// Simplified Dimension module types to trigger the bug

public enum Coordinate {
    public struct X<Space> {
        public struct Value<Scalar: BinaryInteger & Sendable>: Sendable, Equatable {
            public var _rawValue: Scalar
            public init(_ rawValue: Scalar) { self._rawValue = rawValue }
        }
    }
}

public enum Displacement {
    public struct X<Space> {
        public struct Value<Scalar: BinaryInteger & Sendable>: Sendable, Equatable {
            public var _rawValue: Scalar
            public init(_ rawValue: Scalar) { self._rawValue = rawValue }
        }
    }
}
