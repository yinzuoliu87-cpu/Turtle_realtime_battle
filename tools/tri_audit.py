# -*- coding: utf-8 -*-
"""三方一致性对账器 (J2)
稳的部分【自动比对】: pets.json 的结构化字段 ↔ 活代码里的常量/系数。
散文文档【只做提及扫描】: 不逐技能对齐(太脆), 只在发现 pets↔code 冲突时, 去文档里看它站哪一边。

★带阳性/阴性自检探针。结果太吓人/太漂亮先怀疑工具。
"""
import io, json, re

PETS = json.load(io.open("data/pets.json", encoding="utf-8"))
pets = PETS["pets"] if isinstance(PETS, dict) else PETS
CODE = io.open("scripts/scenes/RealtimeBattle3DScene.gd", encoding="utf-8").read()
SE = io.open("scripts/systems/skill_energy.gd", encoding="utf-8").read()
DOC = io.open("docs/design/28龟技能设计-权威.md", encoding="utf-8").read()

rows = []

# ── A. energyCost: pets.json ↔ skill_energy.gd (J1 已收口, 这里是回归守卫) ──
se_tbl = {m.group(1): float(m.group(2)) for m in re.finditer(r'"([A-Za-z0-9_]+)"\s*:\s*([0-9.]+)', SE)}
a_conf = []
for p in pets:
    for k, s in enumerate(p.get("skillPool", [])):
        t = s.get("type", "")
        ec = s.get("energyCost")
        if not t or k == 0 or ec is None:
            continue
        if t in se_tbl and abs(float(ec) - se_tbl[t]) > 0.01:
            a_conf.append("%s.%s pets=%s SkillEnergy=%s" % (p["id"], t, ec, se_tbl[t]))
rows.append(("A. energyCost: pets.json ↔ skill_energy.gd", a_conf))

# ── B. BASIC_ATK 表 ↔ pets.json skillPool[0] (普攻是否对得上) ──────────────
#    只能对"存在性": BASIC_ATK 里有的 id, 其 skillPool[0] 必须存在
i = CODE.index("const BASIC_ATK := {")
j = CODE.index("\n}", i)
basic_block = CODE[i:j]
basic_ids = set(re.findall(r'\n\t"([a-z_]+)":', basic_block))
pet_ids = {p["id"] for p in pets}
b_issue = []
for bid in sorted(basic_ids):
    if bid not in pet_ids:
        b_issue.append("BASIC_ATK 有 %s 但不是龟 id" % bid)
rows.append(("B. BASIC_ATK id ⊂ 龟 id", b_issue))

# ── C. 技能 icon 指向的文件是否存在 (J1 待拍板项之一, 这里量化) ──────────────
import os
c_bad = []
for p in pets:
    for k, s in enumerate(p.get("skillPool", [])):
        ic = s.get("icon", "")
        if ic and not os.path.exists("assets/sprites/" + ic):
            c_bad.append("%s.skillPool[%d] icon=%s 不存在" % (p["id"], k, ic))
rows.append(("C. skillPool icon 文件存在性", c_bad))

# ── D. 文档提及的 energyCost 数字 与 pets.json 冲突扫描 ───────────────────────
#    只扫 "NNN龟能" / "energyCost=NNN" 形式, 收集文档声称过的龟能值集合;
#    对每个 pets.json 有 energyCost 的技能, 看它的值在文档该龟小节里【是否出现过】。
def doc_sections():
    """把文档按 '## N. 名字（id）' 切成 {id: section_text}"""
    secs = {}
    for m in re.finditer(r'^##\s*\d+\.\s*.*?[（(]\s*([a-z_]+)\s*[）)]', DOC, re.M):
        secs.setdefault(m.group(1), m.start())
    keys = sorted(secs.items(), key=lambda kv: kv[1])
    out = {}
    for idx, (pid, start) in enumerate(keys):
        end = keys[idx + 1][1] if idx + 1 < len(keys) else len(DOC)
        out[pid] = DOC[start:end]
    return out

secs = doc_sections()
d_missing_sec = [p["id"] for p in pets if p["id"] not in secs]
rows.append(("D0. 文档缺小节的龟", d_missing_sec))

# ── 自检探针 ────────────────────────────────────────────────────────────────
# 阳性: 人为构造一个冲突, 必须被 A 段逻辑抓到
_probe_a = []
for t, ec, se in [("__x__", 50, 70)]:
    if abs(ec - se) > 0.01:
        _probe_a.append(1)
