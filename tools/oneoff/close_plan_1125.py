"""close_plan_1125.py —— 方案书收尾(2026-11-25, 方案书 docs/plans/20261125r-项目规则与文档整理.md 4.3)

    python tools/oneoff/close_plan_1125.py <方案书文件名(不带 .md)> <已完成|已作废> <状态行备注> <回填文本文件>

把抬头状态行换成「状态：**<新状态>**（11-25 收尾：<备注>）」, 文末追加「## 实施回填（11-25 收尾核对）」+ 回填文本。
保留原行尾(CRLF / LF)。旧状态行原文留在回填第一行(不丢历史)。
"""
import re, sys

name, new, note, body_file = sys.argv[1:5]
assert new in ("已完成", "已作废")
p = "docs/plans/%s.md" % name
b = open(p, "rb").read().decode("utf-8")
nl = "\r\n" if "\r\n" in b else "\n"
t = b.replace("\r\n", "\n")
lines = t.split("\n")
i = next(k for k, ln in enumerate(lines[:12]) if "状态" in ln)
old = lines[i]
m = re.match(r"^(.*?状态\s*[:：]\s*)(.*)$", old)
assert m, old
prefix = m.group(1)
lines[i] = "%s**%s**（11-25 收尾：%s）" % (prefix, new, note)
body = open(body_file, encoding="utf-8").read().strip("\n")
t = "\n".join(lines).rstrip("\n")
t += "\n\n## 实施回填（11-25 收尾核对）\n\n- 收尾前的状态行原文：%s\n%s\n" % (old.strip(), body)
open(p, "wb").write(t.replace("\n", nl).encode("utf-8"))
print("ok", p, "→", new)
