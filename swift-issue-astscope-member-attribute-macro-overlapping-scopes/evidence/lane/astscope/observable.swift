import Observation

@Observable final class C {
    @MainActor var x = 0
    var y: Int = 0
}
