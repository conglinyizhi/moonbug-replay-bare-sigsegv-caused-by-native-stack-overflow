# native 深递归栈溢出是裸 SIGSEGV（没有诊断，输出也一起丢）

## 1. 这个 bug 是什么

### 原因

`1 + deep(n - 1)` 保证每层都留一个栈帧：

```moonbit
fn deep(n : Int) -> Int {
  if n <= 0 { 0 } else { 1 + deep(n - 1) }
}
```

8 MiB 栈下，**50 万层正常跑完，55 万层起 `SIGSEGV`，100 万层必崩**，而崩的现场是：

| 观测项 | 值 |
| --- | --- |
| 退出码 | **139**（128+11，SIGSEGV） |
| stderr | **0 字节** —— 没有任何诊断 |
| stdout | **0 字节** —— 连崩溃前已经 `println` 的内容也没了（stdout 重定向到管道/文件时是块缓冲） |

同一份代码走 js 后端则是普通错误 + 可读堆栈：

```
RangeError: Maximum call stack size exceeded
    at deep (/path/deep/main.mbt:38:3)
    at deep (/path/deep/main.mbt:41:9)
```

native 侧崩溃时 `stderr` 是 0 字节，差距就在这：一方指出源码行，一方只留个 139。

### 复现平台

| 平台 | moon 版本 | 结果 |
| --- | --- | --- |
| 本机 Linux x86-64（8 MiB 栈） | 0.1.20260916（e4f45e4，2026-09-16） | 复现（`make bug` 绿） |
| GitHub Actions `ubuntu-latest` | 未运行 | 仓库还没推上去，CI 没跑过 |

## 2. 快速复现

### 最少需要什么

| 文件 | 内容 |
| --- | --- |
| `moon.mod` | `name = "repro/stack"` / `preferred_target = "native"`（零依赖） |
| `deep/moon.pkg` | `import { "moonbitlang/core/env" }` + `pkgtype(kind: "executable")` |
| `deep/main.mbt` | 深度从命令行取，`deep(1000000)` |

```bash
ulimit -s 8192 && make bug        # 深度结论依赖栈上限，必须钉住 8 MiB
```

期望输出（命中问题即通过）：

```
命中问题 lane —— native 深递归期望裸 SIGSEGV（exit 139，stdout/stderr 空）
  deep-1m            exit=139      stdout=0        stderr=0        PASS
  spin               exit=139      stdout=0        stderr=0        PASS
```

不想用 Makefile：

```bash
ulimit -s 8192
moon update --quiet                       # 首次需要同步 registry 索引
MOON_CC=clang moon run --target native cases.mbtx -- bug
```

### 文件清单：哪些和这个 bug 有关

| 文件 | 行数 | 和 bug 的关系 |
| --- | --- | --- |
| `moon.mod` | 11 | **必需** —— 标记模块；**零依赖** |
| `deep/moon.pkg` | 5 | **必需** —— 标记 package（可执行） |
| `deep/main.mbt` | 51 | **必需** —— 复现本体（有限深度，深度走命令行） |
| `spin/moon.pkg` + `spin/main.mbt` | 1 + 13 | **必需（补充）** —— 无限递归，同样裸崩 |
| `stderr_probe/main.mbt` | 26 | **与 bug 无关** —— 绕过 lane 的对照组（进度写 fd 2） |
| `cases.mbtx` | 464 | **与 bug 无关** —— 可执行规格，负责断言 |
| `Makefile` | 64 | **与 bug 无关** —— 调用规格的入口 |
| `.github/workflows/repro.yml` | 58 | **与 bug 无关** —— CI |
| `README.md` | — | **与 bug 无关** —— 本文档 |

最小复现就是前三个（约 70 行代码，零依赖），其余删掉照样复现。

## 3. 其他

### 触发矩阵

| 用例 | 命令 | exit | stdout | stderr |
| --- | --- | --- | --- | --- |
| 10 万层 | `deep.exe 100000` | 0 | 38 B | 0 B |
| 50 万层 | `deep.exe 500000` | 0 | 38 B | 0 B |
| 100 万层 | `deep.exe 1000000` | **139** | **0 B** | **0 B** |
| 无限递归 | `spin.exe` | **139** | **0 B** | **0 B** |
| release 2000 万层 | `deep.exe 20000000`（`--release --strip`） | 0 | 42 B | 0 B |
| 进度写 fd 2 | `stderr_probe.exe` | **139** | **0 B** | 35 B |
| js 后端 1 万层（对照） | `moon run deep --target js -- 10000` | 1 | 18 B | 1453 B（`RangeError` + 源码位置） |

即：native 崩的时候什么都不吐，js 后端同样深度给行号。

### 可执行规格

