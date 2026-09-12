class_name BattleBallistics
extends RefCounted
## 弹道: 发射(_fire_*各弹种)+逐帧推进(_step_projectiles/_step_pending_shots/_step_homing_arrow)+霰弹弹珠·几何确定性无RNG
## 类内名不变;外部名加 battle.

var battle
## 延时结算队列的两个【静默丢弃点】记账(探针2026-08-22)
var _ps_drop_invalid := 0    # 回调失效
var _ps_drop_cleared := 0    # 换路清空队列
## 暴击对账(仅 DMGSENTINEL): drift=病的频率(分母) / applied_wrong=修完必须恒 0
var _crit_drift := 0
var _crit_applied_wrong := 0

func _init(b) -> void:
	battle = b


## ★★所有弹道【必须】经这里登记 —— 它给每发弹盖上"发射那一刻的伤害类型"。
##
## 由来(2026-08-22 用户实拍):「有的时候物理伤害被跳成了蓝色数字/紫色的」。
## 飘字颜色只看全局 `battle._last_dmg_type`, 而弹在【飞行途中】那个全局会被
## 场上任何一发别的伤害覆写 ⇒ 命中时捡到别人的类型。物理暴击捡到 magic
## 就是 `crit-magic` = 紫字, 与用户描述逐字吻合。
##
## 命中处(`_step_projectiles` frac>=1.0)本来就有一行"用 pr.dtype 还原",
## 但**15 个创建点里只有 3 个真的写了 dtype**, 其余全部落空 ⇒ 那行等于没有。
## ⇒ 不去补 15 处(手抄的副本必然漏一个), 改成【唯一入口】在这里兜底。
## 哨兵 `DMGSENTINEL=1` 量的就是这条路: 修前一场对局 30 发捡类型, 全部出自弹道。
func _push_proj(d: Dictionary) -> void:
	if not d.has("dtype"):
		d["dtype"] = battle._last_dmg_type
	## ★与 dtype 同一个道理: 弹道的伤害是【发射时】算好的, 命中时才落地。
	##   "这一发算没算过护甲"也必须在发射那一刻捕获, 否则命中时问的是"最近一次别人的伤害"。
	if not d.has("dtype_resolved"):
		d["dtype_resolved"] = battle._damage._dt_resolved
	## 暴击态同理(见 battle_damage.set_dtype 的长注释)。`is_crit` 这个键手里剑早就在用,
	## 所以只在【没人写过】时才盖 —— 显式指定的优先。
	if not d.has("is_crit"):
		d["is_crit"] = battle._last_atk_crit
	d["_crit_rolled"] = d["is_crit"]   # 独立副本, 只给门禁对账用(还原用 is_crit)
	battle._projectiles.append(d)

func _fire_trainer_rock(u: Dictionary, tgt: Dictionary, ms_onhit: bool = false) -> void:
	var p = Sprite3D.new()
	var rp = "res://assets/sprites/vfx/lava-rock.png"
	if ResourceLoader.exists(rp):
		p.texture = load(rp)
		p.pixel_size = (26.0 * battle.WS) / float(maxi(1, p.texture.get_height()))
	else:
		p.texture = VfxTex._make_bolt_texture(Color("#b9b3a6"))
		p.pixel_size = 0.02
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false
	p.transparent = true
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var start2d: Vector2 = u["pos"]
	var world_from = battle._world_pos(start2d, 1.1)   # 从胸口高度出手
	p.position = world_from
	battle._world.add_child(p)
	var dist: float = start2d.distance_to(tgt["pos"])
	var pdur = clampf(dist / 650.0, 0.25, 0.9)
	_push_proj({
		"node": p, "from": world_from, "tgt": tgt, "dmg": 1, "col": Color("#d9d2c4"),   # ★伤害写死 1(象征性): 不走 _resolve_dmg 是有意的 —— 吃了护甲也还是 1(maxi(1,…) 兜底)
		"src": u, "t": 0.0, "dur": pdur, "basic_onhit": false,
		"arc": clampf(dist * 0.010, 0.8, 3.2),    # ★抛物线拱高(用户2026-07-23:「弹道是抛物线的」): 远则拱高
		"dtype": "physical", "spin": true, "ms_onhit": ms_onhit,
	})


## ★魔法石(被动·用户2026-07-23): 大师普攻命中→附带 2% 目标最大生命 魔法伤害 + 自己 +5% 攻速(可叠·本场结束重置)。
## ★可测纯函数(不依赖演出): 石头是归巢弹→火时即视作命中, 直接结算(数值稳)。攻速叠层是【计数】(_ms_stacks), 换场清零。
## 008 双穿珊瑚刺的弹体。
## ★★2026-09-08 重做: 改前是 `VfxTex._make_coralspike_texture()` **程序生成** +
##   `TEXTURE_FILTER_LINEAR` + `wisp_dir` 手动 basis 自由旋转 —— 实拍是**一团模糊的粉红雾**
##   飞过去, 完全读不出是"刺"(与 001/003/004/007 完全同族的三件病)。
##   ⇒ 换 Blender 烤的 8 向真素材 + NEAREST + **接现成的 `dirsel` 通道**
##     (按飞行角度选方向帧、贴图永不旋转), 不再手抄一份朝向逻辑。
const CORAL_SPIKE_TEX := "res://assets/sprites/vfx/eq008-coralspike.png"
const CORAL_SPIKE_DIRS := 8
const CORAL_SPIKE_PX := 0.040     # 40px 长的刺 x 0.040 = 1.6 米(龟 2.0 米), 是"一根刺"不是"一根柱子"

func _fire_coral_spike(src: Dictionary, tgt: Dictionary, si: int) -> void:   # 珊瑚尖刺弹→最远敌(dirsel 选帧不旋转)·命中(arrival)物理+%maxHP魔法+珊瑚碎裂
	if tgt == null: return
	if battle._coralspike_tex == null: battle._coralspike_tex = load(CORAL_SPIKE_TEX)
	var start2d: Vector2 = src["pos"]
	var p = Sprite3D.new()
	p.texture = battle._coralspike_tex
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED    # 正对相机, 方向靠选帧
	p.shaded = false; p.transparent = true
	p.pixel_size = CORAL_SPIKE_PX
	p.frame = 0
	p.hframes = CORAL_SPIKE_DIRS; p.vframes = 1       # ★改 hframes 前先归零(setter 会校验当前 frame)
	p.position = battle._world_pos(start2d, 1.0)
	battle._world.add_child(p)
	_push_proj({
		"node": p, "from": battle._world_pos(start2d, 1.0), "tgt": tgt, "dmg": 0, "col": Color(1.0, 0.5, 0.36),
		"src": src, "t": 0.0, "dur": clampf(start2d.distance_to(tgt["pos"]) / 900.0, 0.22, 0.8),
		"coral_spike": true, "dirsel": true, "co_si": si,
	})

