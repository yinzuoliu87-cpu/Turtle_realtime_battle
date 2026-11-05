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


## ★2026-11-05 音效 v2(用户「旧的那个普攻、伤害音效、盾音效，全部都要重做，全部都要达到云顶的标准」
##   「云顶音效怎么做的？每个技能怎么做的这个音效？」): 照云顶 / LoL 的拆法(实拆游戏文件, docs/studies/20261105-云顶音效拆解-科加斯Q声轨逐帧.md) ——
##   普攻 = 出手 bas_<龟>(挥击破风 / 发射) + 命中 bah_<龟>(暴击换 crit_<龟>), 各 2~3 个变体轮换;
##   技能 = 放出 sk_<技能类型> + 命中 skh_<技能类型>(这个技能的伤害落到人身上那一刻);
##   装备 = eq_<编号>(该装备上下文里的伤害 / 治疗 / 护盾那一刻, 或装备自己的触发点调 sfx_equip);
##   小将 / 召唤物 / 认不出来源的 = 公共 g_*。全部只管声音: 不碰 sim、不用战斗随机流、不往单位字典写东西。
const SWING_GAIN := 0.8          # 出手声比命中再轻 2 dB(命中才是「打中了」的信息)
const SWING_WINDOW := 0.1        # 全场出手声同一窗口最多 1 路
var _swing_ts: Array = []
const SKH_GAIN := 0.8            # 技能命中层(比放出轻 2 dB)
const SKH_GAP := 0.12            # 同一个技能命中声的最小间隔(多段 / 多目标不刷屏)
const SKH_VOICES := 2            # 全场技能命中声同一窗口最多 2 路
const SKH_WINDOW := 0.15
var _skh_ts: Array = []
const CAST_HIT_WINDOW := 6.0     # 放技能后这么久之内、这只龟打出的非普攻伤害 = 这个技能的命中
var _cast_by: Array = []         # [[单位, 技能类型, 时刻], ...] 每只龟最近一次放的技能(单位只做引用, 用 is_same 比)
const EQ_GAIN := 0.8
const EQ_GAP := 0.5              # 同一件装备的声音最小间隔
## 持续回复 / 每次攻击叠盾的装备(温泉蛋每秒 / 深海项链 16 秒持续 / 咸鱼砖灰血 / 魔法胸甲每攻 / 龟甲片每 0.25 秒):
##   每一跳都响会刷屏(云顶持续回复不出声) ⇒ 它们上下文里的治疗与护盾不出声; 触发那一刻由装备自己的 sfx_equip 出声。
const QUIET_AUX := ["p2eq_036", "p2eq_044", "p2eq_070", "p2eq_074", "p2eq_091", "p2eq_060"]


func _hit_slot() -> bool:
	while not _hit_ts.is_empty() and battle._t - float(_hit_ts[0]) > HIT_WINDOW:
		_hit_ts.pop_front()
	if _hit_ts.size() >= HIT_VOICES:
		return false
	_hit_ts.append(battle._t)
	return true


func _swing_slot() -> bool:
	while not _swing_ts.is_empty() and battle._t - float(_swing_ts[0]) > SWING_WINDOW:
		_swing_ts.pop_front()
	if _swing_ts.size() >= 1:
		return false
	_swing_ts.append(battle._t)
	return true


func _skh_slot() -> bool:
	while not _skh_ts.is_empty() and battle._t - float(_skh_ts[0]) > SKH_WINDOW:
		_skh_ts.pop_front()
	if _skh_ts.size() >= SKH_VOICES:
		return false
	_skh_ts.append(battle._t)
	return true


static func _is_turtle(src) -> bool:
	return src is Dictionary and not (src as Dictionary).has("minion_role") and not bool((src as Dictionary).get("is_summon", false))


## 普攻出手(_basic_attack 开头调): 近战挥击破风 / 远程发射声。小将 / 召唤物不出(它们只有命中声)。
func sfx_basic_swing(u: Dictionary) -> void:
	var a = _audio()
	if a == null or not _is_turtle(u):
		return
	var ev := "bas_" + str(u.get("id", ""))
	if not a.has_sfx(ev) or battle._t - float(_ev_last_t.get(ev, -99.0)) < battle.SFX_HIT_MIN_GAP:
		return
	if not _swing_slot():
		return
	_ev_last_t[ev] = battle._t
	a.play_sfx(ev, ATK_GAIN * SWING_GAIN, 1.0, 0.04)


