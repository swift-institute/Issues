//
//  IO.Event.Wakeup.Channel+Readiness.swift
//  swift-io
//
//  Bridge from Kernel.Wakeup.Channel to IO.Event.Wakeup.Channel.
//

extension IO.Event.Wakeup.Channel {
    /// Creates an IO wakeup channel from a kernel wakeup channel.
    ///
    /// Wraps the kernel channel's `wake()` as the signal closure.
    @inlinable
    init(_ kernel: Kernel.Wakeup.Channel) {
        self.init(signal: kernel.wake)
    }
}
