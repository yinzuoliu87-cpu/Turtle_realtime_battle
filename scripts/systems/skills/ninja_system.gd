class_name NinjaSystem
extends RefCounted
## 忍者龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _ninja_mark_shatter(spr) -> void:
	if not is_instance_valid(spr): return
	var pos: Vector3 = spr.position
	var sc0: Vector3 = spr.scale
	var bt = battle._reg_tween(); bt.set_parallel(true)
	bt.tween_property(spr, "modulate:a", 0.0, 0.2)
	bt.tween_property(spr, "scale", sc0 * 1.6, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bt.chain().tween_callback(spr.queue_free)
	for k in range(4):
		var sh = Sprite3D.new()
		sh.texture = load("res://assets/sprites/vfx/crystal-shard.png")
		sh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sh.shaded = false; sh.transparent = true
		sh.modulate = Color(1.0, 0.35, 0.35, 0.9)
		sh.pixel_size = 0.006
		sh.position = pos
		battle._world.add_child(sh)
		var ang: float = float(k) * TAU / 4.0 + 0.4
		var dst = pos + Vector3(DetMath.dcos(ang) * 0.2, 0.06, DetMath.dsin(ang) * 0.2)
		var st = battle._reg_tween().bind_node(sh); st.set_parallel(true)
		st.tween_property(sh, "position", dst, 0.24)
		st.tween_property(sh, "modulate:a", 0.0, 0.24)
		st.chain().tween_callback(sh.queue_free)

## ★★2026-08-22 文案根除: 忍术(被动)这一组原来散在本文件与主场景/battle_spawn 三处。
## 【开局永久属性】真正的落点是 `battle_spawn.gd` 的 spawn 分支(不在本文件, 极难 grep 到)
## 【斩击(普攻)】近战单段 + 流血。真值在主场景普攻表, 那里引用本常量。
const SLASH_ATK_COEF := 1.0       # ×ATK 物理
## 斩击流血层数 = 攻击力 × 系数(四舍五入, 至少 1 层)。流血每层每秒 1 点物理 ⇒ 层数就是伤害量。
## 用户 2026-10-16「斩击施加的流血层数改为4%ATK，暴击时为6%」(原固定 2 层 / 暴击 3 层)。
const SLASH_BLEED_ATK := 0.04
const SLASH_BLEED_ATK_CRIT := 0.06

static func slash_bleed_stacks(u: Dictionary, crit: bool) -> int:
	return maxi(1, roundi(float(u.get("atk", 0.0)) * (SLASH_BLEED_ATK_CRIT if crit else SLASH_BLEED_ATK)))

## ── 普攻命中刀痕(11-11 用户「攻击的命中特效」「每个角色将有自己的…普攻和技能命中特效」)──
## 参考外部商业游戏(LoL Battle Boss 亚索普攻命中 + Katana ZERO 刀斩, 逐帧研究 docs/studies/20261111b-忍者普攻命中刀痕逐帧.md):
##   一条细长亮线斜穿目标、出现即全长再从起手端缩短 + 命中点星闪 1 ~ 2 格 + 像素碎片沿刀向迸出下落; 6 格共 0.2 秒。
## 图画的是「出手方朝左」(刀路右上 → 左下, 接 build_ninja_slash.py 的挥刀), 朝右时镜像。只管画面, sim 不读。
const HIT_SLASH_TEX := "res://assets/sprites/vfx/ninja-hit-slash.png"
const HIT_SLASH_FW := 96
const HIT_SLASH_FRAME_SEC := 1.0 / 30.0
const HIT_SLASH_PX := 2.0 / 64.0       # 与龟人物图同一个像素尺寸(帧高 64 像素 = 2 米), 固定不缩放
const HIT_SLASH_UP := 0.95             # 目标胸口离脚底多高(米)

func basic_hit_vfx(u: Dictionary, tgt: Dictionary) -> void:
	if str(u.get("id", "")) != "ninja" or battle._world == null or not tgt.get("alive", false):
		return
	var tex: Texture2D = load(HIT_SLASH_TEX)
	if tex == null:
		return
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = maxi(1, tex.get_width() / HIT_SLASH_FW)
	s.frame = 0
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.no_depth_test = true
	s.render_priority = 12                 # 画在目标身上(刀痕穿过目标, 被立绘挡住就看不出是砍中)
	s.pixel_size = HIT_SLASH_PX
	s.flip_h = bool(u.get("face_right", false))
	s.position = battle._world_pos(tgt["pos"], float(tgt.get("height", 0.0)) + HIT_SLASH_UP)
	battle._world.add_child(s)
	var n: int = s.hframes
	var tw = battle._reg_tween()
	tw.bind_node(s)
	tw.tween_method(func(fv: float) -> void:
		if is_instance_valid(s):
			s.frame = clampi(int(fv), 0, n - 1)
	, 0.0, float(n) - 0.001, HIT_SLASH_FRAME_SEC * float(n))
	tw.tween_callback(s.queue_free)


## ── 被动冲击(自动冲刺斩)专属特效(11-11 用户「关于忍者龟被动，就是这个冲击，它的这个命中特效，你看看」「你想办法先改喽」)──
## 原来: 冲刺前青色虚线方块 / 滑行糊的白蓝光条 / 命中深蓝大月牙 + 通用火花 / 落地蓝月牙盖在自己身上 0.6 秒。
## 参考 Katana ZERO 冲刺斩(逐帧 docs/studies/20261111c-忍者普攻挥刀参考-KatanaZERO逐帧.md「冲刺命中」): 硬边速度拖影 + 斩中时
##   一条细亮线穿过敌人(出现即全长, 最亮停一下, 再从冲来的那头缩短) + 碎光; 颜色接普攻刀光(白芯 / 浅金 / 金边)。
## 图: tools/assetgen/build_ninja_dash_vfx.py(都画「朝右冲」; 这里按冲刺方向在屏幕上转角度, 朝左镜像)。只管画面, sim 不读。
const DASH_TRAIL_TEX := "res://assets/sprites/vfx/ninja-dash-trail.png"
const DASH_HIT_TEX := "res://assets/sprites/vfx/ninja-dash-hit.png"
const DASH_DUST_TEX := "res://assets/sprites/vfx/ninja-dash-dust.png"
const DASH_HIT_FW := 144
const DASH_DUST_FW := 48
const DASH_FX_PX := 2.0 / 64.0          # 与龟人物图同一个像素尺寸, 固定不缩放(拖影只横向拉长)
const DASH_TRAIL_LEN := 170.0           # 拖影最长(码)
const DASH_TRAIL_H := 0.7               # 拖影离地高(米, 腰)
const DASH_TRAIL_BACK := 24.0           # 拖影头离忍者中心往后让(码), 不盖身体
const DASH_HIT_SEC := 1.0 / 30.0        # 命中亮线每格
const DASH_DUST_SEC := 1.0 / 25.0       # 扬尘每格


## 屏幕上沿 dir 的朝向: [基(x 沿冲刺在屏幕上的方向, 面朝镜头), 是否镜像(朝屏幕左冲)]
func _dash_screen_basis(at2d: Vector2, dir: Vector2) -> Array:
	var cb: Basis = battle._vfx.cam_basis()
	var d3: Vector3 = battle._world_pos(at2d + dir * 10.0, 0.0) - battle._world_pos(at2d, 0.0)
	var sx: float = d3.dot(cb.x)
	var sy: float = d3.dot(cb.y)
	var flip: bool = sx < 0.0
	if flip:
		sx = -sx
		sy = -sy
	var ang: float = DetMath.datan2(sy, sx)
	var bx: Vector3 = (cb.x * DetMath.dcos(ang) + cb.y * DetMath.dsin(ang)).normalized()
	var by: Vector3 = (cb.y * DetMath.dcos(ang) - cb.x * DetMath.dsin(ang)).normalized()
	return [Basis(bx, by, cb.z.normalized()), flip]


func _dash_sprite(path: String, fw: int) -> Sprite3D:
	var tex: Texture2D = load(path)
	if tex == null or battle._world == null:
		return null
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = maxi(1, tex.get_width() / fw) if fw > 0 else 1   # fw = 0: 单张图(拖影)
	s.shaded = false
	s.transparent = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = DASH_FX_PX
	battle._world.add_child(s)
	return s


## 拖影: 从 tail 到 head(都是 2D 位置)横向拉长, 腰高, 面朝镜头
func _dash_trail_set(s: Sprite3D, tail: Vector2, head: Vector2, dir: Vector2) -> void:
	if not is_instance_valid(s):
		return
	var bf: Array = _dash_screen_basis(head, dir)
	var b: Basis = bf[0]
	var a3: Vector3 = battle._world_pos(tail, DASH_TRAIL_H)
	var h3: Vector3 = battle._world_pos(head, DASH_TRAIL_H)
	var L: float = absf((h3 - a3).dot(b.x))
	s.visible = L > DASH_FX_PX * 4.0
	s.flip_h = bool(bf[1])
	var k: float = L / maxf(0.001, float(s.texture.get_width()) * DASH_FX_PX)
	s.transform = Transform3D(Basis(b.x * maxf(0.001, k), b.y, b.z), (a3 + h3) * 0.5)


func _dash_trail_ends(start: Vector2, cur: Vector2, dir: Vector2) -> Array:
	var head: Vector2 = cur - dir * DASH_TRAIL_BACK
	var back: float = clampf(DetMath.dot(head - start, dir), 0.0, DASH_TRAIL_LEN)
	return [head - dir * back, head]


## 命中亮线: 目标胸口, 沿冲刺方向; 6 格共 0.2 秒
func dash_hit_vfx(o: Dictionary, dir: Vector2) -> void:
	var s: Sprite3D = _dash_sprite(DASH_HIT_TEX, DASH_HIT_FW)
	if s == null:
		return
	s.no_depth_test = true
	s.render_priority = 12                 # 亮线穿过目标, 画在立绘前面
	var bf: Array = _dash_screen_basis(o["pos"], dir)
	s.flip_h = bool(bf[1])
	s.transform = Transform3D(bf[0], battle._world_pos(o["pos"], float(o.get("height", 0.0)) + HIT_SLASH_UP))
	_dash_play(s, DASH_HIT_SEC)


## 落地扬尘: 脚下, 5 格
func dash_dust_vfx(at2d: Vector2) -> void:
	var s: Sprite3D = _dash_sprite(DASH_DUST_TEX, DASH_DUST_FW)
	if s == null:
		return
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.position = battle._world_pos(at2d, float(s.texture.get_height()) * 0.5 * DASH_FX_PX)
	_dash_play(s, DASH_DUST_SEC)


func _dash_play(s: Sprite3D, sec: float) -> void:
	var n: int = s.hframes
	var tw = battle._reg_tween()
	tw.bind_node(s)
	tw.tween_method(func(fv: float) -> void:
		if is_instance_valid(s):
			s.frame = clampi(int(fv), 0, n - 1)
	, 0.0, float(n) - 0.001, sec * float(n))
	tw.tween_callback(s.queue_free)
const INSTINCT_CRIT := 0.20       # 暴击率 +
const INSTINCT_CRIT_DMG := 0.15   # 暴击伤害 +
const INSTINCT_ARMOR_PEN := 10.0  # 护甲穿透 +(flat)
## 【冲击·自动冲刺斩】
## 【手里剑】掷飞镖; 暴击时把暴击总伤【拆两段】(真伤 + 剩余物理), 不是整发转真伤。
## 【炸弹】落点范围物理 + 破甲(时长走通用 BUFF_SEC)。
const BOMB_ATK_COEF := 2.0    # ×ATK 物理
const BOMB_DEF_DOWN := 0.20   # 目标护甲 −(破甲 25% → 20%·用户 2026-07-29 第五轮)
const SHURIKEN_COEF := 1.6        # ×ATK 物理(基础·未减甲未暴击)
const SHURIKEN_TRUE_BASE := 40.0  # 暴击总伤转真实的起始百分比
const SHURIKEN_TRUE_PER_LV := 2.0 # 每级再 +(百分点)
const SHURIKEN_TRUE_CAP := 100.0  # 封顶(百分比)
## 文案用的两端(推导, 不手写): 照 LoL「4% =（4% - 10%⬆）」写 1 级与满级的比例(用户 2026-10-15「lol怎么做的」)。
##   满级 = Phase2Config.MAX_LEVEL(10) ⇒ 60%, 封顶 100% 正常等级下碰不到, 所以文案不写它。
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const SHURIKEN_TRUE_LV1 := SHURIKEN_TRUE_BASE + SHURIKEN_TRUE_PER_LV
const SHURIKEN_TRUE_LVMAX := SHURIKEN_TRUE_BASE + SHURIKEN_TRUE_PER_LV * _P2C.MAX_LEVEL
## 【忍者足】选手里剑后打包的登场被动。
const FOOT_DODGE := 0.15          # 闪避 +
const FOOT_CRIT := 0.30           # 暴击率 +
## 【背刺】先给自己一段穿甲, 再闪到全场最远敌身后连刺。
const BACKSTAB_PEN := 15.0     # 护甲穿透 +(flat)
const BACKSTAB_PEN_SEC := 5.0  # 穿甲持续(秒)
const BACKSTAB_SEGMENTS := 3   # 背刺几段
const BACKSTAB_TOTAL := 2.0    # 三段合计 ×ATK 物理
const BACKSTAB_SEG_COEF := BACKSTAB_TOTAL / BACKSTAB_SEGMENTS   # 推导: 每段(0.6667)
const DASH_SENSE := 290.0         # 触发射程(码)·**故意 < 冲刺距离**, 所以冲刺会略穿过目标
const DASH_RANGE := 300.0         # 冲刺位移(码)
const DASH_WIDTH := 62.0          # 判定带半宽(码)
const DASH_MAIN_COEF := 1.3       # 主目标 ×ATK 物理
const DASH_SIDE_COEF := 0.8       # 路径其余 ×ATK 物理
const DASH_KNOCK_SEC := 0.8       # 击飞滞空(秒)
const DASH_SELF_CD := 0.4         # 本体两次冲刺的最小间隔(秒)
const DASH_TARGET_CD := 10.0      # 同一敌人被冲后的冷却(秒)

func _ninja_dash(u: Dictionary, target: Dictionary) -> void:    # 被动·冲击(亚索E式): 朝最近敌固定位移300码(2026-07-22订正: 头注释一直没跟上同日的 450→300)·主目标1.3A/路径其余0.8A物理+击飞0.8s·每敌10s冷却·无伤害递增
	battle._audio_sys.sfx_passive(u, "ninja")   # 被动音效(11-05; 只管声音)
	# 〖用户2026-07-06〗"450码固定距离，最近，所以理想的效果就是他会连着滑几下，不用加递增"; 伤害取回合制 ninjaImpact(atkScale=1.3 / behindScale=0.8)
	u["_ninja_last_dash"] = battle._t
	var start: Vector2 = u["pos"]
	var dir: Vector2 = target["pos"] - start
	if DetMath.vlen(dir) < 1.0: dir = Vector2.RIGHT
	dir = DetMath.norm(dir)
	# ★#5修〖用户2026-07-11〗: 亚索 E 式【滑行穿过】(非瞬移), 滑速 600 码/秒. 固定路径 300 码(同日 450→300).
	var endp: Vector2 = start + dir * DASH_RANGE                     # 冲刺距离 300码(用户2026-07-11: 450→300)
	endp = ArenaShape.clamp_in(endp, battle.ARENA)
	# 路径上的敌 (按沿路投影排序 → 滑到谁割谁)
	var hits: Array = []
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		if not battle._on_line(start, dir, o["pos"], DASH_WIDTH): continue
		var proj: float = DetMath.dot((o["pos"] - start), dir)
		if proj < 0.0 or proj > DASH_RANGE: continue
		hits.append({"o": o, "proj": proj, "done": false})
	hits.sort_custom(func(a, b): return float(a["proj"]) < float(b["proj"]))
	## 原来这里 battle._bolt_line 画一排青色虚线方块标出路线(11-11 用户看冲击命中特效时去掉; 拖影改在滑行里跟着走)
	_ninja_glide(u, start, endp, dir, target, hits)            # 滑行(async, fire-and-forget)

## 忍者冲击滑行 (亚索 E 式 · 600 码/秒 · 穿过路径敌逐个割). no_move 期间分离跳过, 每帧直接推 pos.
func _ninja_glide(u: Dictionary, start: Vector2, endp: Vector2, dir: Vector2, target: Dictionary, hits: Array) -> void:
	var total: float = DetMath.dist(start, endp)
	if total < 1.0:
		return
	var was_nm: bool = bool(u.get("no_move", false))
	var was_nb: bool = bool(u.get("no_basic", false))
	u["no_move"] = true
	u["no_basic"] = true
	u["_ninja_gliding"] = true                                 # 滑行中(含起手/落地)→触发器不再触发下一次冲刺(用户2026-07-11)
	var _nspr = u.get("sprite", null)
	var _ndsd = battle._resolve_action("pets/animations/ninja/dash.png", 16.0)   # 忍者冲刺动作。★真实表只有 7 帧(0~6) —— 帧号一律经 _nspr_last() 钳制, 别照旧注释的"5-8/9-11"写死(见下方 2026-08-07 那段)
	var _ndash: bool = (not _ndsd.is_empty()) and is_instance_valid(_nspr)
	if _ndash:
		u["_manual_anim"] = true                          # 手动逐帧(阻止_advance_anim自动推进)
		battle._set_anim_sheet(u, _ndsd, "dash", false)
		u["face_right"] = dir.x > 0.0                      # 朝滑行方向
		for _wf in range(4):                                # 起手 1-4帧
			if not u.get("alive", false): break
			if is_instance_valid(_nspr): _nspr.frame = _wf
			await battle._wait_sim(0.045, u)
			if not is_instance_valid(battle): return   ## await 回来 battle 可能已被 queue_free(战斗结束)
	var traveled = 0.0
	# ★冲击拖影(用户2026-07-11 要一道疾风拖影伴随滑行; 11-11 换成专属硬边像素拖影, 跟在身后、落地从尾巴往前收)
	var lead: Sprite3D = _dash_sprite(DASH_TRAIL_TEX, 0)
	if lead != null:
		lead.visible = false
	while is_instance_valid(battle) and traveled < total and u.get("alive", false) and battle.is_inside_tree():
		await battle._dl_sys.lane_step()
		if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 queue_free), 回来必须重新确认
		if battle._timestop.holds(u): continue   # 时停: 被定格的单位这一步不推进(携带者照常; 顿帧行为不变)
		traveled = minf(total, traveled + 600.0 * battle._frame_sim_dt)   # 恒速 600 码/秒
		u["pos"] = start + dir * traveled
		if is_instance_valid(lead):
			var _te: Array = _dash_trail_ends(start, u["pos"], dir)
			_dash_trail_set(lead, _te[0], _te[1], dir)
		# ★★2026-08-07 修: 这里原来写死 `4 + (…% 4)` = 取第 4~7 帧, 落地那段写死 range(8, 11) = 第 8~10 帧,
		#   两处都按【≥11 帧的精灵表】算。而真实的忍者冲刺表只有 **7 帧(0~6)**
		#   ⇒ 每次冲刺都刷 `ERROR: Index p_frame = 7/8/9/10 is out of bounds (…= 7)`。
		#   注释写着"滑行 5-8帧""落地 9-11帧" —— **表换过、代码没跟上**, 而这条报错原先不在
		#   run-tests.sh 的 FATAL 正则里 ⇒ 一直红着没人看见(补了 `is out of bounds` 才暴露)。
		#   改成**按表的真实帧数钳制**: 表以后再换也不会越界。
		if _ndash and is_instance_valid(_nspr):
			_nspr.frame = mini(4 + (int(traveled / 45.0) % 4), _nspr_last(_nspr))
		for h in hits:
			if not h["done"] and traveled >= float(h["proj"]):
				h["done"] = true
				var o: Dictionary = h["o"]
				if o.get("alive", false):
					battle._vfx.own_hit_vfx = true    # 有专属命中特效: 伤害与击飞都不叠通用星芒 / 起跳火花(只管画面)
					battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, DASH_MAIN_COEF if is_same(o, target) else DASH_SIDE_COEF, o), Color("#9fe8ff"))
					battle._damage._knockback(u, o, 40.0, 1.468, 1.0)          # 击飞 0.8s 滞空
					battle._vfx.own_hit_vfx = false
					if is_same(o, target): o["_ninja_dash_until"] = battle._t + DASH_TARGET_CD          # 只有【目标】进10s冷却·顺路割到的不占(用户2026-07-11)
					dash_hit_vfx(o, dir)
	u["pos"] = endp
	u["no_move"] = was_nm
	u["no_basic"] = was_nb
	if is_instance_valid(lead):                                # 冲刺结束→拖影从尾巴往前收(实心, 不淡出)
		var _e: Array = _dash_trail_ends(start, u["pos"], dir)
		var _t0: Vector2 = _e[0]
		var _h0: Vector2 = _e[1]
		var _lw = battle._reg_tween()
		_lw.bind_node(lead)
		_lw.tween_method(func(fv: float) -> void:
			_dash_trail_set(lead, _t0 + (_h0 - _t0) * fv, _h0, dir)
		, 0.0, 1.0, 0.12)
		_lw.tween_callback(lead.queue_free)
	dash_dust_vfx(u["pos"])                                    # 落地脚下扬尘(原来在自己身上弹一个蓝月牙 0.6 秒, 11-11 去掉)
	if _ndash:
		# 落地三帧: 取表的最后三帧(原来写死 8/9/10, 越界; 理由见上面滑行那段的注释)
		# ★★2026-08-07 真根因(冒烟随机报 `p_frame = 16/17 out of bounds (…=7)` 追了很久):
		#   上限 `_nlast` 原来**在循环外算一次**(冲刺表 18 帧 ⇒ 17), 而循环里**有 await** ——
		#   忍者若在这三帧之间**阵亡**, 表会被换成 7 帧的 `ninja/death.png`,
		#   后续两次写就是 frame=16、17 打在 7 帧的表上。**两条连续报错正是这么来的。**
		#   ⇒ **每次写之前重新按精灵当前的 hframes×vframes 算上限**。
		#   通则: **跨 await 的帧号上限一律不能缓存** —— await 中间世界会变。
		## ★2026-11-11 落地改用第 8 / 9 / 10 帧(双刀落地 → 收势 → 站姿)。原来取表末三帧 15 / 16 / 17, 而第 11~16 帧是一组「白闪淡出」
		##   (平均亮度 126 / 160 / 234 / 179 / 140 / 93, 待机 64) ⇒ 每次落地身体发白闪一下(用户 11-10「整个动作播放是不是有问题」逐帧查到)。
		##   帧号仍每次按精灵当前的表钳(上面 2026-08-07 的教训)。
		for _lf in [8, 9, 10]:
			if is_instance_valid(_nspr):
				var _lim: int = _nspr_last(_nspr)
				_nspr.frame = clampi(_lf, 0, _lim)
			await battle._wait_sim(0.05, u)
			if not is_instance_valid(battle): return   ## await 回来 battle 可能已被 queue_free(战斗结束)
		u["_manual_anim"] = false
		if is_instance_valid(_nspr): battle._set_anim_sheet(u, u.get("idle_sd", {}), "", true)   # 回idle
	u["_ninja_gliding"] = false                               # 冲刺(含落地)结束→放开触发

