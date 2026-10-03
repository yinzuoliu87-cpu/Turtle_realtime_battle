# -*- coding: utf-8 -*-
"""tools/freed_is_order_audit.py —— 「先 is 后 is_instance_valid」一律判红。

由来(2026-10-03 周六 10 窗口实操台账 S7): 三个特效文件每帧刷
「Left operand of 'is' is a previously freed instance」, 一场几千行。
探针实测(Godot 4.6.3): 对**已释放**的对象做 `x is T` 本身就是 SCRIPT ERROR,
而且**会中断整个函数** —— 特效的推进循环一碰到就整段停掉(不只是刷屏)。
写成 `not (x is T) or not is_instance_valid(x)` 时, 守卫自己先炸了, 后面那半句永远轮不到。
⇒ 必须先 `is_instance_valid(x)`, 再 `x is T`。全仓当时 60 处, 已全部翻转。
"""
import glob, io, re, sys
sys.stdout.reconfigure(encoding="utf-8")
PATS = [
    re.compile(r"not \((\w+) is \w+\) or not is_instance_valid\(\1\)"),
    re.compile(r"(\()?\b(\w+) is \w+(?(1)\)) and is_instance_valid\(\2\)"),
]
bad = []
files = glob.glob("scripts/**/*.gd", recursive=True) + glob.glob("autoload/**/*.gd", recursive=True)
for P in files:
    for i, line in enumerate(io.open(P, encoding="utf-8").read().split("\n"), 1):
        for p in PATS:
            if p.search(line):
                bad.append("%s:%d  %s" % (P.replace("\\", "/"), i, line.strip()[:120]))
print("  [分母] 扫了 %d 个 .gd" % len(files))
if len(files) < 50:
    print("  [FAIL] 扫到的文件太少, 路径不对(空检查不算通过)")
    sys.exit(1)
if bad:
    for b in bad:
        print("  [FAIL] 先 is 后 is_instance_valid(对已释放对象 is 会报错并中断函数): " + b)
    print("FAIL x%d" % len(bad))
    sys.exit(1)
print("ALL OK — 没有「先 is 后 is_instance_valid」的守卫")
