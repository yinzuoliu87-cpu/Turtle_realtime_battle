# -*- coding: utf-8 -*-
"""J1 死代码勘察 (静态可达性) —— 只报【能证明不可达】的, 拿不准就标 ⚠。
★工具先自检: 已知阳性(确实可达的 case)必须判活; 已知阴性(编造的 case)必须判死。

可达性前提(已核实活代码):
  · _do_skill(u,tgt,stype) 的调用方只有两处:
      ① _cast_skill  ← 由主动轮转调用, stype ∈ _resolve_active_skills(id) ⊂ _chosen_skill_types(id)
         而 _chosen_skill_types 取 skillPool[_resolve_chosen_index()], 且该函数保证 idx >= 1
         → 【skillPool[0] 的 type (普攻) 永远不会被分派】
      ② 龟壳「复制」_sk_shell_copy → _do_skill(u,tgt,pool[0]) , pool 来自 _COPYABLE 白名单 ∩ 敌方 active_skills
         → 仍然只可能是别的龟的 skillPool[1..3].type
  ⇒ 一个 match case 可达 ⟺ 它出现在某只龟的 skillPool[1..3].type 里
"""
import io, json, re, os

SRC = "scripts/scenes/RealtimeBattle3DScene.gd"
src = io.open(SRC, encoding="utf-8").read()

# ── 1. 取 _do_skill 的 match cases ──────────────────────────────────────────
i = src.index("func _do_skill(")
body = src[i: src.index("\nfunc ", i + 10)]
cases = re.findall(r'^\t\t"([A-Za-z0-9_]+)":', body, re.M)

# ── 2. 各龟 skillPool[1..3].type ────────────────────────────────────────────
doc = json.load(io.open("data/pets.json", encoding="utf-8"))
pets = doc["pets"] if isinstance(doc, dict) else doc
active_types, basic_types = set(), set()
for p in pets:
    pool = p.get("skillPool", [])
    for k, s in enumerate(pool):
        t = str(s.get("type", ""))
        if not t:
            continue
        (basic_types if k == 0 else active_types).add(t)

# ── ★自检 ───────────────────────────────────────────────────────────────────
assert "lineInkBomb" in active_types, "自检失败: 已知可达的 lineInkBomb 不在 active 集"
assert "__不存在的技能__" not in active_types, "自检失败: 编造的 case 竟在 active 集"
assert "crystalSpike" in basic_types, "自检失败: crystalSpike 应当是 crystal 的普攻(pool[0])"

dead_cases = [c for c in cases if c not in active_types]
L = []
L.append("自检探针: 通过")
L.append("")
L.append("_do_skill 的 match case 共 %d 个; 各龟 skillPool[1..3].type 共 %d 种" % (len(cases), len(active_types)))
L.append("")
L.append("=== 【永不可达】的 match case: %d 个 ===" % len(dead_cases))
for c in sorted(dead_cases):
    where = "  (是某龟的普攻 pool[0].type)" if c in basic_types else "  (任何龟的 skillPool 里都没有)"
    L.append("  %-24s%s" % (c, where))

# ── 3. _IMPL_SKILLS 里出现但 skillPool 里没有的 type ────────────────────────
j = src.index("const _IMPL_SKILLS := {")
k = src.index("\n}", j)
impl = set(re.findall(r'"([A-Za-z0-9_]+)":', src[j:k]))
L.append("")
L.append("=== _IMPL_SKILLS 里 skillPool[1..3] 用不到的 type: %d 个 ===" % len(impl - active_types))
for c in sorted(impl - active_types):
    L.append("  " + c + ("  (普攻)" if c in basic_types else "  (无归属)"))

# ── 4. 各 pet 的 skillPool 里出现但 _do_skill 没实装的 type (反向, 更危险) ──
missing = sorted(active_types - set(cases) - impl)
L.append("")
L.append("=== ⚠ skillPool[1..3] 用到但 _do_skill 没有 case 的 type: %d 个 ===" % len(missing))
for c in missing:
    L.append("  " + c)

# ── 5. 单纯"无调用方"的函数 (路径规范化, 排除定义行本身) ────────────────────
files = []
for dp, dn, fn in os.walk("."):
    dn[:] = [d for d in dn if d not in (".git", ".godot", "assets", "build", "docs", "tools", "tests")]
    for f in fn:
        if f.endswith((".gd", ".tscn")):
            files.append(os.path.normpath(os.path.join(dp, f)).replace("\\", "/"))
blob = "\n".join(io.open(f, encoding="utf-8", errors="replace").read() for f in files)

CAND = ["_sk_phoenix_purify", "_sk_lava_cast", "_lava_bolt", "_sk_crystal_orb", "_sk_hiding_command"]
L.append("")
L.append("=== 候选函数的调用点数 (不含定义行) ===")
for fn in CAND:
    calls = len(re.findall(r"(?<!func )\b%s\(" % re.escape(fn), blob))
    L.append("  %-24s 调用 %d 次" % (fn, calls))
# 自检: 一个肯定被调用的 + 一个肯定不存在的
assert len(re.findall(r"(?<!func )\b_apply_damage_from\(", blob)) > 10
assert len(re.findall(r"(?<!func )\b__不存在的函数__\(", blob)) == 0

# ── 6. REVIEW_* 常量引用 ────────────────────────────────────────────────────
L.append("")
L.append("=== REVIEW_* 常量的引用点数 (不含声明行) ===")
for c in ["REVIEW_SHOWCASE", "REVIEW_SKILL_IDX", "REVIEW_TURTLE", "REVIEW_DUMMY_KILLABLE", "REVIEW_DUMMY_ATTACKS", "REVIEW_DUMMY_COUNT", "REVIEW_DUMMY_HP", "REVIEW_DUMMY"]:
    n = len(re.findall(r"(?<!const )\b%s\b" % c, blob))
    L.append("  %-24s 引用 %d 次" % (c, n))

io.open("c:/tmp/deadcode.txt", "w", encoding="utf-8").write("\n".join(L))
print("selftest OK -> c:/tmp/deadcode.txt")
