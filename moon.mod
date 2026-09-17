// 最小复现：native 深递归栈溢出是裸 SIGSEGV，没有诊断，且崩溃前的 stdout 整块丢失
//
// 复现本体零依赖（deep/ 与 spin/ 只用到 core）。
// 绕过 lane 的 stderr_probe/ 也只是 libc 的 write(2)，不需要任何 MoonBit 依赖。
//
// 详细说明、触发矩阵与上游情况见 README.md。
name = "repro/stack"

version = "0.1.0"

preferred_target = "native"
