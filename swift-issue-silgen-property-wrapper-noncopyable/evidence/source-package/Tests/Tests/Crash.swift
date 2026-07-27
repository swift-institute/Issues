import Lib

func crash() {
    let box = Box<Int>(42)
    _ = box.value  // SILGen CRASH
}
