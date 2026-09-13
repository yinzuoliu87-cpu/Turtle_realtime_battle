class_name BattleVfx
extends RefCounted
## 战斗视觉特效(飘字/命中火花/冲击/挥击juice/技能vfx·纯表现·不改战斗态)
## 类内名不变;外部名加 battle.

var battle

## 十条羁绊演出层的共用原语 (方案书 docs/plans/20260804-羁绊特效批.md · 批 A · A1)。
## ★接在这里而不是主场景: CLAUDE.md §5「不在 _sim_step 调用链上的不进主文件」。
##   批 B/C 的每条羁绊只写一行 `battle._vfx._syn.xxx(...)`。
var _syn: SynergyVfx = null

const SkillIcons = preload("res://scripts/gamedata/skill_icons.gd")
const ShellSystem = preload("res://scripts/systems/skills/shell_system.gd")


func _init(b) -> void:
	battle = b
	_syn = SynergyVfx.new(b)

## 相机朝向 —— **所有公告板/定向立牌都走这里**, 不许各自读 `battle._cam.global_transform`。
##
## ★由来(2026-08-22): smoke 与新哨兵门禁间歇刷
##   `Condition "!is_inside_tree()" is true. Returning: Transform3D()`。
##   根因是**拆场时相机先离树, 而演出/弹道还会再跑一帧**去读它的朝向。
##   全仓这样的读点有 16 处(ballistics 9 / 主场景 7), 逐处加守卫 = 又一份手抄副本,
##   漏一处就继续偶发红(我第一版猜是触手, 加完守卫那一轮碰巧全绿 —— 运气不是修好)。
##   ⇒ 收口成一个入口: 相机不在树上就返回单位基, 演出画得不对无所谓(那一帧场景正在拆)。
func cam_basis() -> Basis:
	if battle._cam == null or not is_instance_valid(battle._cam) or not battle._cam.is_inside_tree():
		return Basis()
	return battle._cam.global_transform.basis


func _play_action(u: Dictionary, kind: String) -> void:
	if u == null or not is_instance_valid(u.get("sprite", null)):
		return
	# death 优先级最高; 已在播 death 不打断
	if u.get("anim_action", "") == "death":
		return
	# committed 动作: 播完前不被普攻/受击换掉(死亡除外·用户2026-07-11 动作播完前不打断)
	#   backstab=忍者背刺; battle.ACTION_ELITE 五个=精英小将旋刃/铁锤/强化铁锤/铁链/吞噬
	var _cur_act = str(u.get("anim_action", ""))
	if (_cur_act == "backstab" or battle.ACTION_ELITE.has(_cur_act) or battle.ACTION_MELEE.has(_cur_act) or MinionCodex.ACTION_RANGED.has(_cur_act) or u.get("_manual_anim", false)) and kind != "death":
		return
	var id = battle._anim_key(u)   # ★不能直接用 u["id"]: 三种小将(前排/后排/精英)共用 "__minion__",
							 #   按 id 查表会让普通小将也命中精英的动作帧。见 battle._anim_key。
	var table: Dictionary
	match kind:
		"attack": table = battle.ACTION_ATTACK
		"hurt":   table = battle.ACTION_HURT
		"death":  table = battle.ACTION_DEATH
		_:        return
	if not table.has(id):
		return
	# hurt 不打断正在播的 attack (避免普攻动作被打断闪烁); attack 不打断 hurt 中
	if kind != "death" and u.get("anim_action", "") in ["attack", "hurt"]:
		if kind == "hurt" and u.get("anim_action", "") == "hurt":
			pass   # 刷新 hurt
		elif kind != u.get("anim_action", ""):
			return
	var entry: Array = table[id]
	var asd = battle._resolve_action(str(entry[0]), float(entry[1]))
	if asd.is_empty():
		return
	if kind == "attack" and id == "ninja":
		var _afr: float = float(asd.get("frames", 1))
		var _aiv: float = maxf(0.15, float(u.get("atk_interval", 0.85)))
		asd["fps"] = clampf(_afr / (_aiv * 0.45), 10.0, 30.0)   # 斩击动作时长随攻速(LoL式·越快越短): 占攻击周期~45%
	battle._set_anim_sheet(u, asd, kind, false)
	if battle.ANIM_NORM.has(id):
		battle._elite_sys._elite_fix_norm(u, asd)   # 普攻(battle.ACTION_ATTACK)也是 96×96 的 PixelLab 图, 同样要修归一

# ----------------------------------------------------------------------------
#  §GROUNDING — 立绘底部软渐隐 ShaderMaterial (根治"纸板硬切地面").
#  原理: 立绘 = 朝镜头的竖面 billboard, 底边是张不透明硬线 → 撞俯视地面像被刀切.
#    本 shader 让图底部 GROUND_FADE_FRAC 这段 UV 高度内 alpha 线性衰减到 GROUND_FADE_FLOOR,
#    脚部柔和淡入地面; 配合 GROUND_LIFT 略沉 + 接触核影盖交界 → 自然"站在地上".
#  render_mode depth_prepass_alpha: alpha 测深度预通道 → 立绘彼此/与地面正确排序 (替代
#    原 ALPHA_CUT_DISCARD 的硬切, 既不闪烁又保软边). vertex() 重建 upright billboard (朝相机不翻 Y).
#  material_override 接管 Sprite3D 渲染 → 闪白(flash)经 Sprite3D.modulate→COLOR 仍生效.
# ----------------------------------------------------------------------------
## 龟蛋碎裂死亡。★★2026-08-02 重做(用户:「龟蛋爆炸的时候用的什么特效, 到底有没有用对」——
## 答: 没用对)。旧版第二帧用 `assets/sprites/map/egg_shards.png`, 那张画的是
## 【白壳磕开 + 黄色蛋黄流出来】= 打鸡蛋下锅的图; 而龟蛋本体是【米白带绿斑 + 棕色底座】。
## 同一颗蛋碎前碎后换了个颜色, 一眼穿帮; "流蛋黄"的语义也不是"蛋被打爆"。
##
## 现在【不用任何碎片贴图】: 碎壳直接从【蛋本体的贴图上切下来】——
##   Sprite3D 的 region_rect 在 egg.png 第 0 帧上切 3×3 小块, 每块朝外抛飞 + 重力下落 + 自旋 + 淡出。
##   ★颜色永远对得上, 因为那【就是】那颗蛋的像素。而且静态碎片图本来就是偷懒版:
##     一张图放大淡出 ≠ 蛋炸开。破蛋是决胜时刻, 该有真的碎壳飞散。
const EGG_SHARD_GRID := 3
const EGG_SHARD_SEC := 0.85
func _play_egg_shatter(u: Dictionary) -> void:
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr):
		return
	_flash(u, Color(1, 1, 1))
	battle._shake(battle.JUICE_SHAKE_BIG)
	var crack: Texture2D = load("res://assets/sprites/map/egg_crack.png") if ResourceLoader.exists("res://assets/sprites/map/egg_crack.png") else null
	if crack != null:                       # 裂纹帧是对的(米白+绿斑+裂纹), 保留
		# ★★这里是**复用单位自己的精灵**(把它换成裂纹图), 不是新建 ——
		#   所以必须**先把 frame 归零再改帧网格**: Godot 在 hframes/vframes 的 setter 里
		#   会立即用新乘积校验当前 frame, 而这里新乘积是 **1**, 旧 frame 可能是 17 ⇒ 直接越界。
		#   冒烟随机报的 `p_frame = 17 is out of bounds (vframes*hframes = 7)` 同族。
		spr.frame = 0
		spr.texture = crack; spr.hframes = 1; spr.vframes = 1; spr.frame = 0
		spr.material_override = null
		spr.pixel_size = battle.TARGET_BODY_H / float(maxi(1, crack.get_height()))
		spr.offset = Vector2(0.0, crack.get_height() * 0.5)
	var pos2d: Vector2 = u["pos"]
	var uu: Dictionary = u
	var tw = battle._reg_tween()
	tw.tween_interval(0.14)                 # 裂一下 → 才炸
	tw.tween_callback(func() -> void:
		if is_instance_valid(spr):
			(spr as Node3D).visible = false  # 本体没了, 交给碎壳
		_egg_shards_burst(pos2d)
		battle._shake(battle.JUICE_SHAKE_BIG)
		# ★尘环两道(内快外慢)。★不用 _particle_burst —— 那是【橙色火星】的通用粒子,
		#   蛋壳崩裂不该有火(实拍确认: 中间炸出一团橙色, 和米白碎壳完全不搭)。
		battle._skill_ring(pos2d, Color(1.00, 0.96, 0.82, 0.90), 120.0)
		_dust_ring_later(pos2d))   # ★本文件自己的函数, 别加 battle. 前缀


## 破蛋的第二道尘环: 晚半拍、更大更淡 = 冲击波扩散出去。
func _dust_ring_later(pos2d: Vector2) -> void:
	var tw = battle._reg_tween()
	tw.tween_interval(0.10)
	tw.tween_callback(func() -> void: battle._skill_ring(pos2d, Color(0.94, 0.90, 0.76, 0.45), 210.0))


## 从 egg.png 第 0 帧切 3×3 小块当碎壳, 抛物线飞散。
func _egg_shards_burst(pos2d: Vector2) -> void:
	if battle._world == null:
		return
	var tex: Texture2D = load("res://assets/sprites/pets/egg.png") if ResourceLoader.exists("res://assets/sprites/pets/egg.png") else null
	if tex == null:
		return
	var fw: float = float(tex.get_width()) / 3.0     # egg.png = 3 帧横排
	var fh: float = float(tex.get_height())
	var cw: float = fw / float(EGG_SHARD_GRID)
	var ch: float = fh / float(EGG_SHARD_GRID)
	var idx: int = 0
	for gy in range(EGG_SHARD_GRID):
		for gx in range(EGG_SHARD_GRID):
			var sh := Sprite3D.new()
			sh.texture = tex
			sh.region_enabled = true
			sh.region_rect = Rect2(cw * float(gx), ch * float(gy), cw, ch)
			sh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sh.shaded = false
			sh.transparent = true
			sh.no_depth_test = true
			sh.render_priority = 8
			sh.pixel_size = battle.TARGET_BODY_H / fh
			battle._world.add_child(sh)
			# 方向: 按它在蛋上的【原始位置】往外飞(左上角的碎片就往左上飞) —— 比随机方向像"炸开"
			var ox: float = float(gx) - 1.0
			var oy: float = float(gy) - 1.0
			# ★三个维度都要给, 不能只给横向 —— 只给 vx 的话九片全贴着一条水平线飞出去,
			#   看着像"被推开"不像"炸开"(实拍确认)。
			#   · vx  横向: 左边的碎片往左、右边往右
			#   · vz  纵深: 上排往画面里、下排往画面外 —— 散开成一片而不是一条线
			#   · vy0 起跳: 上排飞得最高, 底座那排几乎贴地弹开
			var vx: float = ox * 195.0 + (22.0 if (idx % 2) == 0 else -22.0)
			var vz: float = oy * 74.0 + 16.0
			var vy0: float = 4.2 - 1.5 * oy
			if absf(ox) < 0.01 and absf(oy) < 0.01:
				vy0 = 5.6                              # 正中那片直接冲天
			var spin: float = (1.0 if (idx % 2) == 0 else -1.0) * (7.0 + float(idx))
			var s2 := sh
			var t2 = battle._reg_tween()
			t2.tween_method(func(q: float) -> void:
				if not is_instance_valid(s2):
					return
				var t: float = q * EGG_SHARD_SEC
				var h: float = maxf(0.02, vy0 * t - 6.4 * t * t)          # 抛物线(重力 12.8)
				var p: Vector2 = pos2d + Vector2(vx * t, vz * t)
				(s2 as Node3D).position = battle._world_pos(p, h + 0.25)
				(s2 as Node3D).rotation.z = spin * t
				(s2 as Sprite3D).modulate.a = clampf(1.0 - pow(q, 2.2), 0.0, 1.0)
			, 0.0, 1.0, EGG_SHARD_SEC)
			t2.tween_callback(s2.queue_free)
			idx += 1


func _float_num_font() -> Font:
	if battle._num_font == null:
		battle._num_font = load("res://assets/fonts/m6x11.ttf")
	return battle._num_font

# #1 字号按伤害量级缩放 (暴击×1.2) — 1:1 回合制 VisualConstants.size_by_amount
# #1 字号按伤害量级缩放 (暴击×1.2) — 1:1 回合制 VisualConstants.size_by_amount
func _float_size(amount: int, is_crit: bool) -> int:
	var s: float
	if amount < 20:
		s = 20.0
	elif amount < 60:
		s = 20.0 + (float(amount - 20) / 40.0) * 4.0
	elif amount < 400:
		s = 24.0 + (float(amount - 60) / 340.0) * 11.0
	else:
		s = 35.0
	if is_crit:
		s *= 1.2
	return roundi(s)

# 同时跳出的飘字按规矩错开行: 伤害红0/蓝1/白2 紧凑×22(缺色不留空, 220ms窗口); 非伤害到达序堆叠(100ms)
func _float_row_offset(key: String, kind: String, dmg_type: String, fsize: float = 18.0) -> float:
	if kind == "damage":
		var rank: int = 0 if dmg_type == "physical" else (1 if dmg_type == "magic" else 2)   # 下→上: 物理0/魔法1/真实2 (白上蓝中红下)
		var w: Dictionary = battle._float_dmg_window.get(key, {"sizes": {}, "t": -9.0})
		if battle._t - float(w["t"]) > 0.22:
			w = {"sizes": {}, "t": -9.0}
		var sizes: Dictionary = w["sizes"]
		sizes[rank] = fsize   # 本数字字号(供上方行按下方各行高度累加错开)
		w["sizes"] = sizes; w["t"] = battle._t
		battle._float_dmg_window[key] = w
		var off: float = 0.0   # 贴近: 累加下方已present各行高度×系数 → 随伤害大小缩放, 贴近不重合
		for r in sizes:
			if int(r) < rank: off += float(sizes[r]) * 0.62
		return off
	var rec: Dictionary = battle._float_nd_window.get(key, {"t": -9.0, "n": 0})
	if battle._t - float(rec["t"]) > 0.10:
		rec["n"] = 0
	rec["t"] = battle._t
	var extra: int = int(rec["n"]); rec["n"] = extra + 1
	battle._float_nd_window[key] = rec
	return float(extra) * 22.0