func _fire_bolt_from(src, tgt: Dictionary, dmg: int, col: Color, from = null, basic_onhit: bool = false) -> void:
	var start2d: Vector2 = from if from != null else (src["pos"] if src != null else tgt["pos"])
	var p = Sprite3D.new()
	var oriented = false
	var card_spin = false
	if src is Dictionary and str(src.get("id", "")) == "gambler":   # 赌神: 甩旋转扑克牌(黑桃A)
		p.texture = load("res://assets/sprites/vfx/gambler-card.png")
		p.pixel_size = 0.9 / 54.0   # ~0.9m 高扑克牌
		p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		card_spin = true
	elif src is Dictionary and str(src.get("id", "")) == "space":   # 星际: 星形星光弹(紫白星星·2026-07-15)
		p.texture = VfxTex._make_star_texture()
		p.pixel_size = 0.016
		p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # ★像素贴图: LINEAR 会把它糊成渐变(spec 阶段 4 第一条)
		p.modulate = Color(0.9, 0.8, 1.0)
	elif src is Dictionary and str(src.get("id", "")) == "crystal":   # 水晶: 射冰蓝碎晶(尖端朝前·2026-07-15)
		p.texture = load("res://assets/sprites/vfx/crystal-shard.png")
		p.pixel_size = (30.0 * battle.WS) / float(maxi(1, p.texture.get_height()))
		p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		oriented = true
	elif src is Dictionary and str(src.get("id", "")) == "hunter":   # 猎人: 射箭矢(4帧·点先行贴XZ转向行进方向·接现有hunter-arrow素材)
		p.texture = load("res://assets/sprites/vfx/hunter-arrow.png")
		p.hframes = 4; p.frame = 0
		p.pixel_size = (72.0 * battle.WS) / 128.0   # 箭512×128 4帧·每帧128 → ~1.7m箭
		p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		oriented = true
	elif src is Dictionary and battle._PROJ_WAVE.get(str(src.get("id", "")), false):
		p.texture = VfxTex._make_wave_texture(col)
		p.pixel_size = 0.045   # 尖尖波 52×20 → ~2.3×0.9m
		p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # ★像素贴图: LINEAR 会把它糊成渐变(spec 阶段 4 第一条)
		oriented = true        # 尖尖波有朝向→贴XZ绕Y转向行进方向(否则billboard永远面镜头指右, 斜射/上下射方向错)
	else:
		p.texture = VfxTex._make_bolt_texture(col)
		p.pixel_size = 0.014
	if oriented:
		p.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		p.axis = Vector3.AXIS_Y
	elif card_spin:
		p.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # 手动: 面向相机+滚转(旋转扑克牌)
	else:
		p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false
	p.transparent = true
	var world_from = battle._world_pos(start2d, 1.0)   # 从胸口高度出
	p.position = world_from
	battle._world.add_child(p)
	var pdur = clampf(start2d.distance_to(tgt["pos"]) / 700.0, 0.22, 0.7)
	if card_spin: pdur = clampf(start2d.distance_to(tgt["pos"]) / 430.0, 0.42, 1.1)   # 扑克牌弹道放慢看清(用户2026-07-14)
	var _stt: int = 0
	if basic_onhit and src is Dictionary and str(src.get("id", "")) == "space" and float(src.get("star_energy", 0.0)) > 0.0:
		_stt = int(float(src["star_energy"]) * StarSystem.ENERGY_TRUE_PCT)   # 星能追加真伤=12%当前星能(用户2026-07-16: 30%→12%)·打包进普攻弹道命中才结算
	_push_proj({
		"node": p, "from": world_from, "tgt": tgt, "dmg": dmg, "col": col,
		"src": src, "t": 0.0, "dur": pdur, "basic_onhit": basic_onhit, "star_true": _stt,
		"oriented": oriented, "card_spin": card_spin, "dtype": battle._last_dmg_type,
	})

# 幽灵普攻·幽魂弹道(专属ghost-wisp): 携物理+真实, 命中同发红白两数字(修不同时跳)+灵体怨气
func _fire_ghost_wisp(u: Dictionary, tgt: Dictionary) -> void:
	var atk: float = u["atk"]
	var start2d: Vector2 = u["pos"]
	var p = Sprite3D.new()
	p.texture = load("res://assets/sprites/vfx/ghost-wisp.png")
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # 定向弹道(不billboard·锥尖领着飞·用户2026-07-11「方向不对」)
	p.shaded = false; p.transparent = true
	p.modulate = Color(0.75, 1.0, 0.88, 0.95)
	p.pixel_size = (52.0 * battle.WS) / 64.0
	var world_from = battle._world_pos(start2d, 1.0)
	p.position = world_from
	battle._world.add_child(p)
	_push_proj({
		"node": p, "from": world_from, "tgt": tgt, "src": u, "t": 0.0,
		"dur": clampf(start2d.distance_to(tgt["pos"]) / 620.0, 0.2, 0.62),
		"ghost_touch": true, "gt_phys": 0.4 * atk, "gt_true": 0.9 * atk, "basic_onhit": true, "wisp_dir": true,
	})

## 战斗场还在不在树上。
##
## ★由来(2026-08-22): smoke 间歇刷 `Condition "!is_inside_tree()" is true. Returning: Transform3D()`。
##   根因不是触手 —— 是**弹道每帧读相机朝向**(旋转扑克牌/手里剑要 `battle._vfx.cam_basis()`)。
##   战斗场被硬释放时相机先离树, 而 `_step_projectiles` 还会再跑一帧 ⇒ 引擎报错。
##   ⚠ 我第一版猜是触手, 给 `tentacle_vfx.tick` 加了守卫, 那一轮门禁碰巧全绿 ——
##     **那是运气不是修好了**(下一轮又红)。真正的读点靠 `grep global_transform` 数出来:
##     ballistics 9 处、主场景 7 处, 全是 `battle._cam.` 那一族。
func _scene_live() -> bool:
	return battle._world != null and is_instance_valid(battle._world) and battle._world.is_inside_tree() 		and battle._cam != null and is_instance_valid(battle._cam) and battle._cam.is_inside_tree()


