class_name BattleRender
extends RefCounted
## 战斗渲染/动画显示层(每帧插值/世界变换/跑动画/覆盖/dot飘字/相机抖/技能文案·纯视觉不改战斗态)
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _update_spell_disc() -> void:
	if battle._spell_disc == null or not is_instance_valid(battle._spell_disc):
		return
	var tr = battle._my_trainer()
	var show = tr != null and battle._trainer_sys._trainer_ticks_active()
	battle._spell_disc.visible = show
	if not show:
		return
	var u: Dictionary = tr
	var sid: String = str(u.get("_tr_active", "hook"))
	var cd_max: float = float(battle.TRAINER_SKILLS.get(sid, {}).get("cd", battle.HOOK_CD))
	var cd: float = float(u.get("_active_cd", 0.0))
	battle._spell_disc.set_cd(cd / maxf(0.01, cd_max), cd)
	battle._aim._update_q_aim()             # PC 按住 Q 瞄准: 刷新方向 + 亮 _disc_aiming
	if battle._disc_aiming:
		battle._aim._draw_aim_indicator()   # 拖动/按住Q 瞄准中: 战场上画方向指示器
	elif not battle._aim_ind.is_empty():
		battle._aim._clear_aim_indicator()  # 瞄准结束: 清掉指示器节点

## 移动端【按住圆盘拖动瞄准】回调(Wild Rift 式·用户2026-07-24)。phase: update=拖动中 / cast=松手施法 / cancel=取消。
## screen_dir=圆盘上拖动的屏幕方向; 2.5D 俯视下近似当作战场方向。
# ----------------------------------------------------------------------------
#  立绘动画驱动: 每帧推进 idle 循环 / 动作一次. 设 Sprite3D.frame 切帧 (原生裁帧).
#  idle: frame = int(t*fps) % frames (循环). 动作: 播到末帧后回 idle (清 anim_action).
# ----------------------------------------------------------------------------
# 移动时播 run 走路动画(循环), 停下回 idle. 攻击/受击/死亡/冲刺手动动画期间不切.
func _update_run_anim(u: Dictionary, delta: float) -> void:
	if not u.has("run_sd"):
		var e = battle.ACTION_RUN.get(battle._anim_key(u), null)   # ★同 battle._vfx._play_action: 三种小将共用 id, 要走动画键
		u["run_sd"] = (battle._resolve_action(str(e[0]), float(e[1])) if e != null else {})
	var rsd: Dictionary = u["run_sd"]
	if rsd.is_empty():
		return
	if str(u.get("anim_action", "")) != "" or u.get("_manual_anim", false):
		return
	# ★定步长下 pos 只在 sim step 跳, 逐 render 帧测 moved 会在 step 边界狂切 run↔idle(每切复位 frame=0)
	#   → 高帧率"不动且一直闪"(2026-07-25·4070)。改按 0.1s 时间窗累计位移测速(跨多 step 稳), 窗内不切帧表。
	u["_run_acc"] = float(u.get("_run_acc", 0.0)) + u["pos"].distance_to(u.get("_run_last_pos", u["pos"]))
	u["_run_acc_t"] = float(u.get("_run_acc_t", 0.0)) + delta
	u["_run_last_pos"] = u["pos"]
	if float(u["_run_acc_t"]) < 0.1:
		return   # 窗未满: 保持当前帧表(不切=不复位帧), 让 _advance_anim 继续推帧
	var speed: float = float(u["_run_acc"]) / maxf(0.0001, float(u["_run_acc_t"]))
	u["_run_acc"] = 0.0
	u["_run_acc_t"] = 0.0
	var is_run_now: bool = (u.get("anim_sd", {}) == rsd)
	if speed > 48.0 and not is_run_now:   # 速度阈值(帧率/步长无关): >48px/s → 播走路
		battle._set_anim_sheet(u, rsd, "", true)
		# ★走动走的是 is_idle=true 分支(直接套 idle_px/idle_offy), 同样绕不过归一问题:
		#   idle_px 是按 80px 帧算的, 套到 96px 帧上 → 本体只有 1.17m 且悬空 0.43m。
		if battle.ANIM_NORM.has(battle._anim_key(u)):
			battle._elite_sys._elite_fix_norm(u, rsd)
	elif speed <= 48.0 and is_run_now:   # 停下 → 回 idle
		battle._set_anim_sheet(u, u.get("idle_sd", {}), "", true)   # 回 idle: 该分支会自己还原 idle_px/idle_offy

