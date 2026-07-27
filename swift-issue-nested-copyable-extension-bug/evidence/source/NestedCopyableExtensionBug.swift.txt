// Minimal reproduction for Swift compiler bug:
// Extension on deeply nested generic ~Copyable type fails to compile
// when declared in the SAME FILE as the type definition.

public enum Binary {
    public protocol Contiguous: ~Copyable {
        associatedtype Space
        associatedtype Scalar: FixedWidthInteger & Sendable = Int
        var count: Int { get }
    }

    public protocol Mutable: Binary.Contiguous {}
}

extension Binary {
    public typealias Position<Scalar: BinaryInteger, Space> = Coordinate.X<Space>.Value<Scalar>
    public typealias Offset<Scalar: BinaryInteger, Space> = Displacement.X<Space>.Value<Scalar>
}

extension Binary {
    public struct Cursor<Storage: Binary.Mutable>: ~Copyable {
        public var storage: Storage
        @usableFromInline
        internal var _readerIndex: Binary.Position<Storage.Scalar, Storage.Space>
        @usableFromInline
        internal var _writerIndex: Binary.Position<Storage.Scalar, Storage.Space>
    }
}

// MARK: - Move Namespace

extension Binary.Cursor {
    public struct Move: ~Copyable {
        @usableFromInline
        var cursor: UnsafeMutablePointer<Binary.Cursor<Storage>>

        @usableFromInline
        init(_ cursor: UnsafeMutablePointer<Binary.Cursor<Storage>>) {
            self.cursor = cursor
        }
    }
}

extension Binary.Cursor.Move {
    public struct Reader: ~Copyable {
        @usableFromInline
        var cursor: UnsafeMutablePointer<Binary.Cursor<Storage>>

        @usableFromInline
        init(_ cursor: UnsafeMutablePointer<Binary.Cursor<Storage>>) {
            self.cursor = cursor
        }
    }

    public var reader: Reader {
        Reader(cursor)
    }
}

// Extension on Move.Reader - WORKS
extension Binary.Cursor.Move.Reader {
    @inlinable
    public func callAsFunction(
        by offset: Binary.Offset<Storage.Scalar, Storage.Space>
    ) {
        let newIndex = cursor.pointee._readerIndex._rawValue + offset._rawValue
        cursor.pointee._readerIndex = Binary.Position(newIndex)
    }
}

extension Binary.Cursor.Move {
    public struct Writer: ~Copyable {
        @usableFromInline
        var cursor: UnsafeMutablePointer<Binary.Cursor<Storage>>

        @usableFromInline
        init(_ cursor: UnsafeMutablePointer<Binary.Cursor<Storage>>) {
            self.cursor = cursor
        }
    }

    public var writer: Writer {
        Writer(cursor)
    }
}

// Extension on Move.Writer - WORKS
extension Binary.Cursor.Move.Writer {
    @inlinable
    public func callAsFunction(
        by offset: Binary.Offset<Storage.Scalar, Storage.Space>
    ) {
        let newIndex = cursor.pointee._writerIndex._rawValue + offset._rawValue
        cursor.pointee._writerIndex = Binary.Position(newIndex)
    }
}

// MARK: - Set Namespace

extension Binary.Cursor {
    public struct Set: ~Copyable {
        @usableFromInline
        var cursor: UnsafeMutablePointer<Binary.Cursor<Storage>>

        @usableFromInline
        init(_ cursor: UnsafeMutablePointer<Binary.Cursor<Storage>>) {
            self.cursor = cursor
        }
    }
}

extension Binary.Cursor.Set {
    public struct Reader: ~Copyable {
        @usableFromInline
        var cursor: UnsafeMutablePointer<Binary.Cursor<Storage>>

        @usableFromInline
        init(_ cursor: UnsafeMutablePointer<Binary.Cursor<Storage>>) {
            self.cursor = cursor
        }
    }

    public var reader: Reader {
        Reader(cursor)
    }
}

// BUG: This empty extension fails to compile when in the SAME FILE.
// Error: 'Mutable' is not a member type of enum 'Binary.Binary'
extension Binary.Cursor.Set.Reader {}

extension Binary.Cursor.Set {
    public struct Writer: ~Copyable {
        @usableFromInline
        var cursor: UnsafeMutablePointer<Binary.Cursor<Storage>>

        @usableFromInline
        init(_ cursor: UnsafeMutablePointer<Binary.Cursor<Storage>>) {
            self.cursor = cursor
        }
    }

    public var writer: Writer {
        Writer(cursor)
    }
}

extension Binary.Cursor.Set.Writer {}
