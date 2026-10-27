//
//  IO.Event.swift
//  swift-io
//
//  Created by Coen ten Thije Boonkkamp on 28/12/2025.
//

// IO_Core inlined into IO.swift; Kernel re-exported there

extension IO {
    /// A readiness event from the kernel selector.
    ///
    /// Namespace adoption of `Kernel.Event`: IO.Event IS Kernel.Event, extended
    /// with 50+ IO-specific types (Channel, Selector, Driver, Token, etc.)
    /// that add async coordination on top of the kernel primitives.
    ///
    /// This gives `IO.Event.Interest`, `IO.Event.ID`, `IO.Event.Options`
    /// naturally, and all IO extensions build a coherent domain on the
    /// kernel event concept.
    ///
    /// ## Architecture
    ///
    /// The event-driven I/O system is layered:
    /// 1. **Kernel**: `Event`, `Interest`, `Flags`, `ID` (platform-agnostic primitives)
    /// 2. **IO**: `Token`, `Driver`, `Selector` (async coordination)
    /// 3. **Backends**: Platform-specific implementations (kqueue, epoll, IOCP)
    public typealias Event = Kernel.Event
}