func _advance_anim(u: Dictionary, delta: float) -> void:
	if u.get("_manual_anim", false):
		return   # 手动逐帧动画期(忍者冲刺分段)不自动推进帧
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr):
		return
	var sd: Dictionary = u.get("anim_sd", {})
	var frames: int = int(sd.get("frames", 1))
	var fps: float = float(sd.get("fps", 8.0))
	if frames <= 1 or fps <= 0.0:
		spr.frame = 0
		return
	u["anim_t"] = float(u.get("anim_t", 0.0)) + delta
	var idx = int(u["anim_t"] * fps)
	if u.get("anim_action", "") != "":
		# 动作播一次: 到末帧 → 回 idle
		if idx >= frames:
			battle._set_anim_sheet(u, u.get("idle_sd", {}), "", true)
			return
	else:
		idx = idx % frames   # idle 循环
	spr.frame = clampi(idx, 0, frames - 1)

# ═══ 训龟大师 4方向 directional 立绘更新器 (R6-B·2026-07-26·用户「真4方向渲染·非billboard翻转」) ═══
#   与 28 龟(billboard + flip_h 两向)隔离: 大师用真4方向(S/E/N/W 各一套帧)。
#   帧表 trainer-<形象>-{idle(4x1),walk(4x6),throw(4x7)}.png: 行=方向(S0/E1/N2/W3)·列=帧。
#   方向: 扔石头→朝目标 / 走路→朝移动 / 待机→保持(默认朝敌)。 状态优先级: 扔(一次)>走(循环)>待机(定态)。
const _TRAINER_ROW := {"south": 0, "east": 1, "north": 2, "west": 3}
const _TRAINER_ANIM_DIR := "res://assets/sprites/trainer/anim/"
var _trainer_sheet_cache: Dictionary = {}

func _trainer_sheets(app: String) -> Dictionary:
	if _trainer_sheet_cache.has(app):
		return _trainer_sheet_cache[app]
	var out: Dictionary = {}
	var walk_p := _TRAINER_ANIM_DIR + "trainer-" + app + "-walk.png"
	if app != "" and app != "default" and ResourceLoader.exists(walk_p):
		out = {
			"idle": load(_TRAINER_ANIM_DIR + "trainer-" + app + "-idle.png"),
			"walk": load(walk_p),
			"throw": load(_TRAINER_ANIM_DIR + "trainer-" + app + "-throw.png"),
		}
	_trainer_sheet_cache[app] = out
	return out

func _dir_to_cardinal(v: Vector2) -> String:
	# field +Y=南(朝镜头) / -Y=北 / +X=东 / -X=西 (见 _world_pos: field.y→world.z)
	if absf(v.x) >= absf(v.y):
		return "east" if v.x >= 0.0 else "west"
	return "south" if v.y >= 0.0 else "north"

