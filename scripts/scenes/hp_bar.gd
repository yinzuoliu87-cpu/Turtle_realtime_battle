class_name HpBar
extends Node2D
# 战斗血条 — 1:1 PoC **turtle-hud.ts** (真渲染层! Phaser Graphics depth7, 88px **未缩放**).
# 渲染层经 agent 逐行追调用链确认 (view.sceneTurtleDom 实为 TurtleHud 实例 BattleScene.ts:1987;
#   Phaser rect 全 alpha0 诱饵; scene-turtle-dom.ts 从不 import = 死码). 见 docs/BATTLE-RENDER-MAP.md.
# 全部值引 turtle-hud.ts 行号. 自定义 _draw 复刻其 drawFrame/drawFills/fillBand/playDamageTrail.

var bar_w := 88.0        # turtle-hud BAR_W=88 (boss160), 未×baseScale
var bar_h := 5.0         # BAR_H=5 (boss8)
var border := 2.0        # BORDER=2 (boss3)
var is_ally := true

var _hp := 1.0
var _max_hp := 1.0
var _shield := 0.0
var _holy := 0.0          # 圣甲圣盾量 (shield 中属圣盾的部分) — 血条上画成白黄亮 (区别普通盾段)
var _hshell := 0.0        # 缩头防御特殊盾量 (shield 中属壳盾的部分) — 画壳青绿段
var _urchin := 0.0        # 海胆护盾量 (013满层·shield 中属海胆盾的部分) — 画海胆紫段(10秒渐衰肉眼可见)
var _aura := 0.0
var _bubble := 0.0
var _anem := 0.0
var _bm := 1.0           # barMax = max(maxHp, hp+shield+aura+bubble+anemone)
var _trail_frac := -1.0
var _flash_a := 0.0
var _shake := 0.0
var _prev_hp := -1.0
var _trail_tw: Tween = null
var _flash_tw: Tween = null
var _shake_tw: Tween = null
var _special_bars: Array = []   # [{frac,bg,fill,bga,fa}] — HP条下方特殊资源条 (turtle-hud drawSpecialtyBars)

const _SPECIAL_H := 4.0          # turtle-hud SPECIAL_H

const _BORDER := Color8(0x0a, 0x06, 0x06)         # 黑硬边框
const _TROUGH := Color8(0x28, 0x10, 0x10, 242)    # 暗红槽 @.95
const _ALLY_L := Color8(0x3d, 0xeb, 0x9e)
const _ALLY_D := Color8(0x1f, 0xb5, 0x7f)
const _ENEMY_L := Color8(0xc0, 0x84, 0xfc)
const _ENEMY_D := Color8(0x9d, 0x5b, 0xe8)
const _DELAY_L := Color8(0xff, 0x4d, 0x4d)
const _DELAY_D := Color8(0xc8, 0x1e, 0x1e)
const _SHIELD_L := Color8(0xf0, 0xf0, 0xf5)
const _SHIELD_D := Color8(0xc8, 0xc8, 0xdc)
const _HOLY_L := Color8(0xff, 0xf4, 0xc0)    # 圣盾段 白黄亮 (圣光色, 区别普通灰白盾)
const _HSHELL_L := Color8(0x8f, 0xf0, 0xb8)  # 缩头防御特殊盾段 壳青绿亮(用户2026-07-17"特殊点的颜色放血条")
const _HSHELL_D := Color8(0x3f, 0x9f, 0x6e)  # 壳青绿暗
const _URCHIN_L := Color8(0xcc, 0x66, 0xf5)  # 海胆盾段 亮紫 (013满层·用户2026-07-19"特殊颜色")
const _URCHIN_D := Color8(0x93, 0x33, 0xba)  # 海胆紫暗
const _HOLY_D := Color8(0xff, 0xdf, 0x70)
const _AURA := Color8(0xff, 0xd9, 0x66)
const _BUBBLE := Color8(0x4c, 0xc9, 0xf0)
const _ANEM := Color8(0xd9, 0x6b, 0xff)


func setup(p_is_ally: bool, p_is_boss: bool) -> void:
	is_ally = p_is_ally
	bar_w = 160.0 if p_is_boss else 88.0
	bar_h = 8.0 if p_is_boss else 5.0
	border = 3.0 if p_is_boss else 2.0


