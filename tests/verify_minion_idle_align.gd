extends Node
## verify_minion_idle_align.gd — 立绘必须与【动作第 0 帧】逐像素同框
##
## 用户 2026-08-22:「站立的图片和其他动作完全接不上, 位置大小都不一样」
## 实测根因: 立绘是 88x88(脚底行 73)、动作帧是 100x100(脚底行 75)
##   ⇒ 帧尺寸不同 + 脚底相对位置不同(83% vs 75%) ⇒ 一切到待机就【跳大小又跳位置】。
## ★代码里 ANIM_NORM 的注释写的意图就是「idle 等于动作第 0 帧」, 但**素材没做到** ——
##   注释不是门禁, 所以它漂了没人知道。这条把它焊住。
## ★同一个病亡魂也有(88x88 顶20脚67 vs 100x100 顶28脚75), 用户之前"过"的时候没人查这一层。
##
## 判据: 立绘的【帧尺寸】与【本体包围盒】必须与动作第 0 帧完全相等。
## ★量的是 PNG 的真实 alpha 像素, 不读任何配置表。

const PAIRS := [
	["远程小将", "res://assets/sprites/pets/minion-back.png",
		"res://assets/sprites/pets/animations/ranged/run.png"],
	["亡魂", "res://assets/sprites/pets/wraith.png",
		"res://assets/sprites/pets/animations/wraith/run.png"],
	## 援军小将(2026-10-29 新画): 立绘/头像 = 每一张动作图的第 0 帧(含待机循环), 一张都不许差
	["援军小将·移动", "res://assets/sprites/pets/minion-reserve.png",
		"res://assets/sprites/pets/animations/reserve/run.png"],
	["援军小将·待机", "res://assets/sprites/pets/minion-reserve.png",
		"res://assets/sprites/pets/animations/reserve/idle.png"],
	["援军小将·普攻", "res://assets/sprites/pets/minion-reserve.png",
		"res://assets/sprites/pets/animations/reserve/attack.png"],
	["援军小将·技能", "res://assets/sprites/pets/minion-reserve.png",
		"res://assets/sprites/pets/animations/reserve/skill.png"],
	["援军小将·阵亡", "res://assets/sprites/pets/minion-reserve.png",
		"res://assets/sprites/pets/animations/reserve/death.png"],
]

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 本体包围盒(上,下,左,右) —— alpha > 16 的像素范围
func _bbox(img: Image) -> Array:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var top := h
	var bot := -1
	var lft := w
	var rgt := -1
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.06:
				top = mini(top, y)
				bot = maxi(bot, y)
				lft = mini(lft, x)
				rgt = maxi(rgt, x)
	return [top, bot, lft, rgt]


