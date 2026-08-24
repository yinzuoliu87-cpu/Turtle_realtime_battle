class_name LineSystem
extends RefCounted
## 素描龟技能系统
## 类内名不变;外部名加 battle.

## ★线条数值单一事实源(用户2026-07-28 第三轮加强·整只 20.9%)。文案在 data/pets.json。
## 【画龙点睛(收尾)】对墨迹最多的敌人: (BASE + PER_INK×层数) ×ATK 物理, 不消耗墨迹。
## 【被动·墨迹】每层墨迹让目标每次受伤额外承受 % 真实伤害(穿减伤穿盾)。
const INK_TRUE_PER_STACK := 0.05   # 每层额外承受的真实伤害比例
const INK_CAP := 7                 # 层数上限
const INK_CAP_BOMB := 10           # 选了「墨水炸弹」后的上限
## 【墨水炸弹】落点 AOE 四段, 每段叠 1 层。
const BOMB_SEGMENTS := 4           # 溅射几段
const BOMB_SEG_COEF := 0.25        # 每段 ×ATK 魔法
## 满层时的总系数 —— **推导, 不手写**(文案原来写死 385% / 520%)。
## 放在 DOT_* 之后声明会前向引用, 所以这两行在下面(见 DOT_FULL_*)。
const DOT_BASE_COEF := 0.7    # 基础系数
const DOT_PER_INK := 0.45     # 每层墨迹再加
const DOT_FULL_COEF := DOT_BASE_COEF + DOT_PER_INK * INK_CAP           # 推导: 满 7 层
const DOT_FULL_COEF_BOMB := DOT_BASE_COEF + DOT_PER_INK * INK_CAP_BOMB # 推导: 墨水炸弹满 10 层
const ASPD_PER_ATK := 0.005   # 被动·墨迹: 自身获得 =(0.5×攻击力)% 的攻速 → 每1点攻击力 +0.5%

var battle

## 被动·墨迹的自身加成 (用户2026-07-28「线条龟自身获得相当于(0.5ATK)%额外的攻击速度, 实时的」)
##
## ★为什么给线条加这条: 墨迹是【放大器】不是伤害源 —— 它只让目标"每受到一次伤害"额外吃 5%/层真伤。
##   而线条攻速 0.70、移速 70 都是最慢档 → 自己产出频率低 = 放大器没东西可放大。攻速直接补这个短板。
## ★写法与彩虹 _rainbow_prism_convert 同一套(别改成累乘):
##   从【无本加成的基准间隔】整体重算, 绝不在现值上累除 —— 累除会随帧数漂移。
##   实时: 中途吃到加攻的装备/buff 会立刻反映在攻速上。
func _line_aspd_convert(u: Dictionary) -> void:
	var iv0: float = float(u.get("_line_base_iv", 0.0))
	if iv0 <= 0.0:
		iv0 = float(u["atk_interval"])
		u["_line_base_iv"] = iv0
	u["atk_interval"] = iv0 / (1.0 + ASPD_PER_ATK * float(u["atk"]))

func _init(b) -> void:
	battle = b

# 选中的那1个技 type (排除普攻; 供主动/被动判定). 返空 = 没选到有效技.
# 墨迹上限: 选「墨水炸弹」→ 全来源上限提到10层(满10层=50%真伤); 否则7层 (用户2026-07-10)
func _ink_cap(src: Dictionary) -> int:
	if src == null: return 7
	return INK_CAP_BOMB if "lineInkBomb" in battle._chosen_skill_types(str(src.get("id", "")), src.get("side", "") == "left") else INK_CAP

func _sk_line_link(u: Dictionary) -> void:                       # 线条龟·连笔 ✅(连接+传导+同步已补·附录B-05)
	var foes: Array = []
	for o in battle._targeting._enemies_of(u):
		if o.get("alive", false): foes.append(o)
	if foes.is_empty(): return
	foes.sort_custom(func(x, y): return u["pos"].distance_squared_to(x["pos"]) < u["pos"].distance_squared_to(y["pos"]))
	var picks: Array = foes.slice(0, mini(2, foes.size()))
	for o in picks:
		battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, 0.8, o), Color("#dddddd"))
		battle._add_stack(o, "ink", 1, _ink_cap(u))
	if picks.size() < 2: return                                  # 只有1个敌人 → 无链路可连
	battle._make_ink_link(picks[0], picks[1], u)

# 返回 u 所在的有效链路 {a,b,caster,until,spr}; 无 → 空字典 (不返 null: GDScript静态分析对"可能为null再下标"报Parse Error)
func _ink_link_of(u: Dictionary) -> Dictionary:
	for L in battle._ink_links:
		if battle._t >= float(L["until"]): continue
		if L["a"] == u and L["b"].get("alive", false): return L
		if L["b"] == u and L["a"].get("alive", false): return L
	return {}

func _ink_link_partner(u: Dictionary) -> Dictionary:             # 连接对象(仍在有效期且活着); 无 → 空字典
	var L: Dictionary = _ink_link_of(u)
	if L.is_empty(): return {}
	return L["b"] if L["a"] == u else L["a"]

func _ink_link_transfer(u: Dictionary, taken: float) -> void:    # 受伤30%以真实伤害传导给连接对象
	if battle._ink_link_busy or taken <= 0.0: return
	var L: Dictionary = _ink_link_of(u)
	if L.is_empty(): return
	var p: Dictionary = L["b"] if L["a"] == u else L["a"]
	var amt = int(taken * battle.INK_LINK_TRANSFER)
	if amt <= 0: return
	# src = 施法的线条龟(不是受伤的那只敌人!) — 否则敌人"打了队友"会吃到吸血并被记进输出统计
	var sc: Dictionary = L["caster"] if L["caster"].get("alive", false) else u
	battle._ink_link_busy = true
	battle._damage._apply_damage_from(sc, p, amt, Color("#b0b0c8"), 0.0, true, true)   # raw=真实(墨迹系·速写融入被动) / from_equip=true 防反伤·叠层循环
	battle._ink_link_busy = false



