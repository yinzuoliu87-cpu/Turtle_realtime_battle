# -*- coding: utf-8 -*-
"""S12: 把云端顶层的回合制旧元素归档进「📦 回合制存档」。用移动不用删除(HacknPlan 无回收站)。
★API 坑: POST 带 parentId=0 不创建只返回列表; 带 parentId=N 会建在 N 下且之后无法移回顶层
  (PATCH parentId=0 报301, =null 返回成功但实际没动) → 建顶层元素必须【不带 parentId 字段】。"""
import sys, io, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hacknplan_sync import HP

OUT = io.open('tools/hp_s12_report.txt', 'w', encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a) + '\n')

NAME = "📦 回合制存档（已废弃 · 2026-07-19 归档）"
DESC = ("本文件夹是【回合制旧版】的知识库存档, 不代表当前实时版行为, 勿作为实现依据。\n\n"
"归档理由(逐条实证):\n"
"· 「定位 & 设计支柱」自述「龟龟回合制战斗」「技能 5 选 3」—— 实时版是全自动战斗 + 3选1。\n"
"· 顶层 59 件装备是回合制版本, 与实时版重复且数值/节拍全不同\n"
"  (例: 哑铃旧版「每回合开始 +1层锻炼 +20/25/30 · +20龟能」, 实时版「每8秒 +40/75/110 · +10%充能速率」)。\n"
"  实时版装备现行事实源 = 「🐢 实时版 · 权威知识库」下的「🛠️ 装备 · 实时版 (59件)」。\n"
"· 5 个学派元素写的是「冻结 1 回合」「僵硬持续 4 回合」等回合制效果; 且实时版羁绊(11学派/12类型)\n"
"  按用户决定【目前只留名称、效果未来再设计】, 代码里一次都没调用。\n"
"· 「云顶式商店(双路)」= 局内金币商店 + 每回合刷新, 该经济已整体废弃(挪到局外深海币商店)。\n\n"
"★现行事实源一律看「🐢 实时版 · 权威知识库」(28龟 / 59装备 / 系统机制§1-§10 / 小将)。")

hp = HP()
tree = hp._req("/designelements?parentId=0")
arch = [e for e in tree if e.get('name') == NAME]
probe = [e for e in tree if '__probe_root__' in e.get('name', '')]

if arch:
    ARCH = arch[0]['designElementId']; log("存档夹已存在 =", ARCH)
elif probe:
    ARCH = probe[0]['designElementId']
    hp._req('/designelements/%d' % ARCH, {"name": NAME, "description": DESC}, method='PATCH')
    log("复用探针元素 %d → 改名为存档夹(顺带清掉我建探针留下的垃圾)" % ARCH)
else:
    r = hp._req("/designelements", {"name": NAME, "description": DESC, "designElementTypeId": 13}, method="POST")
    ARCH = r['designElementId']; log("新建存档夹(不带parentId→落顶层) =", ARCH)

KEEP = {556, 555, ARCH}
tree = hp._req("/designelements?parentId=0")
targets = [e for e in tree if e.get('designElementId') not in KEEP]
log("顶层 %d, 保留 %d, 待归档 %d\n" % (len(tree), len(KEEP), len(targets)))

moved = fail = 0
for e in targets:
    try:
        hp.move(e['designElementId'], ARCH); moved += 1
        log("  ✓ [%4d] %s" % (e['designElementId'], e.get('name', '')[:44]))
    except Exception as ex:
        fail += 1; log("  ✗ [%4d] %s — %s" % (e['designElementId'], e.get('name', '')[:44], str(ex)[:60]))

# 556 下那个误建的空存档夹(670) 一并挪进存档
k556 = hp.children(556)
for nm, el in list(k556.items()):
    if '回合制存档' in nm and el['designElementId'] != ARCH:
        try:
            hp.move(el['designElementId'], ARCH)
            log("  ✓ 清理: 556 下误建的空存档夹 %d 已挪入存档" % el['designElementId'])
        except Exception as ex: log("  ✗ 清理 670 失败:", str(ex)[:60])

log("\n归档 %d, 失败 %d" % (moved, fail))
t2 = hp._req("/designelements?parentId=0")
log("\n回读顶层 = %d:" % len(t2))
for e in sorted(t2, key=lambda x: x.get('designElementId', 0)):
    log("   [%4d] %s" % (e.get('designElementId', 0), e.get('name', '')[:52]))
OUT.close(); print("done")
