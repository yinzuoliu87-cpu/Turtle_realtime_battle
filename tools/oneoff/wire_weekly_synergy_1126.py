"""wire_weekly_synergy_1126.py —— 本周羁绊轮换 + 商店池版本接线(方案书 docs/plans/20261124d §4.2; 版本号兜底见 WeeklySynergy 头注)。"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")


def ed(rel, old, new, cnt=1):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    crlf = b"\r\n" in raw
    s = raw.decode("utf-8").replace("\r\n", "\n")
    if new in s:
        return
    assert s.count(old) == cnt, (rel, old[:60], s.count(old))
    s = s.replace(old, new)
    if crlf:
        s = s.replace("\n", "\r\n")
    open(p, "wb").write(s.encode("utf-8"))


L = "scripts/gamedata/econ_ledger.gd"
ed(L, '''const CHIP_BURN_SRCS :=''', '''## 商店池版本: 每条流水记当时客户端的版本(WeeklySynergy 头注)。1 = 0.23.5 及以前(流水里没有 pv: 老池 001~096、不轮换);
##   2 = 0.23.6 起(新 60 件 + 16 抽 10 轮换)。★掷货 / 糖果罐按流水里那条的版本出货 ⇒ 换版当天老客户端掷的货重放也对得上。
const POOL_VER := 2
const CHIP_BURN_SRCS :=''')
ed(L, '''	check(gs, "do:" + str(op.get("op", "")))
	var led: Array = gs.econ_log
	var row: Dictionary = op.duplicate(true)''', '''	check(gs, "do:" + str(op.get("op", "")))
	op["pv"] = POOL_VER
	var led: Array = gs.econ_log
	var row: Dictionary = op.duplicate(true)''')
ed(L, '''static func apply(gs, op: Dictionary) -> Dictionary:
	match str(op.get("op", "")):''', '''static func apply(gs, op: Dictionary) -> Dictionary:
	gs._econ_pv = int(op.get("pv", 1))   # 这一条按它记的池版本出货(_roll / 糖果罐读); 用完复位
	var r: Dictionary = _apply(gs, op)
	gs._econ_pv = POOL_VER
	return r


static func _apply(gs, op: Dictionary) -> Dictionary:
	match str(op.get("op", "")):''')
ed(L, '''	gs.ensure_equip_pool()
	pool = EquipPool.available(gs.equip_pool, pool)''', '''	gs.ensure_equip_pool()
	pool = EquipPool.available(gs.equip_pool, pool)
	## 本周羁绊(16 抽 10) + 池版本: 本周没抽到的羁绊的装备不出; 版本 1 的流水只出老池(WeeklySynergy 头注)
	pool = WeeklySynergy.filter_defs(pool, int(gs.week_anchor_ts), int(gs._econ_pv))''')
G = "autoload/GameState.gd"
ed(G, '''func _candy_jar_pick_equip(costs: Array, rng: RandomNumberGenerator = null) -> String:   # 从 DataRegistry.phase2_equipment 按 cost 抽1
	var pool: Array = []
	var has_axe: bool = axe_owned()
	for eq in DataRegistry.phase2_equipment:
		if int(eq.get("cost", 0)) in costs:''', '''func _candy_jar_pick_equip(costs: Array, rng: RandomNumberGenerator = null) -> String:   # 从 DataRegistry.phase2_equipment 按 cost 抽1
	var pool: Array = []
	var has_axe: bool = axe_owned()
	for eq in DataRegistry.phase2_equipment:
		if not WeeklySynergy.pool_ok(str(eq.get("id", "")), int(week_anchor_ts), int(_econ_pv)):
			continue   # 本周羁绊轮换 + 池版本(同商店掷货, 方案书 20261124d)
		if int(eq.get("cost", 0)) in costs:''')
ed(G, '''var persistent_equipped: Dictionary = {}''', '''## 这一条经济流水的商店池版本(EconLedger.apply 进出时设 / 复位; 不存档)。默认 = 当前版本。
var _econ_pv: int = 2
var persistent_equipped: Dictionary = {}''')
R = "scripts/referee/econ_replay.gd"
ed(R, '''	var tm0 := bool(gs.test_mode)
	gs.test_mode = true                  # 任何 save() 空转''', '''	var tm0 := bool(gs.test_mode)
	var wk0 := int(gs.week_anchor_ts)
	if input.has("week"):
		gs.week_anchor_ts = int(input["week"])   # 本周羁绊按这份流水那一周算(轮换, 方案书 20261124d)
	gs.test_mode = true                  # 任何 save() 空转''')
ed(R, '''	gs.test_mode = tm0
	return out''', '''	gs.test_mode = tm0
	gs.week_anchor_ts = wk0
	return out''')
ed(R, '''			var r := run(gs, {"rows": (job as Dictionary).get("rows", []), "strict": bool((j as Dictionary).get("strict", true)),
				"facts": (job as Dictionary).get("facts", {})})''', '''			var r := run(gs, {"rows": (job as Dictionary).get("rows", []), "strict": bool((j as Dictionary).get("strict", true)),
				"facts": (job as Dictionary).get("facts", {}), "week": int(job.get("week", 0))})''')
print("ok")
