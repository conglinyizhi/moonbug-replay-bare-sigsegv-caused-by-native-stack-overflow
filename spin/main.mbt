// 无限递归：每层都留栈帧，且不复用结果，让优化没法把它变成循环。
//
// 实测 exit 139（SIGSEGV），stdout/stderr 全空，没有任何诊断。

///|
fn spin(n : Int) -> Int {
  1 + spin(n + 1)
}

///|
fn main {
  println("enter spin")
  println("result \{spin(0)}")
}
