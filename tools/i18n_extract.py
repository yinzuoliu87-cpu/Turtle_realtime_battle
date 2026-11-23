"""tools/i18n_extract.py —— 抽出玩家看得到的中文、与 locale/en.po 对账（2026-11-23 · 方案书 docs/plans/20261118c-语言选项.md §4.3）。

只读（只写 .out/i18n/）。扫三处：
  ① 场景 .tscn 里控件的 text / placeholder_text / tooltip_text（Godot 显示时自动按 en.po 换字）
  ② 脚本 .gd 里带汉字的字符串字面量（去掉注释、print / push_* / assert / 日志里的）
  ③ data/*.json 的文案字段（名字 / 说明 / 技能文案 …）
不扫：tests/、tools/、addons/、server/、开发用的实验台 / 调试场 / 地图编辑器（§4.5「不翻的」）、昵称词表。

产物：
  .out/i18n/strings.tsv   每条一行：msgid \t 来源（文件:行）\t 种类（tscn / gd / gd-fmt / json）\t 已译(1/0)
  .out/i18n/todo_<种类>.txt 没译的，按出现次数排
用法：python tools/i18n_extract.py           # 打印各类条数 / 已译数，写产物
      python tools/i18n_extract.py --todo gd  # 只打印某一类没译的（看下一批译什么）
"""
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import i18n_audit  # noqa: E402

HAN = re.compile(r"[一-鿿]")
SKIP_DIRS = ("tests", "tools", "addons", "server", ".godot", ".out", "build", "docs", "locale", ".git")
## 开发用的，不给玩家看（§4.5）
SKIP_FILE_RE = re.compile(r"(vfxlab|vfx_lab|debug|mapedit|map_edit|review_stage|eqdemo|_probe|stress|dev_out|audit_)", re.I)
## 这些调用里的字是日志 / 断言，不显示
LOG_CALL = re.compile(r"\b(print|printerr|print_rich|push_error|push_warning|assert|_log|_dbg|_trace|log_line|prints)\s*\($")
TSCN_PROP = re.compile(r'^(text|placeholder_text|tooltip_text|title)\s*=\s*"(.*)"\s*$')
## json 里这些键的值是给玩家看的
JSON_KEYS = {"name", "desc", "description", "brief", "text", "title", "label", "tip", "hint", "short", "lore", "flavor",
             "skillName", "skillDesc", "passiveName", "passiveDesc", "detail", "summary", "body", "caption", "role",
             "type", "typeName", "effect", "note", "line", "lines", "say", "msg", "message", "subtitle", "button"}
JSON_SKIP_FILES = {"nickname-words.json", "ghost_seed.json", "determinism_cross.json"}
FMT = re.compile(r"%(?:%|[-+0]*\d*(?:\.\d+)?[sdifxXcv])")


def _gd_strings(line):
    """一行 GDScript → [(字面量内容, 字面量前面那段代码)]；遇到不在字符串里的 # 就停（注释）。"""
    out = []
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if c == "#":
            break
        if c in "\"'":
            q = c
            if line.startswith(q * 3, i):          # 三引号（少见，按一行内处理）
                j = line.find(q * 3, i + 3)
                if j < 0:
                    break
                out.append((line[i + 3:j], line[:i]))
                i = j + 3
                continue
            j = i + 1
            buf = []
            while j < n and line[j] != q:
                if line[j] == "\\" and j + 1 < n:
                    nx = line[j + 1]
                    buf.append({"n": "\n", "t": "\t", "\"": "\"", "'": "'", "\\": "\\"}.get(nx, "\\" + nx))
                    j += 2
                    continue
                buf.append(line[j])
                j += 1
            pre = line[:i]
            if i > 0 and line[i - 1] in "&^":          # StringName / NodePath 字面量
                pre = None
            if pre is not None:
                out.append(("".join(buf), pre))
            i = j + 1
            continue
        i += 1
    return out


def _is_log(pre):
    p = pre.rstrip()
    ## 最近一个还没闭合的左括号前面那个名字
    depth = 0
    for k in range(len(p) - 1, -1, -1):
        ch = p[k]
        if ch == ")":
            depth += 1
        elif ch == "(":
            if depth == 0:
                return bool(LOG_CALL.search(p[:k + 1]))
            depth -= 1
    return False


def scan_gd(path, rel, sink):
    try:
        lines = io.open(path, encoding="utf-8").read().splitlines()
    except UnicodeDecodeError:
        return
    for ln_no, line in enumerate(lines, 1):
        s = line.strip()
        if s.startswith("#") or s.startswith("##"):
            continue
        for lit, pre in _gd_strings(line):
            if not HAN.search(lit) or _is_log(pre):
                continue
            kind = "gd-fmt" if FMT.search(lit) else "gd"
            sink(lit, "%s:%d" % (rel, ln_no), kind)


