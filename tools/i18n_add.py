"""tools/i18n_add.py —— 把一批译文并进 locale/en.po（2026-11-23 · 方案书 docs/plans/20261118c-语言选项.md §4.3）。

输入：UTF-8 文本，每行「中文原文<TAB>English」；原文 / 译文里的换行写成 \\n。空行与 # 开头的行跳过。
  已有同一原文 ⇒ 用新译文替换（不重复）；译文里还有汉字 ⇒ 拒收这一行（打印出来）。
用法：python tools/i18n_add.py <批次文件>…
写完自动跑一遍 i18n_audit（占位符 / 重复 / 汉字），不过就报错退出（en.po 已写，按报错修）。
"""
import io
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PO = os.path.join(ROOT, "locale", "en.po")
HAN = re.compile(r"[一-鿿]")


def esc(s):
    return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t")


def main(paths):
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import i18n_audit
    text = io.open(PO, encoding="utf-8").read().replace("\r\n", "\n")
    head_end = text.find("\n\n") + 2          # 头部（msgid "" 那一段）到第一个空行
    head = text[:head_end]
    entries = [(m, s) for m, s, _ in i18n_audit.parse(text)]
    idx = {m: i for i, (m, _) in enumerate(entries)}
    added = replaced = rejected = 0
    for p in paths:
        for ln in io.open(p, encoding="utf-8").read().splitlines():
            if not ln.strip() or ln.startswith("#"):
                continue
            if "\t" not in ln:
                print("缺 TAB:", ln)
                rejected += 1
                continue
            zh, en = ln.split("\t", 1)
            zh = zh.replace("\\n", "\n")
            en = en.replace("\\n", "\n")
            if HAN.search(en) or not en.strip():
                print("译文有汉字 / 为空:", ln)
                rejected += 1
                continue
            if zh in idx:
                if entries[idx[zh]][1] != en:
                    entries[idx[zh]] = (zh, en)
                    replaced += 1
            else:
                idx[zh] = len(entries)
                entries.append((zh, en))
                added += 1
    body = "".join('msgid "%s"\nmsgstr "%s"\n\n' % (esc(m), esc(s)) for m, s in entries)
    io.open(PO, "w", encoding="utf-8", newline="\n").write(head + body.rstrip("\n") + "\n")
    print("新增 %d 条 / 改 %d 条 / 拒收 %d 条；en.po 共 %d 条" % (added, replaced, rejected, len(entries)))
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "i18n_audit.py")], capture_output=True, text=True, encoding="utf-8")
    print(r.stdout.strip().splitlines()[-1] if r.stdout.strip() else r.stderr)
    return 0 if (r.returncode == 0 and rejected == 0) else 1


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main(sys.argv[1:]))
