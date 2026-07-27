import Testing
import ContainerLib

@Suite("@_rawLayout Deinit Bug", .serialized)
struct Tests {

    // MARK: - Core Bug Demonstration

    @Test("BUG: Box - nested @_rawLayout with generics")
    func bugBox() {
        print("=== Box<Int, 4> ===")
        do { var b = Box<Int, 4>(); _ = consume b }
        print("=== end (NO 'Box.deinit' = BUG) ===")
    }

    @Test("Control: BoxFixed - @_rawLayout(like: Int)")
    func controlFixed() {
        print("=== BoxFixed<Int, 4> ===")
        do { var b = BoxFixed<Int, 4>(); _ = consume b }
        print("=== end ===")
    }

    // MARK: - Workaround Test

    @Test("Workaround: BoxTopLevel - top-level @_rawLayout")
    func workaroundTopLevel() {
        print("=== BoxTopLevel<Int, 4> ===")
        do { var b = BoxTopLevel<Int, 4>(); _ = consume b }
        print("=== end ===")
    }

    // MARK: - Destruction Analysis

    @Test("Analysis: BoxWithToken - is outer destruction skipped?")
    func analysisToken() {
        print("=== BoxWithToken<Int, 4> ===")
        do { var b = BoxWithToken<Int, 4>(); _ = consume b }
        print("=== end (Token.deinit prints = value destroyed, BoxWithToken.deinit missing = struct deinit skipped) ===")
    }

    // MARK: - withExtendedLifetime

    @Test("BUG: Box with withExtendedLifetime")
    func bugWithExtendedLifetime() {
        print("=== Box<Int, 4> withExtendedLifetime ===")
        do {
            let b = Box<Int, 4>()
            withExtendedLifetime(b) {}
        }
        print("=== end (NO 'Box.deinit' = BUG) ===")
    }
}