func _step_projectiles(delta: float) -> void:
	if not _scene_live():
		return
	var ts_on: bool = not battle._timestop._ts_active.is_empty()
	var keep: Array = []
	for pr in battle._projectiles:
		## ★2026-09-06 从 `Sprite3D` 放宽到 `Node3D`：001 飞斩剑气改成 LoL 式束身后
		##   是 `MeshInstance3D`(quad + 滚动 shader)，不再是 Sprite3D。
		##   本循环里用到的全是 `Node3D` 的东西(position / global_transform / queue_free)，
		##   只有少数分支要 Sprite3D 的属性(frame/flip_h)，那几处各自就地转型。
		var node: Node3D = pr["node"]
		if not is_instance_valid(node):
			continue
		if ts_on and not battle._arr_has_unit(battle._timestop._ts_active, pr.get("src")):   # 同7595: Array.has对单位字典是深比较, 改引用比较
			keep.append(pr); continue   # 时停: 非active携带者的弹道悬空定格(不推进)
		pr["t"] += delta
		if pr.get("homing_arc", false):   # 猎人狩猎弹幕: 慢速抛物线追踪箭(自处理移动/命中/朝向)
			if _step_homing_arrow(pr, node, delta):
				keep.append(pr)
			continue
		var tgt: Dictionary = pr["tgt"]
		var to = battle._world_pos(tgt["pos"], 1.0)
		var frac: float = clampf(pr["t"] / pr["dur"], 0.0, 1.0)
		node.position = pr["from"].lerp(to, frac)

		## ══════════════════════════════════════════════════════════════
		##  ★★★像素风弹体的两件事(2026-09-06, 001 飞斩剑气重做时加的通用件)
		## ══════════════════════════════════════════════════════════════
		## 用户「我要完全对齐 lol 的」「不要考虑成本，不可以省事」。
		## LoL 的**意图**要搬(弹体一直在动 / 拖尾跟速度走 / 五段分离)，
		## 它的**手段**不能搬(3D mesh + 滚动 UV) —— 像素风里那样会把像素拉成长方形。
		##
		## ① `dirsel`: **按飞行角度选方向帧，贴图永不旋转**。
		##    旋转会让像素落在非网格位置 ⇒ 边缘锯齿、飞行中抖动。
		##    全仓此前所有弹体都靠 `wisp_dir` 旋转贴图，这是第一个不旋转的。
		## ★格数由贴图自己的 `hframes` 决定, 不写死 —— 001 一开始做成 8 方向, 实测发现
		##   【8 格里只有 1 格被用过】(探针量飞行全程 di 恒 0), 而另外 7 格贡献了全部素材缺陷,
		##   改成 4 方向(见 tools/build_dir_sheet.py 头注)。写死格数的话这里就得跟着改两处。
		if pr.get("dirsel", false) and node is Sprite3D and battle._cam != null:
			var spd: Sprite3D = node as Sprite3D
			var nd: int = maxi(1, int(spd.hframes))
			## ★方向由【整条航线】(from→to)算, 不由"当前位置→目标"算: 后者在快命中时
			##   delta 缩到几个像素, 2.5D 相机的俯角会让 y 分量占主导, 下标有末段翻格的风险。
			##   航线是常量, 全程只有一个下标。
			## ★★这是**防御性**改动, 不是修了一个已复现的 bug —— 说清楚免得下一个人误会:
			##   我看实拍觉得"t=3.10 竖的、t=3.30 变横的", 量下来两帧轴向 179.3 vs 179.6(差 0.3°),
			##   **根本没翻**; 3.30 那个横着的东西是【拖尾残影】不是弹体。
			##   (同一天第三次"目视报了个不存在的 bug"。判断朝向一律先量再说。)
			var a2: Vector2 = battle._cam.unproject_position(to) 				- battle._cam.unproject_position(pr["from"] if pr.has("from") else node.global_position)
			if a2.length() > 0.5:
				## 屏幕空间角度 → 方向下标。-a2.y 是因为屏幕 Y 向下。
				var ang: float = atan2(-a2.y, a2.x)
				var di: int = int(round(ang / (TAU / float(nd)))) % nd
				if di < 0: di += nd
				spd.frame = int(float(pr["t"]) * 14.0) % int(spd.vframes) * nd + di
		## ② `afterimage`: 每隔 N 秒留一个当前帧的半透明副本, **原地淡出**。
		##    这就是"拖尾"—— 数量跟飞行速度走(飞得快 ⇒ 同样时间跨的距离长 ⇒ 残影铺得开),
		##    所以**绝不能把拖尾画进贴图**(画死了就是"飞快飞慢都那么长")。
		if pr.has("afterimage") and node is Sprite3D:
			pr["_ai_t"] = float(pr.get("_ai_t", 0.0)) + delta
			if float(pr["_ai_t"]) >= float(pr["afterimage"]) and frac < 0.94:
				pr["_ai_t"] = 0.0
				_spawn_afterimage(node as Sprite3D, float(pr.get("ai_life", 0.20)))
		if pr.has("arc"):
			node.position.y += float(pr["arc"]) * sin(PI * frac)   # 抛物线拱起(火球等)
		if pr.get("oriented", false):                              # 尖尖波: 绕Y转向行进方向(尖端领着飞)
			var d3: Vector3 = to - node.position
			if d3.length() > 0.05:
				node.rotation.y = -atan2(d3.z, d3.x)
		if pr.get("wisp_dir", false) and battle._cam != null:            # 幽魂弹: 正对镜头+屏幕roll→火苗尖指向目标屏幕方向(用户2026-07-11)
			var ss2: Vector2 = battle._cam.unproject_position(node.global_position)
			var st2: Vector2 = battle._cam.unproject_position(to)
			var sd2: Vector2 = st2 - ss2
			if sd2.length() > 1.0:
				var roll2: float = atan2(-sd2.y, sd2.x) - PI / 2.0 + float(pr.get("wisp_off", 0.0))   # wisp_off: 纹理朝前方向修正(默认+Y; 横向贴图=+X 传 PI/2)
				var wtf2: Transform3D = node.global_transform
				wtf2.basis = battle._vfx.cam_basis() * Basis(Vector3(0, 0, 1), roll2)
				node.global_transform = wtf2
		if pr.get("card_spin", false) and battle._cam != null:            # 赌神: 面向相机+滚转(旋转扑克牌·复用wisp_dir的相机basis法)
			var ctf: Transform3D = node.global_transform
			ctf.basis = battle._vfx.cam_basis() * Basis(Vector3(0, 0, 1), pr["t"] * 13.0)
			node.global_transform = ctf
		## ★★2026-08-29 改成通用: **只要弹体是多帧贴图就逐帧播**。
		##   原来这个闸只对手里剑开(`shuriken_anim`), 所以猎人的 4 帧箭矢
		##   (`p.hframes = 4` 在 :112)其实**一帧都没动过** —— 挂了帧数却没人推。
		##   用户 2026-08-29:「不要拿图片贴图敷衍我, **我要动画像素特效**」⇒ 这条得是通用的,
		##   否则每加一个动画弹体都要回来开一次闸, 而漏开是静默的(看着就是"贴图不动")。
		##   ★2026-09-06 补 `is Sprite3D` 守卫: 001 改成 LoL 式束身后弹体是 `MeshInstance3D`,
		##     它没有 `hframes` ⇒ 无条件读会每帧刷 `Invalid access to property or key 'hframes'`
		##     (实测一次台子跑出 379 条)。逐帧播只对 Sprite3D 有意义。
		## ★★`dirsel` 的弹体**必须跳过这段**。
		##   这段是给普通弹体做逐帧动画的: 拿 `hframes` 当"动画帧数"取模。
		##   而方向表里 **`hframes` 是"方向数"不是"帧数"** ⇒ 它每秒 18 次在
		##   东→北→西→南 之间循环, **看上去就是剑气在自转**;
		##   而且它在这一行(晚于上面 dirsel 的赋值), 每帧把算好的方向覆盖掉。
		##   用户连问四次「为什么弹道在旋转」, 根因就是这里。
		##   ⇒ 我的探针打在 dirsel 那行, 打出来 di 恒为 0 —— **打的是被覆盖之前的值**,
		##     所以查了很久没查到。逐帧截 400 张图才看见它在横竖之间跳。
		if node is Sprite3D and int((node as Sprite3D).hframes) > 1 and not pr.get("dirsel", false):
			var sp3: Sprite3D = node as Sprite3D
			sp3.frame = int(float(pr["t"]) * float(pr.get("anim_fps", 18.0))) % int(sp3.hframes)
		if frac >= 1.0:
			node.queue_free()
			if tgt["alive"]:
				if pr.has("dtype"):
					## ★对账(DMGSENTINEL 才记): drift = 还原【之前】全局的暴击与本弹发射时
					##   掷的不一致 —— 这是病本身的频率, 也是本条门禁的**分母**(它为 0 说明
					##   这一场根本没有跨帧弹道, 断言就是空的)。
					##   applied = 还原【之后】仍不一致 —— 必须恒为 0; 谁把还原删了它就非 0。
					if OS.has_environment("DMGSENTINEL"):
						if bool(pr.get("_crit_rolled", false)) != bool(battle._last_atk_crit):
							_crit_drift += 1
					battle._damage.set_dtype(str(pr["dtype"]), tgt, bool(pr.get("is_crit", false)), bool(pr.get("dtype_resolved", false)))
					if OS.has_environment("DMGSENTINEL"):
						if bool(pr.get("_crit_rolled", false)) != bool(battle._last_atk_crit):
							_crit_applied_wrong += 1   # ★弹道命中: 还原发射时捕获的类型(飞行期全局会被别的伤害覆写→飘字色错·用户2026-07-11)
				if pr.get("fireball", false):   # 抛物线火球045: 落点火爆+魔法伤(蓝字)+灼烧
					battle._damage._apply_damage_from(pr["src"], tgt, battle._resolve_dmg(pr["src"], float(pr["dmg"]), tgt, true), pr["col"], 0.0, false, true)
					if pr.get("fire_burst", 0) > 0:
						battle._damage._apply_dot_stacks(tgt, "burn", int(pr["fire_burst"]), pr["src"])
					_fire_explosion(tgt["pos"])
				elif pr.get("bamboo", false):   # 竹枝箭039: 命中演出照抄竹叶龟强化普攻(用户2026-07-19"特效用竹叶龟同款")
					battle._damage._apply_damage_from(pr["src"], tgt, battle._resolve_dmg(pr["src"], float(pr["dmg"]), tgt, true), pr["col"], 0.0, false, true)
					battle._hitstop = maxf(battle._hitstop, 0.06)                                # 顿帧=命中厚重感
					battle._shake(0.06)
					battle._vfx._impact_particles(tgt["pos"], float(tgt.get("height", 0.0)))   # 命中碎屑迸发
					battle._vfx._flash(tgt, Color(0.5, 1.7, 0.65))                             # 敌绿闪(生长主题)
					battle._bamboo_sys._bamboo_hit_splash(tgt)                                        # 大淡绿命中爆(≈上半身大小)
					var _bsrc: Dictionary = pr["src"]
					var _bgrow: float = float(pr.get("bamboo_grow", 0.0))   # ★不乘HP_MULT: 装备hp已是最终值(见L45规则), 原来乘了→永久成长实发150/210/270=文案50/70/90的3倍
					battle._spawn_bamboo_orb(tgt["pos"], _bsrc["pos"], func() -> void:    # 绿球飞回携带者, 落到身上才吸收
						if not _bsrc.get("alive", false):
							return
						battle._damage._heal(_bsrc, _bsrc["maxHp"] * 0.06)
						if _bgrow > 0.0:
							_bsrc["maxHp"] += _bgrow; _bsrc["hp"] += _bgrow
							battle._recalc_stats(_bsrc)
						battle._vfx._flash(_bsrc, Color(0.5, 1.7, 0.65)))                      # 吸收瞬间携带者绿闪
				elif pr.get("shuriken_hit", false):   # 手里剑: 物理段(红·减甲)+暴击时真伤段(白·穿甲)→同发跳两数字(飘字系统按类型自动错开行·不合并)
					battle._last_atk_crit = bool(pr.get("is_crit", false))   # 两段都按暴击显示(大字+暴击图标)
					battle._damage.set_dtype("physical", tgt, null, true)   # ★下一行走 _phys_after_armor = 真算护甲
					battle._damage._apply_damage_from(pr["src"], tgt, battle._phys_after_armor(pr["src"], float(pr["nj_phys"]), tgt), Color("#ff4444"), 0.0, false, false, false, false, false, true)   # 物理段(红·basic=普攻)
					if float(pr.get("nj_true", 0.0)) >= 1.0 and tgt.get("alive", false):
						battle._last_atk_crit = bool(pr.get("is_crit", false))   # 物理段hook可能改写→真伤段前重置
						battle._damage._apply_damage_from(pr["src"], tgt, int(round(float(pr["nj_true"]))), Color("#ffffff"), 0.0, true, false, true, false, false, true)   # 真伤段(白·pre_crit=已含暴击不再二次掷·basic=普攻)
				elif pr.get("ghost_touch", false):   # 幽魂触碰: 物理(红·减甲)+真实(白·穿甲) 命中同发跳两数字
					battle._damage.set_dtype("physical", tgt, null, true)   # ★下一行走 _phys_after_armor = 真算护甲
					battle._damage._apply_damage_from(pr["src"], tgt, battle._phys_after_armor(pr["src"], float(pr["gt_phys"]), tgt), Color("#ff4444"), 0.0, false, false, false, false, false, true)
					if tgt.get("alive", false):
						battle._damage._apply_damage_from(pr["src"], tgt, int(round(float(pr["gt_true"]))), Color("#ffffff"), 0.0, true, false, false, false, false, true)
					battle._ghost_sys._ghost_touch_hit(tgt["pos"])
				elif pr.get("eq_bolt", false):   # 装备弹道(弩矢/飞镖等): 记为装备物理伤, 命中溅火花
					battle._damage._apply_damage_from(pr["src"], tgt, pr["dmg"], pr["col"], float(pr.get("eq_ls", 0.0)), false, true)
					if pr.get("eq_bleed", 0) > 0:
						battle._damage._apply_dot_stacks(tgt, "bleed", int(pr["eq_bleed"]), pr["src"])
					battle._vfx._hit_spark(tgt)
				elif pr.get("flyslash", false):   # 木制长剑001飞斩: 命中才结算装备物理伤(红字)
					battle._damage._apply_damage_from(pr["src"], tgt, pr["dmg"], Color("#ff4444"), 0.0, false, true)
					## ★2026-09-06: 命中原来【只有伤害数字 + 一条程序生成的斩弧】。
					##   LoL 式五段结构里 ⑤impact 是独立的一次性特效，锚在命中点 ——
					##   现在接上真素材(`eq001-flyslash-impact.png` 8 帧)。
					battle._vfx.flyslash_impact(tgt["pos"], pr["col"])
				elif pr.get("venom_fang", false):   # 暴君之牙004毒牙: 命中魔法伤(紫)+毒液飞溅+回复携带者100%造成伤害
					var vd: int = battle._resolve_dmg(pr["src"], float(pr.get("fang_base", 0.0)), tgt, true)
					battle._damage._apply_damage_from(pr["src"], tgt, vd, Color("#c96bff"), 0.0, false, true)
					battle._venom_splat(tgt["pos"])
					if pr["src"].get("alive", false):
						battle._damage._heal(pr["src"], float(vd) * EquipSystem.FANG_LIFESTEAL)   # 回复100%造成的伤害值
				elif pr.get("coral_spike", false):   # 双穿珊瑚刺008: 命中→物理(红)+ %maxHP魔法(蓝·走魔抗·修原raw白字真伤)+珊瑚碎裂
					var cs: int = int(pr.get("co_si", 2))
					battle._damage._apply_damage_from(pr["src"], tgt, battle._atk_dmg(pr["src"], [1.0, 1.2, 1.5][cs], tgt), Color("#ff4444"), 0.0, false, true)
					battle._damage._apply_damage_from(pr["src"], tgt, battle._resolve_dmg(pr["src"], float(tgt["maxHp"]) * [0.08, 0.12, 0.18][cs], tgt, true), Color("#bfe9ff"), 0.0, false, true)
					battle._vfx.coral_burst(tgt["pos"])
				elif pr.get("drone_shot", false):   # 赛博浮游炮弹: 命中→本弹触发的装备充能/叠层减半(只减浮游炮触发·本体不减·用户2026-07-19)
					battle._equip_sys._eq_drone_halve = true
					battle._damage._apply_damage_from(pr["src"], tgt, pr["dmg"], pr["col"], 0.0, false)
					battle._equip_sys._eq_drone_halve = false
				elif pr["src"] != null:
					battle._damage._apply_damage_from(pr["src"], tgt, pr["dmg"], pr["col"], 0.0, pr.get("raw", false), false, false, false, false, pr.get("basic_onhit", false))   # raw=手里剑暴击转真伤等; basic 随弹道标
				else:
					battle._damage._apply_damage(tgt, pr["dmg"], pr["col"])
				battle._vfx._flash(tgt)
				if pr.get("basic_onhit", false) and pr["src"] != null:
					battle._on_basic_hit(pr["src"], tgt)   # 远程普攻附带(审判等)弹道命中时触发→与裁决同帧跳数字
				if pr.get("freeze_on_hit", 0.0) > 0.0:
					battle._freeze(tgt, pr["freeze_on_hit"])   # 冰封: 弹道命中→冻结
				if pr.get("coin_true", 0) > 0:
					battle._damage._apply_damage_from(pr["src"], tgt, int(pr["coin_true"]), Color("#fff0a0"), 0.0, true)   # 金币真实那半
				if pr.get("ms_onhit", false) and pr["src"] != null and tgt.get("alive", false):
					battle._trainer_sys._trainer_magicstone_onhit(pr["src"], tgt)   # 魔法石那段: 与物理【同帧】跳字
				if pr.get("star_true", 0) > 0 and tgt.get("alive", false):
					battle._damage._apply_damage_from(pr["src"], tgt, int(pr["star_true"]), Color("#ffffff"), 0.0, true)   # 星能追加真伤(白字·附普攻命中同帧·用户2026-07-16)
			continue
		keep.append(pr)
	battle._projectiles = keep