func _update_trainer_anim(u: Dictionary, delta: float) -> void:
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr):
		return
	var sheets: Dictionary = _trainer_sheets(str(u.get("_appearance", "")))
	if sheets.is_empty():
		return   # 该形象无4方向帧表(敌方/未量产)→ 保持单帧兜底立绘
	if spr.material_override != null:
		spr.material_override = null                       # 关接地shader → 用 Sprite3D 原生裁帧(vframes行=方向)
		spr.transparent = true
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.offset = Vector2(0.0, 48.0 * 0.5 - 6.0)        # 脚底贴地: 48格里角色脚在格底上方~6px, 少抬6px让【脚】而非格底落地(否则悬空~0.29m·实测三形象5~8px padding)
	# ① 测速: 0.1s 窗累计位移(跨定步长稳·仿 _update_run_anim), 存最近非零移动方向
	var lp: Vector2 = u.get("_tr_last_pos", u["pos"])
	var step: float = u["pos"].distance_to(lp)
	if step > 0.01:
		u["_tr_move_dir"] = u["pos"] - lp
	u["_tr_move_acc"] = float(u.get("_tr_move_acc", 0.0)) + step
	u["_tr_last_pos"] = u["pos"]
	u["_tr_move_t"] = float(u.get("_tr_move_t", 0.0)) + delta
	if float(u["_tr_move_t"]) >= 0.1:
		u["_tr_speed"] = float(u["_tr_move_acc"]) / float(u["_tr_move_t"])
		u["_tr_move_acc"] = 0.0
		u["_tr_move_t"] = 0.0
	var speed: float = float(u.get("_tr_speed", 0.0))
	# ② 状态 + 方向 (扔 > 走 > 待机)
	var anim := "idle"; var cols := 1; var fps := 1.0
	var face: String = str(u.get("_tr_face", "east" if str(u.get("side", "")) == "left" else "west"))
	if battle._t < float(u.get("_tr_throw_until", 0.0)):
		anim = "throw"; cols = 7; fps = 11.0
		face = _dir_to_cardinal(u.get("_tr_throw_vec", Vector2.RIGHT))
	elif speed > 20.0:
		anim = "walk"; cols = 6; fps = 9.0
		face = _dir_to_cardinal(u.get("_tr_move_dir", Vector2.RIGHT))
	u["_tr_face"] = face
	# ③ 帧列
	var col := 0
	if anim == "throw":
		col = clampi(int((battle._t - float(u.get("_tr_throw_t0", battle._t))) * fps), 0, cols - 1)
	elif anim == "walk":
		u["_tr_anim_t"] = float(u.get("_tr_anim_t", 0.0)) + delta
		col = int(float(u["_tr_anim_t"]) * fps) % cols
	else:
		u["_tr_anim_t"] = 0.0
	# ④ 应用: 换表 + 行(方向)×列(帧)
	spr.texture = sheets[anim]
	spr.hframes = cols
	spr.vframes = 4
	spr.frame = int(_TRAINER_ROW.get(face, 0)) * cols + col

# 切换当前播放的帧表 (idle 或动作): 换 texture + Sprite3D.hframes/vframes/frame + 复位计时/pixel_size/offset.
#   is_idle=true 时复原 idle 的 px/offy; 动作图帧高可能不同, 按其帧高重算归一.
func _render_step(rd: float, frozen: bool, in_ts: bool) -> void:
	if frozen:
		pass   # 顿帧: 冻结演出(juice/立绘定格保持冲击姿势), 只下方震屏照常
	elif in_ts:
		battle._vfx._juice_decay(rd)                    # 内部gate: 只衰减active的juice(非active冲击姿势定格)
		for u in battle._timestop._ts_active:                # 只推进active立绘帧动画(非active定格)
			if u.get("alive", false):
				if u.get("is_big_bear", false):
					battle._equip_tick_sys._tick_bear_anim(u, rd)
				else:
					_advance_anim(u, rd)
		battle._timestop._ts_tick_visual(rd)                 # 时停视觉维持(钟表脉动/暗角等)
	else:
		battle._vfx._juice_decay(rd)        # squash/闪白/挥击 等计时衰减
		for u in battle._units:           # 立绘帧动画推进 (idle 循环 / 动作一次)
			if u["alive"] or u.get("anim_action", "") == "death":
				if u.get("is_big_bear", false):
					battle._equip_tick_sys._tick_bear_anim(u, rd)   # 大熊: 状态机(走路/停顿/熊爪拍/砸地)
				elif u.get("is_trainer", false):
					_update_trainer_anim(u, rd)                     # 训龟大师: 真4方向(走路/扔石头/待机)·R6-B
				else:
					_update_run_anim(u, rd)
					_advance_anim(u, rd)
	_update_camera_shake(rd)    # 震屏始终推进 (含冻结期)
	_update_world_transforms()
	_tick_follow_vfx()             # 跟随特效(冰块等)贴目标最新世界坐标(含击飞height)
	_update_ninja_marks()          # 忍者冲击标记(纯视觉·用户2026-07-12)
	_tick_ink_links()              # 线条·连笔连接线跟随双方脚底(到期/死亡断链)
	_update_overlay()
	battle._hud._pk_tick(rd)       # 顶部双方总血量 PK 条(用户2026-07-30): 逐帧平滑接缝 + 每0.1s重扫_units
	_update_dot_floats()           # DOT累积数字(点1): 跟随头顶+左右错开; 桶结束→弹射跳走
	_update_spell_disc()           # 法术圆盘(点3): 刷钩锁冷却指示 + 非战斗期隐藏