func _sk_ninja_backstab(u: Dictionary, tgt: Dictionary) -> void: # 技三·背刺(1:1回合制 ninjaBackstab): +15穿甲5秒(用户2026-07-11: 5→15)→闪现到【全场最远敌】身后→背刺【3段·每段300ms(hitStaggerMs)】各0.6667A物理(共2.0A)→留该处追砍
	var far = null
	var fd = -1.0
	for o in battle._targeting._pick_enemies_of(u):   # ★单体定向(闪现到最远敌身后)走 battle._targeting._pick_enemies_of: 否则忍者会瞬移到场外训龟大师身后背刺(场外·永远最远); 见 §PICK-TARGET(用户2026-07-24)
		if not o.get("alive", false): continue
		var dd: float = DetMath.dist(u["pos"], o["pos"])
		if dd > fd: fd = dd; far = o
	if far == null: far = tgt
	if far == null: return
	var from2d: Vector2 = u["pos"]
	u["armor_pen"] = float(u.get("armor_pen", 0.0)) + BACKSTAB_PEN       # +15穿甲(5秒后撤销·用户2026-07-11: 5→15)
	var uu: Dictionary = u
	battle._pending_shots.append({"delay": BACKSTAB_PEN_SEC, "fn": func(): uu["armor_pen"] = float(uu.get("armor_pen", 0.0)) - BACKSTAB_PEN, "src": u})
	battle._dash_to(u, far, -70.0)                                     # 闪现到最远敌身后
	u["face_right"] = far["pos"].x > u["pos"].x                # 面向最远敌(背刺sheet已镜像统一朝向)
	battle._beam_vfx("res://assets/sprites/vfx/fx-trail.png", from2d, u["pos"], 34.0, Color(0.8, 0.9, 1.0, 0.55), 0.28)   # 闪现刀光拖影(起点→落点)
	var asd = battle._resolve_action("pets/animations/ninja/backstab-rt.png", 16.0)   # 忍者背刺18帧全身动作(盖身上·播完回idle)
	if not asd.is_empty():
		battle._set_anim_sheet(u, asd, "backstab", false)                            # action="backstab"→_play_action 里挡普攻/受击换anim
		u["_anim_lock_until"] = battle._t + float(asd.get("frames", 18)) / 16.0 + 0.05   # 动作播完前锁出手/移动(用户2026-07-11「动作播完前不打断」)
	# 背刺三段: 每段 300ms 一刀(hitStaggerMs 300) 各 0.6667A 物理 + 斩弧, 目标死则跳过后续段
	var far2: Dictionary = far
	for i in range(3):
		battle._pending_shots.append({"delay": 0.30 * float(i), "src": u, "fn": func():
			if not u.get("alive", false) or not far2.get("alive", false):
				return
			battle._damage._apply_damage_from(u, far2, battle._atk_dmg(u, 0.6667, far2), Color("#cfd8e8"))
			battle._burst_vfx("res://assets/sprites/vfx/ninja-slash.png", far2["pos"], 88.0, 1.0)   # 每刀斩弧
			battle._vfx._hit_spark(far2)
		})