单文件 `.mbtx`：`moon run cases.mbtx -- <子命令>`。它自己构建 debug / release / js 三份产物，
再用 `@process.run` 起进程、收退出码，stdout/stderr 重定向到 `_build/logs/*.stdout|.stderr` 后读字节数。

```bash
make verify      # 命中问题 lane + 绕过 lane + 对照 lane，本地应全绿
make bug         # 只跑命中问题 lane
make workaround  # 只跑绕过 lane
make contrast    # 只跑对照 lane（js 后端）
make fixed       # 修复验收 lane（上游修好后转 PASS）
make cases       # 列出用例
make diagnose    # 打印环境、栈上限与用例表
make deps        # 同步 registry 索引（首次运行需要，各 lane 会自动先跑）
```

**注意：`deep/`、`spin/`、`stderr_probe/` 都是零依赖；只有 `cases.mbtx` 用到 `moonbitlang/async`。**
越过 Makefile 直接跑规格时记得自己钉住栈上限，否则深度结论会飘（`make diagnose` 会打印当前栈上限）。

### 用例

| case | lane | 期望 | 说明 |
| --- | --- | --- | --- |
| `deep-100k` | bug | `0` / stdout 非空 / stderr 空 | 深度不够，不触发 |
| `deep-500k` | bug | `0` / stdout 非空 / stderr 空 | 仍正常 |
| `deep-1m` | bug | **`139`** / stdout 空 / stderr 空 | 裸 SIGSEGV，输出全丢 |
| `spin` | bug | **`139`** / stdout 空 / stderr 空 | 无限递归同样裸崩 |
| `deep-release-20m` | bug | `0` / stdout 非空 / stderr 空 | release(AOT) 跑完（见「未验证」） |
| `stderr-probe` | workaround | `139` / stdout 空 / stderr **非空** | 崩溃绕不开，但崩前信息留得住 |
| `js-10k` | contrast | 非 0 / stdout 非空 / stderr 含 `RangeError` 与 `main.mbt` | js 后端的诊断质量 |

`fixed` lane 跑 `deep-1m`，期望「不再裸崩」：**exit != 139 或 stderr 非空**。只 flush stdout 不算修复
（那只是丢了输出，诊断还是没有）。

### CI

四个 job：`hit-the-bug` / `workaround` / `contrast` / `upstream-fix-status`（`continue-on-error`，用来看上游修没修）。

### 注意

- **栈上限必须钉住**：`Makefile` 里每个 lane 都以 `ulimit -s 8192; ulimit -c 0` 起跑，深度结论只在这个上限下成立。
- `@process.run` 把「被信号杀死」记成负数（SIGSEGV → `-11`），规格里 `norm_exit` 统一折算成 `128+n`，跟 shell 的 `$?` 一致。
- core dump 即使设了 `ulimit -c 0` 也可能被 systemd-coredump 的 pipe 模式收走，清理用 `sudo coredumpctl vacuum --size=50M`。
- js 对照需要 `node`；`moon run --target js` 的构建也在 `prepare()` 里做了。

### 环境

```
moon 0.1.20260916 (e4f45e4 2026-09-16)
moonc v0.10.13+75bd53fc8-nightly (2026-09-15)
Linux x86-64（内核 7.2.3-arch1-3），clang 22.1.8，node v26.8.1
ulimit -s = 8192 KiB（8 MiB）
```

### 未验证

- release（`--release --strip`）下 2000 万层跑完，疑似被优化成了循环。没看汇编，不当结论用。
- 崩溃深度的边界只测了 50 万 / 55 万两点，没有做精确二分。

### 相关上游 issue

native 后端（codegen + runtime）在 [moonbitlang/moonbit-compiler](https://github.com/moonbitlang/moonbit-compiler)，
但那个仓库的 **issues 是关闭的**（`has_issues = false`，2026-09-17 查）。搜 `stack overflow` / `SIGSEGV`：
moonbit-compiler 里 0 命中；`moonbitlang/moon` 里只有 #1101（`cc-flags` 导致的 segfault，已修）与
#969（tcc 下重复符号），都不是同一件事。所以这条要报哪里还需要先定 —— 这个问题本身是「缺诊断」，不是断言。

### 姊妹仓库

同批的另一个问题（async 紧循环收不到 SIGTERM，与这条无关）：
[moonbug-replay-sigterm-ignored-caused-by-non-yielding-async-loop](https://github.com/conglinyizhi/moonbug-replay-sigterm-ignored-caused-by-non-yielding-async-loop)

同一套结构的既有仓库：
[test-driver-argv](https://github.com/conglinyizhi/moonbug-replay-test-driver-argv-caused-by-missing-bounds-check)、
[broken-pipe](https://github.com/conglinyizhi/moonbug-replay-broken-pipe-caused-by-panic-abort)、
[lib.exe 归档器](https://github.com/conglinyizhi/moonbug-replay-native-build-fails-caused-by-lib-exe-archiver)