# ═══════════════════════════════════════════════════════════════════
#  沙漏059 JoJo时停 — 触发/蓄力/冻结/恢复/视觉 (登场10s → 蓄力1s → 时停4/10/30s, 一场一次)
# ═══════════════════════════════════════════════════════════════════
func _tick_follow_vfx() -> void:
	for i in range(battle._follow_vfx.size() - 1, -1, -1):
		var f: Dictionary = battle._follow_vfx[i]
		var spr = f["spr"]
		if not is_instance_valid(spr):
			battle._follow_vfx.remove_at(i)
			continue
		var u: Dictionary = f["unit"]
		if not u.get("alive", true):                # 目标已死 → 跟随特效随之消失
			spr.queue_free()
			battle._follow_vfx.remove_at(i)
			if f.get("mark", false): u["_mark_spr"] = null
			continue
		if f.get("mark", false) and battle._t > float(u.get("_mark_until", 0.0)):   # 锁定标记到期 → 移除
			spr.queue_free()
			battle._follow_vfx.remove_at(i)
			u["_mark_spr"] = null
			continue
		var base: Vector3 = battle._world_pos(u["pos"], float(u.get("height", 0.0)) + float(f["h"]))
		if f.has("orbit_r"):                         # 绕身环绕(水晶叠层)
			var ang: float = float(f["orbit_a"]) + battle._t * float(f["orbit_spd"])
			base += Vector3(cos(ang) * float(f["orbit_r"]), 0.0, sin(ang) * float(f["orbit_r"]))
		spr.position = base
		if f.get("pulse", false):
			spr.modulate.a = 0.32 + 0.16 * sin(battle._t * 3.2)   # 融合态光环呼吸脉冲

# 通用眩晕圈: 单位眩晕期间头顶 3 颗火花星水平绕转(镜头俯角自然渲成椭圆); 眩晕结束/死亡即撤.
# 每帧从 _tick_unit 调, 门=battle._t<stun_until → 任何来源的眩晕都自动带这圈(用户2026-07-11「做个眩晕通用特效」).
# 忍者冲击标记(用户2026-07-12·纯视觉层, 不改冲击机制): 每个"未被冲击过"(不在_ninja_dash_until 10s冷却里)的敌人头顶挂红色锁定标记; 忍者缩地闪到它→它进10s冷却→标记碎裂; 冷却结束→标记重现. 每帧全局调.
func _update_ninja_marks() -> void:
	var ninja_sides = {}
	for u in battle._units:
		if u.get("alive", false) and str(u.get("id", "")) == "ninja":
			ninja_sides[str(u.get("side", ""))] = true
	if ninja_sides.is_empty():
		return
	for o in battle._units:
		var is_enemy = false
		for ns in ninja_sides.keys():
			if str(o.get("side", "")) != ns:
				is_enemy = true; break
		var eligible: bool = is_enemy and o.get("alive", false) and not o.get("egg", false) and not battle._is_untargetable(o) and battle._t >= float(o.get("_ninja_dash_until", 0.0))
		var spr = o.get("_ninja_mark_spr", null)
		var valid: bool = spr != null and is_instance_valid(spr)
		if eligible and not valid:
			var m = Sprite3D.new()
			m.texture = load("res://assets/sprites/vfx/ninja-mark.png")
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			m.shaded = false; m.transparent = true
			m.modulate = Color(1.0, 0.32, 0.32, 0.92)
			var mtw = float(maxi(1, int(m.texture.get_width())))
			m.pixel_size = (30.0 * battle.WS) / mtw
			m.position = battle._world_pos(o["pos"], float(o.get("height", 0.0)) + 1.9)
			battle._world.add_child(m)
			var pt = battle.create_tween().bind_node(m).set_loops()
			pt.tween_property(m, "modulate:a", 0.5, 0.6).set_trans(Tween.TRANS_SINE)
			pt.tween_property(m, "modulate:a", 0.92, 0.6).set_trans(Tween.TRANS_SINE)
			battle._follow_vfx.append({"spr": m, "unit": o, "h": 1.9})
			o["_ninja_mark_spr"] = m
			o["_ninja_mark_pulse"] = pt
		elif not eligible and valid:
			o["_ninja_mark_spr"] = null
			var pulse = o.get("_ninja_mark_pulse", null)
			if pulse != null and is_instance_valid(pulse): pulse.kill()
			o["_ninja_mark_pulse"] = null
			battle._ninja_sys._ninja_mark_shatter(spr)

