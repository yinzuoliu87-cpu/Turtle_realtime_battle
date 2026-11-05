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
const HIT_VOICES := 1
const HIT_WINDOW := 0.1
var _hit_ts: Array = []
## ★2026-11-04 七轮 · 对标云顶实录(用户「混成云顶之一」→ 录云顶 4 分钟逐声切开): 云顶战斗段大事件比普攻响 6.9 dB,
##   我们原来只有命中这一层(大小差 2.7 dB) ⇒ 普攻(按来源 atk_* 与小将通用命中)压低 4 dB, 另加三类大事件:
##   放技能 cast_<龟 id>(成品比普攻锚点高 3 dB ⇒ 合计差 7 dB) / 单位阵亡 unit_death / 开战 fight_start。
const ATK_GAIN := 0.45          # −7 dB(11-04 第一版 −4 dB 实录大小差只到 3.7 dB, 云顶 6.9 ⇒ 再压 3 dB)
const CAST_VOICES := 2          # 放技能声全场同时最多 2 路(CAST_WINDOW 秒窗口内)
const CAST_WINDOW := 0.15
const CAST_SAME_SRC_GAP := 0.3  # 同一只龟连放两技(大招 + 小技同一刻) 只响一声
const DEATH_GAP := 0.12         # 阵亡声全场最小间隔(团灭那一下不叠成一团)
var _cast_ts: Array = []
var _death_last_t := -99.0
const SKILL_HIT_GAP := 0.35     # 技能 / 装备伤害的通用命中声: 全场最小间隔
const HEAL_SFX_GAP := 0.8       # 治疗声: 全场最小间隔
const AUX_GAIN := 0.6           # 治疗 / 得盾声同属「平时」那一层(−4.4 dB)
const SHIELD_SFX_GAP := 0.5     # 得盾声: 全场最小间隔
var _skill_hit_last_t := -99.0
## 战斗背景音乐的基准音量(Audio.play_bgm 的 base_vol; 原默认 0.45)。实测: 战斗曲文件本身 −13.3 LUFS, 按 0.45 播约 −20 LUFS,
##   压低后的普攻最响 100 ms 约 −22 ⇒ 普攻埋在音乐下面, 录音里「背景」中位 −18 dB 改普攻前后纹丝不动(云顶战斗段底噪 −38)。
##   ⇒ 战斗时音乐让位给音效(商业通行做法): −6 dB。
const BATTLE_BGM_BASE := 0.225


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
				a.play_sfx(ev, ATK_GAIN, 1.0, 0.04)
				if crit:
					a.play_sfx("hit-crit", 0.6 * ATK_GAIN, 1.0, 0.03)
			return
	## ★11-04 探针(一局 2 分钟逐条记播放): 通用命中声 993 次 —— 技能 / 装备每一段、每打到一个人都响 ⇒ 刷成一层底, 盖住大事件。
	##   技能有自己的放技能声(cast_<id>)了 ⇒ 技能 / 装备伤害的通用命中声并进普攻层(同样压 4 dB), 且全场 SKILL_HIT_GAP 内最多一下。
	if not basic:
		if battle._t - _skill_hit_last_t < SKILL_HIT_GAP:
			return
		_skill_hit_last_t = battle._t
	var g: float = ATK_GAIN
	if crit:
		if battle._t - battle._last_crit_sfx_t < battle.SFX_HIT_MIN_GAP or not _hit_slot():
			return
		battle._last_crit_sfx_t = battle._t
		a.play_sfx("hit-crit", 1.0 * g, 1.0, 0.03)
	else:
		if battle._t - battle._last_hit_sfx_t < battle.SFX_HIT_MIN_GAP or not _hit_slot():
			return
		battle._last_hit_sfx_t = battle._t
		a.play_sfx("hit-physical", 0.85 * g, 1.0, 0.08)   # pitch/vol 抖动由 Audio 自带 → 连段听感有差

## 普攻出声的另一个入口: 普攻伤害不带「普攻命中」标记的龟(闪电龟)在出手那一刻播自己的 atk_<id>, 与 _sfx_hit 共用节流表。
func sfx_basic_cast(u: Dictionary) -> void:
	var a = _audio()
	if a == null or not a.has_method("has_sfx"):
		return
	var ev := "atk_" + str(u.get("id", ""))
	if a.has_sfx(ev) and battle._t - float(_ev_last_t.get(ev, -99.0)) >= battle.SFX_HIT_MIN_GAP and _hit_slot():
		_ev_last_t[ev] = battle._t
		a.play_sfx(ev, ATK_GAIN, 1.0, 0.04)


## 放技能: 龟放出主动技那一刻播它自己的 cast_<id>(每只龟一条, 与普攻同一个「按来源」规矩)。小将 / 召唤物没有专属声 ⇒ 不出声。
func sfx_skill_cast(u: Dictionary, tier: int = VfxTiers.NORMAL) -> void:
	var a = _audio()
	if a == null or not a.has_method("has_sfx") or u.has("minion_role") or bool(u.get("is_summon", false)):
		return
	var ev := "cast_" + str(u.get("id", ""))
	if not a.has_sfx(ev) or battle._t - float(_ev_last_t.get(ev, -99.0)) < CAST_SAME_SRC_GAP:
		return
	while not _cast_ts.is_empty() and battle._t - float(_cast_ts[0]) > CAST_WINDOW:
		_cast_ts.pop_front()
	if _cast_ts.size() >= CAST_VOICES:
		return
	_cast_ts.append(battle._t)
	_ev_last_t[ev] = battle._t
	a.play_sfx(ev, VfxTiers.cast_sfx_gain(tier), 1.0, 0.03)   # 音量按重要度档位(VfxTiers; 大招级原音量)


## 阵亡: 主龟与小将倒下播 unit_death(召唤物 / 龟蛋不播: 蛋有自己的碎裂演出)。全场 DEATH_GAP 内只响一声。
func sfx_death(u: Dictionary) -> void:
	var a = _audio()
	if a == null or bool(u.get("is_summon", false)) or bool(u.get("_isEgg", false)):
		return
	if battle._t - _death_last_t < DEATH_GAP:
		return
	_death_last_t = battle._t
	a.play_sfx("unit_death", 1.0, 1.0, 0.04)

## ★11-04 探针: 治疗声一局 489 次(原间隔 0.06 秒 ⇒ 生命偷取 / 持续回血每一跳都响, 满血回 0 也响)。
##   云顶回血 tick 不出声 ⇒ 只在真回了血时(调用方判)且全场 HEAL_SFX_GAP 内最多一下; 得盾同理 SHIELD_SFX_GAP。
func _sfx_heal() -> void:
	var a = _audio()
	if a == null: return
	if battle._t - battle._last_heal_sfx_t < HEAL_SFX_GAP: return
	battle._last_heal_sfx_t = battle._t
	a.play_sfx("heal", AUX_GAIN, 1.0, 0.04)

func _sfx_shield_gain() -> void:
	var a = _audio()
	if a == null: return
	if battle._t - battle._last_shieldgain_sfx_t < SHIELD_SFX_GAP: return
	battle._last_shieldgain_sfx_t = battle._t
	a.play_sfx("shield-gain", 0.9 * AUX_GAIN, 1.0, 0.05)

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