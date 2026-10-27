// Bug1Core: Minimal @_rawLayout type with deinit in generic enum
//
// TRIGGER: A struct in another module that stores 2+ fields of this type
//          crashes the LLVM verifier under -O with:
//          "Instruction does not dominate all uses!"
//
// MINIMAL REQUIREMENTS (all must be present):
//   1. Generic enum wrapper (Container<Element: ~Copyable>)
//   2. @_rawLayout(likeArrayOf: Element, count: capacity) using outer generic
//   3. Value generic parameter (let capacity: Int)
//   4. Explicit deinit
//   5. Cross-module usage: another module stores 2+ fields of this type
//   6. Release mode (-O optimization)
//
// THRESHOLD: 1 field in consumer = OK, 2+ fields = CRASH
//
// REMOVING ANY OF THESE PREVENTS THE CRASH:
//   - Remove deinit → builds fine
//   - Remove generic enum → builds fine (top-level @_rawLayout OK)
//   - Use only 1 field in consumer → builds fine
//   - Debug mode → builds fine

public enum Container<Element: ~Copyable> {
    @_rawLayout(likeArrayOf: Element, count: capacity)
    public struct Inline<let capacity: Int>: ~Copyable {
        public init() {}

        deinit {}
    }
}