## 命中(两条伤害路 → battle_damage 调): eq_iid = 这一段伤害所在的装备上下文(battle_damage 记完账前抓下来的)。
func _sfx_hit(crit: bool, src = null, basic: bool = false, eq_iid: String = "") -> void:
	var a = _audio()
	if a == null:
		return
	if basic and _is_turtle(src):
		var id := str((src as Dictionary).get("id", ""))
		var ev := "bah_" + id
		if a.has_sfx(ev):
			if battle._t - float(_ev_last_t.get(ev, -99.0)) >= battle.SFX_HIT_MIN_GAP and _hit_slot():
				_ev_last_t[ev] = battle._t
				if crit and a.has_sfx("crit_" + id):
					a.play_sfx("crit_" + id, ATK_GAIN * 1.12, 1.0, 0.03)   # 暴击换成这只龟自己的暴击声(云顶 CritAttack_OnHit 是另一套)
				else:
					a.play_sfx(ev, ATK_GAIN, 1.0, 0.04)
			return
	if not basic:
		if eq_iid != "" and sfx_equip(eq_iid):
			return
		var st := "" if eq_iid != "" else _recent_cast(src)   # 装备打的伤害(该件没有自己的声音)不冒充技能命中
		if st != "":
			var hev := hit_event_of(src, st)
			if a.has_sfx(hev):
				if battle._t - float(_ev_last_t.get(hev, -99.0)) >= SKH_GAP and _skh_slot():
					_ev_last_t[hev] = battle._t
					a.play_sfx(hev, SKH_GAIN, 1.0, 0.04)
					if crit:
						a.play_sfx("g_crit", 0.5 * ATK_GAIN, 1.0, 0.03)
				return
		## 认不出来源的技能 / 装备伤害: 公共技能命中声, 全场 SKILL_HIT_GAP 内最多一下(11-04 探针: 每段都响会刷成一层底)
		if battle._t - _skill_hit_last_t < SKILL_HIT_GAP:
			return
		_skill_hit_last_t = battle._t
		a.play_sfx("g_crit" if crit else "g_skill_hit", ATK_GAIN, 1.0, 0.05)
		return
	## 小将 / 召唤物普攻: 公共命中声
	var g: float = ATK_GAIN
	if crit:
		if battle._t - battle._last_crit_sfx_t < battle.SFX_HIT_MIN_GAP or not _hit_slot():
			return
		battle._last_crit_sfx_t = battle._t
		a.play_sfx("g_crit", 1.0 * g, 1.0, 0.03)
	else:
		if battle._t - battle._last_hit_sfx_t < battle.SFX_HIT_MIN_GAP or not _hit_slot():
			return
		battle._last_hit_sfx_t = battle._t
		a.play_sfx("g_hit", 0.85 * g, 1.0, 0.06)


## 装备触发(eq_<编号>): 伤害 / 治疗 / 护盾在装备上下文里时由上面几处转进来; 没有伤害的触发(召唤 / 时停 / 饮药…)在装备自己的触发点调。
##   返回 true = 这件装备有自己的声音(响了或在节流期内, 调用方都不再补通用声)。
func sfx_equip(iid: String) -> bool:
	var a = _audio()
	if a == null or iid.length() < 6:
		return false
	var ev := "eq_" + iid.substr(5)
	if not a.has_sfx(ev):
		return false
	if battle._t - float(_ev_last_t.get(ev, -99.0)) >= EQ_GAP:
		_ev_last_t[ev] = battle._t
		a.play_sfx(ev, EQ_GAIN, 1.0, 0.04)
	return true


func _recent_cast(src) -> String:
	if not (src is Dictionary):
		return ""
	for r in _cast_by:
		if is_same(r[0], src):
			return str(r[1]) if battle._t - float(r[2]) <= CAST_HIT_WINDOW else ""
	return ""


func _note_cast(u: Dictionary, stype: String) -> void:
	for r in _cast_by:
		if is_same(r[0], u):
			r[1] = stype
			r[2] = battle._t
			return
	_cast_by.append([u, stype, battle._t])


## 闪电龟普攻没有「普攻命中」标记(出手即命中): 出手那一刻补播它的命中声, 与 _sfx_hit 共用节流表。
func sfx_basic_cast(u: Dictionary) -> void:
	var a = _audio()
	if a == null or not a.has_method("has_sfx"):
		return
	var ev := "bah_" + str(u.get("id", ""))
	if a.has_sfx(ev) and battle._t - float(_ev_last_t.get(ev, -99.0)) >= battle.SFX_HIT_MIN_GAP and _hit_slot():
		_ev_last_t[ev] = battle._t
		a.play_sfx(ev, ATK_GAIN, 1.0, 0.04)