func _update_dot_floats() -> void:
	if battle._cam == null:
		return
	for u in battle._units:
		if not (u.get("_dot_float") is Dictionary):
			continue
		var df: Dictionary = u["_dot_float"]
		if df.is_empty():
			continue
		var dead: Array = []
		for bucket in df:
			var st: Dictionary = df[bucket]
			var node = st.get("node", null)
			if not is_instance_valid(node):
				dead.append(bucket); continue
			if not u.get("alive", false) or not battle._damage._dot_bucket_active(u, bucket):
				battle._damage._dot_float_flyaway(u, bucket, st)
				dead.append(bucket); continue
			var head = battle._world_pos(u["pos"], 2.7)   # 比伤害飘字(2.2)高一截, 不挡血条
			if battle._cam.is_position_behind(head):
				(node as Control).visible = false; continue
			(node as Control).visible = true
			var screen: Vector2 = battle._cam.unproject_position(head)
			var slot: int = int(st.get("slot", 0))
			var xoff: float = 0.0 if slot == 0 else (-48.0 if slot == 1 else 48.0)
			var lbl = node as Label
			var tsz = battle._vfx._float_num_font().get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, float(lbl.get_theme_font_size("font_size")))
			lbl.position = screen - tsz / 2.0 + Vector2(xoff, 0.0)
		for b in dead:
			df.erase(b)

# ── 竹叶生命球 (1:1 回合制 _spawn_bamboo_orb 港到2.5D): 绿球从目标抛物线(3D高度弧)飞回竹叶龟 + 绿拖尾 + 落点爆 ──
func _tick_ink_links() -> void:                                  # 每帧: 线跟着两只龟脚底走; 到期/死亡→断
	for i in range(battle._ink_links.size() - 1, -1, -1):
		var L: Dictionary = battle._ink_links[i]
		var a: Dictionary = L["a"]; var b: Dictionary = L["b"]
		if battle._t >= float(L["until"]) or not a.get("alive", false) or not b.get("alive", false):
			if is_instance_valid(L["spr"]): L["spr"].queue_free()
			battle._ink_links.remove_at(i); continue
		var spr = L["spr"]
		if not is_instance_valid(spr): continue
		var wf: Vector3 = battle._world_pos(a["pos"], 0.06)             # 贴地(脚底)
		var wt: Vector3 = battle._world_pos(b["pos"], 0.06)
		var seg: Vector3 = wt - wf
		var Lg: float = seg.length()
		if Lg < 0.01: continue
		var th: int = maxi(1, spr.texture.get_height())
		var tw_px: int = maxi(1, spr.texture.get_width())
		spr.pixel_size = (10.0 * battle.WS) / float(th)                 # 线宽10码
		spr.position = wf + seg * 0.5
		spr.rotation = Vector3.ZERO
		spr.rotation.y = -atan2(seg.z, seg.x)
		spr.scale = Vector3(Lg / (float(tw_px) * spr.pixel_size), 1.0, 1.0)

