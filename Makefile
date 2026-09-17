# native 深递归栈溢出是裸 SIGSEGV —— 用 .mbtx 驱动，几乎不靠 shell

SHELL  := /bin/bash
MOON   ?= $(HOME)/.moon/bin/moon
FIX_CC ?= clang

export MOON FIX_CC

# 深度结论依赖栈上限：每个 lane 都在 8 MiB 栈下跑（顺带关掉 core 文件）
LIMITS = ulimit -s 8192; ulimit -c 0;
# MOON_CC 是给「编译这个 .mbtx 自己」用的；脚本内部还会把它传给子进程 moon。
RUN = MOON_CC="$(FIX_CC)" "$(MOON)" run --target native cases.mbtx --

.PHONY: help all deps verify bug workaround contrast fixed cases diagnose clean

help:
	@printf '%s\n' \
	  'native 深递归栈溢出是裸 SIGSEGV（.mbtx 驱动）' \
	  '' \
	  '  make verify      命中问题 lane + 绕过 lane + 对照 lane，本地应全绿' \
	  '  make bug         命中问题 lane：深递归 exit 139，stdout/stderr 全空' \
	  '  make workaround  绕过 lane：崩溃前进度改走 fd 2 → 留得住' \
	  '  make contrast    对照 lane：js 后端同深度给可读 RangeError' \
	  '  make fixed       修复验收 lane：不再裸崩（上游修好后转 PASS）' \
	  '  make cases       列出用例' \
	  '  make diagnose    打印环境、栈上限与用例表' \
	  '  make deps        同步 registry 索引（首次运行需要）' \
	  '  make clean       清掉 _build' \
	  '' \
	  '每个 lane 都以 ulimit -s 8192 / ulimit -c 0 起跑' \
	  '直接跑： $(LIMITS) $(RUN) <子命令>' \
	  "变量： MOON=$(MOON)   FIX_CC=$(FIX_CC)"

all: verify

# .mbtx 的依赖（moonbitlang/async）要靠 registry 索引解析；全新环境里索引是空的，
# 需要先同步一次。同步失败不致命 —— 可能离线，此时改用本地缓存继续。
deps:
	@$(MOON) update --quiet || echo "warn: moon update 失败（可能离线），改用本地缓存"

verify: deps
	@$(LIMITS) $(RUN) verify

bug: deps
	@$(LIMITS) $(RUN) bug

workaround: deps
	@$(LIMITS) $(RUN) workaround

contrast: deps
	@$(LIMITS) $(RUN) contrast

fixed: deps
	@$(LIMITS) $(RUN) fixed

cases: deps
	@$(RUN) list

diagnose: deps
	@$(LIMITS) $(RUN) diagnose

clean:
	@rm -rf _build
	@echo 'cleaned: _build'