func _ready() -> void:
	await get_tree().process_frame
	print("=== 立绘 ↔ 动作第0帧: 文件同框 + 运行时同锚点 ===")
	for p in PAIRS:
		var nm: String = str(p[0])
		var idle_t: Texture2D = load(str(p[1]))
		var act_t: Texture2D = load(str(p[2]))
		_ok("★分母: %s 两张图都加载到了" % nm, idle_t != null and act_t != null)
		if idle_t == null or act_t == null:
			continue
		var ii: Image = idle_t.get_image()
		var ai: Image = act_t.get_image()
		var fh: int = ai.get_height()
		var f0: Image = ai.get_region(Rect2i(0, 0, fh, fh))
		_ok("%s 立绘帧尺寸 == 动作帧尺寸" % nm,
			ii.get_width() == fh and ii.get_height() == fh,
			"立绘 %dx%d · 动作帧 %dx%d" % [ii.get_width(), ii.get_height(), fh, fh])
		var b1: Array = _bbox(ii)
		var b0: Array = _bbox(f0)
		_ok("%s 本体包围盒 == 动作第0帧(顶/脚/左/右)" % nm,
			b1 == b0, "立绘 %s vs 第0帧 %s" % [str(b1), str(b0)])
	## ══ ★★运行时: 待机与动作的【锚点必须一致】 ══════════════
	## 上面那几条只验了**文件**对不对 —— 用户 2026-08-22 当场看出"还是接不上",
	## 因为真正的病在 `idle_offy`(待机 50 / 动作 26, 差 24 像素) —— **文件全对, 摆得不对**。
	## ⇒ 必须在**真场景里**量精灵自己的 offset/pixel_size, 不是量 PNG。
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	for u0 in scn._units.duplicate():
		var sp0 = u0.get("sprite", null)
		if sp0 != null and is_instance_valid(sp0):
			sp0.queue_free()
	scn._units.clear()
	var cx: float = scn.ARENA.position.x + scn.ARENA.size.x * 0.5
	var cy: float = scn.ARENA.position.y + scn.ARENA.size.y * 0.5
	var mn: Dictionary = scn._spawn._make_unit("__minion__", "left", Vector2(cx - 300.0, cy),
		{"minion": true, "role": "back"})
	mn["energy"] = 999.0
	scn._units.append(mn)
	## 援军小将(2026-10-29)与远程小将同场: 自己一套形象, 待机是 7 帧呼吸循环(不是单帧)。
	var rs: Dictionary = scn._spawn._make_unit("__minion__", "left", Vector2(cx - 300.0, cy + 90.0),
		{"minion": true, "role": "reserve"})
	## 技能走独立冷却(龟能×0.075 秒, 135 ⇒ 约 10 秒), `energy` 字段不管用; 用产品自己的
	##   「初始龟能 → 开局减冷却」(_tick_skill_cd 懒初始化读 init_energy_bonus) 让它开局就放四面合围。
	rs["init_energy_bonus"] = 999.0
	scn._units.append(rs)
	var dm: Dictionary = scn._spawn._make_unit("basic", "right", Vector2(cx + 200.0, cy))
	dm["no_move"] = true
	dm["no_basic"] = true
	dm["move_spd"] = 0.0
	dm["maxHp"] = 99999.0
	dm["hp"] = 99999.0
	dm["deathfloor_until"] = 999999.0
	scn._units.append(dm)
	_ok("援军小将的动画键是 __minion_reserve__(不落到远程小将的帧上)",
		str(scn._anim_key(rs)) == "__minion_reserve__", str(scn._anim_key(rs)))
	var seen: Dictionary = {}
	var rseen: Dictionary = {}
	for _i in range(420):
		await get_tree().process_frame
		_sample(mn, seen)
		_sample(rs, rseen)
	## 阵亡: 杀掉援军, 看阵亡帧也站在同一个锚点上(阵亡帧表的归一同样查 ANIM_NORM)
	scn._kill(rs)
	for _j in range(12):
		await get_tree().process_frame
		_sample(rs, rseen)
	_anchor_check("远程小将", seen, ["minion-back.png"])
	_anchor_check("援军小将", rseen, ["animations/reserve/idle.png", "animations/reserve/attack.png",
		"animations/reserve/skill.png", "animations/reserve/death.png"])
	var borrowed: Array = []
	for k in rseen:
		if not str(k).contains("/reserve/") and not str(k).ends_with("minion-reserve.png"):
			borrowed.append(k)
	_ok("★援军小将运行时用到的每一张贴图都是它自己的(不借别的单位的素材)", borrowed.is_empty() and rseen.size() > 0,
		"借用: %s" % str(borrowed))
	scn.queue_free()

	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 立绘与动作第0帧同框" if _fail == 0 else "FAIL")
	get_tree().quit(0 if _fail == 0 else 1)


## 记下这一帧精灵用的贴图(按完整路径)及其竖直锚点/缩放
func _sample(u: Dictionary, into: Dictionary) -> void:
	var sp = u.get("sprite", null)
	if sp == null or not is_instance_valid(sp):
		return
	var tx = (sp as Sprite3D).texture
	if tx == null:
		return
	into[str(tx.resource_path)] = [(sp as Sprite3D).offset.y,
		(sp as Sprite3D).pixel_size, float(tx.get_height())]


func _anchor_check(nm: String, seen: Dictionary, must: Array) -> void:
	print("     %s 运行时看到的贴图: %s" % [nm, str(seen.keys())])
	_ok("★分母: %s 待机与至少一个动作都出现过(否则下面是空的)" % nm, seen.size() >= 2,
		"只看到 %d 张" % seen.size())
	for m in must:
		var hit := false
		for k in seen:
			hit = hit or str(k).ends_with(str(m))
		_ok("★分母: %s 运行时出现过 %s" % [nm, str(m)], hit)
	var offs: Array = []
	var pxs: Array = []
	for k in seen:
		offs.append(float((seen[k] as Array)[0]))
		pxs.append(float((seen[k] as Array)[1]))
		print("       %-18s offset.y=%.1f pixel_size=%.4f 帧高=%.0f" % [k,
			(seen[k] as Array)[0], (seen[k] as Array)[1], (seen[k] as Array)[2]])
	var omin := 1e9
	var omax := -1e9
	var pmin := 1e9
	var pmax := -1e9
	for v in offs:
		omin = minf(omin, float(v))
		omax = maxf(omax, float(v))
	for v2 in pxs:
		pmin = minf(pmin, float(v2))
		pmax = maxf(pmax, float(v2))
	_ok("★★★%s 运行时【竖直锚点】待机 == 动作(否则切换时上下跳)" % nm, absf(omax - omin) < 0.51,
		"offset.y 跨度 %.1f 像素" % (omax - omin))
	_ok("★★%s 运行时【缩放】待机 == 动作(否则切换时大小跳)" % nm, absf(pmax - pmin) < 0.0005,
		"pixel_size 跨度 %.4f" % (pmax - pmin))