# ============================================================================
#  每帧: 3D 节点世界坐标更新 (XZ + 高度) + 影/环随高缩放淡 + Phase4 squash/闪白/bob
# ============================================================================
func _update_world_transforms() -> void:
	for u in battle._units:
		if not u["alive"]:
			continue
		var spr: Sprite3D = u["sprite"]
		var shadow: Sprite3D = u["shadow"]
		var ring: Sprite3D = u["ring"]
		if not is_instance_valid(spr):
			continue
		# ★Phase4切片2b 渲染插值: 立绘/影/环用【上一步pos↔当前pos】按 battle._render_alpha lerp 的位置 → 消固定步长在高帧率下的卡顿。
		#   battle._render_alpha=0(det模式/正好整步)时 = 当前 pos, 与不插值一致。朝向/last_x 仍用真 pos(朝向不卡)。
		var _rpos: Vector2 = (u.get("_prev_pos", u["pos"]) as Vector2).lerp(u["pos"] as Vector2, battle._render_alpha)
		var _rh: float = lerpf(float(u.get("_prev_height", u.get("height", 0.0))), float(u.get("height", 0.0)), battle._render_alpha)
		# 朝向: 有战斗目标→由_tick_unit锁定朝敌(死区防抖); 无目标→才随移动方向(立绘默认朝左→flip_h=true朝右); 初始左队朝右/右队朝左
		var _px: float = u["pos"].x
		var _dx: float = _px - float(u.get("last_x", _px))
		if not bool(u.get("_has_target", false)) and absf(_dx) > 0.3:
			u["face_right"] = _dx > 0.0
		u["last_x"] = _px
		if u.get("is_trainer", false) and str(u.get("_appearance", "")) != "" and str(u.get("_appearance", "")) != "default":
			spr.flip_h = false   # 大师真4方向(帧表已含左右)·不镜像; 兜底单帧形象仍走下面翻转
		else:
			spr.flip_h = bool(u.get("face_right", str(u["side"]) == "left")) != battle._art_faces_right(u)   # 原图朝右的立绘取反(用户2026-07-17"建模左右反")
		# --- Phase4: squash/stretch 形变 + idle bob 高度微浮 (全从 base 起算, 不累积) ---
		var sq = battle._vfx._juice_scale_for(u)              # (sx, sy) 形变系数 (base=1,1)
		var bob = battle._vfx._juice_bob_for(u)               # idle 呼吸 Y 偏移 (米)
		# 立绘: XZ + Y(高度 + 落地基线抬升 + bob). billboard 自动朝镜头, 不翻 facing.
		spr.position = battle._world_pos(_rpos, _rh + battle.GROUND_LIFT + bob) + u.get("_bear_voff", Vector3.ZERO) + u.get("_atk_voff", Vector3.ZERO) + u.get("_slam_voff", Vector3.ZERO)   # 大熊扑击/砸地 + 近战踏步lunge + 过肩摔起跳(#7)·pos/height 走渲染插值
		var bs: Vector3 = u.get("spr_base_scale", Vector3.ONE)
		var gm: float = float(u.get("size_mult", 1.0))   # 体型倍率(石头岩层+2%/层); 从base起算不累积
		spr.scale = Vector3(bs.x * sq.x * gm, bs.y * sq.y * gm, bs.z)
		# 受击闪白: modulate 由 base 白 → 过曝白线性插值 (flash_t/battle.JUICE_FLASH_SEC); 死亡淡出走 alpha 不冲突
		var fl: float = clampf(u.get("flash_t", 0.0) / battle.JUICE_FLASH_SEC, 0.0, 1.0)
		spr.modulate = Color.WHITE.lerp(u.get("flash_col", battle.JUICE_FLASH_COLOR), fl)
		if str(u.get("id","")) == "ghost" and battle._t < float(u.get("phase_until", 0.0)):   # 虚化态本体(用户2026-07-11): 半透明+忽隐忽现幽紫 + 残影拖尾
			spr.modulate = Color(0.78, 0.62, 1.0, 0.34 + 0.14 * sin(battle._t * 9.0))
			if battle._t - float(u.get("_phase_ai_t", -1.0)) >= 0.08:
				u["_phase_ai_t"] = battle._t
				battle._spawn_phase_afterimage(spr)
		# 影/环: 跟 XZ 不跟 Y (贴地), 随高度缩小变淡 (从各自基准 scale 起算, 召唤体影更小)
		var s: float = 1.0 - clampf(_rh / 3.0, 0.0, 0.7)
		if is_instance_valid(shadow):
			var base_sc: Vector3 = u.get("shadow_base_scale", battle.SHADOW_BASE)
			shadow.position = battle._world_pos(_rpos, 0.02)
			# 影也随 squash 横向张缩 (压扁→影变宽, 拉长→影变窄) 加重量感
			shadow.scale = Vector3(base_sc.x * s * sq.x * gm, base_sc.y * s * gm, base_sc.z * s)   # 影随体型一起涨
			shadow.modulate.a = battle.SHADOW_BASE_A * s
		# 接触核影: 紧贴脚下, 离地越高越快淡出(腾空=脚离地, 核影该消失) → 强化"踩地"
		var contact = u.get("contact", null)
		if is_instance_valid(contact):
			var cbase: Vector3 = u.get("contact_base_scale", battle.CONTACT_BASE)
			var cs: float = 1.0 - clampf(_rh / 1.2, 0.0, 1.0)   # 比外影更快随高度收
			contact.position = battle._world_pos(_rpos, 0.028)
			contact.scale = Vector3(cbase.x * cs * sq.x, cbase.y * cs, cbase.z * cs)
			contact.modulate.a = 0.0   # 隐藏接触核影(用户"只留影子")
		if is_instance_valid(ring):
			ring.position = battle._world_pos(_rpos, 0.015)

