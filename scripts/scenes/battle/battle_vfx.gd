class_name BattleVfx
extends RefCounted
## 战斗视觉特效(飘字/命中火花/冲击/挥击juice/技能vfx·纯表现·不改战斗态)
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _play_action(u: Dictionary, kind: String) -> void:
	if u == null or not is_instance_valid(u.get("sprite", null)):
		return
	# death 优先级最高; 已在播 death 不打断
	if u.get("anim_action", "") == "death":
		return
	# committed 动作: 播完前不被普攻/受击换掉(死亡除外·用户2026-07-11 动作播完前不打断)
	#   backstab=忍者背刺; battle.ACTION_ELITE 五个=精英小将旋刃/铁锤/强化铁锤/铁链/吞噬
	var _cur_act = str(u.get("anim_action", ""))
	if (_cur_act == "backstab" or battle.ACTION_ELITE.has(_cur_act) or battle.ACTION_MELEE.has(_cur_act) or u.get("_manual_anim", false)) and kind != "death":
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
func _hit_spark(tgt, at_pos = null) -> void:
	if tgt == null or battle._t < float(tgt.get("_spark_t", 0.0)):
		return
	tgt["_spark_t"] = battle._t + 0.05
	var pos2d: Vector2 = at_pos if at_pos != null else tgt.get("pos", Vector2.ZERO)
	var h: float = float(tgt.get("height", 0.0)) + 0.6
	if battle._hitring_tex == null:
		battle._hitring_tex = VfxTex._make_ring_texture(Color(1, 1, 1, 1))
	var r = Sprite3D.new()
	r.texture = battle._hitring_tex
	r.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	r.shaded = false; r.transparent = true
	r.modulate = Color(1.0, 0.96, 0.8, 0.95)
	r.position = battle._world_pos(pos2d, h)
	r.pixel_size = 0.006
	battle._world.add_child(r)
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(r, "pixel_size", 0.018, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "modulate:a", 0.0, 0.14)
	tw.chain().tween_callback(r.queue_free)
	if battle._spark_tex == null:
		battle._spark_tex = VfxTex._make_glow_texture()
	var sp = Sprite3D.new()
	sp.texture = battle._spark_tex
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false; sp.transparent = true
	sp.modulate = Color(1.0, 1.0, 0.85, 0.9)
	sp.position = battle._world_pos(pos2d, h)
	sp.pixel_size = 0.012
	sp.scale = Vector3.ONE * 0.5
	battle._world.add_child(sp)
	var tw2 = battle._reg_tween(); tw2.set_parallel(true)
	tw2.tween_property(sp, "scale", Vector3.ONE * 1.1, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(sp, "modulate:a", 0.0, 0.12)
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
	while is_instance_valid(self):
		var origin: Vector2 = battle._arena_center
		var dir: Vector2 = Vector2.RIGHT
		if OS.has_environment("VFXPREVIEW_DIR"):   # 验证任意方向: 角度(度)→单位向量
			var _ang = deg_to_rad(float(OS.get_environment("VFXPREVIEW_DIR")))
			dir = Vector2(cos(_ang), sin(_ang))
		var fu: Dictionary = {"pos": origin, "alive": true, "id": "basic", "side": "left", "atk_range": 350.0, "equips": [], "def": 30.0, "mr": 30.0, "atk": 100.0, "crit": 0.25, "crit_dmg": 1.5, "lifesteal": 0.0, "armor_pen": 0.0, "energy_cost": {}}
		match eff:
			"laser_sweep": battle._laser_blade_sweep(fu, origin, dir, 350.0, 60.0)
			"laser_chop": battle._equip_sys._eq_laser_chop(fu, {"pos": origin + dir * 300.0, "alive": true}, si, 180.0)
			"moon": battle._equip_sys._eq_wide_blade(fu, {"pos": origin + dir * 650.0, "alive": true}, si)
			"slash": battle._blood_slash(origin - dir * 60.0, origin, 0.0)
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
			_: battle._laser_blade_sweep(fu, origin, dir, 350.0, 60.0)
		await battle.get_tree().create_timer(period).timeout

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
