# -*- coding: utf-8 -*-
"""S9: 59 件装备全量刷新到云端 (591 文件夹)。以本地为准。

要点:
- 云端旧描述是 016-059 评审【之前】的, 且带已废弃的「稀有[..]」字段 → 全部重写
- 按 id 尾缀 (p2eq_NNN) 匹配云端元素, 不按名字 —— 本地改过名的(竹叶→竹制弓箭等)才不会变成重复元素
- 属性用 baseStats1: 已核实与运行时真实来源 P2RT.STATS 逐星逐字段 0 差异
"""
import sys, io, os, json, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hacknplan_sync import HP

OUT = io.open('tools/hp_s9_report.txt', 'w', encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a) + '\n')

eq = json.load(io.open('data/phase2-equipment.json', encoding='utf-8'))
eq = eq if isinstance(eq, list) else eq.get('equipment', [])
types = json.load(io.open('data/p2eq-types.json', encoding='utf-8'))
schools = json.load(io.open('data/p2eq-schools.json', encoding='utf-8'))

hp = HP()
FOLDER = hp.upsert(556, "🛠️ 装备 · 实时版 (59件 · phase2-equipment)",
                   "59 件实时版装备。事实源: data/phase2-equipment.json(名/费/文案) + scripts/engine/phase2_equip_runtime.gd 的 P2RT.STATS(逐星属性, 已核实与 baseStats1 零差异)。"
                   "★不含「稀有度/setTag/series/category」—— 这些字段已废弃并从数据删除。", 13)
log("装备文件夹 =", FOLDER)

kids = hp.children(FOLDER)
by_id = {}
for nm, el in kids.items():
    m = re.search(r'(p2eq_\d+)', nm)
    if m: by_id[m.group(1)] = (nm, el)
log("云端现有 %d 个, 可按 id 匹配 %d 个\n" % (len(kids), len(by_id)))

renamed = updated = created = 0
for e in eq:
    eid = e['id']
    name = "%s %s (%s)" % (e.get('emoji', ''), e['name'], eid)
    sch = schools.get(eid, [])
    desc = "💰费用%s · 类型[%s] · 学派[%s]\n加成(1★/2★/3★): %s\n\n效果: %s" % (
        e.get('cost', '?'), types.get(eid, '?'), '/'.join(sch) if sch else '-',
        e.get('baseStats1', ''), e.get('effectDesc1', ''))
    d3 = str(e.get('effectDesc3', '')).strip()
    if d3:
        desc += "\n\n3★额外机制: " + d3
    # 按 id 找云端元素; 名字变了就先改名, 避免 upsert 按名字新建重复
    if eid in by_id:
        old_name, el = by_id[eid]
        if old_name != name:
            hp.rename(el['designElementId'], name)
            log("  改名: %s → %s" % (old_name, name))
            renamed += 1
            hp._children.pop(FOLDER, None)
    n_before = len(hp.children(FOLDER))
    did = hp.upsert(FOLDER, name, desc, 12)   # 12=Object
    if len(hp.children(FOLDER)) > n_before: created += 1
    else: updated += 1
    log("  %-34s -> %d" % (name, did))

log("\n改名 %d / 更新 %d / 新建 %d" % (renamed, updated, created))
hp._children.pop(FOLDER, None)
kids2 = hp.children(FOLDER)
log("回读: 云端 %d 个 (本地 %d 件)" % (len(kids2), len(eq)))
extra = [k for k in kids2 if not re.search(r'p2eq_\d+', k) or re.search(r'(p2eq_\d+)', k).group(1) not in {x['id'] for x in eq}]
log("云端多出(本地已无): %s" % (extra if extra else '无'))
OUT.close(); print("done")
