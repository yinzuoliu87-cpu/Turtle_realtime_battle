"""一次性: 给「带汉字、带 %d/%s 的模板 % 值」套上 Lang.t()（2026-11-23 · 方案书 20261118c §4.1）。
只改 .gd；跳过注释、日志调用、开发 / 裁判 / 校验用的文件。按行改，保留原行尾。打印改了几处。"""
import os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import i18n_extract as X
ROOT = X.ROOT
SKIP = ("scripts/referee/", "scripts/net/remote_pool.gd", "scripts/systems/replay/replay_recorder.gd",
        "scripts/systems/sim/", "scripts/gamedata/copy_rules.gd")
LIT = re.compile(r'(?<![\w.(])("(?:[^"\\n]|\.)*")(\s*%\s*)')
FMT = X.FMT
HAN = X.HAN
total = 0
files = 0
for base, dirs, fs in [w for d in ("scripts", "autoload") for w in os.walk(os.path.join(ROOT, d))]:
    for f in fs:
        if not f.endswith(".gd"):
            continue
        p = os.path.join(base, f)
        rel = os.path.relpath(p, ROOT).replace("\\", "/")
        if rel.startswith(SKIP) or X.SKIP_FILE_RE.search(rel):
            continue
        b = open(p, "rb").read()
        nl = "\r\n" if b.count(b"\r\n") > b.count(b"\n") / 2 else "\n"
        lines = b.decode("utf-8").replace("\r\n", "\n").split("\n")
        n = 0
        for i, line in enumerate(lines):
            st = line.strip()
            if st.startswith("#"):
                continue
            # 注释开始位置（不在字符串里的 #）
            cut = len(line)
            q = None
            k = 0
            while k < len(line):
                c = line[k]
                if q:
                    if c == "\\":
                        k += 2
                        continue
                    if c == q:
                        q = None
                elif c in "\"'":
                    q = c
                elif c == "#":
                    cut = k
                    break
                k += 1
            code = line[:cut]
            out = []
            last = 0
            for m in LIT.finditer(code):
                lit = m.group(1)
                if not HAN.search(lit) or not FMT.search(lit):
                    continue
                pre = code[:m.start()]
                if X._is_log(pre) or pre.rstrip().endswith("Lang.t(") or pre.rstrip().endswith("tr("):
                    continue
                out.append(code[last:m.start()] + "Lang.t(" + lit + ")" + m.group(2))
                last = m.end()
                n += 1
            if out:
                lines[i] = "".join(out) + code[last:] + line[cut:]
        if n:
            open(p, "wb").write("\n".join(lines).replace("\n", nl).encode("utf-8"))
            total += n
            files += 1
print("改了 %d 处 / %d 个文件" % (total, files))