# 依次射出的子弹: 每帧减 delay, 到点 call 回调(回调内部再选目标+射线+伤害, 死亡守卫在回调里判)
# 依次射出的子弹: 每帧减 delay, 到点 call 回调(回调内部再选目标+射线+伤害, 死亡守卫在回调里判)
func _step_pending_shots(delta: float) -> void:
	if not _scene_live():
		return
	var ts_on: bool = not battle._timestop._ts_active.is_empty()
	for i in range(battle._pending_shots.size() - 1, -1, -1):
		var s: Dictionary = battle._pending_shots[i]
		if ts_on and not battle._arr_has_unit(battle._timestop._ts_active, s.get("src")):   # is_same引用比较(Array.has对字典是深比较=053卡死同族; 上轮扫雷因它不是裸标识符而漏网)
			continue   # 时停: 非active携带者的依次射击冻结
		s["delay"] = float(s["delay"]) - delta
		if float(s["delay"]) <= 0.0:
			battle._pending_shots.remove_at(i)
			var fn = s["fn"]
			if fn is Callable and fn.is_valid():
				fn.call()
			else:
				## 静默丢弃点(探针·2026-08-22): 回调失效 ⇒ 演出照演、结算永不发生。
				_ps_drop_invalid += 1

# 排队 count 发子弹, 每发间隔 interval 秒, 逐发 call fn (fn 内部自选目标, 支持死亡守卫)
func _shotgun_pellet(from2d: Vector2, to2d: Vector2, col: Color, dur: float = 0.42, on_land: Callable = Callable()) -> void:
	if battle._pellet_tex == null: battle._pellet_tex = VfxTex._make_pellet_texture()
	var sp = Sprite3D.new()
	sp.texture = battle._pellet_tex
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.modulate = col
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false; sp.transparent = true
	sp.pixel_size = 0.02
	var perp = (to2d - from2d).orthogonal().normalized() if (to2d - from2d).length() > 1.0 else Vector2.UP
	sp.position = battle._world_pos(from2d + perp * randf_range(-18.0, 18.0), 1.0)
	battle._world.add_child(sp)
	var tw = battle._reg_tween()   # 顺序: 全程满alpha飞行 → 命中处才快速淡出(修"路中间淡化"用户2026-07-04)
	tw.tween_property(sp, "position", battle._world_pos(to2d, 1.0), dur).set_ease(Tween.EASE_OUT)
	if on_land.is_valid():
		tw.tween_callback(on_land)          # 弹珠飞到才结算(用户2026-07-19: 原来开火瞬间就结算, 数字比弹珠先到)
	tw.tween_property(sp, "modulate:a", 0.0, 0.1)
	tw.tween_callback(sp.queue_free)

