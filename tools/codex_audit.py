# -*- coding: utf-8 -*-
"""codex_audit.py — 图鉴文案 ↔ 活代码 ↔ 权威文档 三方并排

用法（必须在项目根跑，python 读不了 Git Bash 的 /c/... 路径）:
    python tools/codex_audit.py basic stone bamboo angel > C:/tmp/audit.txt

输出（每只龟）:
  [1] pets.json 文案   passive.desc + 每个 skillPool 条目的 name/type/energyCost/brief/detail（已去 HTML 标签）
  [2] 活代码           BASIC_ATK 该龟条目 + 各技的 _sk_* 函数体 + 相关常量 + 战斗龟能口径
  [3] 权威文档         28龟技能设计-权威.md 该龟整节

★脚本自检：已知阳性 + 已知阴性探针，判错即 assert 崩。
  （我已两次被自己的解析脚本骗：`find("}")` 被注释里的 {N/M/T:...} 截断；os.walk 反斜杠路径让定义行被当成调用方。）
"""
import io, json, re, sys, os

BATTLE = "scripts/scenes/RealtimeBattle3DScene.gd"
PETS = "data/pets.json"
DOC = "docs/design/28龟技能设计-权威.md"

TAG = re.compile(r"<[^>]+>")


def strip(s):
    return TAG.sub("", str(s)).replace("\n", "\n      ")


def read(p):
    return io.open(p, encoding="utf-8").read()


# ── 源码块解析: 真括号配对 + 先去注释 ──────────────────────────
def dict_block(src, name):
    i = src.find("const %s := {" % name)
    if i < 0:
        return ""
    j = src.find("{", i)
    depth, k = 0, j
    while k < len(src):
        c = src[k]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        k += 1
    return src[j:k + 1]


def basic_atk_entry(src, pid):
    body = dict_block(src, "BASIC_ATK")
    for line in body.split("\n"):
        if re.match(r'\s*"%s"\s*:' % re.escape(pid), line):
            return line.strip()
    return "(BASIC_ATK 无此龟 → 走专用分支)"


def func_body(src, fname):
    """取 `func fname(` 到下一个顶层 func 之前。"""
    m = re.search(r'^(?:static )?func %s\(' % re.escape(fname), src, re.M)
    if not m:
        return None
    lines = src[m.start():].split("\n")
    out = [lines[0]]
    for l in lines[1:]:
        if l.startswith("func ") or l.startswith("static func ") or l.startswith("const ") or l.startswith("var "):
            break
        out.append(l)
    while out and out[-1].strip() == "":
        out.pop()
    return "\n".join(out)


def dispatch_line(src, sktype):
    for line in src.split("\n"):
        if re.search(r'"%s"\s*:' % re.escape(sktype), line) and ("_sk_" in line or "_sk_dmg" in line):
            return line.strip()
    return None


def doc_section(doc, pid, name):
    m = re.search(r"^## \d+\.\s*%s（%s）" % (re.escape(name), re.escape(pid)), doc, re.M)
    if not m:
        m = re.search(r"^## \d+\..*?（%s）" % re.escape(pid), doc, re.M)
    if not m:
        return "(权威文档未找到该龟小节)"
    nxt = re.search(r"^## \d+\.", doc[m.end():], re.M)
    end = m.end() + (nxt.start() if nxt else len(doc) - m.end())
    return doc[m.start():end]


# ── 自检探针 ────────────────────────────────────────────────
def self_test(src, pets):
    b = dict_block(src, "_IMPL_SKILLS")
    keys = set(re.findall(r'"([A-Za-z_]+)"\s*:\s*true', re.sub(r"#[^\n]*", "", b)))
    assert "basicChiWave" in keys, "自检失败: 括号配对解析漏了 basicChiWave（八成又被注释里的 {N/M/T:...} 截断）"
    assert len(keys) > 50, "自检失败: _IMPL_SKILLS 只解析到 %d 条" % len(keys)
    assert func_body(src, "_sk_line_link") is not None, "自检失败: 已知存在的函数没抓到"
    assert func_body(src, "_sk_no_such_function_zz") is None, "自检失败: 不存在的函数被判成存在"
    pj = {p["id"]: p for p in pets}
    for s in pj["pirate"]["skillPool"]:
        if s.get("type") == "pirateCannonBarrage":
            assert "800" in s.get("detail", ""), "自检失败: pets.json 读到的不是最新文案"
    return len(keys)


def main():
    ids = sys.argv[1:]
    if not ids:
        print("用法: python tools/codex_audit.py <pet_id>...")
        return
    src = read(BATTLE)
    pets = json.load(io.open(PETS, encoding="utf-8"))
    doc = read(DOC)
    n = self_test(src, pets)
    out = io.open("C:/tmp/audit.txt", "w", encoding="utf-8")
    out.write("SELF-TEST OK (_IMPL_SKILLS=%d 条)\n\n" % n)

    by = {p["id"]: p for p in pets}
    for pid in ids:
        p = by[pid]
        out.write("=" * 100 + "\n")
        out.write("### %s  %s\n" % (pid, p.get("name", "")))
        out.write("=" * 100 + "\n\n")

        out.write("[1] pets.json 文案（图鉴显示的就是这个）\n")
        pas = p.get("passive") or {}
        out.write("  被动 %s (%s)\n      %s\n\n" % (pas.get("name", ""), pas.get("type", ""), strip(pas.get("desc") or pas.get("brief", ""))))
        for i, s in enumerate(p.get("skillPool", [])):
            role = "普攻" if i == 0 else "候选%d" % i
            out.write("  idx%d %s  %s (%s)  龟能=%s\n" % (i, role, s.get("name", ""), s.get("type", ""), s.get("energyCost", "—")))
            out.write("      brief : %s\n" % strip(s.get("brief", "")))
            out.write("      detail: %s\n\n" % strip(s.get("detail", "")))

        out.write("[2] 活代码\n")
        out.write("  BASIC_ATK: %s\n\n" % basic_atk_entry(src, pid))
        for i, s in enumerate(p.get("skillPool", [])):
            ty = str(s.get("type", ""))
            if i == 0 or ty in ("physical", "magic"):
                continue
            d = dispatch_line(src, ty)
            out.write("  --- %s (%s) ---\n" % (s.get("name", ""), ty))
            out.write("  分派: %s\n" % (d or "(未在 match 里找到 → 可能走数据驱动 _sk_dmg)"))
            fn = None
            if d and "_sk_" in d:
                m = re.search(r"(_sk_[a-z0-9_]+)\(", d)
                if m:
                    fn = m.group(1)
            if fn:
                body = func_body(src, fn)
                out.write("%s\n\n" % (body if body else "  (函数体未找到)"))
            else:
                out.write("\n")

        out.write("[3] 权威文档小节\n")
        out.write(doc_section(doc, pid, p.get("name", "")) + "\n\n")
    out.close()
    print("wrote C:/tmp/audit.txt")


if __name__ == "__main__":
    main()
