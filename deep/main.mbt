// 有限深度的非尾递归：`1 + deep(...)` 保证每层都留一个栈帧。
//
// 深度取命令行里最后一个纯数字参数，这样 native 与 js 两种调用形态都成立：
//   native: [exe, N]          js: [node, script, N]
// 没给可解析的参数就用默认值。
//
//   ./deep.exe 1000000     实测 exit 139（SIGSEGV），stdout/stderr 全空
//   moon run deep --target js -- 10000   实测 RangeError + 源码位置
///|
fn digits_to_int(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut n = 0
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
fn arg_depth(default : Int) -> Int {
  let mut depth = default
  for arg in @env.args() {
    match digits_to_int(arg) {
      Some(n) => depth = n
      None => ()
    }
  }
  depth
}

///|
fn deep(n : Int) -> Int {
  if n <= 0 {
    0
  } else {
    1 + deep(n - 1)
  }
}

///|
fn main {
  let depth = arg_depth(10000)
  println("start depth=\{depth}")
  println("result \{deep(depth)}")
  println("done")
}