# 装备弹道(弩矢/飞镖等真实贴图投射物): 朝向随飞行方向(2.5D近似 z-roll), 命中记装备物理伤. eq_bleed=命中附加流血层
func _fire_venom_fang(src: Dictionary, tgt: Dictionary, base: float) -> void:
	## 毒牙弹(004 暴君之牙): 飞向目标, 命中(arrival)结算魔法伤 + 毒液飞溅 + 回复。
	## ★2026-09-07 重做 —— 改造前三个毛病与 001 改造前一模一样(实拍确认):
	##   ① 贴图是 `VfxTex._make_venomfang_texture()` 程序生成的软条
	##   ② `TEXTURE_FILTER_LINEAR` ⇒ 糊成一条紫光带, 读起来像激光不像獠牙
	##   ③ `wisp_dir` 旋转贴图 ⇒ 像素落在非网格位置(像素风不许自由旋转)
	## ⇒ 换真素材 + NEAREST + **按飞行角度选方向帧**(4 格, 牙尖朝向已逐格自证)。
	if tgt == null: return
	if _venomfang_sheet == null:
		_venomfang_sheet = load("res://assets/sprites/vfx/eq004-venomfang-dir4.png")
	if _venomfang_sheet == null: return
	var start2d: Vector2 = src["pos"]
	var p := Sprite3D.new()
	p.texture = _venomfang_sheet
	p.hframes = 4          # 4 个方向(东/北/西/南) —— 不是 4 帧动画
	p.vframes = 1
	p.frame = 0
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # 正对相机, **不旋转** —— 方向靠选帧
	p.shaded = false; p.transparent = true
	p.pixel_size = TARGET_BODY_H_FANG / 32.0         # 与龟同口径
	## ★整体染成旧那版的毒紫 #c96bff —— 硬边与内部明暗层级由素材保留, modulate 只换色相。
	##   用户实拍对比后指出新版"不如之前": 旧的强在**饱和亮紫 + 拖得长**, 素材换硬边不该丢掉这两点。
	p.modulate = Color("#c96bff")
	p.position = battle._world_pos(start2d, 1.0)
	battle._world.add_child(p)
	_push_proj({
		"node": p, "from": battle._world_pos(start2d, 1.0), "tgt": tgt, "dmg": 0, "col": Color("#c96bff"),
		"src": src, "t": 0.0, "dur": clampf(start2d.distance_to(tgt["pos"]) / 700.0, 0.28, 0.84),
		"venom_fang": true, "fang_base": base,
		"afterimage": 0.016,     # 拖尾很密(毒牙飞得快, 要拉出旧版那种"一条带"的速度感)
		"ai_life": 0.34,         # 残影活久一点 ⇒ 尾更长(实测 0.20 只有约 2 个龟身, 旧版跨 3 个)
		"_ai_t": 0.0,
		"dirsel": true,          # 按飞行角度选方向帧(不旋转) —— 见本文件 _step_projectiles
	})