func _sk_ninja_shuriken(u: Dictionary, tgt) -> void:           # 技·手里剑(封板·远程·1:1回合制_ninja_shuriken): 掷旋转飞镖·命中1.6A物理; 暴击(按忍者暴击率)=暴击总伤拆两段→红物理(吃减甲)+白真伤(穿甲·占(40+2%/级)%), 同一发跳两个数字
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var base_dmg: float = float(u["atk"]) * SHURIKEN_COEF               # 1.6A 基础(未减甲/未暴击)
	var is_crit: bool = battle._battle_rng.randf() < minf(float(u.get("crit", 0.0)), 1.0)   # 暴击=忍者自身暴击率(非固定概率)
	var phys_raw: float = base_dmg                            # 非暴击: 全物理一发
	var true_raw: float = 0.0
	if is_crit:
		var crit_mult: float = DamageMath.crit_multiplier(float(u.get("crit", 0.0)), float(u.get("crit_dmg", 1.5)))   # 暴击倍率(溢出100%每1%→1.5%·同_resolve_dmg)
		var crit_total: float = round(base_dmg * crit_mult)  # 暴击总伤(已乘暴击倍率)
		var lv: int = int(u.get("level", 1))
		true_raw = round(crit_total * minf(SHURIKEN_TRUE_CAP, SHURIKEN_TRUE_BASE + SHURIKEN_TRUE_PER_LV * float(lv)) / 100.0)   # 其中(40+2%/级)%(封顶100%)→真实伤害(穿甲)
		phys_raw = maxf(0.0, crit_total - true_raw)           # 余下→物理(吃减甲)
	battle._ballistics._fire_shuriken(u, tgt, phys_raw, true_raw, is_crit)

