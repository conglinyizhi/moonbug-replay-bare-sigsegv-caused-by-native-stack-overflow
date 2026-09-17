// 绕过 lane 的对照组：崩溃前的进度直接写 fd 2，不走 stdio 缓冲。
//
// println 写 stdout，在重定向到管道/文件时是块缓冲：进程被信号打死，缓冲区跟着丢。
// 同一份进度写 fd 2 就留得住 —— 崩溃本身绕不开，但「崩了之后什么都看不到」能绕开。
//
// 实测：exit 139，stdout 0 字节，stderr 有内容。

///|
#borrow(buf)
extern "c" fn c_write(fd : Int, buf : Bytes, len : Int) -> Int = "write"

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
  println("stdout: start（这块缓冲会丢）")
  let msg = b"stderr: start（这块留得住）\n"
  ignore(c_write(2, msg, msg.length()))
  println("result \{deep(1000000)}")
}
