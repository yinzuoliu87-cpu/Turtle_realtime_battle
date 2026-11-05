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
const FPS_MIN := 4.0
const FPS_MAX := 40.0


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