## 放技能: 龟放出主动技那一刻播这个技能的 sk_<技能类型>; 并记下「这只龟最近放的是哪个技能」, 之后它的技能伤害播 skh_<技能类型>。
##   小将 / 召唤物没有技能声。11-05 起没有 cast_<龟 id> 退路(旧音效全删, 每个技能都有自己的)。
## ★熔岩龟火山形态: 技能类型不变(冷却键仍是 lavaQuake / lavaSurge / lavaErupt), 声音换成火山那三条。
const VOLCANO_CAST := {"lavaQuake": "volcanoErupt", "lavaSurge": "volcanoSmash", "lavaErupt": "lavaRampage"}

static func _sound_stype(u: Dictionary, stype: String) -> String:
	if bool(u.get("volcano", false)) and VOLCANO_CAST.has(stype):
		return str(VOLCANO_CAST[stype])
	return stype

static func cast_event_of(u: Dictionary, stype: String) -> String:
	return "" if stype == "" else "sk_" + _sound_stype(u, stype)

static func hit_event_of(u: Dictionary, stype: String) -> String:
	return "" if stype == "" else "skh_" + _sound_stype(u, stype)

func sfx_skill_cast(u: Dictionary, tier: int = VfxTiers.NORMAL, stype: String = "") -> void:
	var a = _audio()
	if a == null or not a.has_method("has_sfx") or not _is_turtle(u) or stype == "":
		return
	_note_cast(u, stype)
	var ev := cast_event_of(u, stype)
	if not a.has_sfx(ev) or battle._t - float(_ev_last_t.get(ev, -99.0)) < CAST_SAME_SRC_GAP:
		return
	while not _cast_ts.is_empty() and battle._t - float(_cast_ts[0]) > CAST_WINDOW:
		_cast_ts.pop_front()
	if _cast_ts.size() >= CAST_VOICES:
		return
	_cast_ts.append(battle._t)
	_ev_last_t[ev] = battle._t
	a.play_sfx(ev, VfxTiers.cast_sfx_gain(tier), 1.0, 0.03)   # 音量按重要度档位(VfxTiers; 大招级原音量)


## 阵亡: 主龟与小将倒下播 g_death(召唤物 / 龟蛋不播: 蛋有自己的碎裂演出)。全场 DEATH_GAP 内只响一声。
func sfx_death(u: Dictionary) -> void:
	var a = _audio()
	if a == null or bool(u.get("is_summon", false)) or bool(u.get("_isEgg", false)):
		return
	if battle._t - _death_last_t < DEATH_GAP:
		return
	_death_last_t = battle._t
	a.play_sfx("g_death", 1.0, 1.0, 0.04)

## ★11-04 探针: 治疗声一局 489 次(原间隔 0.06 秒 ⇒ 生命偷取 / 持续回血每一跳都响, 满血回 0 也响)。
##   云顶回血 tick 不出声 ⇒ 只在真回了血时(调用方判)且全场 HEAL_SFX_GAP 内最多一下; 得盾同理 SHIELD_SFX_GAP。
##   11-05: 在装备上下文里(这一下治疗 / 护盾是某件装备给的) ⇒ 播那件装备的声音。
func _cur_equip() -> String:
	var es = battle.get("_equip_sys")
	if es == null or es.get("tally") == null:
		return ""
	return str(es.tally._iid)

func _sfx_heal() -> void:
	var a = _audio()
	if a == null: return
	var iid := _cur_equip()
	if QUIET_AUX.has(iid): return
	if sfx_equip(iid): return
	if battle._t - battle._last_heal_sfx_t < HEAL_SFX_GAP: return
	battle._last_heal_sfx_t = battle._t
	a.play_sfx("g_heal", AUX_GAIN, 1.0, 0.04)

func _sfx_shield_gain() -> void:
	var a = _audio()
	if a == null: return
	var iid := _cur_equip()
	if QUIET_AUX.has(iid): return
	if sfx_equip(iid): return
	if battle._t - battle._last_shieldgain_sfx_t < SHIELD_SFX_GAP: return
	battle._last_shieldgain_sfx_t = battle._t
	a.play_sfx("g_shield_gain", 0.9 * AUX_GAIN, 1.0, 0.05)

func _sfx_shield_break() -> void:
	var a = _audio()
	if a == null: return
	if battle._t - battle._last_shieldbreak_sfx_t < battle.SFX_AUX_MIN_GAP: return
	battle._last_shieldbreak_sfx_t = battle._t
	a.play_sfx("g_shield_break", 1.0, 1.0, 0.06)

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