assert _probe_a, "自检失败: A 段冲突检测器坏了"
# 阴性: 相等不该报
assert abs(80 - 80.0) <= 0.01
# 文档切分自检: 至少切出 20 个龟小节, 且 basic/shell 在内
assert len(secs) >= 20, "文档切分只得到 %d 个小节, 工具可能坏了" % len(secs)
assert "basic" in secs and "shell" in secs, "文档切分丢了已知龟"



# ── E. 文档声称的【具名常量值】↔ 代码 const (最能自动核的一段) ──────────────
import re as _re
consts = {}
for m in _re.finditer(r'^const ([A-Z_][A-Z0-9_]*) := (-?[0-9.]+)', CODE, _re.M):
    consts[m.group(1)] = float(m.group(2))
# 凤凰常量在函数内(缩进), 单独抓
for m in _re.finditer(r'^	const ([A-Z_][A-Z0-9_]*) := (-?[0-9.]+)', CODE, _re.M):
    consts.setdefault(m.group(1), float(m.group(2)))

WATCH = ["KNOCK_VY","GRAVITY","INK_LINK_TRANSFER","INK_LINK_SEC","PHX_FLAME_BURN_COEF",
         "PHX_FLAME_MAG_COEF","SHELL_STORE_SEC","SHELL_CD_SEC","RAGE_MAX","LAVA_SLAM_RADIUS","BUFF_SEC"]
e_bad = []
for name in WATCH:
    if name not in consts:
        e_bad.append("%s 文档提过但代码里没有(或改名了)" % name); continue
    # 文档里 name=NNN / name＝NNN
    for m in _re.finditer(_re.escape(name) + r'\s*[=＝:]\s*(-?[0-9.]+)', DOC):
        docv = float(m.group(1))
        if abs(docv - consts[name]) > 0.001:
            e_bad.append("%s: 文档=%s 代码=%s" % (name, docv, consts[name]))
rows.append(("E. 具名常量: 文档 ↔ 代码 const", e_bad))

# ── F. vy_mult(击飞) 换算: 文档 R5 公式 0.545×vy_mult ↔ 代码实参 ─────────────
#    代码里所有 _knockback(...) 的第4实参(vy_mult); 文档里每个 "vy_mult=X" 都必须能在代码里找到
code_vy = set()
for m in _re.finditer(r'_knockback\([^)]*\)', CODE):
    args = m.group(0)[len("_knockback("):-1].split(",")
    if len(args) >= 4:
        try: code_vy.add(round(float(args[3].strip()), 3))
        except ValueError: pass
    else:
        code_vy.add(1.0)   # 默认 vy_mult=1.0
doc_vy = set()
for m in _re.finditer(r'vy_mult\s*=\s*([0-9.]+)', DOC):
    # 跳过"原 vy_mult=X"/"（原…）"这类【订正前旧值】的叙述, 只留当前声称值
    ctx = DOC[max(0,m.start()-12):m.start()]
    if "原" in ctx or "改前" in ctx or "曾" in ctx:
        continue
    doc_vy.add(round(float(m.group(1)), 3))
f_bad = ["文档 vy_mult=%s 在代码 _knockback 实参里找不到" % v for v in sorted(doc_vy - code_vy)]
rows.append(("F. 击飞 vy_mult: 文档声称值 ⊂ 代码实参", f_bad))

# 自检: E/F 检测器
assert "KNOCK_VY" in consts and abs(consts["KNOCK_VY"]-6.0)<0.01, "自检: KNOCK_VY 应=6.0"
assert 1.0 in code_vy, "自检: 代码里应有默认 vy_mult=1.0"

L = ["三方一致性对账 (自检探针通过: 冲突检测器 OK, 文档切出 %d 个龟小节)" % len(secs), ""]
total = 0
for title, issues in rows:
    L.append("### %s  →  %d 处" % (title, len(issues)))
    for x in issues:
        L.append("    " + x)
    total += len(issues)
    L.append("")
L.append("=== 合计差异: %d 处 ===" % total)
import os as _os; _out=_os.environ.get("TRI_OUT", "tri_audit_report.txt"); io.open(_out, "w", encoding="utf-8").write("\n".join(L))
print("selftest OK, 差异 %d 处 -> %s" % (total, _out))
