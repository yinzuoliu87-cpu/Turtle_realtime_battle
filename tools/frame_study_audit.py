# -*- coding: utf-8 -*-
"""frame_study_audit.py — 「逐帧研究过」必须有逐帧凭据，否则当场红。

★★为什么有这个东西（用户 2026-09-09）：
  「我这样子强调让你拿 100 帧看，你才一张张完整的看，那看来以后我让你看参考某个东西
    都必须 1000 帧起步，不然你这个撒谎精是会直接跳着看几张，然后告诉用户你学会了怎么参考的」

  这是实情。同一天我就犯了两次：拿**缩略接触印相**扫一眼就给 009 的旧特效下结论
  （判成"一整块几乎不透明的实心板"，而实际是**从 alpha 0 淡入、脉动、龟画在它上面**，
  方向整个判反），被推着看原图才发现。

  memory `fb-weld-visual-lessons-into-gate` 说得很清楚：**memory 靠我想起来，门禁自己会红。**
  所以这条不写进 memory，写成门禁。

★判据（就一条，但它焊得住）：
  `docs/studies/*.md` 里每份研究都要**声明帧数**（"共 **N** 帧"），
  并且正文里有 **N 行**逐帧记录，帧号必须是 **0..N-1 连续无缺号无重复**，每行都要有非空观察。
  ⇒ 跳着看几帧就写"研究过"时，行数对不上、帧号不连续，当场红。

★为什么判据落在"行数与帧号"而不是"有没有这个文件"：
  「有文件」是我随手就能满足的；「0..N-1 一行不缺」不逐帧看写不出来。
  同族: memory `fb-verify-check-can-fail`（打印分母，N=0 是空检查不是通过）。
"""
import glob
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUDY_DIR = os.path.join(ROOT, "docs", "studies")

DECL = re.compile(r"共\s*\*{0,2}(\d+)\*{0,2}\s*帧")
ROW = re.compile(r"^\|\s*(\d+)\s*\|(.*)$")


def check(path):
    """返回 (ok, 消息列表)。"""
    msgs = []
    name = os.path.basename(path)
    with open(path, encoding="utf-8", newline="") as f:
        text = f.read()

    m = DECL.search(text)
    if not m:
        return False, ["[FAIL] %s: 没有声明帧数(要写「共 N 帧」) —— 没有分母就没有判据" % name]
    declared = int(m.group(1))

    nums = []
    empty = 0
    for line in text.split("\n"):
        r = ROW.match(line)
        if not r:
            continue
        nums.append(int(r.group(1)))
        cells = [c.strip() for c in r.group(2).split("|")]
        # 最后一格是观察内容(行尾可能有个空格分出来的空格子, 过滤掉)
        body = [c for c in cells if c]
        ## ★判据只要求"非空", 不要求长度: 第一版写成 len>=2, 结果把"同""峰"这类
        ##   **单个汉字**的合法观察判成空(45 行误报)。判据宽一格会造假 bug、
        ##   窄一格会放过真 bug —— 这里要卡的是"有没有写", 不是"写了多少字"。
        if len(body) < 2 or not body[-1]:
            empty += 1

    msgs.append("  %s: 声明 %d 帧, 逐帧记录 %d 行" % (name, declared, len(nums)))

    ok = True
    if len(nums) != declared:
        msgs.append("[FAIL] %s: 声明 %d 帧但只有 %d 行逐帧记录 —— 跳着看了 %d 帧"
                    % (name, declared, len(nums), declared - len(nums)))
        ok = False
    want = list(range(declared))
    if sorted(nums) != want:
        missing = sorted(set(want) - set(nums))
        dup = sorted([n for n in set(nums) if nums.count(n) > 1])
        detail = []
        if missing:
            detail.append("缺帧 %s%s" % (missing[:12], " ..." if len(missing) > 12 else ""))
        if dup:
            detail.append("重复 %s" % dup[:12])
        extra = sorted(set(nums) - set(want))
        if extra:
            detail.append("越界帧号 %s" % extra[:12])
        msgs.append("[FAIL] %s: 帧号不是 0..%d 连续 —— %s" % (name, declared - 1, "; ".join(detail)))
        ok = False
    if empty:
        msgs.append("[FAIL] %s: 有 %d 行没写观察内容 —— 占位不算看过" % (name, empty))
        ok = False
    return ok, msgs


def main():
    print("== frame_study_audit: 「逐帧研究过」必须有逐帧凭据 ==")
    if not os.path.isdir(STUDY_DIR):
        print("  docs/studies/ 不存在 —— 分母 0, 跳过(不是通过)")
        return 0
    files = sorted(glob.glob(os.path.join(STUDY_DIR, "*.md")))
    print("  ★分母: 找到 %d 份逐帧研究" % len(files))
    if not files:
        return 0
    bad = 0
    for p in files:
        ok, msgs = check(p)
        for m in msgs:
            print(m)
        if not ok:
            bad += 1
    print("  共 %d 份, 不合格 %d 份" % (len(files), bad))
    if bad:
        print("FAILED")
        return 1
    print("ALL OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