## 当前血条正显示的 HP 值 (上次 update_state 后定格的 _hp). 多源逐段修用:
##   伤害飘字 chokepoint 据此 step-down (显示血量 ≥ 真实 hp, 逐飘字收敛). 未初始化(-1)→调用方退回真实 hp.
func displayed_hp() -> float:
	return _prev_hp


## hp_override / shield_override >= 0: 用给定值替代 f 的 hp/shield (多段技能血条逐段下降用).
##   _prev_hp 仍保留上次显示值 → 每段 update 自动触发 old→new 红 trail (turtle-hud playDamageTrail).
func update_state(f: Dictionary, hp_override := -1.0, shield_override := -1.0) -> void:
	_max_hp = maxf(1.0, float(f.get("maxHp", 1)))
	var new_hp := clampf(hp_override if hp_override >= 0.0 else float(f.get("hp", 0)), 0.0, _max_hp)
	# 多段血条 step 防回弹: damage 段 override 只允许下降。若某迟到的 step timer (段动画 ~1s 可跨回合,
	#   期间可能已有全量 refresh 把血条降到终值) 想把血条抬回更高值 → 忽略, 防"血条异常回弹"。
	if hp_override >= 0.0 and _prev_hp >= 0.0 and new_hp > _hp:
		return
	_shield = maxf(0.0, shield_override if shield_override >= 0.0 else float(f.get("shield", 0)))
	# 圣盾量 (圣甲): shield 中属圣盾的部分, 画白黄亮段. 受击消盾时 clamp 不超当前总盾 (盾被打掉则圣盾段同步缩)。
	#   写回 fighter 让 _holyShieldVal 随盾衰减 (盾清零→圣盾归0, 之后新得的普通盾不会被误染金): update_state 每次受伤刷新都收敛。
	_holy = clampf(float(f.get("_holyShieldVal", 0)), 0.0, _shield)
	if f.has("_holyShieldVal") and float(f.get("_holyShieldVal", 0)) > _shield and shield_override < 0.0:
		f["_holyShieldVal"] = _shield
	_hshell = clampf(float(f.get("_hidingShellVal", 0)), 0.0, maxf(0.0, _shield - _holy))
	_urchin = clampf(float(f.get("urchin_sh_left", 0)), 0.0, maxf(0.0, _shield - _holy - _hshell))   # 海胆盾段: 随10秒衰减自动缩
	if f.has("_hidingShellVal") and float(f.get("_hidingShellVal", 0)) > _shield and shield_override < 0.0:
		f["_hidingShellVal"] = _shield   # 盾被打掉→壳盾段同步收敛(圣盾同款写回)
	_aura = maxf(0.0, float(f.get("_auraShieldVal", f.get("_lavaShieldVal", f.get("_hidingShieldVal", 0)))))
	_bubble = maxf(0.0, float(f.get("bubbleShieldVal", 0)))
	_anem = maxf(0.0, float(f.get("_anemoneShield", 0)))
	_bm = maxf(_max_hp, new_hp + _shield + _aura + _bubble + _anem)   # turtle-hud:228-229
	if _prev_hp >= 0.0 and new_hp < _prev_hp:
		_start_trail(_prev_hp / _bm, new_hp / _bm)
		_start_flash()
	_prev_hp = new_hp
	_hp = new_hp
	_special_bars = _compute_special_bars(f)
	queue_redraw()


