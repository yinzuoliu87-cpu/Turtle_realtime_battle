class_name AttackRhythm
extends RefCounted
## 普攻三段: 前摇(举起)→ 命中(伤害 + 命中特效 + 对方受击同一帧)→ 后摇(收手)。只管画面, 不改结算(不动 RULES_VER)。
## 用户 2026-11-05:「英雄在平 A 的时候，应该是有一个攻击前摇，然后命中，然后攻击后摇…比方说盖伦…先是举起来这个剑，
##   然后砍到一半…敌方身上出现命中特效…继续挥剑…直到收手…近战小将…站位待机动画，然后突然戳一下…又回到待机动画」;
##  「你攻速越快，他这个整个前摇后摇命中都会短一点点」。
## 根因(11-05 查): sim 本来就有前摇(状态 "windup", 攻击间隔 × ATK_WINDUP_PCT, 随攻速缩短 —— LoL 默认 30%,
##   游戏数据 mAttackDelayCastOffsetPercent 在此基础上 ±), 但普攻帧条在前摇**结束**(= _basic_attack 结算)才从第 0 帧开播
##   ⇒ 前摇期间站着不动、结算时「突然戳一下」、命中特效落在动作第一帧。
## 现在: 前摇一开始 begin() 就播, 帧率 = 命中帧(AttackHits)/ 前摇秒数 ⇒ 结算那一刻正好显示命中帧, 同一帧率播完后摇;
##   攻速越快前摇越短 ⇒ 帧率越高、整段越短。没有帧条的单位: 形变在整个前摇里慢慢缩(蓄力), 结算那刻弹出去。
## 门禁 tests/verify_attack_rhythm.gd(真场景量「进前摇那帧在播普攻」「结算那帧显示命中帧」)。
const SkillForms = preload("res://scripts/gamedata/skill_forms.gd")
const FPS_MIN := 4.0
const FPS_MAX := 40.0
const CAST_CANCEL_AFTER := 3   # 释放帧之后几帧起可被走路 / 普攻打断(约 0.25 秒, 对上 CAST_RECOVER)


## 动作帧条 → 帧字典(主场景 _resolve_action 用)。方帧; 长动作折行(宽超手机 GPU 上限 4096, build_turtle_seq.py 登记在 ROWS)
static func action_sd(rel: String, tex: Texture2D, fps: float) -> Dictionary:
	var row: Array = TurtleActions.ROWS.get(rel, [1, 0])
	var fh: int = tex.get_height() / int(row[0])
	var hframes: int = maxi(1, int(floor(float(tex.get_width()) / float(fh))))
	var nf: int = int(row[1]) if int(row[1]) > 0 else hframes
	return {"tex": tex, "frames": nf, "fps": fps, "frame_h": fh, "hframes": hframes, "vframes": int(row[0]), "loop": false}


## 进普攻前摇时调(sim 步里; 只写渲染专属键 anim_* / windup_t / swing_t / _windup_total / _atk_wind / _atk_hit_frame)
static func begin(battle, u: Dictionary, wsec: float) -> void:
	if u == null:
		return
	u["_atk_wind"] = false
	if not is_instance_valid(u.get("sprite", null)) or wsec <= 0.0:
		return
	var path := sheet_path(battle, u)
	if path != "":
		var probe: Dictionary = battle._resolve_action(path, 1.0)
		if not probe.is_empty():
			var hit: int = AttackHits.hit_frame(path, int(probe.get("frames", 1)))
			battle._vfx._play_action(u, "attack", clampf(float(maxi(1, hit)) / wsec, FPS_MIN, FPS_MAX))
			if str(u.get("anim_action", "")) == "attack":
				u["_atk_wind"] = true
				u["_atk_hit_frame"] = hit
			return
	u["windup_t"] = wsec
	u["_windup_total"] = wsec
	u["swing_t"] = wsec + battle.JUICE_SWING_SEC
	u["_atk_wind"] = true


## 普攻结算(_basic_attack)时调: 前摇里已开播 ⇒ 此刻正是命中帧, 不重播; 追打等没有前摇的出手照旧(预备形变 + 开播)
static func on_hit(battle, u: Dictionary) -> void:
	if not u.get("_atk_wind", false):
		battle._anticipate(u)
		battle._vfx._play_action(u, "attack")
	u["_atk_wind"] = false