# ============================================================================
#  §JUICE — Phase4 商业级打击感 (squash&stretch / 闪白 / 顿帧 / 震屏 / idle bob / 粒子)
#  统一态机: 触发函数只置"剩余秒"字段, 每帧 battle._vfx._juice_decay 自减, 视觉由 battle._vfx._juice_scale_for/
#  battle._vfx._juice_bob_for + _update_world_transforms 重建 → 复原干净(scale/modulate 都回 base, 无漂移).
# ============================================================================

# 震屏每帧推进: 衰减幅度 + 伪随机偏移镜头, 归零时精确复位到缩放后基准
func _update_camera_shake(delta: float) -> void:
	if battle._cam == null or not is_instance_valid(battle._cam):
		return
	if battle._shake_amp <= 0.0001:
		battle._shake_amp = 0.0
		battle._cam.position = battle._cam_zoom_base
		return
	battle._shake_t += delta
	battle._shake_amp = battle._shake_amp * exp(-battle.JUICE_SHAKE_DECAY * delta)   # 指数衰减
	# 伪随机偏移 (sin/cos 不同频 → 不规则); 横/竖各一份, 不动深度 z
	var ox: float = sin(battle._shake_t * battle.JUICE_SHAKE_FREQ * TAU) * battle._shake_amp
	var oy: float = cos(battle._shake_t * battle.JUICE_SHAKE_FREQ * 0.81 * TAU + 1.3) * battle._shake_amp
	battle._cam.position = battle._cam_zoom_base + Vector3(ox, oy, 0.0)