## 特殊资源条 (turtle-hud drawSpecialtyBars:503-548) — 按 passive.type 决定显哪条; 0-1 条/龟.
func _compute_special_bars(f: Dictionary) -> Array:
	var passive = f.get("passive", null)
	var pt: String = str(passive.get("type", "")) if passive is Dictionary else ""
	var out: Array = []
	if pt == "bubbleStore":
		var store := float(f.get("bubbleStore", 0))
		out.append({"frac": store / maxf(1.0, _max_hp), "bg": _BUBBLE, "fill": _BUBBLE, "bga": 0.15, "fa": 0.6})
	elif pt == "lavaRage":
		var rage := float(f.get("_lavaRage", 0))
		var rmax := float(passive.get("rageMax", 100)) if passive is Dictionary else 100.0
		out.append({"frac": rage / maxf(1.0, rmax), "bg": Color8(0xff, 0x64, 0x00), "fill": Color8(0xff, 0x33, 0x00), "bga": 0.15, "fa": 0.6})
	elif pt == "starEnergy" or (pt == "auraAwaken" and passive is Dictionary and passive.has("energyStore")):
		# 按type读对应字段: 龟壳(auraAwaken)读_auraEnergy, 星能龟(starEnergy)读_starEnergy. (原回退链被全局镜像_starEnergy=0破坏→龟壳恒读0=黄条不动)
		var en := float(f.get("_auraEnergy", 0.0)) if pt == "auraAwaken" else float(f.get("_starEnergy", 0.0))
		var maxe: float
		if passive is Dictionary and passive.has("maxChargePct"):
			maxe = roundf(_max_hp * float(passive.get("maxChargePct", 0)) / 100.0)
		else:
			maxe = roundf(_max_hp * (float(passive.get("energyMaxStorePct", 0.5)) if passive is Dictionary else 0.5))
		out.append({"frac": en / maxf(1.0, maxe), "bg": Color8(0xff, 0xa5, 0x00), "fill": Color8(0xff, 0xcc, 0x00), "bga": 0.15, "fa": 0.6})
	elif pt == "stoneWall":
		var gained := float(f.get("_stoneDefGained", 0))
		var initdef := float(f.get("_initDef", f.get("baseDef", f.get("def", 1))))
		var pct := float(passive.get("maxDefInitPct", 100)) if passive is Dictionary else 100.0
		var maxcap := roundf(initdef * pct / 100.0)
		out.append({"frac": gained / maxf(1.0, maxcap), "bg": Color8(0xff, 0xc8, 0x50), "fill": Color8(0xff, 0xd4, 0x5c), "bga": 0.22, "fa": 0.85})
	return out