## 这个单位的普攻帧条路径(与 _play_action 选表同一套: 单位自带 → 主表 → 外包 11 只的生成表); 没有 = ""
static func sheet_path(battle, u: Dictionary) -> String:
	var own_rows: Dictionary = u.get("_act_rows", {})
	if own_rows.has("attack"):
		return str((own_rows["attack"] as Array)[0])
	var id = battle._anim_key(u)
	if battle.ACTION_ATTACK.has(id):
		return str((battle.ACTION_ATTACK[id] as Array)[0])
	if TurtleActions.ATTACK.has(id):
		return str((TurtleActions.ATTACK[id] as Array)[0])
	return ""


## ── 技能释放: 同一套对齐 —— 技能前摇(CAST_WINDUP)一开始就播这只龟这个技能的释放动作, 释放帧对上 _cast_skill 生效那一刻 ──
## 释放动作表 TurtleActions.CAST[动画键][技能类型] = [路径, 帧率, 释放帧](build_spine_actions.py 生成; 方案书 20261105b §2.4 / §4.1:
##   每个技能一段、不共用)。没有释放动作的照旧蓄力形变(_anticipate)。
static func cast_begin(battle, u: Dictionary, stype: String, wsec: float) -> void:
	u["_cast_wind"] = false
	var ent: Array = cast_entry(battle, u, stype)
	if ent.is_empty() or not is_instance_valid(u.get("sprite", null)) or wsec <= 0.0 or str(u.get("anim_action", "")) == "death":
		battle._anticipate(u)
		return
	var asd: Dictionary = battle._resolve_action(str(ent[0]), 1.0)
	if asd.is_empty():
		battle._anticipate(u)
		return
	var rel: int = int(ent[2]) if ent.size() > 2 else maxi(1, int(asd.get("frames", 2)) / 2)
	asd["fps"] = clampf(float(maxi(1, rel)) / wsec, FPS_MIN, FPS_MAX)
	battle._set_anim_sheet(u, asd, "cast", false)
	u["_cast_cancel"] = int(ent[3]) if ent.size() > 3 else rel + CAST_CANCEL_AFTER
	var key = battle._anim_key(u)
	if battle.ANIM_NORM.has(key) or TurtleActions.NORM.has(key):
		battle._elite_sys._elite_fix_norm(u, asd)
	u["_cast_wind"] = true


## 释放后走路 / 普攻能不能打断释放动作。
## 11-07 查: 释放后 CAST_RECOVER(0.24 秒)AI 就恢复, 而动作普遍还要播 0.5 秒以上 ⇒ 不让打断, 身体摆着施法姿势滑步、普攻没动作。
##   打断帧之前的部分是技能本身(蓄力 / 连射 / 落锤), 不让断; 之后是收招, 可以断。登记在 CAST 第 4 列, 没登记 = 释放帧 + CAST_CANCEL_AFTER。
static func cast_cancelable(u: Dictionary) -> bool:
	if str(u.get("anim_action", "")) != "cast":
		return false
	var sd: Dictionary = u.get("anim_sd", {})
	return int(float(u.get("anim_t", 0.0)) * float(sd.get("fps", 0.0))) >= int(u.get("_cast_cancel", 9999))


## 被动的一次性段(闪避 / 处决箭 / 吸取 / 连击 / 登场): 不打断技能、形态段, 也不打断普攻前摇; 这只龟没这一段就什么都不做
static func play_passive(battle, u: Dictionary, seg: String) -> void:
	if str(u.get("anim_action", "")) in ["cast", "transform", "death"] or u.get("_atk_wind", false):
		return
	play_form(battle, u, str(battle._anim_key(u)), seg)


## 技能生效(_cast_skill)时调: 前摇里已开播 ⇒ 此刻正是释放帧, 不重播; 没有释放动作的照旧预备形变
static func cast_on(battle, u: Dictionary) -> void:
	if not u.get("_cast_wind", false):
		battle._anticipate(u)
	u["_cast_wind"] = false


static func cast_entry(battle, u: Dictionary, stype: String) -> Array:
	var key = battle._anim_key(u)
	var tbl: Dictionary = TurtleActions.CAST.get(key, {})
	if stype == "pirateShipPassive" and SkillForms.current_index(u, stype) == 1:
		stype = "pirateShipShot"   # 海盗船第二形态 = 霰弹, 是另一个动作(形态判据只认 SkillForms)
	if tbl.has(stype):
		return tbl[stype]
	return (CastSheets.CAST.get(key, {}) as Dictionary).get(stype, [])   # 外包 11 只以外的龟(忍者 / 幽灵…; build_extra_casts.py 生成)


