"""revive_gradual_1127.py —— 全项目复活统一成「2.5 秒内分 5 段回血到目标值, 每段弹回血数字」
用户 11-27:「复活的，在两点五秒内血量是逐渐涨的…回血啊，规矩走啊，要有加的数字啊，头上要有数字在跑啊…
  你可以断断的加血，然后加到那个百分之三十。项目里其他的复活都要根据这个复活来做…包括凤凰龟和天使龟」
改: battle_damage(共用 revive_begin / revive_tick / _heal_apply)· 主文件(天使/宝箱雕像 + 每步推进)· 凤凰涅槃 · 134 威尼斯 / 154 棕筹码 · 驯服重生 · 斧头亡灵形态。
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        n = s.count(a)
        if n != 1:
            sys.exit("%s: 命中 %d 次: %r" % (rel, n, a[:90]))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("ok", rel)


patch("scripts/scenes/battle/battle_damage.gd", [
("""	var _hcap: float = float(u.get("_heal_cap_val", 0.0))
	if _hcap > 0.0:
		amt = minf(amt, _hcap)
	var hb: float = u["hp"]""",
"""	var _hcap: float = float(u.get("_heal_cap_val", 0.0))
	if _hcap > 0.0:
		amt = minf(amt, _hcap)
	return _heal_apply(u, amt, silent)


## 回血的后半段(加血 + 统计 + 溢出转盾 + 受治疗钩子 + 绿字累加): `_heal` 乘完各种治疗系数后走这里;
##   复活分段回血(revive_tick)不吃治疗系数(复活回多少是写死的比例), 直接走这里 —— 绿字 / 统计 / 钩子与普通回血同一套。
func _heal_apply(u: Dictionary, amt: float, silent: bool = false) -> float:
	if amt <= 0.0:
		return 0.0
	var hb: float = u["hp"]"""),
("""func _heal_flush(u: Dictionary) -> void:""",
"""## ════ 复活: 2.5 秒内分 5 段回血到目标值(用户 11-27, 全项目统一; 样板 = 134 威尼斯面具) ════
##   每 0.5 秒一段, 每段把血补到「目标 × 段数 / 5」(这期间被打掉的也补回来), 走 _heal_apply ⇒ 头上弹绿色回血数字、记进治疗统计。
##   不吃治疗系数(决胜期减半 / 重伤 / 077 封顶): 复活回多少是这个复活写死的比例。
##   protect = true ⇒ 这 2.5 秒倒地: 不可选中 + 血量不会掉到 1 以下 + 不行动(天使 / 宝箱雕像; 凤凰 / 威尼斯 / 驯服各自已有保护)。
##   from_dead = true ⇒ 单位还没站起来(斧头亡灵形态倒地期间就开始回), 照样推进。
const REVIVE_SEC := 2.5
const REVIVE_STEPS := 5
var _revq: Array = []


func revive_begin(u: Dictionary, to_hp: float, protect: bool = true, from_dead: bool = false) -> void:
	var t: float = battle._t
	for R in _revq:
		if is_same(R["u"], u):
			_revq.erase(R)
			break
	if protect:
		u["deathfloor_until"] = maxf(float(u.get("deathfloor_until", 0.0)), t + REVIVE_SEC)
		u["untargetable_until"] = maxf(float(u.get("untargetable_until", 0.0)), t + REVIVE_SEC)
		channel(u, REVIVE_SEC)
	u["_revive_until"] = t + REVIVE_SEC
	_revq.append({"u": u, "t0": t, "to": maxf(1.0, to_hp), "n": 0, "dead": from_dead})


func revive_tick() -> void:
	if _revq.is_empty():
		return
	var t: float = battle._t
	var keep: Array = []
	for R in _revq:
		var u: Dictionary = R["u"]
		if not u.get("alive", false) and not bool(R["dead"]):
			continue
		if bool(R["dead"]) and u.get("alive", false):
			R["dead"] = false
		var due: int = mini(REVIVE_STEPS, int(floor((t - float(R["t0"])) / (REVIVE_SEC / float(REVIVE_STEPS)) + 0.0001)))
		while int(R["n"]) < due:
			R["n"] = int(R["n"]) + 1
			var want: float = float(R["to"]) * float(R["n"]) / float(REVIVE_STEPS)
			var add: float = minf(want, float(u["maxHp"])) - float(u["hp"])
			if add > 0.0:
				_heal_apply(u, add)
				u["_heal_acc_t"] = t - 1.0   # 每段单独弹一个数字(不和下一段合并)
				_heal_flush(u)
		if int(R["n"]) < REVIVE_STEPS:
			keep.append(R)
	_revq = keep


