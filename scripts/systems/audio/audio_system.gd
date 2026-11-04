class_name AudioSystem
extends RefCounted
## 音效系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

# ============================================================================
#  §AUDIO 辅助 — 节流封装 (防高频命中音刷屏). 拿不到 Audio autoload 时静默 no-op.
# ============================================================================
func _audio() -> Node:
	return battle.get_node_or_null("/root/Audio")

# 命中音 (普攻/技能/装备直接伤害): 暴击→hit-crit, 否则→hit-physical. 同名音 battle.SFX_HIT_MIN_GAP 内只响一次.
## ★2026-11-04 普攻按来源出声(用户「一个乌龟攻击是物理伤害，另外一个也是物理伤害，它们两个音效…应该是用一样的音效吗？」):
##   龟的普攻命中播它自己那一条 atk_<id>(音效事件表), 暴击时再叠一层 hit-crit(压低)。
##   小将 / 召唤物 / 没有专属声的龟 ⇒ 照旧通用命中音。同一来源 SFX_HIT_MIN_GAP 内只响一次(多段普攻不刷屏)。
##   ★只管声音, 不碰 sim: 节流表记在本对象上, 不写单位字典。
var _ev_last_t: Dictionary = {}
## ★2026-11-04 全场命中声同时最多 HIT_VOICES 路(HIT_WINDOW 秒窗口内): 按来源出声后 6 只单位同一刻出手 = 6 声叠加,
##   实机录 2 分钟 1200 个 0.1 秒块里 981 个贴顶(削波)。原来全场只有一路命中声(一个 45 ms 节流), 现在允许 2 路 ——
##   不同的龟仍听得出, 但不会叠爆。按来源 / 通用 / 暴击 / 出手(闪电)四个入口共用这一张时间表。
const HIT_VOICES := 2
const HIT_WINDOW := 0.09
var _hit_ts: Array = []


func _hit_slot() -> bool:
	while not _hit_ts.is_empty() and battle._t - float(_hit_ts[0]) > HIT_WINDOW:
		_hit_ts.pop_front()
	if _hit_ts.size() >= HIT_VOICES:
		return false
	_hit_ts.append(battle._t)
	return true


func _sfx_hit(crit: bool, src = null, basic: bool = false) -> void:
	var a = _audio()
	if a == null:
		return
	if basic and src is Dictionary and not (src as Dictionary).has("minion_role") and not bool((src as Dictionary).get("is_summon", false)):
		var ev := "atk_" + str((src as Dictionary).get("id", ""))
		if a.has_method("has_sfx") and a.has_sfx(ev):
			if battle._t - float(_ev_last_t.get(ev, -99.0)) >= battle.SFX_HIT_MIN_GAP and _hit_slot():
				_ev_last_t[ev] = battle._t
				a.play_sfx(ev, 1.0, 1.0, 0.04)
				if crit:
					a.play_sfx("hit-crit", 0.6, 1.0, 0.03)
			return
	if crit:
		if battle._t - battle._last_crit_sfx_t < battle.SFX_HIT_MIN_GAP or not _hit_slot():
			return
		battle._last_crit_sfx_t = battle._t
		a.play_sfx("hit-crit", 1.0, 1.0, 0.03)
	else:
		if battle._t - battle._last_hit_sfx_t < battle.SFX_HIT_MIN_GAP or not _hit_slot():
			return
		battle._last_hit_sfx_t = battle._t
		a.play_sfx("hit-physical", 0.85, 1.0, 0.08)   # pitch/vol 抖动由 Audio 自带 → 连段听感有差

## 普攻出声的另一个入口: 普攻伤害不带「普攻命中」标记的龟(闪电龟)在出手那一刻播自己的 atk_<id>, 与 _sfx_hit 共用节流表。
func sfx_basic_cast(u: Dictionary) -> void:
	var a = _audio()
	if a == null or not a.has_method("has_sfx"):
		return
	var ev := "atk_" + str(u.get("id", ""))
	if a.has_sfx(ev) and battle._t - float(_ev_last_t.get(ev, -99.0)) >= battle.SFX_HIT_MIN_GAP and _hit_slot():
		_ev_last_t[ev] = battle._t
		a.play_sfx(ev, 1.0, 1.0, 0.04)

func _sfx_heal() -> void:
	var a = _audio()
	if a == null: return
	if battle._t - battle._last_heal_sfx_t < battle.SFX_AUX_MIN_GAP: return
	battle._last_heal_sfx_t = battle._t
	a.play_sfx("heal", 1.0, 1.0, 0.04)

func _sfx_shield_gain() -> void:
	var a = _audio()
	if a == null: return
	if battle._t - battle._last_shieldgain_sfx_t < battle.SFX_AUX_MIN_GAP: return
	battle._last_shieldgain_sfx_t = battle._t
	a.play_sfx("shield-gain", 0.9, 1.0, 0.05)

func _sfx_shield_break() -> void:
	var a = _audio()
	if a == null: return
	if battle._t - battle._last_shieldbreak_sfx_t < battle.SFX_AUX_MIN_GAP: return
	battle._last_shieldbreak_sfx_t = battle._t
	a.play_sfx("shield-break", 1.0, 1.0, 0.06)

func _sfx_simple(name: String) -> void:    # 复活/失败 等低频事件, 不节流
	var a = _audio()
	if a != null:
		a.play_sfx(name)

# ============================================================================
#  §SKILLVFX 框架 — 技能特效真贴图 (替程序圈). 有匹配贴图才放, 没有静默回退现有程序圈/飘字.
#  _play_skill_vfx(skill_key, pos2d, [height]) → 在该点放一个朝镜头的 billboard:
#    单帧贴图按 SKILL_VFX_WORLD_H 归一 → 一次性 "放大入场 → 保持 → 淡出" tween 后 queue_free.
#  (133 张技能图实测全单帧近方形, 非 spritesheet → 不需逐帧步进; 真要逐帧也能扩 hframes.)
# ============================================================================