func _start_trail(old_frac: float, new_frac: float) -> void:
	if _trail_tw != null and _trail_tw.is_valid():
		_trail_tw.kill()
	var start := old_frac if _trail_frac < 0.0 else maxf(_trail_frac, old_frac)
	_trail_frac = start
	_trail_tw = create_tween()
	_trail_tw.tween_interval(0.2)                                    # hold 200ms (turtle-hud:457 delay)
	_trail_tw.tween_method(_set_trail, start, new_frac, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_trail_tw.tween_callback(func() -> void:
		_trail_frac = -1.0
		queue_redraw())
	if _shake_tw != null and _shake_tw.is_valid():
		_shake_tw.kill()
	_shake_tw = create_tween()                                      # 横抖 _shakeX:3 yoyo×2 (turtle-hud:428)
	_shake_tw.tween_method(_set_shake, 0.0, 3.0, 0.03)
	_shake_tw.tween_method(_set_shake, 3.0, -3.0, 0.06)
	_shake_tw.tween_method(_set_shake, -3.0, 0.0, 0.03)


func _set_trail(v: float) -> void:
	_trail_frac = v
	queue_redraw()


func _set_shake(v: float) -> void:
	_shake = v
	queue_redraw()


func _start_flash() -> void:
	if _flash_tw != null and _flash_tw.is_valid():
		_flash_tw.kill()
	_flash_a = 0.6                                                   # 0xffffff @.6 (turtle-hud:467)
	queue_redraw()
	_flash_tw = create_tween()
	_flash_tw.tween_interval(0.06)                                   # 60ms
	_flash_tw.tween_callback(func() -> void:
		_flash_a = 0.0
		queue_redraw())


func _draw() -> void:
	var x := _shake
	var w := bar_w
	var h := bar_h
	var bd := border
	# 1) 阴影 (下偏2px)  2) 黑边框  3) 暗红槽  4) 顶玻璃高光  5) 底暗线 (drawFrame:319-331)
	draw_rect(Rect2(x - bd, -bd + 2.0, w + 2.0 * bd, h + 2.0 * bd), Color(0, 0, 0, 0.4))
	draw_rect(Rect2(x - bd, -bd, w + 2.0 * bd, h + 2.0 * bd), _BORDER)
	draw_rect(Rect2(x, 0, w, h), _TROUGH)
	draw_rect(Rect2(x, 0, w, 1.0), Color(1, 1, 1, 0.22))
	draw_rect(Rect2(x, h - 1.0, w, 1.0), Color(0, 0, 0, 0.55))
	# 受击红 trail (2带, 在 fill 之下; playDamageTrail:445-448)
	if _trail_frac > 0.0:
		var tw := w * clampf(_trail_frac, 0.0, 1.0)
		var th := roundf(h * 0.42)
		draw_rect(Rect2(x, 0, tw, th), _DELAY_L)
		draw_rect(Rect2(x, th, tw, h - th), _DELAY_D)
	# HP fill (逐行渐变 gloss首行) + 护盾段 (cursor链)
	var hp_w := w * (_hp / _bm)
	var ftop := _ALLY_L if is_ally else _ENEMY_L
	var fbot := _ALLY_D if is_ally else _ENEMY_D
	_fill_band(x, hp_w, ftop, fbot, 1.0)
	var cursor := hp_w
	# 护盾段: 圣盾部分(白黄亮)先画, 普通盾部分(灰白)接其后 — 一看血条即区分圣盾 (圣甲) 与普通盾。
	cursor += _seg(x, cursor, w, _holy, _HOLY_L, _HOLY_D, 0.6)
	cursor += _seg(x, cursor, w, _hshell, _HSHELL_L, _HSHELL_D, 0.6)
	cursor += _seg(x, cursor, w, _urchin, _URCHIN_L, _URCHIN_D, 0.6)
	cursor += _seg(x, cursor, w, maxf(0.0, _shield - _holy - _hshell - _urchin), _SHIELD_L, _SHIELD_D, 0.55)
	cursor += _seg(x, cursor, w, _aura, _AURA, _AURA, 0.6)
	cursor += _seg(x, cursor, w, _bubble, _BUBBLE, _BUBBLE, 0.55)
	cursor += _seg(x, cursor, w, _anem, _ANEM, _ANEM, 0.7)
	# 刻度 100/500 (在 fill 之上; drawFrame:333-352)
	var minor_px := (100.0 / _bm) * w
	if minor_px >= w * 0.02:
		var v := 100.0
		while v < _bm:
			var tx := roundf(x + (v / _bm) * w)
			draw_rect(Rect2(tx, 0, 1.0, maxf(2.0, ceilf(h / 2.0))), Color(0, 0, 0, 0.35))
			v += 100.0
		var v2 := 500.0
		while v2 < _bm:
			var tx2 := roundf(x + (v2 / _bm) * w)
			draw_rect(Rect2(tx2, 0, 1.0, h), Color(0, 0, 0, 0.6))
			v2 += 500.0
	# 60ms 白闪
	if _flash_a > 0.0 and hp_w > 0.0:
		draw_rect(Rect2(x, 0, hp_w, h), Color(1, 1, 1, _flash_a))
	# 特殊资源条 (HP条下方 gap1; turtle-hud drawSpecialtyBars): bg@bga 满宽 + fill@fa frac宽
	var srow := h + 1.0
	for sb in _special_bars:
		var bgc: Color = sb["bg"]
		bgc.a = sb["bga"]
		draw_rect(Rect2(x, srow, w, _SPECIAL_H), bgc)
		var fw2: float = w * clampf(sb["frac"], 0.0, 1.0)
		if fw2 > 0.0:
			var flc: Color = sb["fill"]
			flc.a = sb["fa"]
			draw_rect(Rect2(x, srow, fw2, _SPECIAL_H), flc)
		srow += _SPECIAL_H + 1.0


## 逐行渐变 (fillBand:401-419): r=0&h>=3 → gloss(light→白.55); else lerp(light,dark,(r-1)/(h-2))
func _fill_band(bx: float, bw: float, light: Color, dark: Color, alpha: float) -> void:
	if bw <= 0.0:
		return
	var n := int(bar_h)
	for r in range(n):
		var c: Color
		if r == 0 and n >= 3:
			c = light.lerp(Color(1, 1, 1), 0.55)
		else:
			var t := (float(r - 1) / float(n - 2)) if n > 2 else 0.0
			c = light.lerp(dark, clampf(t, 0.0, 1.0))
		c.a = alpha
		draw_rect(Rect2(bx, float(r), bw, 1.0), c)


## 护盾段: 接 cursor, 宽=val/barMax×w 裁到 bar 内. 返回实际宽.
func _seg(x0: float, cursor: float, w: float, val: float, light: Color, dark: Color, alpha: float) -> float:
	if val <= 0.0:
		return 0.0
	var sw: float = minf(w * (val / _bm), w - cursor)
	if sw <= 0.0:
		return 0.0
	_fill_band(x0 + cursor, sw, light, dark, alpha)
	return sw