# 飘字 (1:1 回合制 _spawn_float_text): kind=damage → 爆大pop(1.6~2.5)+抛物弹射(重力200,朝屏边跳); 否则(heal/shield/label) → pop1.2+缓升50px(sine)1.5s淡出
# 飘字 (1:1 回合制 _spawn_float_text): kind=damage → 爆大pop(1.6~2.5)+抛物弹射(重力200,朝屏边跳); 否则(heal/shield/label) → pop1.2+缓升50px(sine)1.5s淡出
func _float_text(pos2d: Vector2, text: String, col: Color, is_crit: bool = false, kind: String = "label", dmg_type: String = "physical", jump_dir: float = 0.0) -> void:
	if battle._cam == null:
		return
	var head = battle._world_pos(pos2d, 2.2)
	if battle._cam.is_position_behind(head):
		return
	var screen: Vector2 = battle._cam.unproject_position(head)
	var amount = absi(text.to_int()) if text.is_valid_int() else 0
	var fsize = _float_size(amount, is_crit) if amount > 0 else (22 if is_crit else 18)
	var is_dmg_crit = is_crit and amount > 0 and kind == "damage"
	# 奥恩式合并: 同目标+同类型+同帧的伤害 → 累加到已在跳的那个数字(跳两者之和), 不新建
	var _mk = ""
	if kind == "damage" and amount > 0:
		_mk = "%d_%d_%s" % [roundi(pos2d.x), roundi(pos2d.y), dmg_type]
		var _m: Dictionary = battle._float_merge.get(_mk, {})
		if not _m.is_empty() and battle._t - float(_m.get("t", -9.0)) < 0.04 and is_instance_valid(_m.get("lbl", null)):
			var _na: int = int(_m["amount"]) + amount
			_m["amount"] = _na; _m["t"] = battle._t
			var _l: Label = _m["lbl"]
			_l.text = str(_na)
			_l.add_theme_font_size_override("font_size", _float_size(_na, bool(_m.get("crit", false))))
			battle._float_merge[_mk] = _m
			return
	var fly: Control
	var num_lbl: Label = null
	if is_dmg_crit:
		# 暴击伤害: 数字前嵌 crit 图标 (1:1 回合制 .floating-num crit 内嵌 20×20)
		var box = HBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		var icon = TextureRect.new()
		icon.texture = load("res://assets/sprites/stats/crit-dmg-icon.png")
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # 忽略贴图原尺寸→缩到20 (缺它则700px原图撑爆)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		num_lbl = battle._make_num_label(text, col, fsize)
		box.add_child(num_lbl)
		fly = box
	else:
		num_lbl = battle._make_num_label(text, col, fsize)
		fly = num_lbl
	battle._ui_layer.add_child(fly)
	## ★入组 = 换路兜底清场认得它(用户 2026-08-13 第 9 条「数字残留到下一个战场」)。
	##   飘字的 queue_free 挂在 create_tween 的回调上, 换路演出期一顿就一直挂着。
	fly.add_to_group(BattleHud.UI_TRANSIENT_GROUP)
	if _mk != "" and num_lbl != null:   # 注册本帧该目标该类型的数字, 供同帧后续伤害合并
		battle._float_merge[_mk] = {"lbl": num_lbl, "amount": amount, "t": battle._t, "crit": is_dmg_crit}
	# 居中起跳 + pivot 居中 (pop 绕中心, 1:1 PoC origin 0.5)
	var tsz = _float_num_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize)
	var unit_sz = Vector2(20.0 + 1.0 + tsz.x, maxf(20.0, tsz.y)) if is_dmg_crit else tsz
	fly.pivot_offset = unit_sz / 2.0
	var base_pos = screen - unit_sz / 2.0
	base_pos.y -= _float_row_offset("%d_%d" % [roundi(pos2d.x), roundi(pos2d.y)], kind, dmg_type, float(fsize))   # 按类型排行错开(白上红下, 贴近随大小缩放)
	if kind == "damage":
		# 伤害: 爆大pop(1.6~2.5按量级)→hold→抛物弹射(jump_x朝屏边, 重力200先上后下)→淡出 (1:1 PoC runFloatAnim)
		fly.position = base_pos
		fly.scale = Vector2(0.01, 0.01)
		var hold_scale = 1.0 if is_crit else 0.7
		var pop_size = 1.6 if amount < 20 else (1.8 if amount < 60 else (2.2 if amount < 150 else 2.5))
		var dir = (jump_dir if absf(jump_dir) > 0.5 else (-1.0 if base_pos.x < 640.0 else 1.0))   # 用户规则: 数字朝远离来源方向跳(来源左→往右/来源右→往左); 无来源朝屏边
		var jump_x = dir * (12.0 + randf() * 14.0)
		var jump_y = (-(10.0 + randf() * 8.0)) if is_crit else (-(22.0 + randf() * 10.0))
		var hold_end = 0.4 if is_crit else 0.15
		var total_dur = hold_end + 0.65
		var fade_start = hold_end + 0.3
		var tw = battle.create_tween()
		tw.tween_method(battle._dmg_float_step.bind(fly, base_pos, jump_x, jump_y, hold_end, hold_scale, pop_size, total_dur, fade_start), 0.0, total_dur, total_dur)
		tw.tween_callback(fly.queue_free)
	else:
		# 治疗/护盾/名: pop1.2 → 缓升50px(sine) → 1.5s淡出 (1:1 PoC label路径)
		var lsy = base_pos.y - 15.0
		fly.position = Vector2(base_pos.x, lsy)
		fly.scale = Vector2.ONE
		var pop = battle.create_tween()
		pop.tween_property(fly, "scale", Vector2(1.2, 1.2), 0.1)
		var tw = battle.create_tween()
		tw.set_parallel(true)
		tw.tween_property(fly, "position:y", lsy - 50.0, 1.5).set_delay(0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(fly, "modulate:a", 0.0, 1.5).set_delay(0.1)
		tw.chain().tween_callback(fly.queue_free)

# 伤害飘字每帧: pop→hold→抛物弹射 (1:1 PoC ticker). el=已过秒数; node_fl=飞行单元(label或含图标HBox)
func _play_heal_glow(pos2d: Vector2) -> void:
	battle._skill_ring(pos2d, Color(0.36, 0.92, 0.5, 0.5), 48.0)   # 绿脉冲环
	for i in range(6):
		var g = Sprite3D.new()
		g.texture = VfxTex._make_glow_texture()
		g.modulate = Color(0.36, 0.92, 0.5, 0.85)   # #5cea80 治疗绿
		g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		g.shaded = false
		g.transparent = true
		g.pixel_size = 0.009
		g.position = battle._world_pos(pos2d, 0.2) + Vector3(randf_range(-0.45, 0.45), 0.0, randf_range(-0.2, 0.2))
		battle._world.add_child(g)
		var tw = battle._reg_tween()
		tw.set_parallel(true)
		tw.tween_property(g, "position:y", g.position.y + 1.6, 0.7).set_ease(Tween.EASE_OUT)
		tw.tween_property(g, "modulate:a", 0.0, 0.7).set_delay(0.1)
		tw.chain().tween_callback(g.queue_free)

# ── 通用: 2D序列帧特效 贴 billboard 在2.5D场景逐帧播 (AI产出的序列帧丢进来即可, 零3D建模) ──
# skill_key: 优先按龟 id 查 battle.SKILL_VFX_MAP; 也可直接传贴图名 (装备/特殊技直指定). 找不到 → no-op (保留程序圈).
func _play_skill_vfx(skill_key: String, pos2d: Vector2, height: float = 1.2) -> void:
	if battle._cam == null:
		return
	var name: String = battle.SKILL_VFX_MAP.get(skill_key, skill_key)
	var tex = battle._skill_vfx_tex(name)
	if tex == null:
		return                            # 无匹配贴图: 静默回退 (调用点已有 battle._skill_ring/飘字)
	var spr = Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	# 单帧图按 battle.SKILL_VFX_WORLD_H 归一: pixel_size = 目标世界高 / 图高 px
	var th: int = maxi(1, tex.get_height())
	spr.pixel_size = battle.SKILL_VFX_WORLD_H / float(th)
	spr.position = battle._world_pos(pos2d, height)
	spr.scale = Vector3.ONE * battle.SKILL_VFX_START_SCALE
	battle._world.add_child(spr)
	# 一次性: 放大入场 → 保持 → 淡出 → 自销 (播一遍消失)
	var tw = battle._reg_tween()
	tw.tween_property(spr, "scale", Vector3.ONE, battle.SKILL_VFX_GROW_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(battle.SKILL_VFX_HOLD_SEC)
	tw.tween_property(spr, "modulate:a", 0.0, battle.SKILL_VFX_FADE_SEC)
	tw.tween_callback(spr.queue_free)

## 龟壳「复制」的抄袭图标: 在龟壳头顶浮出【它这一发要放的技能的图标】。
##
## 用户 2026-08-27 描述的演出:
##   龟壳聚起复制光 → 头顶浮出【技能1 图标】→ 释放技能1
##   → 图标1 收 → 头顶浮出【技能2 图标】→ 释放技能2
##
## ★为什么非做不可: 复制之前是【什么提示都没有】的 —— 屏幕上突然多出两段别人的技能,
##   玩家既不知道抄到了什么, 也看不出第二发是哪来的(它还隔了 0.6 秒凭空出现)。
##
## ★跟随用 `battle._follow_vfx` —— 那是全项目"贴着单位走"的既有机制(`_aura_vfx` 也用它),
##   不自己每帧算位置(memory [[fb-hand-rolled-copies-drift]])。
##
## ★不做"一出生就线性淡出"(memory [[fb-vfx-defect-families]] 的淡出病, 一天踩过四次):
##   短命特效那样做, 实拍读到的永远是半透明的脏色。这里是 **弹入 → 满亮保持 → 才淡出**。
##
## `stype` 查不到图标时(小将技就没有)**静默不画** —— 但复制光圈仍然有, 调用点不受影响。
func copy_steal_icon(u: Dictionary, stype: String, hold: float = 0.55) -> void:
	if battle._world == null or u == null or not u.get("alive", false):
		return
	var path: String = SkillIcons.path_of(stype, u)
	if path == "":
		return                                    # 没图标(小将技): 静默跳过, 不画空框
	var tex: Texture2D = load(path)
	if tex == null:
		return
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	## ★NEAREST: 技能图标是像素画, LINEAR 会糊成一团(memory 里"贴图糊=没设 NEAREST")
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	## 目标世界高 = COPY_ICON_H 码。按图高归一 —— 这些图 186~923px 不等, 写死 pixel_size 会大小乱跳。
	s.pixel_size = (ShellSystem.COPY_ICON_H * battle.WS) / float(maxi(1, tex.get_height()))
	s.position = battle._world_pos(u["pos"] as Vector2, ShellSystem.COPY_ICON_HEIGHT)
	s.modulate = Color(1.0, 1.0, 1.0, 0.0)
	battle._world.add_child(s)
	battle._follow_vfx.append({"spr": s, "unit": u, "h": ShellSystem.COPY_ICON_HEIGHT})
	## 弹入(0.16) → **满亮保持** → 淡出(0.22)。保持段占大头, 拍出来才是它本来的颜色。
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "modulate:a", 1.0, 0.16)
	tw.tween_property(s, "scale", Vector3.ONE, 0.16).from(Vector3.ONE * 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(maxf(0.05, hold))
	tw.chain().tween_property(s, "modulate:a", 0.0, 0.22)
	tw.chain().tween_callback(s.queue_free)


# 通用命中爆发VFX: 单帧burst贴图在pos放大入场→保持→淡出→自销 (A组爆发/溅射类共用)
# 一次性帧动画VFX(横排sheet·帧宽=图高·逐帧播一遍→自销) — 1:1 回合制 BattleScene._play_vfx(横排帧sheet)
func _play_anim_vfx(path: String, pos2d: Vector2, size_px: float, fps: float = 14.0, height: float = 1.1, flip_h: bool = false) -> void:
	var tex: Texture2D = load(path)
	if tex == null:
		return
	var fh: int = maxi(1, tex.get_height())
	var n: int = maxi(1, int(tex.get_width() / fh))
	var spr = Sprite3D.new()
	spr.texture = tex
	spr.hframes = n
	spr.frame = 0
	spr.flip_h = flip_h
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = (size_px * battle.WS) / float(fh)
	spr.position = battle._world_pos(pos2d, height)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	tw.tween_method(battle._anim_vfx_frame.bind(spr, n), 0.0, float(n), float(n) / maxf(1.0, fps))
	tw.tween_callback(spr.queue_free)

# 每帧衰减各单位 juice 计时 (hit-stop 冻结期不调 → 冲击姿势保持)
func _juice_decay(delta: float) -> void:
	var ts_on: bool = not battle._timestop._ts_active.is_empty()
	for u in battle._units:
		if not u["alive"]:
			continue
		if ts_on and not battle._arr_has_unit(battle._timestop._ts_active, u):
			continue   # 时停: 非active的juice计时不衰 → 冲击/挥击姿势定格
		if u.get("flash_t", 0.0) > 0.0:  u["flash_t"]  = maxf(0.0, u["flash_t"]  - delta)
		if u.get("hitsq_t", 0.0) > 0.0:  u["hitsq_t"]  = maxf(0.0, u["hitsq_t"]  - delta)
		if u.get("land_t", 0.0) > 0.0:   u["land_t"]   = maxf(0.0, u["land_t"]   - delta)
		if u.get("swing_t", 0.0) > 0.0:  u["swing_t"]  = maxf(0.0, u["swing_t"]  - delta)
		if u.get("windup_t", 0.0) > 0.0: u["windup_t"] = maxf(0.0, u["windup_t"] - delta)
		# 近战踏步: _lunge_t 递减 → _atk_voff = 方向×sin(0→π)幅度(前冲再回), render叠加
		if u.get("_lunge_t", 0.0) > 0.0:
			u["_lunge_t"] = maxf(0.0, u["_lunge_t"] - delta)
			var _ld: float = maxf(0.001, float(u.get("_lunge_dur", battle.ATK_LUNGE_MIN)))
			var _lp: float = 1.0 - float(u["_lunge_t"]) / _ld   # 0→1
			u["_atk_voff"] = u.get("_lunge_dir", Vector3.ZERO) * (sin(_lp * PI) * float(u.get("_lunge_amp", battle.ATK_LUNGE_AMP)))
			if u["_lunge_t"] <= 0.0: u["_lunge_amp"] = battle.ATK_LUNGE_AMP   # 踏步结束→幅度复位(强化发的加大踏步用完即还原)
		elif u.get("_atk_voff", Vector3.ZERO) != Vector3.ZERO:
			u["_atk_voff"] = Vector3.ZERO

# 合成形变系数 (x,y): 优先级 起跳拉长 > 落地压扁 > 受击压扁 > 出招预备(缩)/挥出(伸).
# 各相位用 ease 衰减到 (1,1), 互不累积 — 取主导相位 + 出招缩放叠乘.
# 合成形变系数 (x,y): 优先级 起跳拉长 > 落地压扁 > 受击压扁 > 出招预备(缩)/挥出(伸).
# 各相位用 ease 衰减到 (1,1), 互不累积 — 取主导相位 + 出招缩放叠乘.
func _juice_scale_for(u: Dictionary) -> Vector2:
	var sx = 1.0
	var sy = 1.0
	# 击飞中: 起跳上行拉长, 下落渐回 (随竖速 vy 符号/大小)
	if u.get("airborne", false):
		var vy: float = u.get("vy", 0.0)
		var k: float = clampf(absf(vy) / battle.KNOCK_VY, 0.0, 1.0)
		if vy > 0.0:    # 上升: 拉长
			sx = lerpf(1.0, battle.JUICE_STRETCH_UP.x, k)
			sy = lerpf(1.0, battle.JUICE_STRETCH_UP.y, k)
		else:           # 下落: 轻微拉长(惯性), 落地瞬间由 land_t 接管压扁
			sx = lerpf(1.0, lerpf(1.0, battle.JUICE_STRETCH_UP.x, 0.5), k)
			sy = lerpf(1.0, lerpf(1.0, battle.JUICE_STRETCH_UP.y, 0.5), k)
		return Vector2(sx, sy)
	# 落地压扁 (ease-out 回弹)
	var lt: float = u.get("land_t", 0.0)
	if lt > 0.0:
		var f: float = lt / battle.JUICE_LAND_SEC          # 1→0
		var e: float = f * f                          # ease (回弹快)
		sx = lerpf(1.0, battle.JUICE_SQUASH_LAND.x, e)
		sy = lerpf(1.0, battle.JUICE_SQUASH_LAND.y, e)
		return Vector2(sx, sy)
	# 受击压扁
	var ht: float = u.get("hitsq_t", 0.0)
	if ht > 0.0:
		var f2: float = ht / battle.JUICE_HIT_SQUASH_SEC
		var e2: float = f2 * f2
		sx = lerpf(1.0, battle.JUICE_HIT_SQUASH.x, e2)
		sy = lerpf(1.0, battle.JUICE_HIT_SQUASH.y, e2)
	# 出招: 预备(整体缩) → 挥出(整体伸), 顺序非叠加 (windup 在前, 结束后 swing 接管)
	var wt: float = u.get("windup_t", 0.0)
	var st: float = u.get("swing_t", 0.0)
	if wt > 0.0:
		var fw: float = wt / battle.JUICE_WINDUP_SEC        # 1→0
		var m: float = lerpf(1.0, battle.JUICE_WINDUP_SCALE, fw)
		sx *= m; sy *= m
	elif st > 0.0:
		var fs: float = clampf(st / battle.JUICE_SWING_SEC, 0.0, 1.0)   # swing 段 (windup 已耗尽)
		var m2: float = lerpf(1.0, battle.JUICE_SWING_SCALE, fs)
		sx *= m2; sy *= m2
	return Vector2(sx, sy)

# idle 呼吸 bob: 仅待机时(不击飞/不快移/无 juice 相位) 立绘极轻上下浮
# idle 呼吸 bob: 仅待机时(不击飞/不快移/无 juice 相位) 立绘极轻上下浮
func _juice_bob_for(u: Dictionary) -> float:
	if u.get("airborne", false):
		return 0.0
	# 移动中不 bob (vel 速度阈值: 像素/s)
	var v: Vector2 = u.get("vel", Vector2.ZERO)
	if v.length() > 6.0:
		return 0.0
	# 出招/受击/落地相位中不 bob (避免叠加抖)
	if u.get("land_t", 0.0) > 0.0 or u.get("hitsq_t", 0.0) > 0.0 or u.get("swing_t", 0.0) > 0.0 or u.get("windup_t", 0.0) > 0.0:
		return 0.0
	var ph: float = u.get("bob_phase", 0.0) + battle._t * battle.JUICE_BOB_SPEED
	return sin(ph) * battle.JUICE_BOB_AMP

# 战场缩放: 沿视轴向 CAM_TARGET 推拉镜头(方向不变→无需重look_at); shake 围绕缩放后基准
func _flash(u: Dictionary, col: Color = battle.JUICE_FLASH_COLOR) -> void:
	if u == null or not u.get("alive", false):
		return
	u["flash_t"] = battle.JUICE_FLASH_SEC
	u["flash_col"] = col            # 受击闪光色 (默认过曝白; 可传绿等特殊色)
	u["hitsq_t"] = battle.JUICE_HIT_SQUASH_SEC
	# ★E1 黑屏排查(用户2026-07-11「按理压根不该用受伤动画」): 实时高频命中下, 受击帧动画会反复打断
	#   idle/攻击动画 → 动画状态抖动。改为只保留闪白+压扁(juice), 不再切 hurt 动画帧。
	# _play_action(u, "hurt")   # 已停用: 受击 flinch 动画在实时战斗里反复冲突

# 命中重量分级: 单段伤害(或暴击/大招标志)决定 闪白/顿帧/震屏/粒子 强度.
# heavy=技能/暴击命中级; big=大招/击飞级. light(普攻小段)只闪白不顿帧不抖.
# 命中重量分级: 单段伤害(或暴击/大招标志)决定 闪白/顿帧/震屏/粒子 强度.
# heavy=技能/暴击命中级; big=大招/击飞级. light(普攻小段)只闪白不顿帧不抖.
func _impact(tgt: Dictionary, dmg: int, level: String = "auto", at_pos = null) -> void:
	if tgt == null:
		return
	var lvl = level
	if lvl == "auto":
		lvl = "heavy" if float(dmg) >= battle.JUICE_HITSTOP_DMG_GATE else "light"
	match lvl:
		"big":
			battle._add_hitstop(battle.JUICE_HITSTOP_HEAVY)
			battle._shake(battle.JUICE_SHAKE_BIG)
		"heavy":
			battle._add_hitstop(battle.JUICE_HITSTOP_HEAVY)
			battle._shake(battle.JUICE_SHAKE_HEAVY)
		_:   # light
			if battle.JUICE_HITSTOP_LIGHT > 0.0: battle._add_hitstop(battle.JUICE_HITSTOP_LIGHT)
			if battle.JUICE_SHAKE_LIGHT > 0.0:   battle._shake(battle.JUICE_SHAKE_LIGHT)
	# 命中特效 (Botworld式: 普攻不打断敌人, 反馈全靠特效) — 每次命中迸 Hit Spark + Impact Ring
	_hit_spark(tgt, at_pos)
	# 冲击粒子: 只在重击/大招迸火花
	if (lvl == "heavy" or lvl == "big") and float(dmg) >= battle.JUICE_PARTICLE_MIN_DMG:
		var p2d: Vector2 = at_pos if at_pos != null else tgt.get("pos", Vector2.ZERO)
		_impact_particles(p2d, tgt.get("height", 0.0))

# Hit Spark(亮星) + Impact Ring(快环): 朝镜头 billboard, ~0.14s pop→淡; 同目标50ms节流防多段刷爆
## ★★「扔」一件东西给某个单位 —— 2026-09-01 补。
##
## ★由来: 需求原话是「技能或装备，会**扔**给目标一把古灵精怪枪」, 而 FPGA 板发枪的
##   整条路径(`GremlinGun.hand_out`)**一个 vfx 调用都没有** —— 属性静悄悄加上去,
##   玩家完全看不到发生过什么。逐句核对原话时抓到(第 2 句)。
##
## ★演出与结算**分开**(CLAUDE.md §3.5): `give()` 已经在调用方同步做完了,
##   这里纯粹是让玩家看见。所以就算这条 tween 在无头 CI 下推不动, 数值也一分不差。
##
## ★避开特效八类常见毛病(memory [[fb-vfx-defect-families]]):
##   · **不是一出生就淡出** —— 飞行全程满亮, 落地那一下才淡(hold-then-fade)
##   · 高度不写死 —— 起手/落点都走 `battle._world_pos`, 拱高按距离算
##   · 用**真素材**不是程序生成的白球
##   · NEAREST 采样(像素风; LINEAR 会糊)
func _throw_item(src: Dictionary, tgt: Dictionary, img: String, label: String, col: Color) -> void:
	if not (src is Dictionary) or not (tgt is Dictionary):
		return
	var from2d: Vector2 = src.get("pos", Vector2.ZERO)
	var to2d: Vector2 = tgt.get("pos", Vector2.ZERO)
	var p := Sprite3D.new()
	var path := "res://assets/sprites/vfx/" + img
	if not ResourceLoader.exists(path):
		return                                  # 缺图就不画, 不拿别的图顶替(素材不复用铁律)
	p.texture = load(path)
	p.pixel_size = (30.0 * battle.WS) / float(maxi(1, p.texture.get_height()))
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false
	p.transparent = true
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var h0 := 1.1                               # 出手在胸口高度(与 lava-rock 那条一致)
	p.position = battle._world_pos(from2d, h0)
	battle._world.add_child(p)
	var dist: float = from2d.distance_to(to2d)
	var dur: float = clampf(dist / 700.0, 0.22, 0.62)
	var arc: float = clampf(dist * 0.004, 0.5, 2.2)   # 远则拱高
	var tw: Tween = battle._reg_tween()
	tw.tween_method(func(s: float) -> void:
		if not is_instance_valid(p):
			return
		## 真抛物线: 4·h·s(1−s) 是拱高为 h 的标准形(与 090 浪潮同一条公式, 不另立)
		var at2d: Vector2 = from2d.lerp(to2d, s)
		p.position = battle._world_pos(at2d, h0 + arc * 4.0 * s * (1.0 - s))
		p.rotation.z = s * TAU * 1.5             # 翻滚 —— 扔出去的东西会转
	, 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		if is_instance_valid(p):
			_hit_spark(tgt)
		_float_text(to2d + Vector2(0, -66), label, col))
	## ★落地才淡 —— 不是从出手就开始淡(那正是"淡出病": 实拍读成一团灰)
	tw.tween_property(p, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


func _hit_spark(tgt, at_pos = null) -> void:
	if tgt == null or battle._t < float(tgt.get("_spark_t", 0.0)):
		return
	tgt["_spark_t"] = battle._t + 0.05
	var pos2d: Vector2 = at_pos if at_pos != null else tgt.get("pos", Vector2.ZERO)
	var h: float = float(tgt.get("height", 0.0)) + 0.6
	## ★★2026-08-13 命中反馈重做: 原来是【完整圆环 + 发光球】—— 正好踩中两条禁区
	##   (程序生成的圆 / 白球), 而且**两者都一出生就线性淡出**(淡出病)。
	##   它挂在 `_impact()` 上, **每一次命中都走** ⇒ 路线图里挂着的两条"未查线索"
	##   其实是同一个东西: 「假人身上那个大白圆环」= 这个 ring(077 自带 50% 暴击、
	##   射速又快, 几乎每发都刷); 「小龟普攻里那颗灰白半透明球」= 下面那颗 spark。
	##   按装备去查当然查不到主人 —— 它谁都不属于。
	##   ⇒ 换形状语言: 圆环 → **四尖冲击星**(复用现成的 `_make_star_texture`, 眩晕圈同款,
	##     不新造纹理); 发光球 → 同族的小星芒。形状一眼和场上所有圆形区分得开。
	if battle._hitring_tex == null:
		battle._hitring_tex = VfxTex._make_star_texture()
	var r = Sprite3D.new()
	r.texture = battle._hitring_tex
	r.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	r.shaded = false; r.transparent = true
	r.modulate = Color(1.0, 0.96, 0.8, 0.95)
	r.position = battle._world_pos(pos2d, h)
	r.pixel_size = 0.006
	battle._world.add_child(r)
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(r, "pixel_size", 0.020, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	## ★保亮到 65% 再淡: 一出生就线性淡出会被实拍读成"一团灰"(memory 里那条"淡出病",
	##   一天踩过四次)。0.09 秒满亮 + 0.05 秒收。
	tw.tween_property(r, "modulate:a", 0.0, 0.05).set_delay(0.09)
	tw.chain().tween_callback(r.queue_free)
	## ★用【专用】纹理字段, 不跟 `_spark_tex` 共用 —— 主场景另一处会把它懒创建成发光球,
	##   共用的话"谁先跑谁定", 命中星芒会随机变回白球(这种"看起来时好时坏"最难查)。
	if battle._hitspark_tex == null:
		battle._hitspark_tex = VfxTex._make_star_texture()
	var sp = Sprite3D.new()
	sp.texture = battle._hitspark_tex
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false; sp.transparent = true
	sp.modulate = Color(1.0, 1.0, 0.85, 0.9)
	sp.position = battle._world_pos(pos2d, h)
	sp.pixel_size = 0.012
	sp.scale = Vector3.ONE * 0.5
	battle._world.add_child(sp)
	var tw2 = battle._reg_tween(); tw2.set_parallel(true)
	tw2.tween_property(sp, "scale", Vector3.ONE * 1.1, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(sp, "modulate:a", 0.0, 0.05).set_delay(0.07)   # 同上: 先满亮再收
	tw2.chain().tween_callback(sp.queue_free)



# 一瞬锁定框: 从大缩到目标身上再淡出(瞄准镜"必中"命中反馈)
# 冲击火花粒子: 命中点一撮 3D 火花, GPUParticles3D 一次性 emit → 计时自销 (占位红橙火花)
func _impact_particles(pos2d: Vector2, height: float) -> void:
	var ps = GPUParticles3D.new()
	ps.amount = 10
	ps.lifetime = 0.35
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.local_coords = false
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 80.0
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -9.0, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.2
	mat.color = Color(1.0, 0.8, 0.35, 1.0)
	ps.process_material = mat
	var dm = StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(1.0, 0.85, 0.4, 1.0)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var qm = QuadMesh.new()
	qm.size = Vector2(0.16, 0.16)
	qm.material = dm
	ps.draw_pass_1 = qm
	ps.position = battle._world_pos(pos2d, height + 1.0)
	battle._world.add_child(ps)
	ps.emitting = true
	# 一次性: lifetime + 余量后自销 (不靠 one_shot finished 信号, 计时更稳)
	var tw = battle._reg_tween()
	tw.tween_interval(ps.lifetime + 0.15)
	tw.tween_callback(ps.queue_free)

# ============================================================================
#  §VFX-DEMO — GPUParticles3D 动态特效验证 (证明 2.5D 引擎能做"活"的粒子, 非静态图滑动)
#  两个 GPU 粒子函数: 火焰爆发 (球向上抛, 重力回落, 白热→橙→红→透) + 能量冲击波 (环向外扩散).
#  全程 GPU 模拟 (每颗独立速度/重力/缩放/颜色随生命渐变), 加色发光叠加, billboard 永远朝镜头.
# ============================================================================

# 火焰爆发: 球形原点喷出 70 颗火苗, 初速向上+扩散, 重力回落形成蘑菇状火球; 颜色随生命白热→橙→红→透明.
func _vfx_smolder(origin: Vector2, dir: Vector2, si: int = 1) -> void:
	dir = dir.normalized()
	var reach: float = 620.0
	battle._smolder_sys._smolder_mother(origin, dir)
	var t = battle._reg_tween()
	t.tween_interval(0.5)
	t.tween_callback(battle._smolder_sys._smolder_erupt.bind(origin, dir, reach, si))

func _vfx_preview_start() -> void:   # VFX预览: 清单位/放大相机/场地中心反复放特效 (自截图迭代用)
	for u in battle._units:
		var sp = u.get("sprite", null)
		if sp != null and is_instance_valid(sp): sp.queue_free()
	battle._units = []
	if battle._team_panel_left != null and is_instance_valid(battle._team_panel_left): battle._team_panel_left.queue_free()
	if battle._team_panel_right != null and is_instance_valid(battle._team_panel_right): battle._team_panel_right.queue_free()
	battle._cam.fov = float(OS.get_environment("VFXPREVIEW_FOV")) if OS.has_environment("VFXPREVIEW_FOV") else 26.0
	_vfx_preview_loop()

func _vfx_preview_loop() -> void:
	var eff: String = OS.get_environment("VFXPREVIEW")
	var si: int = (int(OS.get_environment("VFXPREVIEW_STAR")) - 1) if OS.has_environment("VFXPREVIEW_STAR") else 1
	var period: float = float(OS.get_environment("VFXPREVIEW_PERIOD")) if OS.has_environment("VFXPREVIEW_PERIOD") else 1.2
	await battle.get_tree().create_timer(0.4).timeout
	while is_instance_valid(self) and is_instance_valid(battle):
		var origin: Vector2 = battle._arena_center
		var dir: Vector2 = Vector2.RIGHT
		if OS.has_environment("VFXPREVIEW_DIR"):   # 验证任意方向: 角度(度)→单位向量
			var _ang = deg_to_rad(float(OS.get_environment("VFXPREVIEW_DIR")))
			dir = Vector2(cos(_ang), sin(_ang))
		var fu: Dictionary = {"pos": origin, "alive": true, "id": "basic", "side": "left", "atk_range": 350.0, "equips": [], "def": 30.0, "mr": 30.0, "atk": 100.0, "crit": 0.25, "crit_dmg": 1.5, "lifesteal": 0.0, "armor_pen": 0.0, "energy_cost": {}}
		match eff:
			"laser_sweep": battle._equip_sys._eq_laser_sweep(fu, {"pos": origin + dir * 350.0, "alive": true}, si)
			"laser_chop": battle._equip_sys._eq_laser_chop(fu, si, origin, dir, battle._equip_sys._ground_dir_frame(dir, 16), 360.0)
			"moon": battle._equip_sys._eq_wide_blade(fu, {"pos": origin + dir * 650.0, "alive": true}, si)
			"slash": battle._equip_sys._blood_sys._blood_slash_play(0, battle._equip_sys._blood_sys.blood_slash_at(origin - dir * 60.0, origin), EqBloodCombo.BLOOD_SLASH_W)
			"smolder": _vfx_smolder(origin, dir, si)
			"qibo": battle._sk_basic_chiwave(fu, {"pos": origin + dir * 600.0, "alive": true, "id": "dummy", "def": 30.0, "mr": 30.0, "maxHp": 5000.0, "hp": 5000.0})
			"stone_slam": battle._burst_vfx("res://assets/sprites/vfx/stone-slam-impact.png", origin, 220.0)
			"ninja_slash": battle._burst_vfx("res://assets/sprites/vfx/ninja-slash.png", origin, 98.0, 1.0)
			"beam": battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", origin, origin + dir * 700.0, 126.0, Color(0.6, 0.94, 1.0, 0.9), 1.6)
			"aura": battle._aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", fu, 300.0, Color(0.86, 0.68, 0.42, 0.5), 1.8)
			"vortex": battle._burst_vfx("res://assets/sprites/vfx/fx-vortex.png", origin, 240.0, 0.6)
			"blackhole": battle._burst_vfx("res://assets/sprites/vfx/fx-black-hole.png", origin, 260.0, 0.12)
			"hexbubble": battle._aura_vfx("res://assets/sprites/vfx/fx-hex-bubble.png", fu, 62.0, Color(0.68, 0.9, 1.0, 0.62), 1.8, 0.9)
			# ── 训龟大师 7 技演出预览(2026-07-30 补齐; 原来只有 glacier 一条) ──
			# ★"trainer" = 一轮过 7 技(每 period 换一个), 用于需求3 的【逐技目视】。
			#   单看某一技: VFXPREVIEW=tr_hook / tr_fury / tr_whistle / tr_glacier /
			#               tr_hunt / tr_tame / tr_stone
			# 靶向器 055 钩索炸弹(2026-08-01 用户:「打开窗口给我看看靶向器的特效」)
			# 灵物【触手拍击】程序化 3D 网格(2026-08-04 用户:「等下直接打开窗口给我看拍击动作」)
			"tentacle": _vfx_preview_tentacle(origin, dir)
			"hookbomb": _vfx_preview_hookbomb(origin, si)
			# 信号放大器 038 弧形电磁波(2026-08-01 用户:「什么是扇形波你不懂吗」→ 重做成实心扇带)
			"sigwave": _vfx_preview_sigwave(origin, dir, si)
			"trainer": _vfx_preview_trainer(origin, dir, -1)
			"tr_hook": _vfx_preview_trainer(origin, dir, 0)
			"tr_fury": _vfx_preview_trainer(origin, dir, 1)
			"tr_whistle": _vfx_preview_trainer(origin, dir, 2)
			"glacier", "tr_glacier": _vfx_preview_trainer(origin, dir, 3)
			"tr_hunt": _vfx_preview_trainer(origin, dir, 4)
			"tr_tame": _vfx_preview_trainer(origin, dir, 5)
			"tr_stone": _vfx_preview_trainer(origin, dir, 6)
			_: battle._equip_sys._eq_laser_sweep(fu, {"pos": origin + dir * 350.0, "alive": true}, si)
		await battle.get_tree().create_timer(period).timeout
		if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 queue_free), 回来必须重新确认

## 灵物【触手】预览：左边放一只**真的带 5 件灵物装备**的龟，右边放一个假人当靶。
##
## ★★为什么必须给真装备，而不是直接 `ensure(2)`：
##   `spirit_synergy_system.tick()` **每帧**都在跑 `ensure(side, 该档位应有的根数)`。
##   预览里如果没有带灵物的单位，档位 = 0 ⇒ 它每帧把我生的触手 `ensure(…, 0)` 撤掉。
##   **自截图实测**：16 帧里 14 帧画面上一根触手都没有，我第一版就是这么错的。
##   ⇒ 给真装备 = 走真实路径（memory [[fb-verify-must-run-the-real-path]]），
##     顺带也验证了"档位 → 根数"这条链是通的。
var _tt_prev_foe = null
## 预览台的待机间隔 —— 对齐真实对局：拍击周期 5 秒 − 动作 2.2 秒 ≈ 2.8 秒待机
const TT_IDLE_GAP := 2.8
var _tt_idle_t := 0.0
var _tt_prev_src = null

func _vfx_preview_tentacle(origin: Vector2, dir: Vector2) -> void:
	_tt_isolate()                      # ★第一轮就要藏, 否则出土那 2 秒还带着整张地图
	if _tt_prev_foe == null or not (_tt_prev_foe is Dictionary):
		# ★★2026-08-04 用户：「你调试做干净点啊，友军为什么带装备？用一个触手一个假人就好了」
		#   ——对。原来这里为了"走真实羁绊链"给友军塞 5 件灵物装备，
		#   再等 `spirit_synergy_system` 每 5 秒拍一次。结果：
		#   ① 台上两根触手 + 一个带装备的假人，看谁是谁都费劲
		#   ② 出手时机被 5 秒周期绑死，自截图的时间窗一错开就 240 帧全是待机
		#   ⇒ 现在只摆【一根触手 + 一个靶子】，节拍自己控（仍走 `strike()` 真实入口，
		#     memory [[fb-verify-must-run-the-real-path]]：预览不能绕过真实分派）。
		battle._tentacle_vfx.preview_lock = true
		battle._tentacle_vfx.clear()
		battle._tentacle_vfx.ensure_forced("left", 1)
		# ★★触手根部直接摆到【相机中心】—— 预览相机是对着 `origin` 的，
		#   而 `root_pos` 的默认点在 ARENA 18% 处：两者不重合 ⇒ **触手演在画面外**
		#   （实测抓了 150 帧才发现右边一片空，动作全对但看不见）。
		var rng: float = float(battle._tentacle_vfx.attack_range_2d)
		var r0: Vector2 = origin - dir * (rng * 0.42)      # 根部退后一点，让整条都进画面
		battle._tentacle_vfx.set_root("left", 0, r0)
		print("[tt-preview] 一根触手 + 一个靶子: 射程 %.0f  根部 %s  靶子前推 %.0f"
			% [rng, str(r0), rng * 0.8])
		_tt_prev_foe = battle._spawn._make_unit("basic", "right", r0 + dir * (rng * 0.8))
		(_tt_prev_foe as Dictionary)["maxHp"] = 999999.0
		(_tt_prev_foe as Dictionary)["hp"] = 999999.0
		(_tt_prev_foe as Dictionary)["no_move"] = true
		(_tt_prev_foe as Dictionary)["no_basic"] = true
		(_tt_prev_foe as Dictionary)["move_spd"] = 0.0
		battle._units.append(_tt_prev_foe)
		return                      # 头一轮只登场, 让人看清 2 秒出土
	# ★节拍：只在【待机】时才下指令 —— 免得打断正在演的动作。
	#   （原来预览和 spirit 各拍各的、错开 0.2 秒互相打断：
	#     探针实测 `SLAM/0.15` 被打回 `REAR/0.00`，动作只演了 0.15 秒。）
	# ★`TENT_IDLE_ONLY=1`：只保持待机、不下拍击指令 ——
	#   审待机形态时不想每 2 秒被一次拍击打断（用户 2026-08-05：「等下你就把 idle 打开给我看」）。
	if OS.has_environment("TENT_IDLE_ONLY"):
		return
	# ★★2026-08-05【用户："为什么完整的没有出现刚刚的 idle"】—— 因为这里是
	#   **一进待机就立刻拍**，触手根本没有停留在待机的时间。
	#   真实对局是 `SLAP_PERIOD = 5 秒`：动作 2.2 秒 + **待机 2.8 秒**。
	#   预览台不模拟这个间隔，看到的就是"一个动作接一个动作"，审不了待机。
	if battle._tentacle_vfx.state_of("left", 0) != 1:
		_tt_idle_t = 0.0
		return
	_tt_idle_t += float(OS.get_environment("VFXPREVIEW_PERIOD")) if OS.has_environment("VFXPREVIEW_PERIOD") else 1.2
	if _tt_idle_t < TT_IDLE_GAP:
		return
	_tt_idle_t = 0.0
	battle._tentacle_vfx.strike("left", 0,
		Vector2((_tt_prev_foe as Dictionary)["pos"]), 1.0)


## `TENT_ISO=1`：把场景里【除了触手以外】的一切藏掉，黑底只看触手。
## 用户 2026-08-04：「验证你可以把周围所有场景都关掉，只看触手相关特效」
## ★做法是"白名单"而不是"逐个点名藏"—— 逐个点名的话以后加了新装饰又会漏。
func _tt_isolate() -> void:
	if not OS.has_environment("TENT_ISO"):
		return
	for c in battle._world.get_children():
		if c is Camera3D or c is DirectionalLight3D or c is OmniLight3D:
			continue
		# ★★白名单必须是 `Tentacle`（不带下划线）—— 外发光壳叫 `TentacleHalo_left_0`，
		#   `begins_with("Tentacle_")` 对它是 **false**，于是【隔离模式把辉光藏了】。
		#   探针实测（`SHOT_PROBE`）：第二次进 `_tt_isolate` 之后每一帧都是 `ha0`，
		#   我却一直对着"没有辉光的截图"调辉光参数 —— 三轮全废在这。
		if str(c.name).begins_with("Tentacle"):
			continue
		if c is Node3D or c is Sprite3D or c is MeshInstance3D:
			(c as Node3D).visible = false
	# 黑底 + 关雾
	if battle._sub != null:
		battle._sub.transparent_bg = false
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	if battle._cam != null:
		battle._cam.environment = env


## 信号放大器 038 弧形电磁波预览: 每次调用发一道, 张角 90→180→270→360 递增(看张角变化)。
## ★单位钉住(移速0/不普攻) —— 演示台的单位是给人看的道具, 不该让 AI 动它们。
var _sw_prev_src = null
var _sw_prev_foes: Array = []
var _sw_prev_stt: Dictionary = {}

func _vfx_preview_sigwave(origin: Vector2, dir: Vector2, si: int) -> void:
	if _sw_prev_src == null or not (_sw_prev_src is Dictionary):
		_sw_prev_src = battle._spawn._make_unit("hunter", "left", origin + Vector2(-120.0, 0.0))
		(_sw_prev_src as Dictionary)["maxHp"] = 9999.0
		(_sw_prev_src as Dictionary)["hp"] = 9999.0
		# ★必须真给它装上 038 —— 波的推进(_sigwave.tick)挂在 _eq_tick 里, 而 _eq_tick 只对
		#   【带装备的单位】跑。不装的话波建出来了但一帧都不推进, 画面上什么都没有
		#   (我第一版就是这样, 只看到"电磁波 90°"的飘字, 波本身根本没画)。
		(_sw_prev_src as Dictionary)["equips"] = [{"id": "p2eq_038", "star": si + 1}]
		(_sw_prev_src as Dictionary)["eq_state"] = {}
		_hb_pin(_sw_prev_src)
		battle._units.append(_sw_prev_src)
		for i in range(7):
			var a: float = TAU * float(i) / 7.0
			var e: Dictionary = battle._spawn._make_unit("basic", "right",
				origin + Vector2(-120.0, 0.0) + Vector2(cos(a), sin(a)) * 380.0)
			e["maxHp"] = 9999.0
			e["hp"] = 9999.0
			_hb_pin(e)
			battle._units.append(e)
			_sw_prev_foes.append(e)
	for e in _sw_prev_foes:
		(e as Dictionary)["hp"] = 9999.0
		(e as Dictionary)["alive"] = true
		(e as Dictionary)["stun_until"] = 0.0
	var tgt: Dictionary = _sw_prev_foes[0]
	battle._equip_sys._sigwave._fire(_sw_prev_src, tgt, si, _sw_prev_stt)


## 靶向器 055 钩索炸弹预览: 挂弹 → 每秒跳伤 → 宿主死亡 → 甩钩/眩晕/拉拢 → 聚爆。
## ★走【真函数】(_hb_attach / _hb_tick / _hb_detonate), 不是另画一套演出 ——
##   照 _cast_real 那条先例: 预览里看到的就是实战里发生的。
## ★单位用 _make_unit 真实构造(真判定要走完整伤害管线); 只建一次, 之后每轮复位血量重播。
var _hb_prev_car = null
var _hb_prev_foes: Array = []
var _hb_prev_phase: int = 0

## 把预览单位【钉住】: 移速 0 + 不普攻 + 不索敌。
## ★不钉住的话它们会自己走位靠拢, 我摆得再开也会挪成一坨(用户 2026-08-01:「都挤在一起」
##   「你不能把4个假人移速设为0吗」)。演示台的单位是【给人看的道具】, 不该让 AI 动它们。
func _hb_pin(u) -> void:
	var d: Dictionary = u
	d["move_spd"] = 0.0
	d["no_basic"] = true          # 不发普攻(演示不需要它们互殴)
	d["_pinned"] = true


func _vfx_preview_hookbomb(origin: Vector2, si: int) -> void:
	if _hb_prev_car == null or not (_hb_prev_car is Dictionary):
		# ★摆位是给【人看】的: 原来敌人挤在半径 130 的小圈里, 拉拢后又聚到半径 60 ——
		#   用户 2026-08-01:「你这样我怎么看呢，都挤在一起？」。现在摊到半径 330 的大圈,
		#   钩索飞出去和拖回来都有足够行程能看清。
		_hb_prev_car = battle._spawn._make_unit("hunter", "left", origin + Vector2(-430.0, -30.0))
		(_hb_prev_car as Dictionary)["maxHp"] = 9999.0
		(_hb_prev_car as Dictionary)["hp"] = 9999.0
		_hb_pin(_hb_prev_car)
		battle._units.append(_hb_prev_car)
		for i in range(5):
			var a: float = TAU * float(i) / 5.0 - PI * 0.5
			var e: Dictionary = battle._spawn._make_unit("basic", "right",
				origin + Vector2(150.0, 0.0) + Vector2(cos(a), sin(a)) * 330.0)
			e["maxHp"] = 3000.0
			e["hp"] = 3000.0
			_hb_pin(e)
			battle._units.append(e)
			_hb_prev_foes.append(e)
	var car: Dictionary = _hb_prev_car
	match _hb_prev_phase:
		0:   # 复位 + 挂弹(位置也复位 —— 上一轮被拉到震中去了)
			for i in range(_hb_prev_foes.size()):
				var e: Dictionary = _hb_prev_foes[i]
				var a2: float = TAU * float(i) / float(maxi(1, _hb_prev_foes.size())) - PI * 0.5
				e["pos"] = origin + Vector2(150.0, 0.0) + Vector2(cos(a2), sin(a2)) * 330.0
				e["_home_pos"] = e["pos"]
				e["hp"] = 3000.0
				e["alive"] = true
				e["hookbomb_pct"] = 0.0
				e["stun_until"] = 0.0
				_hb_pin(e)
			car["eq_state"] = {}
			car["_st_dealt"] = 400
			car["equips"] = [{"id": "p2eq_055", "star": si + 1}]
			battle._equip_tick_sys._tick_targeter(car, 0.1)
		1, 2:   # 每秒跳伤(看炸弹脉动 + 掉血飘字)
			for e in _hb_prev_foes:
				if float((e as Dictionary).get("hookbomb_pct", 0.0)) > 0.0:
					battle._hookbomb_sys._hb_tick(e, 1.05)
		3:   # 宿主死亡 → 甩钩 + 拉拢 + 聚爆
			for e in _hb_prev_foes:
				if float((e as Dictionary).get("hookbomb_pct", 0.0)) > 0.0:
					(e as Dictionary)["hp"] = 1.0
					battle._kill(e)      # _kill → _hb_on_death → 以【宿主倒地处】为震中引爆
					break
	_hb_prev_phase = (_hb_prev_phase + 1) % 4


## 训龟大师技能演出预览。idx<0 = 每次调用轮换一个(一轮过 7 技)。
##
## ★★这里跑【真判定】(2026-07-30 改) —— 六个主动技走玩家真入口 _cast_active,
##   而不是各自的演出函数。所以画面里看到的是真射程/真朝向/真命中/真冷却, 不只是美术。
##   (旧注释曾写"只跑演出不跑判定" —— 现在说反了, 已改。)
## ★代价: 施放【可能被拒】(射程外/无目标) → 画面什么都不出。_cast_real 会打印
##   "成功 / ★被拒(未施放)" 区分这两种, 否则会把"没施放"错当成"特效不可见"去查。
## ★大师与靶子必须用 _make_unit 真实构造(见下), 因为真判定会走完整伤害管线。
var _tr_prev_i: int = 0
var _tr_prev_tr = null            # 预览用的大师/靶子(真实 _make_unit 建的, 只建一次)
var _tr_prev_tgt = null
## 预览用: 装上这一技再走玩家真入口 _cast_active(冷却先清零, 预览不受 CD 限制)。
## ★装 _tr_active 是必须的 —— _cast_active 按这个字段分派, 不设就永远只放 hook(默认值)。
func _cast_real(tr: Dictionary, sid: String, aim: Vector2) -> void:
	tr["_tr_active"] = sid
	tr["_active_cd"] = 0.0
	var hit: bool = battle._trainer_sys._cast_active(tr, aim)
	# ★打印返回值: 预览里"什么都没发生"分两种 —— 施放被拒(false·射程/冷却/无目标)
	#   与 施放了但看不见(true·纯特效问题)。不打这一行就分不清, 会去错的方向查。
	print("      _cast_active(%s) → %s" % [sid, "成功" if hit else "★被拒(未施放)"])


func _vfx_preview_trainer(origin: Vector2, dir: Vector2, idx: int) -> void:
	var i: int = idx
	if i < 0:
		i = _tr_prev_i % 7
		_tr_prev_i += 1
	# ★★ 用【真实的单位构造函数】建大师与靶子, 不要手搓字典 ——
	#   血泪: 魔法石那一技(idx 6)的演出是 _fire_trainer_rock, 它建的是【真弹道】,
	#   石头落地照样走 _apply_damage_from(石头本身 1 点物理), 与 ms_onhit 开关无关。
	#   我先手搓了个精简 tgt, 结果缺 shield 刷 17 条报错; 补上 shield 又缺 dmg_dealt……
	#   ——【手搓字典喂进伤害管线是个无底洞】。伤害管线读几十个字段, 一个个补是打地鼠。
	#   用 _make_unit 走真实构造路径, 所有字段一次到位。
	#   _review_dummy=true: 受击即回满血(见 battle_damage.gd:116), 预览可以一直打不死。
	if _tr_prev_tr == null:
		_tr_prev_tr = battle._spawn._make_unit(battle.TRAINER_ID, "left",
			origin - dir * 260.0, {"trainer": true})
		_tr_prev_tgt = battle._spawn._make_unit("basic", "right", origin + dir * 300.0, {})
		_tr_prev_tgt["_review_dummy"] = true
		battle._units.append(_tr_prev_tr)
		battle._units.append(_tr_prev_tgt)
	var tr: Dictionary = _tr_prev_tr
	var tgt: Dictionary = _tr_prev_tgt
	tr["pos"] = origin - dir * 260.0
	tgt["pos"] = origin + dir * 300.0
	tr["_active_cd"] = 0.0
	var names := ["钩锁", "怒火药水", "口哨·灵体气波", "冰川", "猎龟令", "驯服", "魔法石·投石"]
	print("[VFXPREVIEW·大师] %d/7 %s" % [i + 1, names[i]])
	# ★★六个主动技【全部】走玩家真入口 _cast_active(设 _tr_active 再分派), 不再直接点演出函数。
	#   血泪由来: 钩锁 2026-07-30 改成真 skillshot 后, 飞行/命中都搬进了 _tick_hook_flights,
	#   旧的 _hook_dramatize 变成【零调用者的死代码】—— 而预览还指着它。于是我
	#   "目视确认新实现" 看到的其实是【旧实现】= 无效验证, 白跑一轮截图。
	#   更阴的是 verify_trainer_audit 有条 "_hook_dramatize 存在" 的断言, 全套门禁照样绿:
	#   【断言函数存在, 守不住这个函数还有没有人调】。
	#   所以预览要能当验证用, 就必须跑玩家真正会跑的那条路 —— 法术盘按下去走的正是 _cast_active。
	#   顺带白送: 冷却/射程/朝向/命中判定这些"真逻辑"也一起进画面了, 不只看特效。
	var aim: Vector2 = dir * battle.HOOK_RANGE
	match i:
		0: _cast_real(tr, "hook", aim)
		1: _cast_real(tr, "fury_potion", dir * 200.0)
		2: _cast_real(tr, "whistle", dir)
		3: _cast_real(tr, "glacier", dir * 120.0)
		4: _cast_real(tr, "hunt_order", tgt["pos"] - tr["pos"])
		5: _cast_real(tr, "tame", tgt["pos"] - tr["pos"])
		# ★ms_onhit 必须 false —— 传 true 会让石头落地时触发【真判定】
		#   _trainer_magicstone_onhit → _resolve_dmg / _apply_damage_from,
		#   而这里的 tr/tgt 是【只够演出用】的精简字典, 缺一堆战斗字段 → 报错刷屏
		#   (实测 18 条 SCRIPT ERROR)。我在上面注释里写了"只跑演出不跑判定",
		#   结果自己在这一行违背了。预览要的是弹道的样子, 不是伤害。
		6: battle._ballistics._fire_trainer_rock(tr, tgt, false)

## ★★2026-09-01 从主场景搬过来(CLAUDE.md §5 落位表: 特效演出 → battle_vfx.gd)。
##   搬的直接原因: 修它那两个 `!is_inside_tree` bug 时给上帝文件加了 10 行, arch_budget 当场红。
##   台账是"只减不增"的 —— 正确做法是把它放对地方, 不是把台账抬上去。
##   它本来就不在 `_sim_step` 调用链上, 只被 battle_render 的渲染步调用。
## 虚化残影: 复制本体当前帧→渐隐(青紫)·移动时成拖尾(用户 2026-07-11)。
func phase_afterimage(spr) -> void:
	if not is_instance_valid(spr):
		return
	## ★★`is_instance_valid` 只保证"没被 free", **不保证"在场景树里"** ——
	##   不在树里读 `global_position` 会走 `get_global_transform` 的 `!is_inside_tree()` 分支:
	##   引擎打一条 ERROR 并**返回单位矩阵**, 于是残影被画到世界原点。
	##   2026-09-01: 这条被"从没跑过的死技能门禁"(tests/verify_skills_not_dead.gd)翻出来 ——
	##   它逐个放 84 个技能, 走到幽灵龟虚化态时刷了 13 条。
	if not spr.is_inside_tree():
		return
	var ai := Sprite3D.new()
	ai.texture = spr.texture
	ai.frame = 0                      # ★先归零再改帧网格(同族)
	ai.hframes = spr.hframes
	ai.vframes = spr.vframes
	ai.frame = clampi(int(spr.frame), 0, maxi(0, int(ai.hframes) * int(ai.vframes) - 1))
	ai.pixel_size = spr.pixel_size
	ai.billboard = spr.billboard
	ai.flip_h = spr.flip_h
	ai.shaded = false
	ai.transparent = true
	ai.texture_filter = spr.texture_filter
	ai.scale = spr.scale
	ai.modulate = Color(0.55, 0.45, 1.0, 0.5)
	## ★★先进树【再】设 global_position —— 不在树里设它, 引擎拿不到父节点的全局变换,
	##   会把"全局坐标"当"相对 _world 的局部坐标"存下来; `_world` 一旦不是单位变换,
	##   残影就偏了。原来这两行是反的。
	battle._world.add_child(ai)
	ai.global_position = spr.global_position
	var tw: Tween = battle._reg_tween()
	tw.tween_property(ai, "modulate:a", 0.0, 0.35)
	tw.tween_callback(ai.queue_free)


## ══════════════════════════════════════════════════════════════════
##  001 木制长剑·飞斩剑气 —— 发射 muzzle / 命中 impact
## ══════════════════════════════════════════════════════════════════
## ★2026-09-06 从上帝文件搬过来: 判据只有一条 ——【不在 `_sim_step` 调用链上的不进主文件】,
##   特效演出属于 `battle_vfx.gd`(CLAUDE.md §5 那张表)。
##   我一开始直接写进 RealtimeBattle3DScene.gd, `arch_budget` 当场红:
##   「现 9013 行 > 台账冻结的 8925 行 —— 往上帝文件里加代码=违规」。
## ★4 不是 5 —— animate_image 的最后一帧是【整幅 960/1024 像素不透明】的垃圾帧,
## 播到它就是屏幕上闪一个灰方块。门禁 ① 抓的就是这个。
const MUZZLE_FRAMES := 4
## ★3 不是 8 —— 第 4 帧起星爆糊成【实心奶油盘】且开始发褐。只取爆开的那三帧,
## 收尾靠 tween 拉 alpha(演出该holdfade, 不该让素材自己变黑)。
const IMPACT_FRAMES := 3
var _fs_muzzle_tex: Texture2D = null
var _fs_impact_tex: Texture2D = null

## 001 飞斩·②发射 muzzle —— 一次性，锚在出手点，**不跟着飞**(LoL 的 cast VFX 就是分离的)。
func flyslash_muzzle(at2d: Vector2, col: Color) -> void:
	if _fs_muzzle_tex == null:
		_fs_muzzle_tex = load("res://assets/sprites/vfx/eq001-flyslash-muzzle.png")
	if _fs_muzzle_tex == null:
		return
	var s := Sprite3D.new()
	s.texture = _fs_muzzle_tex
	s.hframes = MUZZLE_FRAMES
	s.frame = 0
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false; s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = col
	s.pixel_size = battle.TARGET_BODY_H / float(_fs_muzzle_tex.get_height())
	s.position = battle._world_pos(at2d, 1.1)
	battle._world.add_child(s)
	var tw: Tween = battle._reg_tween()   # ★不能用 `:=` —— `battle` 无类型, 推不出返回类型 ⇒ Parse Error ⇒ 整个脚本编译失败
	tw.tween_method(func(f: float) -> void:
		## ★闭包里必须先判存活: 节点可能先被 queue_free / 换路清场,
		##   否则每帧刷 "Lambda capture at index 0 was freed"(实测一轮 23 条,
		##   而 run-tests 的致命正则会当场判红)。
		if not is_instance_valid(s):
			return
		s.frame = clampi(int(f), 0, MUZZLE_FRAMES - 1),
		0.0, float(MUZZLE_FRAMES), 0.22)
	tw.tween_callback(func() -> void:
		if is_instance_valid(s): s.queue_free())


## 001 飞斩·⑤命中 impact —— 一次性，锚在命中点。改造前【命中完全没有特效】，只有伤害数字。
func flyslash_impact(at2d: Vector2, col: Color) -> void:
	if _fs_impact_tex == null:
		_fs_impact_tex = load("res://assets/sprites/vfx/eq001-flyslash-impact.png")
	if _fs_impact_tex == null:
		return
	var s := Sprite3D.new()
	s.texture = _fs_impact_tex
	s.hframes = IMPACT_FRAMES
	s.frame = 0
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false; s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = col
	s.pixel_size = battle.TARGET_BODY_H / float(_fs_impact_tex.get_height())
	s.position = battle._world_pos(at2d, 1.0)
	battle._world.add_child(s)
	var tw: Tween = battle._reg_tween()   # ★不能用 `:=` —— `battle` 无类型, 推不出返回类型 ⇒ Parse Error ⇒ 整个脚本编译失败
	tw.tween_method(func(f: float) -> void:
		## ★闭包里必须先判存活: 节点可能先被 queue_free / 换路清场,
		##   否则每帧刷 "Lambda capture at index 0 was freed"(实测一轮 23 条,
		##   而 run-tests 的致命正则会当场判红)。
		if not is_instance_valid(s):
			return
		s.frame = clampi(int(f), 0, IMPACT_FRAMES - 1),
		0.0, float(IMPACT_FRAMES), 0.16)
	## ★收尾靠拉 alpha, 不靠素材自己变黑(门禁 ② 量的就是这条)。
	##   而且**先满亮 hold 完 3 帧再淡**, 不是一出生就线性淡出 ——
	##   短命特效一出生就淡, 实拍读出来是土棕色的一团(见 memory fb-vfx-defect-families "淡出病")。
	var c0: Color = col
	tw.tween_method(func(a: float) -> void:
		if not is_instance_valid(s):
			return
		s.modulate = Color(c0.r, c0.g, c0.b, a),
		1.0, 0.0, 0.14)
	tw.tween_callback(func() -> void:
		if is_instance_valid(s): s.queue_free())


## ══════════════════════════════════════════════════════════════════
##  流血持续视觉 —— 往下滴的血滴
## ══════════════════════════════════════════════════════════════════
## ★由来(2026-09-06 审 002 辣椒时发现, 但这是**全局**缺口不是 002 一件的事):
##   三种层数式 DoT 里, 灼烧每 0.15 秒窜一个小火苗、中毒每 0.2 秒冒一个毒绿泡,
##   **流血一个像素都没有** —— 实拍 002 的台子, 施加流血后整个画面空白。
##   ⇒ 补上同族的第三个, 让"这单位在流血"一眼可辨。
## ★方向刻意与另外两个相反: 火苗和毒泡【上升】, 血滴【下坠】—— 物理上对, 也帮玩家区分。
## ★频率低于另两个(每 0.28 秒一滴): 流血叠层常年挂着, 太密会糊住单位(LoL 的可读性原则:
##   高频状态特效必须克制, 否则把玩家的注意力从"谁在打谁"上吃掉)。
const BLEED_DROP_SEC := 0.55
var _bleed_drop_tex: Texture2D = null


func spawn_bleed_drop(u: Dictionary) -> void:
	if _bleed_drop_tex == null:
		_bleed_drop_tex = load("res://assets/sprites/vfx/dot-bleed-drop.png")
	if _bleed_drop_tex == null:
		return
	var rng = battle._juice_rng
	var pos2d: Vector2 = u["pos"] + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-2.0, 8.0))
	var s := Sprite3D.new()
	s.texture = _bleed_drop_tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素风: 不许线性糊
	s.pixel_size = 0.0176   # ★用户 2026-09-06: 先「大4倍」(0.011→0.044), 再「缩小60%」⇒ 0.044×0.4
	s.scale = Vector3(0.85, 0.85, 0.85)
	var h0: float = 0.62 + rng.randf_range(-0.10, 0.16)
	s.position = battle._world_pos(pos2d, h0)
	battle._world.add_child(s)
	var tw: Tween = battle._reg_tween()   # ★不能用 `:=` —— `battle` 无类型, 推不出返回类型
	tw.set_parallel(true)
	tw.tween_property(s, "position", battle._world_pos(pos2d, 0.06), BLEED_DROP_SEC)   # 下坠
	tw.tween_property(s, "scale", Vector3(0.62, 0.62, 0.62), BLEED_DROP_SEC)
	## ★先满亮 hold 再淡: 一出生就线性淡出的话, 实拍读出来是一团土褐色
	##   (memory fb-vfx-defect-families "淡出病", 一天踩过四次)。
	tw.chain().tween_property(s, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(s): s.queue_free())


## ══════════════════════════════════════════════════════════════════
##  005 双生匕首·追加刺击 —— 目标身上一记交叉斩
## ══════════════════════════════════════════════════════════════════
## ★由来(2026-09-07 审 005): 实拍确认这件装备的追加刺击**一行演出都没有**,
##   ★3 是 100% 触发, 但玩家只看到一个红色伤害数字, 一把"双生匕首"完全看不见。
##   (全仓扫过: 105 个装备分支里"造成伤害但零演出"只剩 3 个, 002 已补、023 走灼烧自己的视觉。)
## ★做成一记短促的交叉斩: 素材是硬边像素 X(steel 锁定板), 0.16 秒拉 alpha 收掉,
##   尺寸只有龟的一半 —— 它是"补了一刀"不是大招, 排场要和威胁度匹配(LoL 的可读性原则)。
var _twinstrike_tex: Texture2D = null

func twin_strike(at2d: Vector2) -> void:
	if _twinstrike_tex == null:
		_twinstrike_tex = load("res://assets/sprites/vfx/eq005-twinstrike.png")
	if _twinstrike_tex == null:
		return
	var s := Sprite3D.new()
	s.texture = _twinstrike_tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素风: 不许线性糊
	s.pixel_size = battle.TARGET_BODY_H * 0.5 / 32.0           # 半个龟高
	s.position = battle._world_pos(at2d, 1.05)
	battle._world.add_child(s)
	var sr := s
	var tw: Tween = battle._reg_tween()   # ★不能用 `:=`: battle 无类型, 推不出返回类型 ⇒ Parse Error
	tw.set_parallel(true)
	## ★先满亮再收 —— 短命特效一出生就淡, 实拍读出来是灰的(memory fb-vfx-defect-families "淡出病")。
	tw.tween_property(s, "modulate:a", 1.0, 0.06)
	tw.tween_property(s, "scale", s.scale * 1.25, 0.16)
	tw.chain().tween_property(s, "modulate:a", 0.0, 0.10)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(sr): sr.queue_free())

## 008 双穿珊瑚刺【命中碎裂】。
## ★★2026-09-08 从上帝文件 `_coral_burst` 搬来 + 重做。改前是
##   `VfxTex._make_glow_texture()` 的**软光球中心 + 6 个软光点四溅** ——
##   通病「无含义圆环与白球」的另一张脸: 那是通用爆炸, 说明不了"珊瑚碎了"。
##   ⇒ 换 Blender 烤的 5 帧碎块(tools/blender_coralspike.py --mode shatter),
##     碎块**大小不一、角度不匀、飞得不一样远** —— 第一版 9 片等长等角均匀发散,
##     我自己看实拍读成【烟花】, 规律的放射就是通用爆炸。
## ★逐帧展开走 `_wait_sim` 不走 tween(v0.19.345 学到的: tween 走真实时钟, 与实拍口径对不上)。
const CORAL_SHATTER_TEX := "res://assets/sprites/vfx/eq008-shatter.png"
const CORAL_SHATTER_FRAMES := 5
const CORAL_SHATTER_PX := 0.048   # 48px 格 x 0.048 = 2.3 米, 与刺(1.6 米)成比例

var _coral_shatter_tex: Texture2D = null

func coral_burst(pos2d: Vector2) -> void:
	if _coral_shatter_tex == null:
		_coral_shatter_tex = load(CORAL_SHATTER_TEX)
	var sp := Sprite3D.new()
	sp.texture = _coral_shatter_tex
	sp.frame = 0
	sp.hframes = CORAL_SHATTER_FRAMES; sp.vframes = 1
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false; sp.transparent = true
	sp.pixel_size = CORAL_SHATTER_PX
	sp.position = battle._world_pos(pos2d, 0.9)
	battle._world.add_child(sp)
	for f in range(1, CORAL_SHATTER_FRAMES):
		await battle._wait_sim(0.045)
		if not is_instance_valid(battle) or not is_instance_valid(sp):
			return
		sp.frame = f
	## ★先满亮再收 —— 不许一出生就淡(memory fb-vfx-defect-families 的"淡出病")
	var ft: Tween = battle._reg_tween()
	ft.tween_property(sp, "modulate:a", 0.0, 0.14)
	ft.tween_callback(sp.queue_free)


## ════════════════════════════════════════════════════════════════════════
##  通用【获得护盾】演出 —— 罩在单位身上的六棱护罩
## ════════════════════════════════════════════════════════════════════════
## ★由来(用户 2026-09-11 看 012 的护盾演出):
##     「**我不明白lol里获得护盾都是你这样在地上搞一下的吗**」
##   被否的是 `battle_damage._grant_shield` 末尾那行 `_skill_ring(...)` ——
##   在**地上**画个金圈, 而它封着全游戏 44 个给盾点。LoL 的 Barrier/护盾一律在角色身上。
##
## ★素材是这条专用的新图 `shield-shell.png`(8 帧·64×64·4 色·0 半透),
##   不借 046 的 `shield-dome.png` 也不借石龟的 `fx-hex-bubble.png`
##   (铁律 [[fb-no-asset-reuse-unless-told]]:「别拿别的顶替」)。
##
## ★一条钟: 帧推进挂在 `_follow_vfx` 的 `anim_fps` 上(走游戏时钟), 不用 tween。
##   没有 alpha 渐变 —— 明暗变化烤在素材的 8 帧里(防【淡出病】)。
const SHELL_TEX := "res://assets/sprites/vfx/shield-shell.png"
const SHELL_FRAMES := 12
const SHELL_FPS := 24.0        # 12 帧 / 24fps = 0.50 秒(参考实测: 满态 0.33 + 消散 ≈ 0.55 秒)
const SHELL_YARDS := 132.0     # 整格直径(码)。★盘面只占格子 78%(剩下留给碎屑飞出去)
                               #   ⇒ 可见盘径 ≈ 103 码, 与上一版的 108 码基本持平
const SHELL_H := 0.92          # 挂在单位身上的高度(米·跟着 height 走, 击飞时一起抬)

func shield_shell(u: Dictionary, col: Color) -> void:
	if battle._world == null or u == null or not u.get("alive", false):
		return
	var tex: Texture2D = load(SHELL_TEX)
	if tex == null:
		return                                  # 素材没 import 就静默跳过, 不崩战斗
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = SHELL_FRAMES
	s.frame = 0
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素画, LINEAR 会糊
	## 一帧的边长 = 图宽 / 帧数; 按它归一, 换素材尺寸不用回来改这里
	s.pixel_size = (SHELL_YARDS * battle.WS) / float(maxi(1, int(tex.get_width()) / SHELL_FRAMES))
	s.modulate = Color(col.r, col.g, col.b, 1.0)
	## ★★叠加混合(用户 2026-09-11 拍板:「开」) —— **只给这一层罩子开**。
	##   为什么非开不可: 1:1 实拍量过 —— 不用 additive 时, 任何浅色以低 alpha 叠在
	##   近黑地图上都会变成**灰褐薄雾**(深金→浅金只减轻一点), 读不成"发光的罩"。
	## ★ docs/specs/装备特效制作流程.md 阶段 4 写着「不用 blend_add(会洗白, 颜色该由美术定)」——
	##   那条是给**不透明的手绘素材**定的(additive 会洗掉美术定的颜色);
	##   护盾罩是**刻意的半透叠加层**, additive 正是它该用的工具。例外范围就这一个函数。
	## ★为什么要自己搭材质: Sprite3D 的 billboard/modulate/texture_filter 都是喂给它
	##   **内部材质**的, 而 material_override 会把内部材质整个替掉 ⇒ 这几样得在材质上再设一遍。
	##   帧选择不受影响: hframes 改的是**网格 UV**, 覆盖材质照样采到对的那一格。
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(col.r, col.g, col.b, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	s.material_override = mat
	s.position = battle._world_pos(u["pos"] as Vector2, SHELL_H)
	battle._world.add_child(s)
	battle._follow_vfx.append({
		"spr": s, "unit": u, "h": SHELL_H,
		"anim_fps": SHELL_FPS, "anim_n": SHELL_FRAMES, "anim_t0": battle._t,
	})


## ════════════════════════════════════════════════════════════════════════
##  012【海藻】的来源标识 —— 脚下长出一丛海藻
## ════════════════════════════════════════════════════════════════════════
## ★用户 2026-09-11:「我觉得特效完全不够商业游戏，**名称也不好，改为海藻**，重做图标」
##   ⇒ 012 改名【海藻】; 它每 4 秒给自己一次护盾, 演出就该是海藻从脚下长起来
##   ([[fb-effect-text-is-the-spec]]: 演出必须就是效果本身)。
##
## ★与通用六棱护罩是**两层**不是二选一: 护罩是全游戏"我有盾了"的统一语言,
##   这丛海藻说的是"这次的盾是谁给的"。所以 012 不置 `_own_grant_vfx`。
##
## ★四丛错开 KELP_STAGGER 秒起跳 —— 齐刷刷同时冒出来像一个印章盖下去。
const KELP_TEX := "res://assets/sprites/vfx/kelp-frond.png"
const KELP_FRAMES := 6
const KELP_FPS := 18.0          # 6 帧 / 18fps = 0.333 秒; 加上错开 0.09 秒 = 0.42 秒 ≈ 六棱罩的 0.40 秒
const KELP_YARDS := 34.0        # 海藻高度(码)。★实拍改过: 50 码时海藻把龟的头和壳全埋了(读成"龟站在灌木丛里")
const KELP_N := 4               # 一次长几丛
const KELP_R := 0.46            # 绕身半径(米)。★实拍改过: 0.30 时四丛全堆在正中间, 散开才读得出"绕一圈"
const KELP_STAGGER := 0.030     # 每丛错开几秒起跳(总时长要收在六棱罩之内, 否则罩没了还剩一丛孤零零的草)

func kelp_burst(u: Dictionary) -> void:
	if battle._world == null or u == null or not u.get("alive", false):
		return
	var tex: Texture2D = load(KELP_TEX)
	if tex == null:
		return
	var fh: float = float(maxi(1, int(tex.get_height())))
	var ps: float = (KELP_YARDS * battle.WS) / fh          # 按**帧高**归一: 目标是"多高", 不是"多宽"
	for i in range(KELP_N):
		var s := Sprite3D.new()
		s.texture = tex
		s.hframes = KELP_FRAMES
		s.frame = 0
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.pixel_size = ps
		## Sprite3D 以图心为锚 ⇒ 抬高半个身位, 根部才落在地面上而不是悬空
		var h: float = fh * ps * 0.5
		var ang: float = TAU * (float(i) + 0.5) / float(KELP_N)
		s.position = battle._world_pos(u["pos"] as Vector2, h) \
			+ Vector3(cos(ang) * KELP_R, 0.0, sin(ang) * KELP_R)
		battle._world.add_child(s)
		battle._follow_vfx.append({
			"spr": s, "unit": u, "h": h,
			"orbit_r": KELP_R, "orbit_a": ang, "orbit_spd": 0.0,   # 静态绕身偏移(复用既有机制)
			"anim_fps": KELP_FPS, "anim_n": KELP_FRAMES,
			"anim_t0": battle._t + float(i) * KELP_STAGGER,
		})

## ★★2026-09-12 重做。`_bolt_line` 是**全仓 24 处共用**的连线原语
##   (闪电链/凤凰喷火/竹弓/水晶/忍者/火箭/星星/双头/天使/赛博/熔岩/触手/014 汲取…)。
## 被换掉的两个毛病, 都是 1:1 实拍量出来的(014 汲取线在画面上**完全找不到**):
##   ① **1 像素宽的裸 GPU 线**(`PRIMITIVE_LINES`, 无贴图) —— 像素风里几乎不可见,
##      而且线宽在多数驱动上根本不可调。
##   ② `albedo_color:a` **从出生就开始淡** —— memory `fb-vfx-defect-families` 的头一条
##      「淡出病」: 短命特效一出生就线性淡出, 实拍读成一抹灰。
## ⇒ 改成**沿路径排一串方点**(每点是一个正方形 quad, 世界尺寸固定 ⇒ 屏幕上恒是方块),
##   **先满亮 hold 再淡出**。方块=像素, 不需要旋转贴图, 任意角度都不会重采样
##   —— 这是像素游戏画光束/锁链的标准做法。
## ★签名一个字没动 ⇒ 24 个调用点全部不用改。
## ★★尺寸必须按**屏幕像素**反算, 不能拍一个"米"就完事。
##   换算: 1 码 = WS = 0.024 m; 实战镜头下约 **0.69 屏幕像素/码**。
##   第一版写 0.085 m 并注“≈4px” —— **算错了**: 0.085/0.024 = 3.5 码 ≈ **2.4 px**,
##   再被俯视角压扁就剩 1~2 px ⇒ 1:1 实拍里根本看不见。
##   这是 2026-09-12 同一天第五次犯同一条(海藻/护罩三段/013 刺/018 壳沟/这里):
##   **尺寸与层次要按它在屏幕上占多少像素定, 不是按世界单位拍脑袋。**
const BOLT_DOT_M := 0.175      # 方点边长(米) = 7.3 码 ≈ **5 屏幕像素**
const BOLT_GAP_M := 0.34       # 点间距(米) ≈ 10 px —— 疏一点才读成「一串」而不是实线
const BOLT_HOLD_T := 0.14      # ①满亮段: 这一整段 alpha 不降(治淡出病)
const BOLT_FADE_T := 0.13      # ②淡出段(总时长 0.27s, 与改造前的 0.25 基本持平)
func bolt_line(a2d: Vector2, b2d: Vector2, col: Color) -> void:
	var pa: Vector3 = battle._world_pos(a2d, 1.0)
	var pb: Vector3 = battle._world_pos(b2d, 1.0)
	var span: float = pa.distance_to(pb)
	if span <= 0.001:
		return
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	## ★★关深度测试 + 抬排序偏移: 连线是【两个单位之间】的关系,
	##   而近战时两单位贴在一起 ⇒ 线被立绘挡得一点不剩。
	##   014 汲取“实拍里完全找不到”的真因之一就是这个:
	##   整帧实拍一看, 四只龟挤在 60px 内。同族做法见 `_splash_ring_bold`。
	mat.no_depth_test = true
	im.sorting_offset = 2.0
	## 点朝相机: 场景是固定俯视角, 用 XZ 平面上的方块即可(与贴地演出同一个平面),
	## 不做 billboard —— billboard 要每点一个节点, 24 处共用的原语开不起那个销。
	## ★★方点必须**面朝相机**。用户 2026-09-12 一句话点出来的:「点串是在地上吗」——
	##   第一版我建的是 `Vector3(±h, 0, ±h)`, 即**水平面上的正方形**(只是抬到 1m 高)。
	##   俯视角下水平面会被压扁 ⇒ 5px 的方块竖向只剩 2~3px, 难怪看不见。
	## ⇒ 拿相机的右/上向量建方块。相机是固定视角, **算一次就行**,
	##   不用给每个点开一个 billboard 节点(24 处共用的原语开不起那个销)。
	var cam: Camera3D = battle._cam
	var rgt: Vector3 = Vector3.RIGHT
	var upv: Vector3 = Vector3.BACK
	if is_instance_valid(cam):
		rgt = cam.global_transform.basis.x.normalized()
		upv = cam.global_transform.basis.y.normalized()
	var n: int = maxi(2, int(span / BOLT_GAP_M))
	var h: float = BOLT_DOT_M * 0.5
	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for k in range(n + 1):
		var c: Vector3 = pa.lerp(pb, float(k) / float(n))
		## ★两端各留半个点: 端点压在单位身上会被立绘盖住, 读起来像线没连上
		var q := [c - rgt * h - upv * h, c + rgt * h - upv * h,
			c + rgt * h + upv * h, c - rgt * h + upv * h]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for vi in tri:
				imesh.surface_set_color(col)
				imesh.surface_add_vertex(q[vi])
	imesh.surface_end()
	battle._world.add_child(im)
	## ①满亮 hold(等值 tween 占住这一段) → ②才淡出。少了第一段, chain 会紧跟着排 ⇒ 又变回一出生就淡。
	## ★写显式类型: `battle` 无类型, `:=` 推不出来 ⇒ Parse Error
	##   (spec《装备特效制作流程》001 那轮就栏在这一行上)
	var tw: Tween = battle._reg_tween()
	tw.tween_property(mat, "albedo_color:a", col.a, BOLT_HOLD_T)
	tw.tween_property(mat, "albedo_color:a", 0.0, BOLT_FADE_T)
	tw.tween_callback(im.queue_free)



## ══════════════════════════════════════════════════════════════════════
##  014 深海堡垒甲【汲取生命】—— 用户 2026-09-12 逐字定的四拍
## ══════════════════════════════════════════════════════════════════════
## 他否掉的是我拿 `bolt_line`(一条直线排一串方块)当汲取用:
##   「**为什么又用什么长方形来敷衍**」「**你怎么能这样敷衍我呢**」
## **一串静止的方块不是特效, 是几何占位** —— 与他先前否掉的「程序生成的圆环白球」同一类。
##
## 四拍(钉住不许漂):
##   ① 一道**绿色粒子波纹**从**目标身上抽取出来**
##   ② 在**空中飘舞**(飘动的曲线, 不是直线)
##   ③ **飞到携带者身上**
##   ④ 携带者身上**绿色粒子爆发**
##
## ★为什么用 tween 而不是 `_wait_sim`: 这一段**纯观感, 不挂任何结算** ——
##   伤害与回血在 `_tick_fortress` 里已经当场算完了, 演出到不到位都不影响账。
##   (memory [[fb-second-clock-drops-events]]: tween 只适合纯观感; 一旦有结算必须走游戏钟。)
## ★★尺寸的判据是【一个贴图像素落在一个屏幕像素上】, 不是「世界里多少米」。
##   2026-09-12 染色实测(把 `_mote` 整体 modulate 成品红 + 关泛光, 再数连通域):
##     · 一粒在屏幕上 **7×7 像素**, 而当时贴图一格是 **24×24** ⇒ 被压 3.4 倍
##     · 像素画非整数倍缩放 = 像素网格被打烂(像素风三条硬约束之首,
##       battle_ballistics.gd:675) ⇒ 菱形糊成一坨亮点, 连「是绿的」都读不出来
##   同一帧量到的标尺: 一只龟 ≈45 屏幕像素高, 立绘帧高 = TARGET_BODY_H = 2.0 m
##   ⇒ 台子(1280×720 · zoom=1.0)下 **≈23.5 屏幕像素/米**。
##   ⚠ 这个数**随视口高度变**(别处文件里的 28.148 px/m 是另一档视口量的, 两边都不算错);
##     真正与分辨率无关的说法是下面这条 ——
##   ⇒ **一粒 = 0.511 m ≈ 四分之一个龟高**, 贴图一格 12px ⇒ pixel_size 0.0426 ≈ 1:1。
const MOTE_TEX := "res://assets/sprites/vfx/life-mote.png"
const MOTE_FRAMES := 4
## ★配色也踩过一次: 素材原先重索引到 `pixelize_sheet` 的 jade 板 —— **jade 是薄荷青**,
##   而场上龟本身就是青身+暗绿壳, 同色系 + 泛光 ⇒ 1:1 实拍读成**白色亮片**。
##   已另立 'life' 板(正绿/高彩度), 素材主色 55.6% 是 (104,244,112)。
const MOTE_YARDS := 21.3        # 一粒的边长(码) = 0.511 m ≈ 1/4 龟高; 配 12px 一格 ⇒ 1 texel : 1 屏幕像素
const DRAIN_N := 14             # 一个目标抽几粒(9 太稀, 连不成一道波纹)
const DRAIN_T := 0.52           # 单粒飞行时长(秒)
const DRAIN_STAGGER := 0.028    # 粒与粒的出发间隔 ⇒ 读成「一道波纹」而不是同时一坨
const DRAIN_PULL := 0.16        # ①抽取: 先从目标身上往外挣出这么久
const DRAIN_WAVE := 26.0        # ②飘舞: 垂直于路径的最大摆幅(码)
const BURST_N := 10             # ④到达时携带者身上爆开几粒
const BURST_T := 0.30
const BURST_R := 34.0           # 爆发半径(码)
var _mote_tex: Texture2D = null


func _mote(pos2d: Vector2, h: float, k: int) -> Sprite3D:
	if _mote_tex == null:
		_mote_tex = load(MOTE_TEX)
	var sp := Sprite3D.new()
	sp.texture = _mote_tex
	sp.hframes = MOTE_FRAMES
	sp.frame = k % MOTE_FRAMES
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.transparent = true
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.no_depth_test = true          # 粒子是「两个单位之间」的关系, 被立绘挡住就读不出来了
	sp.render_priority = 7
	sp.pixel_size = (MOTE_YARDS * battle.WS) / float(maxi(1, int(_mote_tex.get_width()) / MOTE_FRAMES))
	sp.position = battle._world_pos(pos2d, h)
	battle._world.add_child(sp)
	return sp


## 从 `from2d`(被汲取的目标) 抽一道绿色粒子波纹, 飘舞着飞到 `to2d`(携带者), 到达时爆发。
func drain_stream(from2d: Vector2, to2d: Vector2) -> void:
	var dir: Vector2 = (to2d - from2d)
	if dir.length() < 1.0:
		dir = Vector2(1.0, 0.0)
	var perp: Vector2 = dir.orthogonal().normalized()
	for i in range(DRAIN_N):
		var t01: float = float(i) / float(maxi(1, DRAIN_N - 1))
		var sp: Sprite3D = _mote(from2d, 0.55 + 0.5 * t01, i)
		sp.modulate = Color(1, 1, 1, 0)
		## ① 抽取: 先从目标身上「挣」出来一点(朝外, 带一点随机散开)
		var out2: Vector2 = from2d - dir.normalized() * 16.0 + perp * (t01 - 0.5) * 34.0
		## ② 飘舞: 路径中点往垂直方向甩开, 左右交替 ⇒ 一串粒子读成波纹而不是直线
		var swing: float = DRAIN_WAVE * (1.0 if i % 2 == 0 else -1.0) * (0.55 + 0.45 * t01)
		var mid2: Vector2 = from2d.lerp(to2d, 0.5) + perp * swing
		var d: float = float(i) * DRAIN_STAGGER
		var tw: Tween = battle._reg_tween().bind_node(sp)
		tw.tween_interval(d)
		tw.tween_property(sp, "position", battle._world_pos(out2, 0.75), DRAIN_PULL)
		tw.tween_property(sp, "position", battle._world_pos(mid2, 1.15), DRAIN_T * 0.5) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(sp, "position", battle._world_pos(to2d, 0.85), DRAIN_T * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(sp.queue_free)
		## alpha 单独一条链: 淡入 → **满亮占住整个飞行段** → 到达才收
		##   (memory [[fb-vfx-defect-families]] 头一条「淡出病」: 不许一出生就淡)
		var tf: Tween = battle._reg_tween().bind_node(sp)
		tf.tween_interval(d)
		tf.tween_property(sp, "modulate", Color(1, 1, 1, 1), 0.04)   # ★淡入越短越亮: 0.07 时大半路程还在半透
		tf.tween_interval(DRAIN_PULL + DRAIN_T - 0.04)
		tf.tween_property(sp, "modulate", Color(1, 1, 1, 0), 0.06)
	## ④ 到达: 携带者身上绿色粒子爆发(等最后一粒飞到才开)
	var bt: Tween = battle._reg_tween()
	bt.tween_interval(float(DRAIN_N - 1) * DRAIN_STAGGER + DRAIN_PULL + DRAIN_T * 0.82)
	bt.tween_callback(func() -> void: _drain_burst(to2d))


## ④ 携带者身上的绿色粒子爆发。
func _drain_burst(at2d: Vector2) -> void:
	if not is_instance_valid(battle) or not is_instance_valid(battle._world):
		return
	for i in range(BURST_N):
		var ang: float = TAU * float(i) / float(BURST_N) + 0.3
		var sp: Sprite3D = _mote(at2d, 0.8, i)
		var to2: Vector2 = at2d + Vector2(cos(ang), sin(ang)) * BURST_R
		var tw: Tween = battle._reg_tween().bind_node(sp)
		tw.tween_property(sp, "position", battle._world_pos(to2, 1.05), BURST_T) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(sp.queue_free)
		var tf: Tween = battle._reg_tween().bind_node(sp)
		tf.tween_interval(BURST_T * 0.62)        # ★前 62% 满亮, 之后才淡
		tf.tween_property(sp, "modulate", Color(1, 1, 1, 0), BURST_T * 0.38)


## ══════════════════════════════════════════════════════════════════════
##  【治疗】身上冒绿光 + 绿粒子 —— 用户 2026-09-12 看 019 海葵药膏之后定的
## ══════════════════════════════════════════════════════════════════════
## 他的原话:「**应该要身上冒绿光和绿粒子，但不要复用**」
##
## 被否的是「治疗只有脚下一圈淡绿地环 + 一个飘字」——
## **治疗这个动作在画面上读不出来**(和 015 的反伤同类: 文案写了、画面读不出)。
##
## ★★挂在哪: **只有 019**(`equip_tick_system._tick_anemone`), 携带者自己 + 被奶的那只友军。
##   我一度挂在 `battle_damage._heal_flush()` —— 那是 `_heal` 全仓 **80 个调用点**的中央收口,
##   等于全游戏所有治疗(装备/技能/羁绊/食物/温泉蛋/不沉之锚…)一起换了演出。用户当场否:
##     「**我只让你对019做这次的绿光和绿粒子，你不对把其他的也全用了吧**」
##   ⇒ 已收回。**范围由需求定, 不由我推广。**
##   ★这条和 memory [[fb-fix-the-shared-primitive-not-one-instance]] 不矛盾:
##     那条说的是「用户**否掉**某个共享原语时别只改一件」; 这次他没有否原语,
##     他是给 019 **加了一个新演出**。两种情形的范围判断刚好相反, 别混。
##
## ★「不要复用」是铁律([[fb-no-asset-reuse-unless-told]]) ⇒ 两张都是新烤的,
##   而且和 014 汲取的粒子**形状与色相都拉开**:
##     · 014 汲取 = 四芒星(尖) · `life` 板正绿    —— 「夺」
##     · 019 治疗 = 圆药滴(圆) · `jade` 板薄荷青  —— 「给」
##
## ★尺寸按【屏幕像素】反算(实测 1 屏幕像素 = 0.0426 m, 染色法量的):
##     光束 48px 一格 ⇒ 2.045 m ≈ 一个龟高 ⇒ pixel_size 0.0426 = 1 texel : 1 屏幕像素
##     药滴 10px 一格 ⇒ 0.426 m ≈ 1/5 个龟高 ⇒ 同样 1:1
const HEAL_PLUME_TEX := "res://assets/sprites/vfx/heal-plume.png"
const HEAL_PLUME_FRAMES := 6
const HEAL_PLUME_FPS := 15.0          # 6 帧 / 15fps = 0.40 秒
const HEAL_PLUME_YARDS := 85.2        # 48 texel × 0.0426 m ÷ WS
const HEAL_PLUME_H := 1.02            # 贴图中心抬到这个高度 ⇒ 光束底边正好落在脚下
const HEAL_PLUME_HOLD := 0.30         # ★先满亮再淡(治「淡出病」: 一出生就淡会读成一团灰)
const HEAL_PLUME_FADE := 0.10
const HEAL_DROP_TEX := "res://assets/sprites/vfx/heal-drop.png"
const HEAL_DROP_FRAMES := 4
const HEAL_DROP_YARDS := 17.75        # 10 texel × 0.0426 m ÷ WS
const HEAL_DROP_N := 5                # 一次冒几粒
const HEAL_DROP_RISE := 46.0          # 往上飘多少码
const HEAL_DROP_SPREAD := 22.0        # 左右散开(码)
const HEAL_DROP_T := 0.50
var _heal_plume_tex: Texture2D = null
var _heal_drop_tex: Texture2D = null


## 被治疗的单位身上冒绿光 + 绿粒子。由 `battle_damage._heal_flush()` 在弹绿字时调。
func heal_burst(u: Dictionary) -> void:
	if battle._world == null or u == null or not u.get("alive", false):
		return
	if _heal_plume_tex == null:
		_heal_plume_tex = load(HEAL_PLUME_TEX)
	if _heal_drop_tex == null:
		_heal_drop_tex = load(HEAL_DROP_TEX)
	if _heal_plume_tex == null or _heal_drop_tex == null:
		return                              # 素材没 import 就静默跳过, 不崩战斗
	_heal_plume(u)
	_heal_drops(u)


## ① 绿光: 从脚下升起、裹住单位的一束光。**加色混合** —— 暗像素不贡献,
##   所以它叠在龟身上 = 龟被照亮, 黑背景仍是黑的, 这才是「身上冒绿光」的物理读法。
func _heal_plume(u: Dictionary) -> void:
	var cell: int = maxi(1, int(_heal_plume_tex.get_width()) / HEAL_PLUME_FRAMES)
	var sp := Sprite3D.new()
	sp.texture = _heal_plume_tex
	sp.hframes = HEAL_PLUME_FRAMES
	sp.frame = 0
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.transparent = true
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.pixel_size = (HEAL_PLUME_YARDS * battle.WS) / float(cell)
	sp.render_priority = 5
	## ★自己搭材质才设得上 BLEND_MODE_ADD: Sprite3D 的 billboard/modulate/filter 都是喂给
	##   **内部材质**的, material_override 会把内部材质整个替掉 ⇒ 这几样要在材质上再设一遍。
	##   帧选择不受影响(hframes 改的是网格 UV, 覆盖材质照样采到对的那一格)。
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _heal_plume_tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sp.material_override = mat
	sp.position = battle._world_pos(u["pos"] as Vector2, float(u.get("height", 0.0)) + HEAL_PLUME_H)
	battle._world.add_child(sp)
	## 跟着单位走 + 按【游戏钟】切帧, 放完自销(不用 tween: tween 走未钳制 delta = 第二条钟)
	battle._follow_vfx.append({
		"spr": sp, "unit": u, "h": HEAL_PLUME_H,
		"anim_fps": HEAL_PLUME_FPS, "anim_n": HEAL_PLUME_FRAMES, "anim_t0": battle._t,
	})
	## ★alpha 单独一条: **先满亮 hold 再淡** —— memory [[fb-vfx-defect-families]] 头一条
	##   「淡出病」: 短命特效一出生就线性淡出, 实拍读成一团灰。
	var tf: Tween = battle._reg_tween().bind_node(sp)
	tf.tween_interval(HEAL_PLUME_HOLD)
	tf.tween_property(sp, "modulate", Color(1, 1, 1, 0), HEAL_PLUME_FADE)


## ② 绿粒子: 几粒圆药滴从脚下往上飘。
func _heal_drops(u: Dictionary) -> void:
	var cell: int = maxi(1, int(_heal_drop_tex.get_width()) / HEAL_DROP_FRAMES)
	var ps: float = (HEAL_DROP_YARDS * battle.WS) / float(cell)
	var base: Vector2 = u["pos"] as Vector2
	var h0: float = float(u.get("height", 0.0))
	for i in range(HEAL_DROP_N):
		var t01: float = float(i) / float(maxi(1, HEAL_DROP_N - 1))
		var sp := Sprite3D.new()
		sp.texture = _heal_drop_tex
		sp.hframes = HEAL_DROP_FRAMES
		sp.frame = i % HEAL_DROP_FRAMES
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false
		sp.transparent = true
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.no_depth_test = true          # 被立绘挡住就读不出来了
		sp.render_priority = 8
		sp.pixel_size = ps
		var dx: float = (t01 - 0.5) * 2.0 * HEAL_DROP_SPREAD
		var p0: Vector2 = base + Vector2(dx, 0.0)
		sp.position = battle._world_pos(p0, h0 + 0.10)
		battle._world.add_child(sp)
		var d: float = t01 * 0.10          # 错开出发 ⇒ 读成「一串往上冒」而不是同时一坨
		var rise: float = (HEAL_DROP_RISE * (0.7 + 0.6 * t01)) * battle.WS
		var tw: Tween = battle._reg_tween().bind_node(sp)
		tw.tween_interval(d)
		var dst: Vector3 = battle._world_pos(p0 + Vector2(dx * 0.35, 0.0), h0 + 0.10 + rise)
		tw.tween_property(sp, "position", dst, HEAL_DROP_T).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_callback(sp.queue_free)
		var tf: Tween = battle._reg_tween().bind_node(sp)
		tf.tween_interval(d + HEAL_DROP_T * 0.62)      # ★前 62% 满亮, 之后才淡
		tf.tween_property(sp, "modulate", Color(1, 1, 1, 0), HEAL_DROP_T * 0.38)

## 021 绑定绳的珠子。尺寸按**屏幕像素**反算: 实测 1 屏幕像素 = 0.0426 m
## ⇒ 8 texel 一格 × 0.0426 = 0.341 m, pixel_size 恰好 1 texel : 1 屏幕像素。
const BIND_BEAD_TEX := "res://assets/sprites/vfx/bind-bead.png"
const BIND_BEAD_FRAMES := 4
## ★★按【2026 现版】重定(第一次量的是 2013 那版, 粗了 5 倍 —— 见 blender_bindbead 头注):
##   现版线粗只占角色高 **约 8%**; 我们的龟 ≈45 屏幕像素高 ⇒ 目标 **≈4 屏幕像素**。
const BIND_BEAD_M := 0.170      # 一片的边长(米) = 4 屏幕像素; 加泛光后屏上约 5px, 对上参考
## ★片距只有片径的 1/3 ⇒ 片与片**大幅重叠** ⇒ 读成一条**连续的粗光带**, 不是一串珠子。
##   用户原话:「不要用什么规则图案敷衍我」—— 等距可辨的小珠子就是规则图案。
## ★★片距再减半的理由(1:1 实拍看出来的): 0.28 时**白热芯被相邻片遮住**, 只剩零星亮点,
##   整条带读成一片平的绿。芯直径 = 0.42 × 0.852 = 0.358 m ⇒ 片距要小于它的一半,
##   芯才连成**一条连续的亮线** —— 那正是实测横截面里的白热芯(亮度 186)。
const BIND_GAP_M := 0.038       # 片距(米) —— 仍是片径的 ~1/4.5, 芯连成一条连续亮线
## ★★垂坠 = 0: **实测 LoL 那条线是直的**(峰值行离首尾直线最大偏离 6.6px / 132px = 5.0%)。
##   垂坠与摆动是我自己加的, 参考里根本没有 —— 「生硬」不是因为它直,
##   是因为它**细、没厚度、没层次**(我那版粗细只有龟高的 2%, 实测应是 47%)。
const BIND_SAG := 0.0           # 保留这个常量是为了让门禁能把它改坏来反向验证

const BIND_FLOW := 0.62         # 珠子沿绳流动速度(米/秒) ⇒ 看得出能量往被连的友军走
const BIND_H := 1.15            # 绳挂在单位身上的高度(米) —— 原来钉死 2.05 = 飘在头顶上方
var _bind_bead_tex: Texture2D = null

func barnacle_line(u: Dictionary, target) -> void:   # 守护贝母021: 携带者↔连接友军的持续绿色绑定线(每帧重绘跟随, 能量脉动α)
	var im = u.get("barnacle_line", null)
	if not (target is Dictionary) or not target.get("alive", false) or is_same(target, u) or not u.get("alive", false):   # is_same: 同上
		if is_instance_valid(im): im.visible = false
		return
	if not is_instance_valid(im):
		im = MeshInstance3D.new()
		im.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true   # 绑定线画在最上层(不被龟立绘遮挡)
		mat.vertex_color_use_as_albedo = true   # 顶点色驱动(照可显的_bolt_line)
		im.material_override = mat
		battle._world.add_child(im)
		u["barnacle_line"] = im
	im.visible = true
	_barnacle_rope(im, u, target)


## 021 的绑定绳: **一条粗光带**(密排的三层圆片), 沿带从携带者流向被连的友军。
## ★★2026-09-12 用户:「**这个线感觉生硬啊**」—— 他是对的, 根因在代码里一眼可见:
##   原来是 `PRIMITIVE_LINES` 画 **5 条平行的 1 像素裸 GPU 线**(无贴图)、**完全笔直**、
##   两端钉死在 2.05 m、除了 alpha 脉动之外**一帧都不动**。那是一根绷直的杆, 不是「绑定」。
## ★这与 v0.19.361 修过的 `_bolt_line`(1px 裸线)是**同一个毛病** —— 021 这一处是它自己的
##   一份手抄实现, 不走 bolt_line, 所以当时没被扫到。(memory fb-hand-rolled-copies-drift)
## ★★做法**照 LoL 卡尔玛【灵魂链接】的逐帧实测**, 不是我拿手感猜:
##     直不直 : 峰值行离首尾直线最大偏离 6.6px / 132px = **5.0%** ⇒ 直的
##     粗细   : 半高全宽 11px(芯) / 四分之一高全宽 19px(含晕) ⇒ 长:粗 = 7.4:1
##     横截面 : 白热芯(亮度 186) → 主体(173) → 外晕(105~130)
##     相对角色: 角色高 ~40px ⇒ **线粗 ≈ 角色高的 47%**
##   我第一版(被用户当场否的那个)是 8px 小珠子 + 我自己加的垂坠与摆动:
##   **粗细只有龟高的 2% —— 差 20 倍**, 而垂坠/摆动参考里根本没有。
##   ⇒ 现版: 20px 三层圆片(白芯/主体/外晕)、片距只有片径 1/3 **密排成一条连续的带**、
##     **不垂不摆**、沿带流动。
##   用户:「不要用什么规则图案敷衍我」—— 等距可辨的小珠子就是规则图案。
## ★珠子为什么是**圆**的: 像素风不许自由旋转(battle_ballistics.gd:675), 而绳的角度每帧都变;
##   **圆是旋转不变的** —— 形状是被约束逼出来的, 不是随手挑的。
func _barnacle_rope(im: MeshInstance3D, u: Dictionary, target: Dictionary) -> void:
	if _bind_bead_tex == null:
		_bind_bead_tex = load(BIND_BEAD_TEX)
	if _bind_bead_tex == null:
		return                                  # 素材没 import 就静默跳过, 不崩战斗
	var mat: StandardMaterial3D = im.material_override as StandardMaterial3D
	if mat != null and mat.albedo_texture != _bind_bead_tex:
		mat.albedo_texture = _bind_bead_tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素画, LINEAR 会糊
	var a: Vector3 = battle._world_pos(u["pos"] as Vector2, float(u.get("height", 0.0)) + BIND_H)
	var b: Vector3 = battle._world_pos(target["pos"] as Vector2, float(target.get("height", 0.0)) + BIND_H)
	var span: float = a.distance_to(b)
	if span < 0.05:
		return
	## 垂坠量随跨度走: 短绳几乎不垂, 长绳垂得多(真绳子就是这样)
	var sag: float = BIND_SAG * clampf(span / 3.0, 0.35, 1.8)
	var n: int = clampi(int(span / BIND_GAP_M), 3, 220)   # 片更小更密 ⇒ 上限再放宽
	## 流动相位走【游戏钟】(不是 tween: tween 走未钳制 delta = 第二条钟)
	var ph: float = fposmod(battle._t * BIND_FLOW / BIND_GAP_M, 1.0)
	var cam_r: Vector3 = Vector3.RIGHT
	var cam_u: Vector3 = Vector3.UP
	if is_instance_valid(battle._cam):
		var gx: Basis = battle._cam.global_transform.basis
		cam_r = gx.x
		cam_u = gx.y
	var h: float = BIND_BEAD_M * 0.5
	var pulse: float = 0.86 + 0.14 * sin(battle._t * 5.0)
	var col := Color(1.0, 1.0, 1.0, pulse)
	var imesh: ImmediateMesh = im.mesh
	imesh.clear_surfaces()
	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, im.material_override)
	for i in range(n + 1):
		var tt: float = (float(i) + ph) / float(n)
		if tt > 1.0:
			continue
		## 抛物线近似的悬链: 两端贴着单位, 中间往下垂
		var p: Vector3 = a.lerp(b, tt)
		p.y -= sag * 4.0 * tt * (1.0 - tt)
		## ★★摆动那两行**删了**(2026-09-12 反向验证抓到的): 它是沿【相机右向】偏的,
		##   而这条线本身就是横的 ⇒ 摆动把片沿着线自己的方向推, **根本不产生位移**。
		##   把 BIND_SWAY 改成 0.20 再跑门禁, **一条都不红** —— 不是判据松, 是那段代码本来就是死的。
		##   (参考实测里也没有摆动, 那是我凭手感加的。)
		## 4 帧里挑一格(珠子呼吸) —— 用序号挑, 相邻珠子不同帧 ⇒ 一串珠子不是死的
		var fr: int = i % BIND_BEAD_FRAMES
		var u0: float = float(fr) / float(BIND_BEAD_FRAMES)
		var u1: float = float(fr + 1) / float(BIND_BEAD_FRAMES)
		## 面朝相机的正方形(所以任意角度都不重采样 —— 同 bolt_line 的做法)
		var p0: Vector3 = p - cam_r * h - cam_u * h
		var p1: Vector3 = p + cam_r * h - cam_u * h
		var p2: Vector3 = p + cam_r * h + cam_u * h
		var p3: Vector3 = p - cam_r * h + cam_u * h
		imesh.surface_set_color(col); imesh.surface_set_uv(Vector2(u0, 1.0)); imesh.surface_add_vertex(p0)
		imesh.surface_set_color(col); imesh.surface_set_uv(Vector2(u1, 1.0)); imesh.surface_add_vertex(p1)
		imesh.surface_set_color(col); imesh.surface_set_uv(Vector2(u1, 0.0)); imesh.surface_add_vertex(p2)
		imesh.surface_set_color(col); imesh.surface_set_uv(Vector2(u0, 1.0)); imesh.surface_add_vertex(p0)
		imesh.surface_set_color(col); imesh.surface_set_uv(Vector2(u1, 0.0)); imesh.surface_add_vertex(p2)
		imesh.surface_set_color(col); imesh.surface_set_uv(Vector2(u0, 0.0)); imesh.surface_add_vertex(p3)
	imesh.surface_end()



## ══════════════════════════════════════════════════════════════════════
##  022 余烬燃油瓶【真火】—— 挂在目标身上的持续燃烧状态
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-09-12:「**022只需要做一个真火的特效**」「**真火是个buff你明白吗**」
## ⇒ 它是**状态**(EMBER_TRUEFIRE_SEC = 5 秒), 期间目标受到的灼烧改判真实伤害。
##   在此之前画面上**完全没有表现** —— 只有飘字从蓝变白。
##
## ★形态照实测参考做(「Burning knight - Real time VFX」, 上传 **2026-02-20**):
##   火高/角色高 = 1.5~1.7 · 火宽/角色高 = 1.6~2.1(火把人整个吞掉)
##   面积剖面下宽上尖 · 亮度最亮在中上部 · 橙白
##   ⇒ 素材 80×80 一格 = 3.41 m ≈ **1.7 个龟高**, pixel_size 0.0426 = 1 texel : 1 屏幕像素。
## ★★先看上传日期: 上一轮我拿了 2013 年的参考, 被用户当场抓。
# ══════════════════════════════════════════════════════════════════════
#  027 电棍 —— 就绪跳弧 + 命中落雷 (2026-09-13)
# ══════════════════════════════════════════════════════════════════════
## ★为什么新出两张素材, 而不是接着用 `electric-zap.png`(原来两处都用它):
##   ① 那张图【不是电】—— 五帧都是对称放射星爆(中心一颗白球 + 均匀放射线),
##      而 027 的文案从头到尾写的是「电棍 / 电击 / 眩晕」。
##      memory [[fb-effect-text-is-the-spec]]: 演出必须就是效果本身。
##   ② 它有【黑帧】—— 实测 frame4 均色 R18 G25 B34、近白像素 0 个, frame3 近白也只有 167 个,
##      而就绪火花用的是 `randi() % 5` ⇒ **五帧里两帧是黑的, 40% 的火花在黑场里读成污渍**
##      (我在 3.25s 那一帧亲眼看到那团灰)。
##   ③ 它还被赛博侵入 / 雷电龟 / 026 共 5 处在用 ⇒ 改它会连坐
##      (memory [[fb-no-asset-reuse-unless-told]]: 新内容一律新素材)。
## ★尺寸按【整数倍】缩放(像素风硬约束): 1 texel = 0.0426 m, 两张都按 1× 摆。
##   · 跳弧 24 texel = 1.02 m ≈ 0.51 个龟高 —— 就绪态本来就该是小火花, 不该盖住龟。
##   · 落雷 56 texel = 2.39 m ≈ 1.2 个龟高 —— 单体判定, 演出就只罩住被打的那一个。
## ★两个都挂 `_follow_vfx`(游戏钟自推进帧 + 跟着单位走), **不用 tween** ——
##   tween 走未钳制真实 delta, 与游戏钟是两条钟(memory [[fb-second-clock-drops-events]])。
## ══════════════════════════════════════════════════════════════════════
##  【冰寒】持续期的身上标记 (2026-09-13)
## ══════════════════════════════════════════════════════════════════════
## ★为什么要有: 028 的文案写「施加冰寒 5 秒(移速 -20% / 攻速 -10%)」——
##   这是个**持续 5 秒的状态**, 而逐帧看下来画面上**零提示**: 砸中之后目标身上什么都没有,
##   玩家读不出"它被冻慢了"。文案写了画面读不出, 也是缺陷(memory [[fb-effect-text-is-the-spec]])。
## ★★挂在**状态字段**上而不是挂在 028 里 —— 与 022 真火同一个做法:
##   判据是 `battle._t < u["spd_dbf_until"]`, 于是**以后任何**写这个字段的来源
##   (冰龟登场光环、别的减速件…)都自动带上标记, 不用再接一次线
##   (memory [[fb-zero-caller-is-a-whole-class]]: 「写了没人读」是一整类)。
const CHILL_TEX := "res://assets/sprites/vfx/frost-chill.png"
const CHILL_FRAMES := 6
const CHILL_FPS := 8.0            # 6 帧 / 8fps = 0.75 秒一轮呼吸
## ★用户 2026-09-13 两句: 先说「挂着霜需要大 2 倍」, 看过之后改口
##   「感觉不是这样放大, 而是**加更多粒子**」。
##   ⇒ 覆盖面保持放大后的那么大, 但**不是把单粒放大** —— 贴图格子从 20 扩到 40 texel、
##     里面塞 9 粒小冰晶(原来 3 粒), 仍按 **1× 整数倍**摆(1 texel = 1 屏幕像素, 不糊)。
##   40 texel × 0.0426 m ÷ WS = 1.70 m ≈ 0.85 个龟高。
const CHILL_YARDS := 71.0
const CHILL_H := 1.15             # 放大 2 倍后同步抬高一点, 免得下缘扎进地里
var _chill_tex: Texture2D = null


func chill_mark(u: Dictionary) -> void:
	if battle._world == null or u == null or not u.get("alive", false):
		return
	if is_instance_valid(u.get("_chill_spr", null)):
		return                          # 已经挂着 ⇒ 续时间由 spd_dbf_until 自己管
	if _chill_tex == null:
		_chill_tex = load(CHILL_TEX)
	if _chill_tex == null:
		return
	var cell: int = maxi(1, int(_chill_tex.get_width()) / CHILL_FRAMES)
	var sp := Sprite3D.new()
	sp.texture = _chill_tex
	sp.hframes = CHILL_FRAMES
	sp.frame = 0
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.transparent = true
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.no_depth_test = true
	sp.render_priority = 5
	sp.pixel_size = (CHILL_YARDS * battle.WS) / float(cell)
	sp.position = battle._world_pos(u["pos"] as Vector2, float(u.get("height", 0.0)) + CHILL_H)
	battle._world.add_child(sp)
	u["_chill_spr"] = sp
	battle._follow_vfx.append({
		"spr": sp, "unit": u, "h": CHILL_H,
		"loop_fps": CHILL_FPS, "loop_n": CHILL_FRAMES,
		"loop_t0": battle._t, "until_key": "spd_dbf_until",
		"clear_key": "_chill_spr",
	})


## 【027 眩晕期间挂在被电中目标身上的持续电击】(用户 2026-09-13 点名)
## ★与就绪跳弧 `baton-arc` 刻意做成两个样子: 就绪是零星短弧, 中电是顺着身体上下窜的长弧 ——
##   一眼要能分出「他蓄好了」和「它被电住了」。
## ★判据挂在 `baton_zap_until` 这个**只属于 027** 的时间戳上(不挂通用 `stun_until`,
##   否则全游戏任何来源的眩晕都会带电弧)。与 022 真火 / 028 冰寒同一个原语。
const ZAP_TEX := "res://assets/sprites/vfx/baton-shock.png"
const ZAP_FRAMES := 6
const ZAP_FPS := 14.0             # 6 帧 / 14fps = 0.43 秒一轮, 3 秒眩晕转 7 轮
const ZAP_YARDS := 42.6           # 24 texel × 0.0426 m ÷ WS = 1.02 m ≈ 0.51 个龟高
const ZAP_H := 0.95
var _zap_tex: Texture2D = null


func baton_zap_mark(u: Dictionary) -> void:
	if battle._world == null or u == null or not u.get("alive", false):
		return
	if is_instance_valid(u.get("_baton_zap_spr", null)):
		return                          # 已经挂着 ⇒ 续时间由 baton_zap_until 自己管
	if _zap_tex == null:
		_zap_tex = load(ZAP_TEX)
	if _zap_tex == null:
		return
	var sp := _sheet_sprite(_zap_tex, ZAP_FRAMES, ZAP_YARDS)
	sp.render_priority = 8
	sp.position = battle._world_pos(u["pos"] as Vector2, float(u.get("height", 0.0)) + ZAP_H)
	battle._world.add_child(sp)
	u["_baton_zap_spr"] = sp
	battle._follow_vfx.append({
		"spr": sp, "unit": u, "h": ZAP_H,
		"loop_fps": ZAP_FPS, "loop_n": ZAP_FRAMES,
		"loop_t0": battle._t, "until_key": "baton_zap_until",
		"clear_key": "_baton_zap_spr",
	})


const BATON_ARC_TEX := "res://assets/sprites/vfx/baton-arc.png"
const BATON_ARC_FRAMES := 8
const BATON_ARC_YARDS := 42.6     # 24 texel × 0.0426 m ÷ WS = 1.02 m ≈ 0.51 个龟高
const BATON_ARC_FPS := 30.0       # 8 帧 / 30fps = 0.27 秒一次跳弧
const BATON_STRIKE_TEX := "res://assets/sprites/vfx/baton-strike.png"
const BATON_STRIKE_FRAMES := 8
const BATON_STRIKE_YARDS := 99.4  # 56 texel × 0.0426 m ÷ WS
const BATON_STRIKE_FPS := 24.0    # 8 帧 / 24fps = 0.33 秒一次放电
## 落雷贴图里【触地点】在格子从上往下 0.62 处 ⇒ 想让触地点落在目标身上 0.90 m,
## 精灵中心要抬到 0.90 + (0.62 − 0.5) × 2.386 = 1.19 m。
const BATON_STRIKE_H := 1.19
var _baton_arc_tex: Texture2D = null
var _baton_strike_tex: Texture2D = null


## 精灵表 → Sprite3D 的共享原语(027 电棍先用的, 034 大熊土浪也用它 ⇒ 名字从 `_baton_` 改成中性)。
func _sheet_sprite(tex: Texture2D, frames: int, yards: float) -> Sprite3D:
	var cell: int = maxi(1, int(tex.get_width()) / frames)
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.hframes = frames
	sp.frame = 0
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.transparent = true
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # ★Sprite3D 默认是 3=LINEAR_WITH_MIPMAPS, 不写就糊
	sp.no_depth_test = true
	sp.render_priority = 7
	sp.pixel_size = (yards * battle.WS) / float(cell)
	return sp


## 就绪态: 棍身上噼啪跳的短弧(每 0.16 秒一次, 由 `EquipTickSystem._tick_baton` 排)
func baton_spark(u: Dictionary) -> void:
	if battle._world == null or u == null or not u.get("alive", false):
		return
	if _baton_arc_tex == null:
		_baton_arc_tex = load(BATON_ARC_TEX)
	if _baton_arc_tex == null:
		return
	var sp := _sheet_sprite(_baton_arc_tex, BATON_ARC_FRAMES, BATON_ARC_YARDS)
	## 抖在【身上】不是脚下 —— 原来 height 抽 0.45~1.1 且 y 也抖 ±12 码, 一半的火花落在地上,
	## 读成「地上冒火星」而不是「他手里那根棍带电了」。
	var h: float = 0.80 + randf_range(-0.12, 0.34)
	sp.position = battle._world_pos(u["pos"] + Vector2(randf_range(-10.0, 10.0), randf_range(-6.0, 6.0)), h)
	battle._world.add_child(sp)
	battle._follow_vfx.append({
		"spr": sp, "unit": u, "h": h,
		"anim_fps": BATON_ARC_FPS, "anim_n": BATON_ARC_FRAMES, "anim_t0": battle._t,
	})


## 命中态: 一道落雷劈在**被打中的那一个**目标身上(027 是单体判定, 演出就只罩它)
func baton_strike(tgt: Dictionary) -> void:
	if battle._world == null or tgt == null or not tgt.get("alive", false):
		return
	if _baton_strike_tex == null:
		_baton_strike_tex = load(BATON_STRIKE_TEX)
	if _baton_strike_tex == null:
		return
	var sp := _sheet_sprite(_baton_strike_tex, BATON_STRIKE_FRAMES, BATON_STRIKE_YARDS)
	sp.position = battle._world_pos(tgt["pos"], float(tgt.get("height", 0.0)) + BATON_STRIKE_H)
	battle._world.add_child(sp)
	battle._follow_vfx.append({
		"spr": sp, "unit": tgt, "h": BATON_STRIKE_H,
		"anim_fps": BATON_STRIKE_FPS, "anim_n": BATON_STRIKE_FRAMES, "anim_t0": battle._t,
	})


const TRUEFIRE_TEX := "res://assets/sprites/vfx/true-fire.png"
const TRUEFIRE_FRAMES := 8
const TRUEFIRE_FPS := 12.0        # 8 帧 / 12fps = 0.67 秒一轮, 5 秒烧 7.5 轮
const TRUEFIRE_YARDS := 142.0     # 80 texel × 0.0426 m ÷ WS = 3.41 m ≈ 1.7 龟高
## ★★贴图中心高度 = **半格**(80 texel / 2 × 0.0426 = 1.704) ⇒ 火底正好齐脚。
##   原值 1.30 是我拍的, 探针读真实 AABB 量出来**火底在脚下 -0.404 m** ——
##   黑场台子上看不出来(地面是纯黑), 但到真实地图、或单位被击飞抬高时火根会穿地。
##   ★连带的真缺陷: 沉下去 0.40 m 之后**露出地面的火只有 1.33~1.42 龟高**,
##     低于参考实测的 1.5~1.7 —— 而门禁 ④ 量的是【贴图高】不是【露出地面的高】,
##     所以它一直绿着(判据量的不是需求, memory [[fb-judge-must-fit-the-shape]])。
##   素材画到了格子最底行, 所以「格底齐脚」= 「火底齐脚」。
const TRUEFIRE_H := 1.704
var _truefire_tex: Texture2D = null


## 给 `u` 挂上真火(持续到 `u["true_fire_until"]`)。已经挂着就不重复挂, 只续时间。
func true_fire_aura(u: Dictionary) -> void:
	if battle._world == null or u == null or not u.get("alive", false):
		return
	if is_instance_valid(u.get("_truefire_spr", null)):
		return                              # 已在烧 ⇒ 续时间由 true_fire_until 自己管
	if _truefire_tex == null:
		_truefire_tex = load(TRUEFIRE_TEX)
	if _truefire_tex == null:
		return                              # 素材没 import 就静默跳过, 不崩战斗
	var cell: int = maxi(1, int(_truefire_tex.get_width()) / TRUEFIRE_FRAMES)
	var sp := Sprite3D.new()
	sp.texture = _truefire_tex
	sp.hframes = TRUEFIRE_FRAMES
	sp.frame = 0
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.transparent = true
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.no_depth_test = true          # 火要压在立绘上, 被挡住就读不出「这只在烧」
	sp.render_priority = 6
	sp.pixel_size = (TRUEFIRE_YARDS * battle.WS) / float(cell)
	sp.position = battle._world_pos(u["pos"] as Vector2, float(u.get("height", 0.0)) + TRUEFIRE_H)
	battle._world.add_child(sp)
	u["_truefire_spr"] = sp
	## 跟着单位走 + 按【游戏钟】循环切帧, 到期自销(不用 tween: tween 走未钳制 delta = 第二条钟)
	battle._follow_vfx.append({
		"spr": sp, "unit": u, "h": TRUEFIRE_H,
		"loop_fps": TRUEFIRE_FPS, "loop_n": TRUEFIRE_FRAMES,
		"loop_t0": battle._t, "until_key": "true_fire_until",
		"clear_key": "_truefire_spr",
	})

## 竹叶生命球落点的爆散(从主文件搬来 —— 纯演出, CLAUDE.md §5 该住这儿)
func bamboo_burst(pos2d: Vector2) -> void:
	var bpath := "res://assets/sprites/vfx/bamboo-charge-burst.png"
	if not ResourceLoader.exists(bpath):
		return
	var tex: Texture2D = load(bpath)
	var fh: int = maxi(1, tex.get_height())
	var nframes: int = maxi(1, int(tex.get_width() / fh))
	var b := Sprite3D.new()
	b.texture = tex
	b.hframes = nframes
	b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	b.shaded = false
	b.transparent = true
	b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	b.pixel_size = 1.3 / float(fh)
	b.position = battle._world_pos(pos2d, 1.0)
	battle._world.add_child(b)
	var tw = battle._reg_tween()   # battle 无类型 ⇒ := 推不出来
	tw.tween_method(battle._bamboo_sys._bamboo_burst_step.bind(b, nframes), 0.0, 1.0, 0.35)
	tw.tween_callback(b.queue_free)


# ════════════════════════════════════════════════════════════════════════════
#  034 玩偶小熊 · 大熊【冲击波】—— 2026-09-13 用户:「这个大熊冲击波的特效不好, 你得重做」
# ════════════════════════════════════════════════════════════════════════════
## 重做前实拍(16 帧逐帧看过)读出来的四条毛病, 每条对应下面一处改动:
##   ① **根本没有波前** —— 原来全场只有 `gold-chunk` 一簇簇随机冒、横向散 ±26/±55 码,
##      拼不出一条线, 读成"地上插了一排蜡烛"。⇒ 改成一排**土浪**沿 perp 铺开同步推进。
##   ② 脚下一个又大又细的黄色椭圆环(`_skill_ring`)挂几秒 = 无含义圆环(禁区)。⇒ 删。
##   ③ 前摇那颗 `VfxTex._make_fire_glow_tex()` 程序光球 —— 同一类禁区。⇒ 换成破土预兆。
##   ④ 金块一出生就淡出, 中段在黑场里读成深褐柱子(淡出病)。⇒ 碎石只在波前冒、短命、不早淡。
##
## ★方向不靠旋转(像素风不许自由旋转): 照 043 浪墙的老办法 —— 一排**直立 billboard**
##   沿 perp 铺开、沿 dir 平移, 朝向只用 `flip_h`。
const QUAKE_ERUPT_TEX := "res://assets/sprites/vfx/bear-quake-erupt.png"
const QUAKE_ERUPT_FRAMES := 8
const QUAKE_ERUPT_FPS := 17.0     # 8 帧 / 17fps = 0.47 秒一次"鼓起→崩解"
const QUAKE_ERUPT_YARDS := 78.1   # 44 texel × 1.775 码/texel —— 1:1 不缩放
const QUAKE_ERUPT_H := 0.72       # 土刺中心离地(米); 刺高 42 texel × 0.0426 = 1.79 m
const QUAKE_TELL_TEX := "res://assets/sprites/vfx/bear-quake-tell.png"
const QUAKE_TELL_FRAMES := 5
const QUAKE_TELL_FPS := 16.0
const QUAKE_TELL_YARDS := 49.8    # 14 texel × 1.775 × **2 倍整数缩放** —— 1× 时只有 13 屏幕像素,
                                  #   实拍里几乎看不见; 整数倍是像素风允许的放大方式
const QUAKE_TELL_H := 0.30
var _quake_erupt_tex: Texture2D = null
var _quake_tell_tex: Texture2D = null


## 一处破土隆起 —— **原地**播一次"鼓起→顶到最高→崩解"。
## ★★用户 2026-09-13 第二轮:「不如原版啊, 不是一个墙飞过去啊, 是一段段地突起啊动画」。
##   我上一版做成了"一整面土墙平移" —— 那把**概念**也换掉了。原版的概念(沿途一段段破土)
##   是对的, 坏的只是执行。⇒ 回到逐段隆起: 由 `EquipTickSystem` 按波前位置一段一段地点,
##   方向感来自【点的顺序】, 不来自平移。
## ★左右对称的刺 ⇒ 不 flip 不旋转, 像素风三条约束天然满足。
func bear_quake_erupt(at2d: Vector2) -> void:
	if battle._world == null:
		return
	if _quake_erupt_tex == null:
		_quake_erupt_tex = load(QUAKE_ERUPT_TEX)
	if _quake_erupt_tex == null:
		return                            # 缺图就不画, 不拿别的图顶替(素材不复用铁律)
	var sp := _sheet_sprite(_quake_erupt_tex, QUAKE_ERUPT_FRAMES, QUAKE_ERUPT_YARDS)
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y   # 土刺是立在地上的, 不跟着俯仰翻
	sp.render_priority = 6
	sp.position = battle._world_pos(at2d, QUAKE_ERUPT_H)
	battle._world.add_child(sp)
	## 走 `_anim_fx`(游戏钟逐帧, 放完自销) —— 不挂 tween: tween 走未钳制真实 delta。
	battle._anim_fx.append({
		"spr": sp, "fps": QUAKE_ERUPT_FPS, "n": QUAKE_ERUPT_FRAMES, "t0": battle._t,
	})


## 破土预兆: 波会经过的那条线上, 一节一节往外冒的小土喷。
## ★它带的信息量 = 波的**路径与射程**(摆到哪、摆几节), 不是"一个更漂亮的闪光"。
func bear_quake_tell(at2d: Vector2) -> void:
	if battle._world == null:
		return
	if _quake_tell_tex == null:
		_quake_tell_tex = load(QUAKE_TELL_TEX)
	if _quake_tell_tex == null:
		return
	var sp := _sheet_sprite(_quake_tell_tex, QUAKE_TELL_FRAMES, QUAKE_TELL_YARDS)
	sp.render_priority = 5
	sp.position = battle._world_pos(at2d, QUAKE_TELL_H)
	battle._world.add_child(sp)
	## 走 `_anim_fx`(游戏钟逐帧) —— 不挂 tween: tween 走未钳制真实 delta, 无头下推不动。
	battle._anim_fx.append({
		"spr": sp, "fps": QUAKE_TELL_FPS, "n": QUAKE_TELL_FRAMES, "t0": battle._t,
	})


# ════════════════════════════════════════════════════════════════════════════
#  041 退潮浊液 · 涨潮 / 退潮
# ════════════════════════════════════════════════════════════════════════════
## 实拍(13 帧逐帧看过)读出来的原状: 两圈**程序生成的圆环**(`_skill_ring` +
## `_splash_ring_bold`)罩在龟身上, 外加 11 颗 `VfxTex._make_fire_glow_tex()` **白球**
## 四散上浮 —— 圆环与白球都在禁区里, 而且那 11 颗写的是 `TEXTURE_FILTER_LINEAR`,
## **连像素风都不是**, 实拍就是一团糊。文案的「体积 +30%」在那团糊里根本读不出来。
## ⇒ 换成一圈**从脚下窜起来的水柱**(涨潮) / **沉下去的水柱**(退潮)。
const TIDE_TEX := "res://assets/sprites/vfx/tide-swell.png"
const TIDE_FRAMES := 12           # 0~5 涨 / 6~11 退(同一件效果的两个方向)
const TIDE_CLIP := 6
const TIDE_FPS := 13.0
const TIDE_YARDS := 35.5          # 20 texel × 1.775 码/texel —— 1:1 不缩放
const TIDE_H := 0.60
var _tide_tex: Texture2D = null


func tide_swell(at2d: Vector2, rising: bool, t_delay: float) -> void:
	if battle._world == null:
		return
	if _tide_tex == null:
		_tide_tex = load(TIDE_TEX)
	if _tide_tex == null:
		return                            # 缺图就不画, 不拿别的图顶替(素材不复用铁律)
	var sp := _sheet_sprite(_tide_tex, TIDE_FRAMES, TIDE_YARDS)
	sp.frame = 0 if rising else TIDE_CLIP
	sp.render_priority = 5
	sp.position = battle._world_pos(at2d, TIDE_H)
	battle._world.add_child(sp)
	## 走 `_anim_fx`(游戏钟逐帧, 放完自销); `t0` 往后推 = 一根一根错峰窜起来。
	battle._anim_fx.append({
		"spr": sp, "fps": TIDE_FPS, "n": TIDE_CLIP, "t0": battle._t + t_delay,
		"base": 0 if rising else TIDE_CLIP,
	})


# ════════════════════════════════════════════════════════════════════════════
#  035 黄铜齿轮 · 进账深海币 —— 头顶旋转金币
# ════════════════════════════════════════════════════════════════════════════
## 用户 2026-09-13:「这最好做一个头顶获得金币旋转的特效吧, 我也说不清,
##   你搜搜网上 blender 有没有例子, 照着做一板板」。
## ★参考是真找了真量了(OpenGameArt CC0 "Spinning Coin Sprites", 16 帧 × 32×32, **只量不用**),
##   逐帧量出宽度包络再重采样到 12 帧 —— 详见 `tools/bake_coin_spin.py` 的头注。
##   两条细节是纯 cos 给不出的: 正面**多停 2 帧**、侧面最窄**不为 0**(那是币的厚度)。
const COIN_TEX := "res://assets/sprites/vfx/deepsea-coin-spin.png"
const COIN_FRAMES := 12
const COIN_FPS := 16.0            # 12 帧 / 16fps = 0.75 秒转一圈
const COIN_YARDS := 32.0          # 18 texel × 1.775 码/texel
const COIN_H0 := 2.85             # 起始高度(米) —— 实拍第一版给 1.55, 金币压在龟壳中间
                                  #   而需求原话是「**头顶**获得金币旋转」; 龟高 2.0 m + 血条那一行 ⇒ 抬到 2.85 才真的在头顶上方
const COIN_RISE := 0.55           # 往上飘多少米
const COIN_LIFE := 1.05           # 存活(秒) —— 转一圈半
var _coin_tex: Texture2D = null


## 在 `u` 头顶生出 `n` 枚旋转金币(横向排开, 逐枚错峰), 边转边往上飘。
## ★不挂 tween: tween 走未钳制真实 delta。走 `_follow_vfx` 的**位置+循环帧**通道,
##   由 `battle_render` 每帧按游戏钟推 —— 与 `coin_until` 一起过期自销。
func coin_pop(u: Dictionary, n: int) -> void:
	if battle._world == null or u == null or not u.get("alive", false):
		return
	if _coin_tex == null:
		_coin_tex = load(COIN_TEX)
	if _coin_tex == null:
		return                            # 缺图就不画, 不拿别的图顶替(素材不复用铁律)
	for k in range(maxi(1, n)):
		var sp := _sheet_sprite(_coin_tex, COIN_FRAMES, COIN_YARDS)
		sp.render_priority = 9
		var xoff: float = (float(k) - float(maxi(1, n) - 1) / 2.0) * 26.0
		sp.position = battle._world_pos((u["pos"] as Vector2) + Vector2(xoff, 0.0),
										float(u.get("height", 0.0)) + COIN_H0)
		battle._world.add_child(sp)
		battle._coin_fx.append({
			"spr": sp, "unit": u, "xoff": xoff, "t0": battle._t + float(k) * 0.09,
			"h0": float(u.get("height", 0.0)) + COIN_H0,
		})


# ════════════════════════════════════════════════════════════════════════════
#  043 海浪护符 · 浪墙扫到谁那一下的水花
# ════════════════════════════════════════════════════════════════════════════
## 原 `_water_splash`(主场景) = `_skill_ring` 一圈**程序生成的椭圆环** + 4 颗
## `VfxTex._make_glow_texture()` 上飘光点 —— 圆环与光球都在禁区里, 实拍在每个被扫到的
## 单位脚下留下两个蓝圈, 读不出"被浪打到"。⇒ 换成真水花: 王冠状水冠 + 往外崩的水滴。
const SPLASH_TEX := "res://assets/sprites/vfx/wave-splash.png"
const SPLASH_FRAMES := 6
const SPLASH_FPS := 15.0
const SPLASH_YARDS := 42.6        # 24 texel × 1.775 码/texel —— 1:1 不缩放
const SPLASH_H := 0.34
var _splash_tex: Texture2D = null


func wave_splash(at2d: Vector2, ally: bool) -> void:
	if battle._world == null:
		return
	if _splash_tex == null:
		_splash_tex = load(SPLASH_TEX)
	if _splash_tex == null:
		return                            # 缺图就不画, 不拿别的图顶替(素材不复用铁律)
	var sp := _sheet_sprite(_splash_tex, SPLASH_FRAMES, SPLASH_YARDS)
	sp.render_priority = 5
	## 友军偏亮、敌人偏冷 —— 同一张图两种染色是"同一件效果的两侧", 不是拿别的图顶替
	sp.modulate = Color(1.0, 1.0, 1.0) if ally else Color(0.72, 0.86, 1.0)
	sp.position = battle._world_pos(at2d, SPLASH_H)
	battle._world.add_child(sp)
	battle._anim_fx.append({
		"spr": sp, "fps": SPLASH_FPS, "n": SPLASH_FRAMES, "t0": battle._t,
	})


# ════════════════════════════════════════════════════════════════════════════
#  036 温泉蛋 · 孵化升一级
# ════════════════════════════════════════════════════════════════════════════
## ★★用户 2026-09-13:「你复用素材了, 你凭什么敢?」「你用素材的时候 036,
##   有没有直接拿旧素材做」—— 说中了。原 `_egg_level_up_vfx` 是三样现成货拼的:
##     ① `_skill_ring(...)`                        程序生成的圆环(禁区)
##     ② `VfxTex._make_fire_glow_tex()` 当"金光柱"  程序光球(禁区)
##     ③ `_gold_chunk_erupt(...)` × 5              **直接拿 gold-chunk.png**, 那是【034 大熊】的素材
##   而我上一轮体检 036 时**根本没读这个函数** —— 录制里没拍到升级, 就登记成
##   "台子窗口不够长", 把一条真缺陷当成拍摄问题放过了(「没看见」当成「没问题」)。
## ⇒ 这一张是 036 自己的素材, 形状说的也是它自己的事:
##   蛋壳从中间裂开 → 壳片往两侧翻 → 缝里透出金光 → 温泉的热气团涌上来散开。
const EGG_TEX := "res://assets/sprites/vfx/egg-hatch-levelup.png"
const EGG_FRAMES := 8
const EGG_FPS := 12.0             # 8 帧 / 12fps = 0.67 秒
const EGG_YARDS := 78.1           # 22 texel × 1.775 × **2 倍整数缩放** —— 1× 时只有 20 屏幕像素,
                                  #   实拍缩在龟脚边读不出是"蛋壳裂开"; 整数倍是像素风允许的放大
const EGG_H := 1.05
var _egg_tex: Texture2D = null


func egg_hatch_levelup(at2d: Vector2) -> void:
	if battle._world == null:
		return
	if _egg_tex == null:
		_egg_tex = load(EGG_TEX)
	if _egg_tex == null:
		return                            # 缺图就不画, 不拿别的图顶替(素材不复用铁律)
	var sp := _sheet_sprite(_egg_tex, EGG_FRAMES, EGG_YARDS)
	sp.render_priority = 7
	sp.position = battle._world_pos(at2d, EGG_H)
	battle._world.add_child(sp)
	battle._anim_fx.append({
		"spr": sp, "fps": EGG_FPS, "n": EGG_FRAMES, "t0": battle._t,
	})


# ════════════════════════════════════════════════════════════════════════════
#  037 蛋糕蜡烛 · 燃烧阶段的火焰爆开
# ════════════════════════════════════════════════════════════════════════════
## 用户 2026-09-13:「燃烧阶段不合适, 应该是**有火炎从中间爆开**, 有命中特效,
##   **像烟雾那种感觉但是火焰**, 明白吗」。
## 原状: `_boom_wave(u.pos, 260)` + 每个被波及敌人 `_boom_wave(o.pos, 110)` —— 用的是通用的
##   `boom-wave-anim.png`(一圈冲击波环), 读出来是"环"不是"火"; 而且那张图在**借用台账**里
##   (主场景 + dual_lane_flow 都在用), 037 是第三家。
## ⇒ 037 自己的 `candle-fire-burst.png`: 中心炸开 → 翻滚的火团撑到最大 → **裂成几坨飘散**。
##   「像烟雾」体现在**轮廓由圆鼓的团拼成 + 消散时整团裂开**, 不是一圈环也不是一簇尖火苗。
## ★整数倍缩放(像素风): 1× = 85 码(命中点小爆) / 3× = 255.6 码(携带者脚下大爆)。
const CFIRE_TEX := "res://assets/sprites/vfx/candle-fire-burst.png"
const CFIRE_FRAMES := 8
const CFIRE_FPS := 22.0           # 8 帧 / 22fps = **0.36 秒** —— 用户 2026-09-13:
                                  #   「为什么燃烧爆发的时间要这么久, 特效应该就是火焰从中间爆开一下子的事」
                                  #   上一版把参考那条电影级 50 帧整条照搬(含「炸开→收缩→二次点火」), 0.93 秒, 拖沓。
const CFIRE_CELL := 188           # 一格多少 texel
## ★★演出范围 = 判定范围(用户 2026-09-13:「没符合实际爆炸范围?」):
##   判定是 `EquipSystem.CANDLE_BURN_R` = 500 码**半径** ⇒ 画面直径 1000 码。
##   188 texel × **3 倍整数缩放** × 1.775 码/texel = 1001 码 —— 正好盖住判定圆。
##   (上一版画成 255.6 码宽 = 判定的四分之一, 被当场点名。)
const CFIRE_YARDS := 1001.0
const CFIRE_H := 1.10
## 命中: 那个敌人**被点燃** —— 与爆炸**不是同一件事, 不共用同一张表**。
## (用户:「爆炸和命中是一回事吗我问你, 为什么用相同特效?」上一版两处只换了缩放。)
const CIGN_TEX := "res://assets/sprites/vfx/candle-ignite.png"
const CIGN_FRAMES := 8
const CIGN_FPS := 14.0
const CIGN_YARDS := 85.2          # 48 texel × 1.775 —— 1:1 不缩放, 约一个龟高
const CIGN_H := 0.92
var _cfire_tex: Texture2D = null
var _cign_tex: Texture2D = null


## 蜡烛自己炸开 —— 球状, 从中心向外。
func candle_fire_burst(at2d: Vector2) -> void:
	if battle._world == null:
		return
	if _cfire_tex == null:
		_cfire_tex = load(CFIRE_TEX)
	if _cfire_tex == null:
		return                            # 缺图就不画, 不拿别的图顶替(素材不复用铁律)
	var sp := _sheet_sprite(_cfire_tex, CFIRE_FRAMES, CFIRE_YARDS)
	sp.render_priority = 8
	sp.position = battle._world_pos(at2d, CFIRE_H)
	battle._world.add_child(sp)
	battle._anim_fx.append({
		"spr": sp, "fps": CFIRE_FPS, "n": CFIRE_FRAMES, "t0": battle._t,
	})


## 被波及的敌人**被点燃** —— 火贴着他往上舔, 不是又一次爆炸。
func candle_ignite(at2d: Vector2) -> void:
	if battle._world == null:
		return
	if _cign_tex == null:
		_cign_tex = load(CIGN_TEX)
	if _cign_tex == null:
		return
	var sp := _sheet_sprite(_cign_tex, CIGN_FRAMES, CIGN_YARDS)
	sp.render_priority = 9
	sp.position = battle._world_pos(at2d, CIGN_H)
	battle._world.add_child(sp)
	battle._anim_fx.append({
		"spr": sp, "fps": CIGN_FPS, "n": CIGN_FRAMES, "t0": battle._t,
	})


## ════════════════════════════════════════════════════════════════════════════
##  直线判定带的【地面可视化】—— 文案写明「中线两侧各 N 码」的那几件共用
## ════════════════════════════════════════════════════════════════════════════
## ★为什么要有这个 (2026-09-14): 扫了全部 96 件的 effectDesc, 文案里写明判定半宽的
##   共 3 件 —— 029 冰封水母(90 码) / 030 迷你水晶球A(55 码) / 051 激光手枪(50 码)。
##   三件演出画出来的**地面横向**宽度分别是 ±46 码 / ≈0 / **恒 0**。
##   051 的 0 不是估的, 是几何事实: `_laser_beam` 的六个顶点只在 ±Y 上偏移,
##   四个角在地面 (X,Z) 上完全重合成一条线 ⇒ 玩家看到一条细光线,
##   实际被打到的是一条 100 码宽的带子。
##   (memory [[fb-effect-text-is-the-spec]]: 文案写了而画面读不出来, 也是缺陷)
##
## ★`half_w` 一律由调用方把**判定自己用的那个常量**传进来, 这里一个数都不许写死 ——
##   写死等于又抄了一份副本, 判定改了演出不会跟着改
##   (memory [[fb-hand-rolled-copies-drift]])。
##
## ★为什么用顶点色而不是贴图: 带子要跟着 `dir` 转任意角度, 像素贴图铺上去必然被
##   重采样成糊(像素风硬约束「不许自由旋转」)。顶点色三角带没这个问题, 而且
##   `bolt_line` / `_laser_beam` 走的就是这条渲染路径 —— 是仓库既有语汇不是现造的。
##   材质感由调用方另外撒的**不旋转的贴地精灵**提供, 两层分工。
##
## 横向剖面(7 个采样点, 归一化到 half_w): **边缘最亮** —— 判定边界就画在那儿;
## 内侧压暗 ⇒ 读出来是「一条有边的带子」, 不是一块实心糊
## (memory [[fb-telegraph-needs-a-cause-not-a-flash]] 的形状规则: 亮轮廓才读成一个东西)。
const BAND_OFFS: Array[float] = [-1.00, -0.92, -0.55, 0.00, 0.55, 0.92, 1.00]
const BAND_ALPHA: Array[float] = [1.00, 0.85, 0.18, 0.30, 0.18, 0.85, 1.00]
const BAND_H := 0.035          # 贴地高度(米): 低于任何立绘, 又高于地板免得 z-fight

func line_band_ground(a2d: Vector2, dir: Vector2, half_w: float, reach: float,
					  col: Color, hold: float = 0.45, fade: float = 0.35) -> MeshInstance3D:
	if battle._world == null or half_w <= 0.0 or reach <= 0.0:
		return null
	var d: Vector2 = dir.normalized()
	if d.length_squared() < 0.5:
		return null
	var perp: Vector2 = d.orthogonal()
	var b2d: Vector2 = a2d + d * reach
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for i in range(BAND_OFFS.size() - 1):
		var o0: float = BAND_OFFS[i] * half_w
		var o1: float = BAND_OFFS[i + 1] * half_w
		var c0 := Color(col.r, col.g, col.b, col.a * BAND_ALPHA[i])
		var c1 := Color(col.r, col.g, col.b, col.a * BAND_ALPHA[i + 1])
		var a0: Vector3 = battle._world_pos(a2d + perp * o0, BAND_H)
		var a1: Vector3 = battle._world_pos(a2d + perp * o1, BAND_H)
		var b0: Vector3 = battle._world_pos(b2d + perp * o0, BAND_H)
		var b1: Vector3 = battle._world_pos(b2d + perp * o1, BAND_H)
		imesh.surface_set_color(c0); imesh.surface_add_vertex(a0)
		imesh.surface_set_color(c1); imesh.surface_add_vertex(a1)
		imesh.surface_set_color(c1); imesh.surface_add_vertex(b1)
		imesh.surface_set_color(c0); imesh.surface_add_vertex(a0)
		imesh.surface_set_color(c1); imesh.surface_add_vertex(b1)
		imesh.surface_set_color(c0); imesh.surface_add_vertex(b0)
	imesh.surface_end()
	im.sorting_offset = -1.0        # 排在立绘后面: 这是地上的印子, 不该盖住龟
	battle._world.add_child(im)
	## ★hold → fade, 不是一出生就线性淡出(memory [[fb-vfx-defect-families]] 淡出病):
	##   一出生就淡出的短命特效, 实拍任何一刻都只有半亮, 读出来就是"土棕/灰"。
	var tw = battle._reg_tween()
	tw.tween_interval(hold)
	tw.tween_property(mat, "albedo_color:a", 0.0, fade)
	tw.tween_callback(im.queue_free)
	return im


## 051 激光手枪的整套演出。分段表见 docs/plans/20260914-046至051第五批与判定带三件.md §方案A。
##   ① 枪口炸闪 ② 贯穿白核(立起的加法带) ③ 地面判定带(半宽 = 判定自己那个常量) ④ 沿线灼痕
## ★⑤"每个命中者一朵火花"不在这里 —— 它要跟着**真的被结算到的那几个**走,
##   放在演出里就成了"我自己插的标记"(memory [[fb-gate-must-measure-requirement-not-my-hook]])。
const SCORCH_TEX := "res://assets/sprites/vfx/laser-scorch.png"
const SCORCH_FRAMES := 4
const SCORCH_YARDS := 34.0
const SCORCH_FPS := 4.5        # 4 帧 ÷ 4.5 = 0.89 秒, 和地面带的 hold+fade 同寿
const SCORCH_STEP := 70.0      # 沿线每多少码撒一枚
var _scorch_tex: Texture2D = null

func laser_pistol_fx(a2d: Vector2, dir: Vector2, half_w: float, reach: float) -> void:
	if battle._world == null:
		return
	var d: Vector2 = dir.normalized()
	var endp: Vector2 = a2d + d * reach
	battle._muzzle_flash(a2d, d, Color("#ff5a72"))                                # ①
	battle._laser_beam(a2d, endp, Color(1.0, 0.24, 0.36, 0.85), 0.22, 0.22)       # ② 红辉(宽)
	battle._laser_beam(a2d, endp, Color(1.0, 0.92, 0.94, 0.95), 0.07, 0.14)       # ② 白核(细)
	line_band_ground(a2d, d, half_w, reach, Color(1.0, 0.22, 0.30, 0.34))         # ③
	if _scorch_tex == null:
		_scorch_tex = load(SCORCH_TEX)
	if _scorch_tex == null:
		return                          # 缺图就不撒, 不拿别的图顶替(素材不复用铁律)
	var perp: Vector2 = d.orthogonal()
	var n: int = clampi(int(reach / SCORCH_STEP), 1, 26)
	for i in range(n):
		## ★横向必须撒满**整个判定带** —— 撒在中线上等于又画了一条线, 宽度还是 0。
		var lat: float = randf_range(-half_w, half_w)
		var at: Vector2 = a2d + d * (SCORCH_STEP * float(i + 1)) + perp * lat
		var sp := _sheet_sprite(_scorch_tex, SCORCH_FRAMES, SCORCH_YARDS)
		## ★贴地: `axis = AXIS_Y` **本身就是平铺**, 千万别再加 rotation.x = -90
		##   (memory [[fb-axis-y-plus-rotation-cancels]]: 那两下会互相抵消成竖着的)。
		sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sp.axis = Vector3.AXIS_Y
		sp.no_depth_test = false        # 地上的印子: 该被龟挡住
		sp.render_priority = 3
		sp.sorting_offset = -0.5
		sp.position = battle._world_pos(at, BAND_H + 0.012)
		battle._world.add_child(sp)
		battle._anim_fx.append({"spr": sp, "fps": SCORCH_FPS, "n": SCORCH_FRAMES, "t0": battle._t})


## ════════════════════════════════════════════════════════════════════════════
##  041 退潮浊液【涨潮持续态】—— 整只龟泡在浊液里, 水面一直在起伏
## ════════════════════════════════════════════════════════════════════════════
## 用户 2026-09-14 看 041 窗口时:「最好做一个 buff 持续期间的特效, **整个身体**怎么样」。
## 原状: 涨潮只有 t=5 那一下水柱 + 体型 +30%, 之后 ★3 整整 15 秒身上一点标记都没有。
##
## ★做法照 022 真火 / 027 电弧 / 冰寒标记的先例 ——【演出是状态的函数】:
##   创建点在 `battle_render._tick_ebb_coat()` 里逐帧扫 `_ebb_until`,
##   **不**写在 `_eq_ebb_surge` 里。这样以后任何把 `_ebb_until` 写上去的路径
##   都自动带这层水, 不用再接一次线(memory [[fb-zero-caller-is-a-whole-class]])。
## ★到期也由 `_ebb_until` 一个字段说了算, 不另起第二条计时
##   (memory [[fb-second-clock-drops-events]]: 两条钟必然丢事件)。
## ★体型会 +30%(`size_mult`) ⇒ 水膜按同一个倍率放大, 否则涨潮后水裹不住身体。
##   `size_mult` 在整个涨潮期内不变, 所以创建时读一次就够。
const TCOAT_TEX := "res://assets/sprites/vfx/tide-coat.png"
const TCOAT_FRAMES := 6
const TCOAT_FPS := 8.0            # 6 帧 / 8fps = 0.75 秒一轮潮汐
const TCOAT_YARDS := 85.0         # 48 texel × 1.775 码 ≈ 2.04 m, 略大于一只龟
const TCOAT_H := 0.98             # 精灵中心对准身体中段(与 _body_glow 的 +1.0 同口径)
var _tcoat_tex: Texture2D = null

func ebb_tide_coat(u: Dictionary) -> void:
	if battle._world == null or u == null or not u.get("alive", false):
		return
	if is_instance_valid(u.get("_ebb_coat_spr", null)):
		return                              # 已经裹上了 ⇒ 续时间由 _ebb_until 自己管
	if _tcoat_tex == null:
		_tcoat_tex = load(TCOAT_TEX)
	if _tcoat_tex == null:
		return                              # 素材没 import 就静默跳过, 不崩战斗
	var mult: float = maxf(0.2, float(u.get("size_mult", 1.0)))
	var sp := _sheet_sprite(_tcoat_tex, TCOAT_FRAMES, TCOAT_YARDS * mult)
	sp.no_depth_test = true          # 水要压在立绘上, 被挡住就读不出「它泡在水里」
	sp.render_priority = 5
	sp.position = battle._world_pos(u["pos"] as Vector2,
									float(u.get("height", 0.0)) + TCOAT_H * mult)
	battle._world.add_child(sp)
	u["_ebb_coat_spr"] = sp
	battle._follow_vfx.append({
		"spr": sp, "unit": u, "h": TCOAT_H * mult,
		"loop_fps": TCOAT_FPS, "loop_n": TCOAT_FRAMES,
		"loop_t0": battle._t, "until_key": "_ebb_until",
		"clear_key": "_ebb_coat_spr",
	})


## ════════════════════════════════════════════════════════════════════════════
##  043 海浪护符【浪墙】—— 真 3D 海浪(生成网格), 宽度固定
## ════════════════════════════════════════════════════════════════════════════
## 用户 2026-09-14 看 043 台子:「这个得重做, **最好是做 3d 的海浪**」「而且**宽度应该固定**啊」。
##
## ── 旧版是什么样(实测, 不是推断) ────────────────────────────────────────────
##  ① **根本不是 3D** —— 是 4~16 片 `Sprite3D`(BILLBOARD_FIXED_Y)拿 `tidal-wave-anim.png`
##     沿 perp 排开、整排平移。是一排立牌, 不是一道有体积的水。
##  ② **宽度每次都不一样** —— `ncrest = clampi((p1-p0)/72+1, 4, 16)`, 而 `p0/p1` 是
##     **涌浪那一刻的单位跨度**。单位在走 ⇒ 这一次 4 片(约 300 码)下一次 16 片(约 1150 码)。
##     而且 `pmin/pmax` 以 `u.pos` 为原点算, crest 却铺在 `startc + perp*pp` ——
##     两个原点不同, 横向中心还是偏的。
##  ③ **演出与判定根本不是一回事** —— 伤害循环 `for o in allies + enemies` **没有任何
##     横向判定**: 全场每个人都吃。所以"宽度按单位跨度算"这件事从头到尾只是装饰,
##     站在侧翼的单位会被一道**视觉上没碰到它**的浪打飞。
##     ⇒ 宽度固定成**盖满全场**, 才是让演出等于判定(用户说的"固定"正好也是对的那个)。
##  ④ **整条演出挂在 tween 上**(`tween_property(p,"position",…)`), 而伤害走
##     `_pending_shots`(sim 钟)⇒ 两条钟。无头下浪一动不动而伤害照结算。
##
## ── 分段表(动手前先分段) ──────────────────────────────────────────────────
##  | 段 | 这一段在说什么事 | 多长 | 形状 / 亮暗怎么变 | 用什么实现 |
##  |---|---|---|---|---|
##  | ① 蓄浪 | 身后 400 码水位在涨 | 0.5s | 水脊整体高度 0→1, 还没有前进 | 同一张网格, 高度整体缩放 |
##  | ② 推进 | 一道浪墙推过全场 | 2.0s | 前坡陡(迎面)/顶上卷唇/背面拖长水体; 沿 perp 有相位差 ⇒ 浪脊不是直尺 | 每个 **sim step** 重建顶点 |
##  | ③ 白沫 | 浪头在卷 | 与②同步 | 顶端一条亮白泡沫带, 随卷曲强度呼吸 | 顶点色 ramp 的最亮档 |
##  | ④ 拍到 | 谁被扫到了 | 各自 | 现有 `wave_splash`(友/敌两种) | 不动 |
##  | ⑤ 退去 | 浪过去了 | 0.35s | **整体高度落回 0**, 不是 alpha 淡出(淡出病) | 高度缩放 |
##
## ★为什么用生成网格而不是贴图: 用户要的就是"3D 的海浪" —— 要有体积、要被单位正确遮挡。
##   而且网格没有"像素贴图跟着任意方向旋转 ⇒ 被重采样成糊"的问题(像素风硬约束)。
##   像素感靠**按高度把颜色量化成 5 档**保住: 渲出来仍是平涂色块, 不是光滑渐变。
const TIDE_NL := 33               # 沿浪墙方向(perp)取几列
const TIDE_NC := 19               # 浪的横截面取几片(加密: 平涂色带才够细)
const TIDE_CREST_H := 1.95        # 浪峰高度(世界单位·米)。一只龟约 1.4 ⇒ 浪比龟高一头
const TIDE_BODY := 230.0          # 浪体往后拖多长(码)
const TIDE_FACE := 74.0           # 迎面那一坡多长(码)
## 高度 ramp(低→高), 5 档量化 —— 平涂, 不做光滑渐变
## ★★★**必须不透明**。第一版给了 alpha 0.90~0.98 + `TRANSPARENCY_ALPHA`,
##   实拍量出来 **92.7% 的浪是同一个色**(最暗那档) —— 而顶点色数组明明是均匀分布的
##   (探针: 深水 26% / 白沫 28%)。根因: 透明物体**不写深度**, 整片浪只能按三角形
##   提交顺序涂, 后提交的那一列的深水把前一列的浪尖直接盖掉。
##   海浪本来就是实体 ⇒ 关掉透明, 交给深度缓冲正常排序。
##   (memory [[fb-clean-vfx-stage-not-squint]]: 拿不准就量, 别眯眼看)
## 分档阈值(归一化高度)。**不均匀** —— 最亮那档门槛抬到 0.93, 免得浪峰平台整片发白。
const TIDE_STEPS: Array[float] = [0.0, 0.18, 0.42, 0.70, 0.93]
const TIDE_RAMP: Array[Color] = [
	Color(0.05, 0.18, 0.32, 1.0),   # 深水
	Color(0.09, 0.32, 0.50, 1.0),   # 水体
	Color(0.16, 0.52, 0.70, 1.0),   # 浪面
	Color(0.36, 0.78, 0.88, 1.0),   # 浪唇
	Color(0.92, 0.99, 1.00, 1.0),   # 白沫
]


## 浪的横截面: t ∈ [0,1] 从**背面最尾**到**迎面最前**, 返回归一化高度 [0,1]。
## 形状是"后面拖很长的水体 → 抬到浪峰 → 前面一坡陡降" —— 海浪就是这个不对称。
func _tide_profile(t: float) -> float:
	if t <= 0.0 or t >= 1.0:
		return 0.0
	var crest: float = 0.78                       # 浪峰落在靠前 78% 处(不是正中)
	if t < crest:
		var a: float = t / crest
		return a * a * (3.0 - 2.0 * a)            # 背面: 平滑抬起
	var b: float = (t - crest) / (1.0 - crest)
	return 1.0 - b * b * b                        # 迎面: 三次方 ⇒ 陡


## 重建这道浪的网格。`rise` = 整体高度倍率(蓄浪/退去用), `trav` = 已推进多少码。
func tide_wall_build(w: Dictionary, rise: float, trav: float) -> void:
	var im = w.get("im", null)
	if not is_instance_valid(im):
		return
	var mesh: ImmediateMesh = w["mesh"]
	var mat: StandardMaterial3D = w["mat"]
	var start: Vector2 = w["start"]
	var dir: Vector2 = w["dir"]
	var perp: Vector2 = w["perp"]
	var half: float = float(w["half"])
	mesh.clear_surfaces()
	if rise <= 0.001:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for li in range(TIDE_NL - 1):
		var u0: float = float(li) / float(TIDE_NL - 1)
		var u1: float = float(li + 1) / float(TIDE_NL - 1)
		for ci in range(TIDE_NC - 1):
			var t0: float = float(ci) / float(TIDE_NC - 1)
			var t1: float = float(ci + 1) / float(TIDE_NC - 1)
			_tide_quad(mesh, start, dir, perp, half, rise, trav, u0, u1, t0, t1)
	mesh.surface_end()


func _tide_vert(start: Vector2, dir: Vector2, perp: Vector2, half: float,
				rise: float, trav: float, u: float, t: float) -> Array:
	## 沿浪墙方向的相位: 让浪脊起伏、峰位左右错开 ⇒ 不是一把直尺。
	var lat: float = lerpf(-half, half, u)
	var ph: float = lat * 0.014
	var amp: float = 1.0 + 0.26 * sin(ph) + 0.13 * sin(ph * 2.37)
	var shift: float = 32.0 * sin(ph * 1.6)          # 峰位前后错开(码): 浪脊不是一把直尺
	## ★卷唇: 浪峰之后那一小段**往前探出去**, 悬在迎面坡的上方 ——
	##   高度场里 `along` 不必随 t 单调, 这正是"浪在卷"与"一个斜坡"的区别。
	var lip: float = 0.0
	if t > 0.74:
		var q: float = (t - 0.74) / 0.26
		lip = 34.0 * sin(q * PI)
	var along: float = trav + shift + lip - TIDE_BODY + t * (TIDE_BODY + TIDE_FACE)
	var hn: float = _tide_profile(t) * amp
	var p2: Vector2 = start + dir * along + perp * lat
	return [p2, clampf(hn, 0.0, 1.35) * rise]


func _tide_quad(mesh: ImmediateMesh, start: Vector2, dir: Vector2, perp: Vector2,
				half: float, rise: float, trav: float,
				u0: float, u1: float, t0: float, t1: float) -> void:
	var a: Array = _tide_vert(start, dir, perp, half, rise, trav, u0, t0)
	var b: Array = _tide_vert(start, dir, perp, half, rise, trav, u1, t0)
	var c: Array = _tide_vert(start, dir, perp, half, rise, trav, u1, t1)
	var d: Array = _tide_vert(start, dir, perp, half, rise, trav, u0, t1)
	## ★★**平涂**: 一个面片一个色。第一版是逐顶点给色, 结果被 Gouraud 插值成光滑渐变 ——
	##   实拍读成"一段 3D 渲染掉进了像素游戏里", 五档量化等于白做。
	##   取四角的平均高度定档, 六个顶点同一个色 ⇒ 渲出来是一块一块的色带。
	var hmean: float = (float(a[1]) + float(b[1]) + float(c[1]) + float(d[1])) * 0.25
	## ★分档**不均匀**: 等分(idx = hmean/1.02*5)会让浪峰那一大片平台全进最亮档,
	##   实拍白沫占了整条浪的一半, 读成"一条冰河"而不是海浪。白沫只留给真正的顶。
	var idx: int = 0
	for k in range(TIDE_STEPS.size()):
		if hmean >= TIDE_STEPS[k]:
			idx = k
	## 浪唇那一小段无条件给白沫 —— 浪之所以读成浪, 靠的就是顶上那条**窄**白线。
	if t0 >= 0.80 and t1 <= 0.90:
		idx = TIDE_RAMP.size() - 1
	var col: Color = TIDE_RAMP[idx]
	for q in [[a, b, c], [a, c, d]]:
		for e in q:
			mesh.surface_set_color(col)
			mesh.surface_add_vertex(battle._world_pos(e[0] as Vector2,
								   float(e[1]) * TIDE_CREST_H))


## 起一道浪 —— 建节点, 推进交给 `EquipTickSystem._tick_tide_walls`(sim 钟)。
func tide_wall_spawn(start: Vector2, dir: Vector2, half: float, dist: float,
					 windup: float, travel: float) -> Dictionary:
	if battle._world == null:
		return {}
	var im := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	im.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED   # ★见 TIDE_RAMP 上面那段
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	battle._world.add_child(im)
	var w: Dictionary = {
		"im": im, "mesh": mesh, "mat": mat,
		"start": start, "dir": dir, "perp": dir.orthogonal(),
		"half": half, "dist": dist,
		"t": 0.0, "windup": windup, "travel": travel, "fade": 0.35,
	}
	tide_wall_build(w, 0.0, 0.0)
	return w