## ── 持续状态循环: 状态期间替代待机(方案书 20261105b §4.1「持续状态」: 虚化 / 缩壳 / 潜影 / 触须 / 侵入 / 滚球 / 火山…) ──
## 表: CastSheets.STATE / TurtleActions.STATE[动画键] = [[状态名, 路径, 帧率], ...]; 状态名 → 判据见 state_active。
## 渲染步(battle_render._advance_anim)在待机时调; 只写渲染专属键(anim_* / _state_on)。
static func state_active(battle, u: Dictionary, name: String) -> bool:
	match name:
		"ghostPhase":
			return battle._t < float(u.get("phase_until", 0.0))
		"volcano":
			return bool(u.get("volcano", false))
		"hidingShrink":   # 缩头乌龟缩头 3 秒(hiding_system._sk_hiding_shrink → channel)
			return battle._t < float(u.get("channel_until", 0.0))
		"diamondRoll":    # 钻石滚球位移态
			return bool(u.get("roll_active", false))
		"headlessTendrils":   # 万千触须引导 4 秒(headless_system: channel)
			return battle._t < float(u.get("channel_until", 0.0))
		"diceDash":       # 稳定骰子连续突刺
			return bool(u.get("dice_dash_active", false))
	return false


static func apply_state_idle(battle, u: Dictionary) -> void:
	if str(u.get("anim_action", "")) != "" or not u.get("alive", true):
		return
	var key = battle._anim_key(u)
	var rows: Array = CastSheets.STATE.get(key, TurtleActions.STATE.get(key, []))
	if rows.is_empty():
		if str(u.get("_state_on", "")) != "":   # 状态结束且动画键已变(火山 → 普通): 回待机
			u["_state_on"] = ""
			battle._set_anim_sheet(u, u.get("idle_sd", {}), "", true)
		return
	var row: Array = []
	for r in rows:
		if state_active(battle, u, str(r[0])):
			row = r
			break
	## 比对「当前帧条是不是该有的那张」(不靠记忆的标记: 状态期间播完一次动作回的是普通待机, 要能再切回状态循环)
	var tex = (u.get("anim_sd", {}) as Dictionary).get("tex", null)
	var cur: String = tex.resource_path if tex != null else ""
	if row.is_empty():
		if str(u.get("_state_on", "")) != "":
			var ended: String = str(u["_state_on"])
			u["_state_on"] = ""
			if cur != ((u.get("idle_sd", {}) as Dictionary).get("tex", null) as Texture2D).resource_path:
				battle._set_anim_sheet(u, u.get("idle_sd", {}), "", true)   # 状态结束 → 回待机
			play_form(battle, u, str(key), ended + "_end")   # 有收招段的(缩壳探头 / 滚球舒展)播完再回待机; 没登记的 play_form 自己返回
		return
	if cur.ends_with(str(row[1])):
		return
	var sd: Dictionary = battle._resolve_action(str(row[1]), float(row[2]))
	if sd.is_empty():
		return
	sd["loop"] = true
	u["_state_on"] = str(row[0])
	_set_sheet_normed(battle, u, sd, "")


## 换帧表并按归一表修正(方帧动作图与待机同像素尺寸、同脚底线); 没登记归一的(64 像素小图)走待机口径
static func _set_sheet_normed(battle, u: Dictionary, sd: Dictionary, action: String) -> void:
	var key = battle._anim_key(u)
	if battle.ANIM_NORM.has(key) or TurtleActions.NORM.has(key):
		battle._set_anim_sheet(u, sd, action, false)
		battle._elite_sys._elite_fix_norm(u, sd)
	else:
		battle._set_anim_sheet(u, sd, action, action == "")


## 形态切换段(熔岩变身 / 变回): TurtleActions.FORM[龟][段] = [路径, 帧率]; 播一次, 期间普攻 / 受击不打断(battle_vfx 白名单)
static func play_form(battle, u: Dictionary, tid: String, seg: String) -> void:
	var ent: Array = (TurtleActions.FORM.get(tid, {}) as Dictionary).get(seg, [])
	if ent.is_empty() or not is_instance_valid(u.get("sprite", null)) or str(u.get("anim_action", "")) == "death":
		return
	var sd: Dictionary = battle._resolve_action(str(ent[0]), float(ent[1]))
	if sd.is_empty():
		return
	u["_state_on"] = ""
	_set_sheet_normed(battle, u, sd, "transform")
	if ent.size() >= 3 and float(ent[2]) > 0.0:
		u["anim_t"] = -float(ent[2])   # 开播前在首帧停留(凤凰复活先趴着; 帧号 int(负数) 钳到 0, battle_render._advance_anim)
