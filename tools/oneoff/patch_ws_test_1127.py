p = "tests/verify_weekly_synergy.gd"
raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
a = '\t_ok("H 魔法海螺小虫的随机装备也只出本周池(源码里挂了 WeeklySynergy.battle_ok)", ci > 0 and eqsrc.substr(ci, cj - ci).contains("WeeklySynergy.battle_ok("))\n'
assert s.count(a) == 1
b = a + '''\t## I 图鉴「本周不出」压暗(11-27): 判据与掷货同一个 pool_ok · 羁绊赠送(费用 0)不标 · 羁绊页只标 16 个轮换的
\tvar i_bad: Array = []
\tvar i_off := 0
\tvar i_on := 0
\tfor e in DataRegistry.phase2_equipment:
\t\tvar eid := str(e.get("id", ""))
\t\tvar want: bool = int(e.get("cost", 0)) > 0 and not WS.pool_ok(eid, wk, WS.BATTLE_PV)
\t\tif CodexList.off_week_eq(e) != want:
\t\t\ti_bad.append(eid)
\t\tif want:
\t\t\ti_off += 1
\t\telif int(e.get("cost", 0)) > 0:
\t\t\ti_on += 1
\tvar syn_bad: Array = []
\tfor t in WS.ALL:
\t\tif CodexList.off_week_syn(str(t)) == in_week.has(t):
\t\t\tsyn_bad.append(t)
\t_ok("I 图鉴装备页: 压暗 %d 件 / 照常 %d 件, 与掷货判据逐件一致 · 羁绊页 16 个逐个一致 · 不轮换的类型不标" % [i_off, i_on],
\t\ti_bad.is_empty() and syn_bad.is_empty() and i_off > 0 and i_on > 0 and not CodexList.off_week_syn("小木斧"), "%s %s" % [str(i_bad.slice(0, 5)), str(syn_bad)])
\t## J 商店顶栏「本周羁绊」木牌: 图标恰好是本周那 10 个(按顺序) · 周锚点 0(演示 / 冷启动)⇒ 不挂
\tvar bt0: int = int(gs.season_total_battles)
\tgs.season_total_battles = maxi(1, bt0)
\tvar shop = load("res://scenes/Shop.tscn").instantiate()
\tadd_child(shop)
\tawait get_tree().process_frame
\tawait get_tree().process_frame
\tvar icons: Array = []
\tfor n in shop.find_children("WeekSyn_*", "TextureRect", true, false):
\t\ticons.append(str(n.name).trim_prefix("WeekSyn_"))
\tvar plq_n: int = shop.find_children("WeekSynPlaque", "", true, false).size()
\tshop.queue_free()
\tgs.week_anchor_ts = 0
\tvar shop0 = load("res://scenes/Shop.tscn").instantiate()
\tadd_child(shop0)
\tawait get_tree().process_frame
\tvar plq0: int = shop0.find_children("WeekSynPlaque", "", true, false).size()
\tshop0.queue_free()
\tgs.season_total_battles = bt0
\t_ok("J 商店木牌: 图标 %d 个 = 本周 %d 个且同序 · 周锚点 0 不挂(%d)" % [icons.size(), in_week.size(), plq0],
\t\tplq_n == 1 and icons == in_week and plq0 == 0, "%s vs %s" % [str(icons), str(in_week)])
'''
s = s.replace(a, b)
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
