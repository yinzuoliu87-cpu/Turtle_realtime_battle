"""downed_pose_1127.py —— 134 威尼斯面具 / 154 棕色筹码倒地复活: 2.5 秒里身体真的倒下 → 趴着 → 起身(原来站着变灰白)。
借该龟自己的阵亡帧条(15 帧, 第 6 帧起已趴平、不淡出): 前 7 帧 15fps 正放倒下, 趴着定格, 最后 0.5 秒倒放回站立, 结束换回待机。
只读 _ven_t0 / _ven_until(stream_recorder 已录) ⇒ 直播回放同样有; 没有阵亡帧条的龟(幽灵 / 忍者 / 变脸)不变姿势。
用户 11-27「都都要吧」(清单里「倒地姿势也做」)。一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:60])
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


patch("scripts/scenes/battle/attack_rhythm.gd", [(
    "## 形态切换段(熔岩变身 / 变回)",
    """## 134 威尼斯 / 154 棕色筹码倒地复活的身体姿势(11-27): 借本龟阵亡帧条前 DOWN_F 帧 —— 倒下正放、趴着定格、最后 DOWN_RISE 秒倒放起身, 结束换回待机。
##   只读 _ven_t0 / _ven_until(直播流里有) ⇒ 回放同样有; 没有阵亡帧条的(幽灵 / 忍者 / 变脸)不变姿势。纯演出, 不碰结算。
const DOWN_F := 7          # 阵亡帧条第 6 帧起已趴平(11-27 量过 basic / bubble / stone 的包围盒)
const DOWN_FPS := 15.0
const DOWN_RISE := 0.5

static func downed_pose(battle, u: Dictionary) -> void:
	var until: float = float(u.get("_ven_until", -1.0))
	var on: bool = battle._t < until and u.get("alive", false)
	if not on:
		if u.get("_downed_pose", false):
			u.erase("_downed_pose")
			u.erase("_manual_anim")
			battle._set_anim_sheet(u, u.get("idle_sd", {}), "", true)
		return
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr):
		return
	if not u.get("_downed_pose", false):
		if u.get("_manual_anim", false):
			return   # 别的演出在手动管帧(忍者冲刺…), 不抢
		var key = battle._anim_key(u)
		var table: Dictionary = battle.ACTION_DEATH if battle.ACTION_DEATH.has(key) else TurtleActions.DEATH
		if not table.has(key):
			return
		var sd: Dictionary = battle._resolve_action(str(table[key][0]), float(table[key][1]))
		if sd.is_empty():
			return
		u["_state_on"] = ""
		_set_sheet_normed(battle, u, sd, "downed")
		u["_downed_pose"] = true
		u["_manual_anim"] = true
	var el: float = battle._t - float(u.get("_ven_t0", battle._t))
	var f: int = mini(DOWN_F, int(el * DOWN_FPS))
	var left: float = until - battle._t
	if left < DOWN_RISE:
		f = mini(f, int(left / DOWN_RISE * float(DOWN_F)))
	var real: int = maxi(1, int(spr.hframes) * int(spr.vframes))
	spr.frame = clampi(f, 0, real - 1)


## 形态切换段(熔岩变身 / 变回)""")])

patch("scripts/scenes/battle/battle_render.gd", [(
    "\t\tif battle._t < float(u.get(\"_ven_until\", -1.0)):   # 134 威尼斯",
    "\t\tif u.has(\"_ven_until\") or u.has(\"_downed_pose\"):\n"
    "\t\t\tAttackRhythm.downed_pose(battle, u)   # 倒地复活: 身体倒下 → 趴着 → 起身(11-27)\n"
    "\t\tif battle._t < float(u.get(\"_ven_until\", -1.0)):   # 134 威尼斯")])
print("ok")