# 触发震屏: 取较大幅度叠加(封顶), 重置相位让新事件抖得明显
# 血条/龟能 overlay: 每帧 unproject 单位头顶 → 屏幕像素 (跟随)
func _update_overlay() -> void:
	if battle._cam == null:
		return
	if battle._dl_hud != null and is_instance_valid(battle._dl_hud):
		battle._dl_sys._dl_update_hud()
	battle._info_sys._update_team_panels()   # 头像框栏: 每帧刷 HP 条 / 死亡变暗 / 选中高亮
	for u in battle._units:
		var root: Control = u["bar_root"]
		if not is_instance_valid(root):
			continue
		if not u["alive"]:
			root.visible = false
			continue
		# HpBar 组件刷新 (HP/护盾/受击红trail+白闪/刻度全自带, 1:1 回合制血条).
		#   update_state 读 u 的 maxHp/hp/shield 字段; 召唤体也是同 HpBar (无护盾段则自然不画).
		var hb = u.get("hp_bar", null)
		if hb != null and is_instance_valid(hb):
			u["_auraEnergy"] = u.get("store_energy", 0.0)   # 镜像→Hp条资源条(储能/怒气/星能/泡泡, 字段对齐回合制端口)
			u["_lavaRage"] = u.get("rage", 0.0)
			u["_starEnergy"] = u.get("star_energy", 0.0)
			u["bubbleStore"] = u.get("bubble_store", 0.0)
			u["_stoneDefGained"] = float(u.get("base_def", 0.0)) - float(u.get("stone_init_def", u.get("base_def", 0.0)))
			u["_initDef"] = float(u.get("stone_init_def", u.get("base_def", 0.0)))
			hb.update_state(u)
			var lvb = u.get("level_badge", null)   # 036温泉蛋临时升级→等级框数字实时跳
			if lvb != null and is_instance_valid(lvb) and lvb.get_child_count() > 0:
				(lvb.get_child(0) as Label).text = str(battle._effective_level(u))
		# 龟能条 (实时资源; 召唤体的 en_fill 已 hide)
		var enf = u.get("en_fill", null)
		if enf != null and is_instance_valid(enf) and enf.visible:
			# 进度 = 最快要冷却好的那个技的进度 (1 - 剩余/总; 即"下一招"的充能条)
			var prog = 0.0
			var cds3: Dictionary = u.get("skill_cd", {})
			for s in u.get("active_skills", []):
				var st = str(s)
				if not battle._IMPL_SKILLS.has(st):
					continue
				var base = battle._skill_cd(u, st)
				var p = 1.0 - clampf(float(cds3.get(st, base)) / maxf(0.1, base), 0.0, 1.0)
				if p > prog:
					prog = p
			enf.size.x = battle.BAR_W * prog
		# 头顶世界坐标 → 屏幕 (bar_head_h 可按单位覆写·大单位如海盗船抬高)
		var head = battle._world_pos(u["pos"], u["height"] + float(u.get("bar_head_h", 2.4)))
		if battle._cam.is_position_behind(head):
			root.visible = false
			continue
		root.visible = true
		var screen: Vector2 = battle._cam.unproject_position(head)
		var _bx: float = battle.BAR_W * 0.5
		if u.get("_isEgg", false):
			_bx -= 8.0   # 蛋: 补偿等级牌左突(bw13+3的一半), 让"牌+血条"整体居中在蛋上(条本身仍对准蛋心)
		root.position = screen - Vector2(_bx, 8)   # 居中 (条宽 battle.BAR_W)

# ============================================================================
#  灭队判定 + 结算横幅 (复用 2D _check_end; 赛季结算 Phase 3 接 GameState)
# ============================================================================
func _render_skill_text(tpl: String, u: Dictionary, sk: Dictionary) -> String:
	if tpl == "":
		return ""
	var out = tpl
	if battle.SkillText != null:
		out = battle.SkillText.render_plain(tpl, u, sk if sk is Dictionary else {})
	return battle._strip_html(out)

## 详情面板【属性行】的单一事实源 —— 建面板和每帧刷新都走这一个函数,
## 所以两边不可能漂移(加属性只改这里一处)。返回 [[图标路径, 文本, 颜色], ...]。
##
## ★核心 7 项恒显示; 其余"有值才显示"(0 的不占位, 免得面板一片 0)。
## ★不要用 emoji 当图标 —— 本项目已「全去emoji(根治绿块+跨平台一致)」, 没图标就留空占位。
