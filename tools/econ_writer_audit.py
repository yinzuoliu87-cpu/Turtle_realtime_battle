"""局外经济字段的直接写入审计(方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.3 / §6)。

用户 2026-11-06「装备要改成伏击机装(= 服务器记账)了，这个要做。」—— 服务器按经济流水重放出权威状态,
前提是**每一笔**改深海币 / 背包 / 身上装备 / 货架 / 卡池 / 大轮等级 / 小木斧 / 糖果罐 / 宝箱 / 香火石的地方
都走 `EconLedger`(scripts/gamedata/econ_ledger.gd)。漏一处 = 本机与重放对不上 = 好人被拒。

判据: 扫 autoload/ 与 scripts/ 里对这些字段的写入(赋值 / 自增 / 容器改动), 按「文件::函数::字段」归类:
  ① 永久放行: 记账口本身、读档 / 清档 / 换周清零、教程沙盒、截图工具(它们不是玩家的经济操作)
  ② 存量(S1 时还没迁走的直接写入, STOCK 表): **只减不增** —— S2 逐个迁进记账口, 迁走一处就从表里删一处
  ③ 其余 = 新增的直接写入 ⇒ 红
另外: STOCK 里登记了但已经不存在的 ⇒ 也红(表要跟着删, 否则存量数是假的)。

只读, 可反复跑:  python tools/econ_writer_audit.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FIELDS = [
	"meta_deepsea_coins", "meta_shop_offer", "meta_shop_locked",
	"equip_pool", "persistent_bench", "persistent_equipped",
	"season_level", "season_xp",
	"axe_exp_bar", "axe_exp_total", "axe_stage", "axe_final", "axe_syn_matches", "axe_evo_pending",
	"candy_jar_count", "candy_jar_broken", "candy_temp_levels",
	"chest_treasure_value", "chest_treasures_won", "incense_marks", "incense_charge",
]
MUT = (r"(\s*(\+=|-=|\*=|=(?!=))|\.(append|push_back|push_front|erase|remove_at|clear|insert|assign|merge|resize|fill|sort|pop_back|pop_front)\("
	r"|\[[^\]]+\]\s*(\+=|-=|=(?!=)))")
RX = {f: re.compile(r"(?<![A-Za-z0-9_\"'])" + re.escape(f) + MUT) for f in FIELDS}
FUNC = re.compile(r"^(static\s+)?func\s+([A-Za-z0-9_]+)")

## ① 永久放行(文件, 函数); 函数为 "*" = 整个文件
ALLOW = {
	("scripts/gamedata/econ_ledger.gd", "*"): "记账口本身",
	("autoload/GameState.gd", "_apply_save_dict"): "读档",
	("autoload/GameState.gd", "reset_save"): "清档",
	("autoload/GameState.gd", "start_new_season"): "换周清零(重放起点)",
	("autoload/tutorial_director.gd", "*"): "教程沙盒(退出整份还原)",
	("autoload/shot_diff.gd", "*"): "截图工具",
	("scripts/scenes/ShopScene.gd", "_shop_selfshot"): "截图工具(SHOT_COINS)",
}

## ② 存量: S1(2026-11-06)时还没迁进记账口的直接写入。只减不增; S2 清零。
STOCK = """
autoload/GameState.gd::add_season_xp::season_level
autoload/GameState.gd::add_season_xp::season_xp
autoload/GameState.gd::apply_temp_leveler::candy_temp_levels
autoload/GameState.gd::auto_merge_all::persistent_bench
autoload/GameState.gd::auto_merge_all::persistent_equipped
autoload/GameState.gd::axe_add_exp::axe_evo_pending
autoload/GameState.gd::axe_add_exp::axe_exp_bar
autoload/GameState.gd::axe_add_exp::axe_exp_total
autoload/GameState.gd::axe_add_exp::axe_stage
autoload/GameState.gd::axe_evo_take::axe_evo_pending
autoload/GameState.gd::axe_on_match_end::axe_syn_matches
autoload/GameState.gd::axe_pick_final::axe_exp_bar
autoload/GameState.gd::axe_pick_final::axe_final
autoload/GameState.gd::backfill_gauntlet_quota::meta_deepsea_coins
autoload/GameState.gd::backfill_ranked_quota::meta_deepsea_coins
autoload/GameState.gd::candy_jar_add::candy_jar_count
autoload/GameState.gd::candy_jar_open_seeded::candy_jar_broken
autoload/GameState.gd::candy_jar_open_seeded::meta_deepsea_coins
autoload/GameState.gd::candy_jar_open_seeded::persistent_bench
autoload/GameState.gd::consume_temp_leveler::persistent_bench
autoload/GameState.gd::ensure_equip_pool::equip_pool
autoload/GameState.gd::migrate_equip_caps::persistent_equipped
autoload/GameState.gd::sync_synergy_grants::persistent_bench
scripts/scenes/InventoryScene.gd::_inject_demo_inventory::persistent_bench
scripts/scenes/InventoryScene.gd::_inject_demo_inventory::season_level
scripts/scenes/RealtimeBattle3DScene.gd::_settle_season::meta_deepsea_coins
scripts/scenes/RealtimeBattle3DScene.gd::_stress_pre::persistent_equipped
scripts/scenes/inventory/equip_ops.gd::_equip_to::persistent_equipped
scripts/scenes/inventory/equip_ops.gd::_sell_selected::meta_deepsea_coins
scripts/scenes/inventory/equip_ops.gd::_sell_selected::persistent_bench
scripts/scenes/inventory/equip_ops.gd::_unequip_at::persistent_bench
scripts/scenes/inventory/equip_ops.gd::_unequip_at::persistent_equipped
scripts/scenes/inventory/equip_ops.gd::_unequip_minion_at::persistent_bench
scripts/scenes/inventory/equip_ops.gd::_write_equips::persistent_equipped
scripts/systems/equip/incense_stone_system.gd::_on_mark_scored::incense_marks
scripts/systems/equip/incense_stone_system.gd::_persist_chg::incense_charge
scripts/systems/equip/incense_stone_system.gd::_save_chg::incense_charge
scripts/systems/replay/abandoned_match.gd::_apply::persistent_equipped
scripts/systems/replay/referee_watch.gd::apply_chest::chest_treasure_value
scripts/systems/replay/referee_watch.gd::apply_chest::chest_treasures_won
scripts/systems/replay/referee_watch.gd::apply_incense::incense_charge
scripts/systems/replay/referee_watch.gd::apply_incense::incense_marks
scripts/systems/replay/referee_watch.gd::finals_coins_settle::meta_deepsea_coins
scripts/systems/replay/referee_watch.gd::finals_seal::meta_deepsea_coins
scripts/systems/replay/referee_watch.gd::settle::meta_deepsea_coins
scripts/systems/replay/referee_watch.gd::settle_ranked::meta_deepsea_coins
scripts/systems/sim/sim_driver.gd::_do_menu::meta_deepsea_coins
scripts/systems/skills/chest_system.gd::_ledger_note_open::chest_treasures_won
scripts/systems/skills/chest_system.gd::note_damage::chest_treasure_value
""".split()

FILES = ("autoload", "scripts")


def scan() -> dict:
	"""{文件::函数::字段: [行号...]}"""
	hits: dict = {}
	for base in FILES:
		for dp, _dn, fns in os.walk(os.path.join(ROOT, base)):
			for n in fns:
				if not n.endswith(".gd"):
					continue
				p = os.path.join(dp, n)
				rel = os.path.relpath(p, ROOT).replace("\\", "/")
				fn = "<顶层>"
				with open(p, encoding="utf-8", errors="replace") as fh:
					for i, line in enumerate(fh, 1):
						m = FUNC.match(line)
						if m:
							fn = m.group(2)
						code = line.split("#", 1)[0]
						if not code.strip():
							continue
						for f in FIELDS:
							if RX[f].search(code):
								hits.setdefault("%s::%s::%s" % (rel, fn, f), []).append(i)
	return hits


def main() -> int:
	try:
		sys.stdout.reconfigure(encoding="utf-8")
	except Exception:
		pass
	hits = scan()
	allowed, stock_live, new = [], [], []
	for k in sorted(hits):
		rel, fn, _f = k.split("::")
		if (rel, "*") in ALLOW or (rel, fn) in ALLOW:
			allowed.append(k)
		elif k in STOCK:
			stock_live.append(k)
		else:
			new.append(k)
	gone = [k for k in STOCK if k not in hits]
	print("  [分母] 扫到经济字段写入 %d 组(文件::函数::字段): 永久放行 %d · 存量 %d / 表里 %d · 新增 %d"
		% (len(hits), len(allowed), len(stock_live), len(STOCK), len(new)))
	bad = 0
	if new:
		bad += 1
		print("[FAIL] 新增了不走记账口(EconLedger)的经济字段写入 %d 组 —— 服务器重放看不到它, 本机与重放必然对不上:" % len(new))
		for k in new:
			print("   %s  (行 %s)" % (k, ",".join(str(x) for x in hits[k])))
		print("  ⇒ 改成 EconLedger.do(GameState, {...}); 真不是玩家的经济操作(读档/沙盒/工具)才进 ALLOW 并写理由。")
	if gone:
		bad += 1
		print("[FAIL] 存量表里登记了、代码里已经没有的 %d 组(迁走了就把表里那行删掉, 存量数才是真的):" % len(gone))
		for k in gone:
			print("   " + k)
	if bad:
		print("FAILED: %d 处" % bad)
		return 1
	print("ALL OK — 经济字段的直接写入没有新增(存量 %d 组待 S2 迁进记账口)" % len(stock_live))
	return 0


if __name__ == "__main__":
	sys.exit(main())