def scan_tscn(path, rel, sink):
    for ln_no, line in enumerate(io.open(path, encoding="utf-8").read().splitlines(), 1):
        m = TSCN_PROP.match(line.strip())
        if m and HAN.search(m.group(2)):
            v = m.group(2).replace('\\"', '"').replace("\\n", "\n")
            sink(v, "%s:%d" % (rel, ln_no), "tscn")


def scan_json(path, rel, sink):
    try:
        data = json.load(io.open(path, encoding="utf-8"))
    except Exception:
        return

    def walk(v, key, trail):
        if isinstance(v, dict):
            for k, x in v.items():
                walk(x, k, trail + "." + str(k))
        elif isinstance(v, list):
            for i, x in enumerate(v):
                walk(x, key, trail + "[%d]" % i)
        elif isinstance(v, str) and HAN.search(v) and (key in JSON_KEYS or key is None or True):
            sink(v, "%s:%s" % (rel, trail.lstrip(".")), "json")
    walk(data, None, "")


def collect():
    found = {}   # msgid -> {"src": [...], "kind": str}

    def sink(msgid, src, kind):
        e = found.setdefault(msgid, {"src": [], "kind": kind})
        e["src"].append(src)
        if kind == "tscn":
            e["kind"] = "tscn"
    for base, dirs, files in os.walk(ROOT):
        rel_base = os.path.relpath(base, ROOT).replace("\\", "/")
        top = rel_base.split("/")[0]
        if rel_base != "." and (top in SKIP_DIRS or rel_base.startswith(".")):
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for f in files:
            rel = (rel_base + "/" + f) if rel_base != "." else f
            if SKIP_FILE_RE.search(rel):
                continue
            p = os.path.join(base, f)
            if f.endswith(".gd"):
                scan_gd(p, rel, sink)
            elif f.endswith(".tscn"):
                scan_tscn(p, rel, sink)
            elif f.endswith(".json") and top == "data" and f not in JSON_SKIP_FILES:
                scan_json(p, rel, sink)
    return found


def main(argv):
    found = collect()
    po = {}
    if os.path.exists(i18n_audit.PO):
        for mid, mstr, _ in i18n_audit.parse(io.open(i18n_audit.PO, encoding="utf-8").read()):
            po[mid] = mstr
    out_dir = os.path.join(ROOT, ".out", "i18n")
    os.makedirs(out_dir, exist_ok=True)
    kinds = {}
    rows = []
    for mid, e in found.items():
        done = 1 if po.get(mid, "") != "" else 0
        k = kinds.setdefault(e["kind"], [0, 0, 0, 0])
        k[0] += 1
        k[1] += done
        k[2] += len(mid)
        k[3] += len(mid) * done
        rows.append((mid, e, done))
    with io.open(os.path.join(out_dir, "strings.tsv"), "w", encoding="utf-8", newline="\n") as fh:
        for mid, e, done in sorted(rows, key=lambda r: (r[1]["kind"], r[1]["src"][0])):
            fh.write("%s\t%s\t%s\t%d\n" % (mid.replace("\n", "\\n").replace("\t", "\\t"), e["src"][0], e["kind"], done))
    for kind in kinds:
        todo = sorted([r for r in rows if r[1]["kind"] == kind and not r[2]], key=lambda r: (-len(r[1]["src"]), r[1]["src"][0]))
        with io.open(os.path.join(out_dir, "todo_%s.txt" % kind), "w", encoding="utf-8", newline="\n") as fh:
            for mid, e, _ in todo:
                fh.write("%s\t%s\n" % (e["src"][0], mid.replace("\n", "\\n")))
    if len(argv) > 2 and argv[1] == "--todo":
        sys.stdout.write(io.open(os.path.join(out_dir, "todo_%s.txt" % argv[2]), encoding="utf-8").read())
        return 0
    tot = [0, 0, 0, 0]
    print("种类      条数   已译   字数    已译字数")
    for kind in sorted(kinds):
        k = kinds[kind]
        print("%-8s %5d  %5d  %6d  %6d" % (kind, k[0], k[1], k[2], k[3]))
        for i in range(4):
            tot[i] += k[i]
    print("%-8s %5d  %5d  %6d  %6d  （%.0f%% 字数已译）" % ("合计", tot[0], tot[1], tot[2], tot[3], 100.0 * tot[3] / max(1, tot[2])))
    stale = [m for m in po if m not in found]
    print("en.po 里有、代码里已经没有的: %d 条" % len(stale))
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main(sys.argv))