func _fire_ice_shard(src: Dictionary, tgt: Dictionary, dmg: int, freeze_sec: float = 1.5) -> void:   # 冰锥弹道(命中魔伤+冻结; 时长传参·2026-07-28 寒冰改2.5s, 默认值保持旧行为)
	var start2d: Vector2 = src["pos"]
	var p = Sprite3D.new()
	p.texture = VfxTex._make_ice_cone_texture()
	p.pixel_size = 0.04
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	p.billboard = BaseMaterial3D.BILLBOARD_DISABLED           # 冰锥有朝向→贴XZ绕Y转向目标(不再永远水平指右/左·斜射方向对·用户2026-07-11)
	p.axis = Vector3.AXIS_Y
	p.shaded = false
	p.transparent = true
	var world_from = battle._world_pos(start2d, 1.0)
	p.position = world_from
	battle._world.add_child(p)
	var dur = clampf(start2d.distance_to(tgt["pos"]) / 600.0, 0.35, 0.9)   # 恒速~600px/s, 慢到看得清(原0.2太快)
	_push_proj({
		"node": p, "from": world_from, "tgt": tgt, "dmg": dmg, "col": Color("#4dabf7"),
		"src": src, "t": 0.0, "dur": dur, "basic_onhit": false, "freeze_on_hit": freeze_sec, "oriented": true, "dtype": battle._last_dmg_type,
	})

func _fire_shuriken(src: Dictionary, tgt: Dictionary, phys_raw: float, true_raw: float, is_crit: bool) -> void:   # 旋转飞镖弹道(4帧自旋): 命中→物理段(红·减甲)+可选真伤段(白·穿甲)·暴击金染
	var start2d: Vector2 = src["pos"]
	var p = Sprite3D.new()
	p.texture = load("res://assets/sprites/vfx/ninja-shuriken.png")
	p.hframes = 4                                              # 512×128 = 4帧忍者飞镖(旋转)
	p.frame = 0
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED             # 面镜头·靠帧旋转不靠转node
	p.shaded = false; p.transparent = true
	p.modulate = (Color(1.0, 0.86, 0.4, 1.0) if is_crit else Color(1, 1, 1, 1))   # 暴击金染 / 普通原色
	p.pixel_size = (58.0 * battle.WS) / 128.0
	var world_from = battle._world_pos(start2d, 1.0)
	p.position = world_from
	battle._world.add_child(p)
	var dur = clampf(start2d.distance_to(tgt["pos"]) / 850.0, 0.12, 0.5)   # 快镖
	_push_proj({
		"node": p, "from": world_from, "tgt": tgt, "src": src, "t": 0.0, "dur": dur,
		"shuriken_hit": true, "shuriken_anim": true,
		"nj_phys": phys_raw, "nj_true": true_raw, "is_crit": is_crit,
	})

func _fire_hunter_arrow(u: Dictionary, tgt: Dictionary, dmg: int) -> void:   # 慢速抛物线追踪箭(箭头随行进角度转·命中才跳白色真伤·处决由中央路径判egg免疫)
	var tex: Texture2D = load("res://assets/sprites/vfx/hunter-arrow.png")
	if tex == null: return
	var fh: int = maxi(1, tex.get_height())
	var p = Sprite3D.new()
	p.texture = tex
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.hframes = maxi(1, int(tex.get_width() / fh))
	p.frame = 0
	p.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # 手动in-plane roll朝向(箭头随角度)
	p.shaded = false; p.transparent = true
	p.pixel_size = (66.0 * battle.WS) / float(fh)
	var from2d: Vector2 = u["pos"]
	p.position = battle._world_pos(from2d, 1.2)
	battle._world.add_child(p)
	_push_proj({
		"node": p, "tgt": tgt, "src": u, "dmg": dmg, "col": Color("#ffffff"),
		"t": 0.0, "homing_arc": true, "pos2d": from2d, "h0": 1.2,
		"init_dist": maxf(120.0, from2d.distance_to(tgt["pos"])),
		"arc": 4.6, "raw": true,
	})

