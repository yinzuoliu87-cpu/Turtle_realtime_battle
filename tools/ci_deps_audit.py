# -*- coding: utf-8 -*-
"""ci_deps_audit — 门禁用到的第三方 python 模块, CI 工作流必须装 (2026-08-30)。

★由来: 2026-08-29 e023f09e 我给门禁加了两条读图的审计器(vfx_ref_match /
  vfx_ingame_check), 它们 `import PIL`。**本机装着 Pillow ⇒ 本地 263/263 全绿**,
  而 GitHub runner 上没有 ⇒ CI 从那一刻起连红【四个提交】, 我一次都没查。
  报错还长得很无辜: 「[FAIL] 需要 Pillow」/「ModuleNotFoundError: No module named 'PIL'」
  —— 看着像环境问题, 其实是**工作流少了一步 pip install**。

★这条审计守的形状: 「本地有、CI 没有」这类差异**在本地是看不见的** ——
  唯一能在本地发现它的办法, 就是拿门禁自己的依赖去对工作流的安装清单。
  (CLAUDE.md §7「本地绿 ≠ CI 绿」的可执行版本; 同族 memory [[fb-ci-vs-local-divergence]])

判据:
  ① 从 run-tests.sh 里抠出所有 `run_audit "tools/xxx.py"` —— 这就是门禁真正会跑的清单
  ② 扫这些文件的 import, 剔掉标准库与本仓自己的模块
  ③ 剩下的每一个, 都必须在 .github/workflows/tests.yml 的某条 pip install 里出现
"""
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

SH = "run-tests.sh"
YML = ".github/workflows/tests.yml"

## import 名 → pip 包名(不一致的才登记)
PIP_NAME = {"PIL": "pillow", "yaml": "pyyaml", "cv2": "opencv-python", "np": "numpy"}

fails = []


def main():
    if not (os.path.exists(SH) and os.path.exists(YML)):
        print("  [FAIL] 找不到 %s 或 %s" % (SH, YML))
        return 1
    sh = io.open(SH, encoding="utf-8", newline="").read()
    yml = io.open(YML, encoding="utf-8", newline="").read()

    tools = sorted(set(re.findall(r'run_audit\s+"(tools/[A-Za-z0-9_/]+\.py)"', sh)))
    print("  [分母] 门禁登记的 python 审计器 %d 个" % len(tools))
    ## ★分母断言: 一个都没抠到 = 正则挂了 / run-tests.sh 改写法了, 不是通过。
    if len(tools) < 10:
        fails.append("只抠到 %d 个审计器(<10) —— 空检查不是通过, 先看 run_audit 的写法变了没" % len(tools))
        for x in fails:
            print("  [FAIL] " + x)
        return 1

    ## 本仓自己的模块(同目录 .py) 不算第三方
    local = set()
    for root, _d, fs in os.walk("tools"):
        for f in fs:
            if f.endswith(".py"):
                local.add(f[:-3])

    need = {}
    missing_files = []
    for t in tools:
        if not os.path.exists(t):
            missing_files.append(t)
            continue
        src = io.open(t, encoding="utf-8", newline="").read()
        mods = set(re.findall(r"(?m)^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)", src))
        mods |= set(re.findall(r"(?m)^\s*from\s+([A-Za-z_][A-Za-z0-9_]*)\s+import", src))
        for m in mods:
            if m in sys.stdlib_module_names or m in local:
                continue
            need.setdefault(m, []).append(os.path.basename(t))

    ## ★引用了不存在的审计器脚本 = run-tests.sh 的账已经烂了, 也要红。
    for t in missing_files:
        fails.append("run-tests.sh 登记了 `%s`, 但文件不在盘上" % t)

    if not need:
        print("  [分母] 这些审计器只用标准库 —— 无第三方依赖要装")
    for mod in sorted(need):
        pip = PIP_NAME.get(mod, mod)
        ok = re.search(r"pip\s+install[^\n]*\b%s\b" % re.escape(pip), yml) is not None
        who = ", ".join(sorted(set(need[mod]))[:3])
        print("  [依赖] %-10s (pip: %-14s) 用它的: %-46s → %s"
              % (mod, pip, who, "工作流已装" if ok else "★工作流没装"))
        if not ok:
            fails.append("门禁审计器 import %s, 但 %s 里没有 `pip install %s` "
                         "—— 本机装着就永远本地绿、CI 必红 (用它的: %s)" % (mod, YML, pip, who))

    for x in fails:
        print("  [FAIL] " + x)
    if fails:
        print("")
        print("FAILED: %d 处" % len(fails))
        return 1
    print("")
    print("ALL OK — 门禁依赖与 CI 安装清单一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