func _sk_ninja_bomb(u: Dictionary, tgt) -> void:
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var opts = {"phys": BOMB_ATK_COEF, "defDown": BOMB_DEF_DOWN, "color": Color("#ff9a3c")}   # 伤害2.0A(用户2026-07-11)·破甲25%→20%(用户2026-07-29 第五轮·龟能同时 100→120)
	var land: Vector2 = tgt["pos"]            # 落点 = 当前目标位置 (400码爆炸半径中心)
	battle._anticipate(u)                            # 短蓄力(掏炸弹)
	var spr = Sprite3D.new()
	spr.texture = load("res://assets/sprites/vfx/ninja-bomb.png")
	spr.hframes = 12                          # 768×64 = 12帧(球0-4→引信5-7→爆闪8→火球9→蘑菇云10-11); 球在帧内小·爆炸填满帧
	spr.frame = 0
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false; spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = (150.0 * battle.WS) / 64.0      # 炸弹/爆炸尺寸(3D里过大会钻地)
	spr.position = battle._world_pos(u["pos"], 0.8)
	battle._world.add_child(spr)
	# 抛物线(3段弹跳)0.4s + 12帧动画1.2s播一次 (并行), 全播完(1.2s)销毁
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_method(_bomb_arc.bind(spr, u["pos"], land), 0.0, 1.0, 0.4)
	tw.tween_method(_bomb_anim.bind(spr), 0.0, 12.0, 1.2)
	tw.chain().tween_callback(spr.queue_free)
	# 引爆 @0.8s: 震屏 + 400码冲击波环 + 半径伤害 (帧动画此刻正到爆炸帧8)
	var boom = battle._reg_tween()
	boom.tween_interval(0.8)
	boom.tween_callback(_bomb_explode.bind(spr, u, land, opts))