## 弹体残影(afterimage) —— 复制当前这一帧，**原地不动**地淡出。
## ★这是像素风做拖尾的正确手段：拖尾长度由「残影间隔 × 飞行速度」自然给出，
##   不是画在贴图里的一条固定长度的尾巴(那样飞快飞慢都一样长 = 穿帮)。
## ★残影不参与任何结算，纯视觉；`_reg_tween` 保证场景释放时一起收掉。
func _spawn_afterimage(src: Sprite3D, life: float = 0.20) -> void:
	## ★`life` 决定拖尾有多长: 残影存活越久, 同一时刻在场的副本越多 ⇒ 尾越长。
	##   默认 0.20(001 剑气用); 毒牙给 0.34 —— 用户实拍指出新版拖尾不如旧版长。
	## ★`_scene_live()` 在**本类**身上, 不在 battle 上 —— 写 `battle._scene_live()` 会每帧刷
	##   "Nonexistent function ... in base Node3D"(实测一次跑 35 条), 而残影静默不出。
	if not _scene_live() or battle._world == null:
		return
	var g := Sprite3D.new()
	g.texture = src.texture
	g.hframes = src.hframes
	g.vframes = src.vframes
	g.frame = src.frame
	g.billboard = src.billboard
	g.shaded = false
	g.transparent = true
	g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	g.pixel_size = src.pixel_size
	g.global_transform = src.global_transform
	var c: Color = src.modulate
	g.modulate = Color(c.r, c.g, c.b, 0.42)
	battle._world.add_child(g)
	## ★不能写 `var tw := battle._reg_tween()` —— `battle` 无类型, `:=` 推不出返回类型,
	##   GDScript 会报 Parse Error 让【整个脚本编译失败】⇒ 所有子系统变 Nil,
	##   表现是每帧刷 "Nonexistent function ... in base 'Nil'"(实测一次跑出 8.7 万条),
	##   而真正的 Parse Error 只在日志最上面出现一次, 极易被淹掉。
	var tw: Tween = battle._reg_tween()
	tw.set_parallel(true)
	## ★残影随寿命【收细】—— 不收的话尾巴是一串等大的块, 读成"一坨"而不是"一条带"。
	##   旧版毒牙那条紫光带强在**细而长**, 换硬边素材后要靠这个把"细"补回来。
	tw.tween_property(g, "scale", g.scale * 0.35, life)
	tw.tween_property(g, "modulate:a", 0.0, life)
	tw.chain().tween_callback(g.queue_free)


func _step_homing_arrow(pr: Dictionary, node: Sprite3D, delta: float) -> bool:   # 追踪抛物箭逐帧: 追踪移动+抛物高度+箭头随角度; 命中/目标消失→自销返false, 否则返true续飞
	var tgt = pr.get("tgt", null)
	if tgt == null or not tgt.get("alive", false) or float(pr["t"]) > 3.5:   # 目标没了/超时→箭消失(不乱跳伤害)
		node.queue_free(); return false
	if int(node.hframes) > 1:
		node.frame = int(float(pr["t"]) * 16.0) % int(node.hframes)   # 箭身帧动画
	var cur2d: Vector2 = pr["pos2d"]
	var tp: Vector2 = tgt["pos"]
	var dist: float = cur2d.distance_to(tp)
	if dist <= 30.0:   # 命中
		node.queue_free()
		if pr.get("hunt_exec", false):                            # 被动强化箭: 命中处决(<斩杀线)
			battle._hunter_sys._hunter_exec_arrow_hit(pr["src"], tgt)
		else:
			battle._damage._apply_damage_from(pr["src"], tgt, int(pr["dmg"]), pr["col"], 0.0, true)   # 弹幕: 白色真伤
			battle._vfx._flash(tgt); battle._vfx._hit_spark(tgt)
		return false
	cur2d = cur2d.move_toward(tp, float(pr.get("spd", battle.HUNTER_ARROW_SPD)) * delta)   # 追踪(向当前目标位置移动·spd可覆写)
	pr["pos2d"] = cur2d
	var progress: float = clampf(1.0 - dist / float(pr["init_dist"]), 0.0, 1.0)
	var h: float = float(pr["h0"]) + float(pr["arc"]) * sin(PI * progress)   # 抛物线高度(升→降)
	var prev_world: Vector3 = node.global_position
	node.position = battle._world_pos(cur2d, h)
	if battle._cam != null:   # 箭头随角度: 屏幕空间速度方向(含上下弧)→in-plane roll(箭尖上扬/下俯)
		var sv: Vector2 = battle._cam.unproject_position(node.global_position) - battle._cam.unproject_position(prev_world)
		if sv.length() > 0.4:
			var roll: float = atan2(-sv.y, sv.x) + float(pr.get("roll_off", 0.0))
			var tf: Transform3D = node.global_transform
			tf.basis = battle._vfx.cam_basis() * Basis(Vector3(0, 0, 1), roll)
			node.global_transform = tf
	return true

func _fire_hunter_exec_arrow(u: Dictionary, tgt: Dictionary) -> void:   # 强化箭(金色·更大·更快·小抛物)→命中处决; 复用homing_arc弹道
	var tex: Texture2D = load("res://assets/sprites/vfx/hunter-arrow.png")
	if tex == null:
		battle._hunter_sys._hunter_exec_arrow_hit(u, tgt); return   # 无素材兜底: 直接处决
	var fh: int = maxi(1, tex.get_height())
	var p = Sprite3D.new()
	p.texture = tex
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.hframes = maxi(1, int(tex.get_width() / fh))
	p.frame = 0
	p.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	p.shaded = false; p.transparent = true
	p.modulate = Color(1.0, 0.85, 0.32)   # 金色强化箭
	p.pixel_size = (88.0 * battle.WS) / float(fh)   # 更大(强化)
	var from2d: Vector2 = u["pos"]
	p.position = battle._world_pos(from2d, 1.3)
	battle._world.add_child(p)
	battle._gambler_sys._gambler_pop(from2d, float(u.get("height", 0.0)) + 0.6, Color(1.0, 0.86, 0.3, 0.8))   # 金色蓄力枪口光
	_push_proj({
		"node": p, "tgt": tgt, "src": u, "dmg": 0, "col": Color("#ffd700"),
		"t": 0.0, "homing_arc": true, "hunt_exec": true, "pos2d": from2d, "h0": 1.3,
		"init_dist": maxf(120.0, from2d.distance_to(tgt["pos"])),
		"arc": 2.0, "spd": 720.0, "raw": true,   # 更快更直(决绝处决箭)
	})

