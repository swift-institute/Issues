// ===----------------------------------------------------------------------===//
//
// swift-issue-rawlayout-noncopyable-extension-rejection
//
// Module A — the Storage namespace + the conforming protocol.
//
// Both declarations are needed by Module B's reproducer. They are placed in
// Module A so the reproducer demonstrates the cross-module shape — but per
// the variable-isolation table in INVESTIGATION-ARC.md (variant V10/V16/V17),
// the bug also fires when all declarations are co-located in one module.
// Module separation is NOT required for the trigger.
//
// ===----------------------------------------------------------------------===//

/// Element-generic namespace. The `~Copyable` suppression on `Element` is
/// load-bearing for the bug — without it, the leak path doesn't exist.
public enum Storage<Element: ~Copyable> {}

/// Protocol with a `~Copyable` associated type. The presence of the
/// `associatedtype Element: ~Copyable` is load-bearing for the trigger
/// (variant V20 with no associatedtype PASSES — see INVESTIGATION-ARC.md).
public protocol Marker: ~Copyable {
    associatedtype Element: ~Copyable
}