func _bomb_arc(pf: float, spr: Sprite3D, from2d: Vector2, to2d: Vector2) -> void:
	if not is_instance_valid(spr):
		return
	# 3段弹跳抛物线 (1:1 PoC ARC_PEAK -160/-55/-22 → 3D height); 水平线性推进; base 0.6=贴地飞(小炸弹球不钻地)
	var arc: float
	var sub: float
	if pf < 0.5:      sub = pf / 0.5;           arc = 2.6
	elif pf < 0.75:   sub = (pf - 0.5) / 0.25;  arc = 1.0
	elif pf < 0.95:   sub = (pf - 0.75) / 0.20; arc = 0.4
	else:             sub = 1.0;                arc = 0.0
	spr.position = battle._world_pos(from2d.lerp(to2d, pf), 0.6 + arc * 4.0 * sub * (1.0 - sub))

func _bomb_anim(fv: float, spr: Sprite3D) -> void:
	if is_instance_valid(spr):
		spr.frame = mini(11, int(fv))          # 12帧播一次(0→11 不循环·1:1 PoC repeat:0)

func _bomb_explode(spr, u: Dictionary, at2d: Vector2, opts: Dictionary) -> void:
	if is_instance_valid(spr):
		spr.position = battle._world_pos(at2d, 1.3)   # ★爆炸中心抬到贴地(大火球底边≈地面·防中心太低被地面挡=钻地)
	battle._shake(0.16)                               # 1:1 PoC cameras.shake(260)
	# ★400码爆炸范围可视: 扩张冲击波环到 battle.NINJA_BOMB_RADIUS + 内圈亮闪 → 看清波及范围
	battle._skill_ring(at2d, Color(1.0, 0.55, 0.2, 0.9), battle.NINJA_BOMB_RADIUS)
	battle._skill_ring(at2d, Color(1.0, 0.82, 0.4, 0.75), battle.NINJA_BOMB_RADIUS * 0.55)
	# 落点 400码内敌人: 先 -20%护甲(吃在这发上) 再 2.0A 物理; 圈外不受影响
	var col: Color = opts.get("color", Color("#ff9a3c"))
	var hit: Array = []
	for e in battle._targeting._enemies_of(u):
		if e != null and e.get("alive", false) and DetMath.dist(e["pos"], at2d) <= battle.NINJA_BOMB_RADIUS:
			hit.append(e)
	for e in hit:
		battle._apply_skill_extras(u, e, opts)        # -20%护甲(defDown 0.20·BUFF_SEC=5秒)
		battle._skill_ring(e["pos"], Color(col.r, col.g, col.b, 0.5), 46.0)   # 每敌破甲小环
	for e in hit:
		if e.get("alive", false):
			var dmg = battle._atk_dmg(u, float(opts.get("phys", 2.0)), e, false)
			if dmg > 0:
				battle._damage._apply_damage_from(u, e, dmg, col)


## 某个 Sprite3D 精灵表的【最后一帧下标】。★不要写死帧号 ——
## 忍者冲刺表就因为"表从 11 帧换成 7 帧、代码没跟"每次冲刺刷 4 条越界报错,
## 而那条报错当时不在 FATAL 正则里, 红了很久没人看见。
static func _nspr_last(spr) -> int:
	if spr == null or not is_instance_valid(spr):
		return 0
	return maxi(0, int(spr.hframes) * int(spr.vframes) - 1)