# 火爆: 落点火色环 + 膨胀火球辉光(火球落地/灼烧爆点)
func _fire_explosion(pos2d: Vector2) -> void:
	battle._skill_ring(pos2d, Color(1.0, 0.5, 0.15, 0.7), 55.0)
	var g = VfxTex._make_fire_glow_tex()
	var sp = Sprite3D.new()
	sp.texture = g
	sp.modulate = Color(1.0, 0.72, 0.32, 0.95)
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false; sp.transparent = true
	sp.pixel_size = (28.0 * battle.WS) / float(maxi(1, g.get_width()))
	sp.position = battle._world_pos(pos2d, 0.6)
	battle._world.add_child(sp)
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(sp, "pixel_size", sp.pixel_size * 2.2, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(sp.queue_free)

# 抛物线火球(珍珠耳环045): 火辉光从 src 抛向 tgt, 落点火爆+灼烧+真伤(橙). burn=灼烧层


## ══════════════════════════════════════════════════════════════════
##  001 木制长剑·飞斩 —— ③ 弹体(travel)
## ══════════════════════════════════════════════════════════════════
## ★2026-09-06 从上帝文件搬过来。判据(CLAUDE.md §5)是【不在 _sim_step 调用链上的不进主文件】,
##   而"发一发弹体"本来就是弹道自己的事: `_push_proj` / 方向选帧 / afterimage 都在本文件。
##   ⇒ 001 的五段现在分居两处: ②发射 ⑤命中在 battle_vfx.gd, ③弹体在这里。
## ── 001 飞斩剑气·五段结构的素材与规格(2026-09-06 重做) ──
## 表布局: 横 4 格 = 方向(E/N/W/S), 纵 4 格 = 4 帧循环。
## ★四格由 1 张基准帧经 **水平镜像 + 90° 旋转** 推出 —— 只有这两种变换对像素无损。
## ★4 不是 8。改的理由与三条实测证据见 tools/build_dir_sheet.py 头注
## (8 格里只有 1 格被用过 / 45° 旋转对像素有损 / 第二张基准帧两条路都拿不到)。
const TARGET_BODY_H_FANG := 1.55   # ★2.35 太大: 残影是等大复制, 叠起来是一坨粗块不是一条细带
## ★★不能只换素材不管可读性(2026-09-07 用户实拍:「这个感觉不如之前的射一颗毒牙」)。
##   并排比才看清: 旧的是**一条扫过半个屏幕的亮紫光带**, 新的是贴在龟身上一个几乎看不见的小白点。
##   三因: ①牙本体太小(1.15m) ②**没有拖尾**——旧那条"带"其实就是速度感 ③骨白在深背景上不如亮紫醒目。
##   ⇒ 放大到 2.35m + 密集拖尾(每 25ms 一个残影, 比 001 的 45ms 密, 毒牙飞得快) + 残影染毒紫。
## ★教训: 把糊的软条换成硬边像素素材是对的, 但**"可读性"是另一件事, 不会自己跟过来**。
var _venomfang_sheet: Texture2D = null
const FLYSLASH_DIRS := 4
## ★3 帧不是 5 —— animate_image 返回 5 帧, 后两帧白边散掉(LoL 剖面的 white_ratio 当场不合格),
## 第 5 帧还长出了黑描边。弹体是**循环**播放的, 循环里混一帧不合格的 = 每圈闪一下。
const FLYSLASH_FRAMES := 3
## 本体的像素高度(不是格子高度)。龟立绘按帧高归一到 TARGET_BODY_H, 32 就是"一个贴图像素 = 龟的一个像素"。
const FLYSLASH_ART_PX := 32.0
## ★出生点要偏出携带者身体, 别盖在它脸上。
##   实拍(vfxlab p2eq_001)改造前: 剑气与发射闪光都生在 src["pos"] 正中心, 把龟整个糊住 ——
##   LoL 的剑气是从手上【扫出去】、从角色身侧掠过的, 不是贴在角色脸上。
##   56 = 半个龟身(33) + 一点余量。龟宽实测 66 场地单位
##   (标定法: 两个假人场地间距 140 ↔ 屏幕 93px ⇒ 1px=1.51 单位; 龟 44px = 66 单位)。
const FLYSLASH_SPAWN_OFF := 56.0
var _flyslash_sheet: Texture2D = null          # ③ 弹体: 8 方向 × 4 帧

func fire_flyslash(src: Dictionary, tgt: Dictionary, dmg: int, col: Color) -> void:   # 木制长剑p2eq_001(射程2000): 朝目标飞的剑气(8方向预渲染帧·不旋转)·命中(frac>=1)才结算伤
	if tgt == null: return
	## ★做法与三条像素风硬约束(整数倍缩放 / 不许自由旋转 / NEAREST 不 blend_add)
	##   见 docs/specs/装备特效制作流程.md —— 那份是 96 件逐件重做的样板, 别在这里复述。
	if _flyslash_sheet == null:
		_flyslash_sheet = load("res://assets/sprites/vfx/eq001-flyslash-dir4.png")
	var aim: Vector2 = (tgt["pos"] - src["pos"])
	var start2d: Vector2 = src["pos"] + (aim.normalized() * FLYSLASH_SPAWN_OFF if aim.length() > 1.0 else Vector2.ZERO)
	battle._vfx.flyslash_muzzle(start2d, col)                    # ② 发射: 一次性，锚在出手点(已偏出身体)，不跟飞
	var p := Sprite3D.new()
	p.texture = _flyslash_sheet
	## 表布局: 横 4 格 = 方向(E, N, W, S), 纵 4 格 = 4 帧循环
	p.hframes = FLYSLASH_DIRS
	p.vframes = FLYSLASH_FRAMES
	p.frame = 0
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED    # ★正对相机, **不旋转** —— 方向靠选帧
	p.shaded = false; p.transparent = true
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.modulate = col
	## ★★像素口径**只能由 ART_PX 定, 不能由格子高度定**。
	##   通用规则 `pixel_size = TARGET_BODY_H / 帧高` 的前提是【本体填满整帧】(见主文件 2018 行注)。
	##   剑气不填满: 它是一道又长又扁的弧, 要放进【方形格】才能做 90° 旋转推方向,
	##   格子一撑大(64) 而本体还是 32 高 ⇒ 用格高算的话像素当场缩一半, 和龟脱钩。
	##   2026-09-06 实测 LoL 参考: 剑气长宽比 2.37, 而 32×32 方格里画不出来(实测最好 1.55),
	##   所以素材改成 64×24 的宽画布、再垫进 64 方格 —— 那一垫正好会踩上面这个坑。
	p.pixel_size = battle.TARGET_BODY_H / FLYSLASH_ART_PX
	p.position = battle._world_pos(start2d, 1.0)
	battle._world.add_child(p)
	_push_proj({
		"node": p, "from": battle._world_pos(start2d, 1.0), "tgt": tgt, "dmg": dmg, "col": col,
		"src": src, "t": 0.0, "dur": clampf(start2d.distance_to(tgt["pos"]) / 520.0, 0.8, 2.6),   # 飞行速度: 降60%后再减半(用户2026-07-19: /2600→/1040→/520)
		"flyslash": true, "o2d": start2d,
		"dirsel": true,                # ③ 按飞行角度选方向帧(不旋转) —— 见本文件 _step_projectiles
		"afterimage": 0.045,           # ④ 拖尾: 每 45ms 留一个半透明残影, 原地淡出(不画进贴图)
		"_ai_t": 0.0,
	})