func revive_clear() -> void:
	_revq.clear()


func _heal_flush(u: Dictionary) -> void:"""),
])

patch("scripts/scenes/RealtimeBattle3DScene.gd", [
("""		if u["id"] != "phoenix":
			u["hp"] = u["maxHp"] * pct                 # 天使/宝箱雕像: 保持原来的"一帧复活"
			_vfx._revive_fx(u)                           # 飘「复活」+ 复活段(倒地 → 站起, 11-05)
			return""",
"""		if u["id"] != "phoenix":
			u["hp"] = 1.0; u["stun_until"] = 0.0; u["airborne"] = false
			_damage.revive_begin(u, float(u["maxHp"]) * pct)   # 天使/宝箱雕像: 倒地 2.5 秒分段回到 25%(用户 11-27 全项目复活统一)
			_vfx._revive_fx(u)                           # 飘「复活」+ 复活段(倒地 → 站起, 11-05)
			return"""),
("""		_mask_syn.tick(dt)    # 面具: 每一路开打偷对面 1/2/3 只龟的脸, 我方阵地生成复制体
""",
"""		_mask_syn.tick(dt)    # 面具: 每一路开打偷对面 1/2/3 只龟的脸, 我方阵地生成复制体
		_damage.revive_tick() # 复活: 2.5 秒分 5 段回血(全项目共用, 用户 11-27)
"""),
])

patch("scripts/systems/skills/phoenix_system.gd", [
("""		u["_assembling"] = true
		u["_phx_reborn_t0"] = battle._t
""",
"""		u["_assembling"] = true
		u["_phx_reborn_t0"] = battle._t
		battle._damage.revive_begin(u, float(u["maxHp"]) * pct, false)   # 2.5 秒里分 5 段回到 60/25%, 每段弹绿字(用户 11-27; 原来展翼那一刻一下跳满)
"""),
("""			u["hp"] = u["maxHp"] * pct                 # ★展翼那一刻才跳血条
""",
""""""),
])

patch("scripts/systems/equip/eq_mask_batch.gd", [
("""	_revives.append({"u": u, "t0": t, "to": float(u.get("maxHp", 1.0)) * heal_pct, "ven": ven})""",
"""	_revives.append({"u": u, "t0": t, "ven": ven})
	battle._damage.revive_begin(u, float(u.get("maxHp", 1.0)) * heal_pct, false)   # 分 5 段回血、每段弹数字(全项目共用, 用户 11-27); 保护上面已设"""),
("""		var k: float = clampf((t - float(R["t0"])) / VEN_SEC, 0.0, 1.0)
		u["hp"] = maxf(float(u["hp"]), maxf(1.0, float(R["to"]) * k))   # 2.5 秒里血量逐渐涨到 30/45/70%
		if k < 1.0:""",
"""		var k: float = clampf((t - float(R["t0"])) / VEN_SEC, 0.0, 1.0)   # 回血在 battle_damage.revive_tick(分段弹数字); 这里只管起身演出
		if k < 1.0:"""),
])

patch("scripts/systems/trainer/trainer_system.gd", [
("""	u["hp"] = float(u["maxHp"]) * battle.TAME_REVIVE_PCT      # B4: 30% 最大生命""",
"""	u["hp"] = 1.0
	battle._damage.revive_begin(u, float(u["maxHp"]) * battle.TAME_REVIVE_PCT, false)   # B4: 30% 最大生命, 演出期 2.5 秒分段回(用户 11-27 全项目复活统一; 演出期本来就无敌不可选中)"""),
])

patch("scripts/systems/equip/axe_final_forms.gd", [
("""	ax["_axe_revive_at"] = float(battle._t) + AF.UNDEAD_REVIVE_DELAY
""",
"""	ax["_axe_revive_at"] = float(battle._t) + AF.UNDEAD_REVIVE_DELAY
	ax["hp"] = 0.0
	battle._damage.revive_begin(ax, float(ax.get("maxHp", 0.0)) * AF.UNDEAD_REVIVE_HP_PCT, false, true)   # 倒地 2.5 秒里分段回到 40%, 站起时正好满(用户 11-27 全项目复活统一)
"""),
("""	ax["hp"] = float(ax.get("maxHp", 0.0)) * AF.UNDEAD_REVIVE_HP_PCT
	ax["shield"] = 0.0""",
"""	ax["hp"] = maxf(float(ax.get("hp", 0.0)), float(ax.get("maxHp", 0.0)) * AF.UNDEAD_REVIVE_HP_PCT)   # 倒地期间已分段回满(revive_begin); 这里兜底
	ax["shield"] = 0.0"""),
])
