# -*- coding: utf-8 -*-
"""tools/coroutine_await_audit.py —— 门禁里「协程被当普通函数调用」的静态审计。

★为什么要有这条: 2026-09-23 在 `verify_finals_feed` 上栽过一次 ——
  `_t_no_spoiler()` / `_t_real_request()` 里有 `await`, 却是**裸调用**。
  GDScript 不报错, 它只是"启动一下就往下走":
    · 判据的执行顺序乱掉(⑤ 的结果先于 ② 打出来)
    · `get_tree().quit()` 可能在尾巴还没跑完时就开了 ⇒ **后面的断言一条都不跑**
  代价是实打实的: 那份门禁**三条断言从来没执行过**, 而总数稳定在 47、还打着 ALL PASS。
  一条变异(拿掉「匿名号不发请求」那道闸)因此**没红** —— 我差点判成"这条判据是恒真式"。
  改成 `await` 之后 47 → 50。

★判据形状: 函数体里有 `await` ⇒ 它是协程 ⇒ **所有调用点都必须带 `await`**。
  例外只有一种: 故意"发完就忘"的(`_fire_and_forget` 前缀, 或同行写了 `# nowait`)。
  —— 门禁里不该有这种, 所以默认一个都不许有, 要就显式标出来。

★只扫 `tests/`: 产品代码里 fire-and-forget 是常规手法(网络请求发完就忘),
  而**门禁里它等于静默截断断言**, 性质完全不同。

跑法: python tools/coroutine_await_audit.py     (进 run-tests.sh 门禁)
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FUNC_RE = re.compile(r"^func\s+([A-Za-z_]\w*)\s*\(", re.M)


def scan(path):
    """→ [(行号, 函数名, 那一行原文)]"""
    src = io.open(path, encoding="utf-8", newline="").read()
    lines = src.split("\n")

    # ① 找出哪些函数是协程(函数体里出现 await)
    starts = [(m.start(), m.group(1)) for m in FUNC_RE.finditer(src)]
    coro = set()
    for i, (pos, name) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(src)
        ## ★先剥注释再找 await —— 注释里写着「不 await 帧」的纯 getter
        ##   第一版被当成了协程, 一个人拖出 105 条误报。
        body = "\n".join(x.split("#")[0] for x in src[pos:end].split("\n"))
        if re.search(r"\bawait\b", body):
            coro.add(name)
    if not coro:
        return []

    # ② 每一行属于哪个函数(按行号切), 用来判断"这一行后面还有没有代码"
    line_of = [0] * (len(lines) + 2)
    starts_ln = sorted([(src[:pos].count("\n") + 1, name) for pos, name in starts])
    owner = {}
    for i, (ln0, name) in enumerate(starts_ln):
        end = starts_ln[i + 1][0] - 1 if i + 1 < len(starts_ln) else len(lines)
        for k in range(ln0, end + 1):
            owner[k] = (ln0, end)

    def next_stmt(ln):
        """同一个函数里, 这一行之后的**第一句实质语句**(跳空行与注释)。"""
        rng = owner.get(ln)
        if rng is None:
            return ""
        for k in range(ln + 1, rng[1] + 1):
            t = lines[k - 1].split("#")[0].strip()
            if t == "":
                continue
            return t
        return ""

    def loses_assertions(ln, same_line_tail):
        """裸调用会不会真的丢断言。

        ★**尾调用不算**: `_done(s); return` 或下一句就是 `return` 的,
          协程启动 → 撞到第一个 await → 把控制权交回来 → 调用者 return →
          协程接着跑完, 结果跟 await 一样, 一条断言都不丢。
          第一版判据没排这个形状, 182 处里绝大多数是它 ——
          **判据宽一格就会造出假 bug**(memory `fb-judge-must-fit-the-shape`)。
        """
        if same_line_tail == "return" or same_line_tail.startswith("return "):
            return False
        nxt = next_stmt(ln)
        if nxt == "" or nxt == "return" or nxt.startswith("return "):
            return False
        return True

    # ③ 找裸调用。★只有**后面还有代码**的才算 ——
    #    `_done(s); return` 这种尾调用结果跟 await 一样, 一条断言都不丢。
    bad = []
    for ln, line in enumerate(lines, 1):
        code = line.split("#")[0]
        if code.strip().startswith("func "):
            continue
        if "# nowait" in line:
            continue
        for name in coro:
            if name.startswith("_fire_and_forget"):
                continue
            for m in re.finditer(r"(?<![\w.])" + re.escape(name) + r"\s*\(", code):
                before = code[:m.start()]
                if re.search(r"\bawait\b[^\n]*$", before):
                    continue
                # ★同一行里 `xxx(); return` 也算尾调用
                after_same_line = code[m.start():]
                tail = after_same_line.split(";", 1)[1].strip() if ";" in after_same_line else ""
                if loses_assertions(ln, tail):
                    bad.append((ln, name, line.strip()))
                    break
    return bad


def main():
    tests = sorted(f for f in os.listdir(os.path.join(ROOT, "tests"))
                   if f.startswith("verify_") and f.endswith(".gd"))
    total = 0
    files = 0
    print("=== 协程裸调用审计 (tests/) ===")
    print("  分母: 扫了 %d 个 verify_*.gd" % len(tests))
    if not tests:
        print("[FAIL] 一个测试文件都没扫到 —— 这是空检查不是通过")
        return 1
    for f in tests:
        hits = scan(os.path.join(ROOT, "tests", f))
        if hits:
            files += 1
            total += len(hits)
            print("")
            print("  [FAIL] tests/%s" % f)
            for ln, name, text in hits:
                print("         %s:%d  %s()  ←  %s" % (f, ln, name, text[:90]))
    print("")
    if total:
        print("[FAIL] %d 处协程裸调用, 分布在 %d 个文件" % (total, files))
        print("       这些函数体里有 await ⇒ 裸调用只是「启动一下就往下走」,")
        print("       后面的断言可能一条都不跑, 而总数看着稳定、照样打 ALL PASS。")
        print("       修法: 调用点加 `await`; 真要发完就忘, 那一行写 `# nowait` 说明理由。")
        return 1
    print("[PASS] ALL OK —— 没有协程裸调用 (扫了 %d 个门禁文件)" % len(tests))
    return 0


if __name__ == "__main__":
    sys.exit(main())