func _sk_line_ink_bomb(u: Dictionary) -> void:                  # 线条龟·墨水炸弹(用户设计·120龟能; 用户2026-07-15: 全体→落点300码AOE): 投墨弹至最密集处→落点300码内敌各4段0.25A魔法+叠4墨迹(打包被动=墨迹上限提到10)
	var es: Array = []                                          # 投掷墨水炸弹→落点大墨爆+命中才溅墨结算(用户2026-07-15做投掷)
	for o in battle._targeting._pick_enemies_of(u):
		if o.get("alive", false): es.append(o)
	if es.is_empty(): return
	var center: Vector2 = es[0]["pos"]                          # 落点=能覆盖最多敌的300码圆心(智能瞄最密集处·非全体质心)
	var best_cnt = -1
	for a in es:
		var cnt = 0
		for b in es:
			if (a["pos"] as Vector2).distance_to(b["pos"]) <= battle.INK_BOMB_RADIUS: cnt += 1
		if cnt > best_cnt:
			best_cnt = cnt; center = a["pos"]
	var uu: Dictionary = u
	var land: Vector2 = center
	_ink_bomb_throw(u["pos"], land, func() -> void:
		battle._burst_vfx("res://assets/sprites/vfx/ink-splat.png", land, 300.0, 0.6)   # 落点大墨爆(300码)
		battle._shake(battle.JUICE_SHAKE_HEAVY)
		for o in battle._targeting._enemies_of(uu):
			if not o.get("alive", false): continue
			if (o["pos"] as Vector2).distance_to(land) > battle.INK_BOMB_RADIUS: continue   # ★只打落点300码内(用户2026-07-15: 原全体)
			for i in range(BOMB_SEGMENTS):
				battle._damage._apply_damage_from(uu, o, battle._atk_dmg(uu, BOMB_SEG_COEF, o, true), Color("#c9b0ff"))
			battle._add_stack(o, "ink", 4, _ink_cap(uu))
			battle._burst_vfx("res://assets/sprites/vfx/ink-splat.png", o["pos"], 110.0, 0.9)   # 每敌身上墨溅
		battle._skill_ring(land, Color(0.55, 0.4, 0.75, 0.5), battle.INK_BOMB_RADIUS))   # 环显300码AOE范围

func _ink_bomb_throw(from2d: Vector2, to2d: Vector2, on_land: Callable) -> void:   # 墨水炸弹: 深墨球抛向敌区→落点自销调on_land
	var ball = Sprite3D.new()
	ball.texture = VfxTex._make_glow_texture()
	ball.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ball.billboard = BaseMaterial3D.BILLBOARD_ENABLED; ball.shaded = false; ball.transparent = true
	ball.modulate = Color(0.22, 0.16, 0.32, 1.0)   # 深墨色
	ball.pixel_size = (30.0 * battle.WS) / float(maxi(1, ball.texture.get_height()))
	ball.position = battle._world_pos(from2d, 1.0)
	battle._world.add_child(ball)
	var dur: float = clampf(from2d.distance_to(to2d) / 900.0, 0.32, 0.6)
	var tw = battle._reg_tween()
	tw.tween_method(func(p: float) -> void:
		if not is_instance_valid(ball): return
		ball.position = battle._world_pos(from2d.lerp(to2d, p), 1.0 * (1.0 - p) + 3.0 * sin(PI * p))   # 抛物
	, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(ball): ball.queue_free()
		if on_land.is_valid(): on_land.call())

# 线条·收尾·画龙点睛: 对墨迹最多敌 (0.7+0.45×层数)×ATK物理 (用户封板L466: 不消耗墨迹)
# 线条·收尾·画龙点睛: 对墨迹最多敌 (0.7+0.45×层数)×ATK物理 (用户封板L466: 不消耗墨迹)
func _sk_line_finish(u: Dictionary) -> void:
	var best = null
	var best_ink = -1
	for o in battle._targeting._pick_enemies_of(u):
		var ink = int((o.get("stacks", {}) as Dictionary).get("ink", 0))
		if ink > best_ink:
			best_ink = ink
			best = o
	if best == null:
		best = battle._targeting._nearest_enemy(u)
		best_ink = 0
	if best == null:
		return
	var scale: float = DOT_BASE_COEF + DOT_PER_INK * maxi(0, best_ink)   # 基础0.7+每层墨迹0.45×ATK (恢复文本设计值, 原0.8/0.35)
	battle._weapon_slash(u["pos"], best["pos"], Color(0.32, 0.24, 0.46))   # 画龙点睛·大终笔墨挥(用户2026-07-15做终笔分量)
	battle._damage._apply_damage_from(u, best, battle._atk_dmg(u, scale, best), Color("#eeeeee"))
	battle._burst_vfx("res://assets/sprites/vfx/ink-splat.png", best["pos"], 210.0, 0.7)   # 点睛大墨爆
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	battle._skill_ring(best["pos"], Color(0.9, 0.9, 0.9, 0.5), 52.0)   # 画龙点睛不消耗墨迹(用户封板L466·原_consume_stacks已删)

# 赛博·部署: 立即放3个浮游炮 (与被动「浮游炮」同型, 上限10)