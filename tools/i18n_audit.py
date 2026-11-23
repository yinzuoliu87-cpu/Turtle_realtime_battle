"""tools/i18n_audit.py —— 英文译文表 locale/en.po 对账(2026-11-18 · 方案书 docs/plans/20261118c-语言选项.md §4.3)。

只读。判红(退出码 1)的只有会让游戏显示出错的:
  ① 占位符对不上: msgid 与 msgstr 里的 `%d / %s / %.1f …`【个数与先后】必须一样(Godot 的 `%` 按位置填, 换了顺序就把数字填错地方);
     `{N:表达式}` 一类技能模板占位与 `[b] [color=…]` 一类 BBCode 标签按【种类与个数】比(英文语序可以挪)。
  ② 同一个 msgid 出现两次(后一条会悄悄盖掉前一条)。
  ③ msgstr 里还有汉字(译了一半)。
只报数不判红: 没译的(msgstr 为空)—— 第一期允许逐批补。

用法: python tools/i18n_audit.py            # 对账, ALL OK / FAIL
      python tools/i18n_audit.py --selftest  # 判据自检: 造几条坏的必须判红
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PO = os.path.join(ROOT, "locale", "en.po")
FMT = re.compile(r"%(?:%|[-+0]*\d*(?:\.\d+)?[sdifxXcv])")
TPL = re.compile(r"\{[A-Za-z]+:[^{}]*\}")
BB = re.compile(r"\[/?(?:b|i|u|s|color|font_size|outline_size|outline_color|center|right|img|url|ul|ol|wave|shake|bgcolor|fgcolor|table|cell)\b[^\]]*\]")
HAN = re.compile(r"[一-鿿]")


def _unq(s):
    return bytes(s, "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in s else s


def parse(text):
    """→ [(msgid, msgstr, 行号)]。只认本工程写法: msgid / msgstr 各一段, 可续行(下一行以 \" 开头)。"""
    out = []
    cur = None
    key = None
    line_no = 0
    for i, raw in enumerate(text.splitlines(), 1):
        ln = raw.strip()
        if ln.startswith("#") or ln == "":
            continue
        m = re.match(r'^(msgid|msgstr)\s+"(.*)"$', ln)
        if m:
            if m.group(1) == "msgid":
                if cur is not None:
                    out.append((cur["msgid"], cur.get("msgstr", ""), cur["line"]))
                cur = {"msgid": _unq(m.group(2)), "line": i}
                key = "msgid"
            else:
                if cur is None:
                    continue
                cur["msgstr"] = _unq(m.group(2))
                key = "msgstr"
            continue
        m = re.match(r'^"(.*)"$', ln)
        if m and cur is not None and key:
            cur[key] = cur.get(key, "") + _unq(m.group(1))
    if cur is not None:
        out.append((cur["msgid"], cur.get("msgstr", ""), cur["line"]))
    return [e for e in out if e[0] != ""]   # 头部那条(msgid "")不算


def check(entries):
    """→ (红的列表, 没译的个数)。"""
    bad = []
    seen = {}
    missing = 0
    for mid, mstr, ln in entries:
        if mid in seen:
            bad.append("第 %d 行: msgid 重复(第 %d 行已有): %s" % (ln, seen[mid], mid[:40]))
        seen[mid] = ln
        if mstr == "":
            missing += 1
            continue
        if FMT.findall(mid) != FMT.findall(mstr):
            bad.append("第 %d 行: %%占位符先后 / 个数不同 %s ≠ %s: %s" % (ln, FMT.findall(mid), FMT.findall(mstr), mid[:40]))
        if sorted(TPL.findall(mid)) != sorted(TPL.findall(mstr)):
            bad.append("第 %d 行: {X:…} 模板占位不同: %s" % (ln, mid[:40]))
        tags_a = sorted(re.sub(r"=[^\]]*", "", t) for t in BB.findall(mid))
        tags_b = sorted(re.sub(r"=[^\]]*", "", t) for t in BB.findall(mstr))
        if tags_a != tags_b:
            bad.append("第 %d 行: BBCode 标签不同 %s ≠ %s: %s" % (ln, tags_a, tags_b, mid[:40]))
        if HAN.search(mstr):
            bad.append("第 %d 行: 译文里还有汉字: %s" % (ln, mstr[:40]))
    return bad, missing


def selftest():
    cases = [
        ('msgid "%d 胜"\nmsgstr "%d W"\n', 0),
        ('msgid "%d 胜 %s"\nmsgstr "%s %d W"\n', 1),            # 先后换了
        ('msgid "%d 胜"\nmsgstr "W"\n', 1),                      # 少了
        ('msgid "造成 {N:atk} 伤害"\nmsgstr "Deals damage"\n', 1),
        ('msgid "[b]胜[/b]"\nmsgstr "Win"\n', 1),
        ('msgid "胜"\nmsgstr "胜利 Win"\n', 1),                   # 译一半
        ('msgid "胜"\nmsgstr "Win"\nmsgid "胜"\nmsgstr "W"\n', 1),  # 重复
        ('msgid "胜"\nmsgstr ""\n', 0),                          # 没译只报数
    ]
    fails = 0
    for src, want in cases:
        bad, _ = check(parse(src))
        got = 1 if bad else 0
        ok = got == want
        fails += 0 if ok else 1
        print("  %s 期望%s: %s" % ("ok " if ok else "FAIL", "红" if want else "绿", src.replace("\n", " ⏎ ")[:70]))
    print("ALL OK — 判据自检 %d 条" % len(cases) if fails == 0 else "FAIL — 判据自检 %d 条错" % fails)
    return 0 if fails == 0 else 1


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if "--selftest" in sys.argv:
        return selftest()
    if not os.path.exists(PO):
        print("FAIL — 没有 %s" % PO)
        return 1
    entries = parse(io.open(PO, encoding="utf-8").read())
    bad, missing = check(entries)
    print("[分母] en.po %d 条 · 已译 %d · 没译 %d" % (len(entries), len(entries) - missing, missing))
    if len(entries) == 0:
        print("FAIL — 一条都没读到(解析坏了 = 空检查)")
        return 1
    if bad:
        for b in bad[:40]:
            print("  ✗ " + b)
        print("FAIL — %d 处会让游戏显示出错" % len(bad))
        return 1
    st = selftest()
    if st != 0:
        return 1
    print("ALL OK — en.po 占位符 / 标签 / 无重复 / 无半译")
    return 0


if __name__ == "__main__":
    sys.exit(main())
