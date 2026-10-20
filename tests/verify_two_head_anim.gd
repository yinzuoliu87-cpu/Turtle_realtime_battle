extends Node
## verify_two_head_anim —— 变脸龟两套动作 + 技能特效(方案书 20261007-双头龟重绘两形态 done-when)。
##
## 判据全部落在【素材像素 + 真对局循环】上, 不落在截图上(memory fb-weld-visual-lessons-into-gate):
##  A 素材: 每条动作帧表在、方帧 128、帧数够到关键帧、宽 ≤ 4096(安卓采样上限)
##  B 归一: 每条从站姿起的动作第 0 帧 == 立绘逐像素(贴在 24,48); 变脸后半段末帧 == 新形态立绘
##          ⇒ 像素尺寸与脚底与立绘完全一致(运行期再核 pixel_size / offset)
##  C 朝向: 量脸不量重心 —— 术士: 头部皮肤重心在兜帽重心左边; 战士: 眼白/牙重心在红脸重心左边
##          (项目约定原图朝左); 每条攻击/技能的关键帧往左伸得比往右远(出手方向 = 朝向)
##  D 接线(真入口 REVIEW 单技能台 + 每帧恰 1 步 sim):
##     普攻: 出手那一步立绘正好在关键帧; 远程弹体用新素材; 命中那一步出命中特效
##     切形态: 切的那一刻斗篷挡满脸(变脸前半段关键帧)
##     锤击: 落地砸下那一步立绘在第 6 帧, 同一步出裂地特效、目标掉血
##     精神干扰 / 吸收 / 灵能冲击 / 融合: 结算那一步立绘在关键帧, 同一步出对应特效
##  E 死亡: 按形态播死亡帧表
## 每条断言都配一条分母断言(这一类事件真的发生过 ≥ N 次)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const FRAME := 128
var _fails := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fails += 1


func _img(path: String) -> Image:
	var t: Texture2D = load(path)
	return t.get_image() if t != null else null


func _base(form: String) -> Image:
	var src := _img("res://assets/sprites/pets/two_head.png" if form == "ranged" else "res://assets/sprites/pets/two_head_melee.png")
	var im := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	src.convert(Image.FORMAT_RGBA8)
	im.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i(TwoHeadArt.ART_X, TwoHeadArt.ART_Y))
	return im


func _frame(sheet: Image, i: int) -> Image:
	var f := sheet.get_region(Rect2i(i * FRAME, 0, FRAME, FRAME))
	f.convert(Image.FORMAT_RGBA8)
	return f


func _same(a: Image, b: Image) -> int:   # 不同像素数(只比不透明区, alpha 也算)
	var d := 0
	for y in range(FRAME):
		for x in range(FRAME):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if ca.a8 == 0 and cb.a8 == 0:
				continue
			if ca.to_rgba32() != cb.to_rgba32():
				d += 1
	return d


func _bbox(im: Image) -> Rect2i:
	return im.get_used_rect()


## 朝向(量脸): 3/4 侧脸里【吻部在眼睛前面】 ⇒ 头部皮肤(术士灰紫 / 战士红)的横向重心 − 眼白的横向重心,
##   < 0 = 吻部在眼睛左边 = 脸朝左。只看头部那几行(52~78), 不碰法杖 / 锤头 / 浮石。
##   ★标定过正反两面: 术士 −2.8 / 镜像 +1.6; 战士 −2.5 / 镜像 +10.6(2026-10-20)。
##   ★为什么不用"眼白对红脸": 我第一版这么量, 战士给出 +5.2(判成朝右) —— 吻部整块是红的, 眼睛在后半边。
func _face_dx(im: Image, form: String) -> float:
	var fx := 0.0; var fn := 0
	var ex := 0.0; var en := 0
	for y in range(52, 79):
		for x in range(40, 82):
			var c := im.get_pixel(x, y)
			if c.a8 == 0:
				continue
			var r := c.r8; var g := c.g8; var b := c.b8
			if mini(r, mini(g, b)) > 190:
				ex += x; en += 1
			elif form == "ranged" and absi(r - g) < 20 and b > r + 10 and r > 70:
				fx += x; fn += 1
			elif form == "melee" and r > 150 and g < 70 and b < 70:
				fx += x; fn += 1
	if fn < 20 or en < 3:
		return 999.0
	return fx / fn - ex / en


## 出手帧集合(量素材, 不读 TwoHeadArt.CLIPS —— 否则改常量判据跟着改 = 恒真):
##   包围盒左沿离最左那一帧 ≤ 2 像素的帧。远程掌心推出 / 锤落左下 / 双臂推法球 / 杖头推出 都是"最往左"的那一下。
var _reach_cache := {}
func _reach_set(key: String) -> Array:
	if _reach_cache.has(key):
		return _reach_cache[key]
	var sh := _img(TwoHeadArt.DIR + key + ".png")
	var n: int = sh.get_width() / FRAME
	var lefts: Array = []
	var mn := 9999
	for i in range(n):
		var bx: int = _bbox(_frame(sh, i)).position.x
		lefts.append(bx)
		mn = mini(mn, bx)
	var out: Array = []
	for i in range(n):
		if int(lefts[i]) <= mn + 2:
			out.append(i)
	_reach_cache[key] = out
	return out


func _static_checks() -> void:
	print("── A 素材 / B 归一 / C 朝向 ──")
	var keys: Array = TwoHeadArt.CLIPS.keys() + ["ranged_death", "melee_death"]
	var n_ok := 0
	for k in keys:
		var t: Texture2D = load(TwoHeadArt.DIR + str(k) + ".png")
		if t == null:
			_ok("帧表在: " + str(k), false)
			continue
		var w := t.get_width(); var h := t.get_height()
		var key: int = int(TwoHeadArt.CLIPS[k][0]) if TwoHeadArt.CLIPS.has(k) else 0
		var good := h == FRAME and w % FRAME == 0 and w <= 4096 and w / FRAME > key
		if good:
			n_ok += 1
		else:
			_ok("帧表规格: " + str(k), false, "%dx%d key=%d" % [w, h, key])
	_ok("分母: 帧表全部在且规格对(方帧128·帧数够到关键帧·宽≤4096)", n_ok == keys.size() and n_ok >= 17, "%d/%d" % [n_ok, keys.size()])
	# B 归一: 起手第 0 帧 == 立绘
	var starts := {"ranged": ["ranged_idle", "ranged_walk", "ranged_attack", "ranged_strike", "ranged_disrupt", "ranged_death", "to_melee_a", "fusion_cast"],
		"melee": ["melee_idle", "melee_walk", "melee_attack", "melee_strike", "melee_absorb", "melee_death", "to_ranged_a"]}
	var n_norm := 0
	for form in starts:
		var base := _base(form)
		for k in starts[form]:
			var d := _same(_frame(_img(TwoHeadArt.DIR + k + ".png"), 0), base)
			if d == 0:
				n_norm += 1
			else:
				_ok("★归一: %s 第0帧 == %s 立绘" % [k, form], false, "差 %d 像素" % d)
	_ok("★归一: 15 条起手动作第 0 帧逐像素 == 立绘(同像素尺寸·同脚底)", n_norm == 15, "%d/15" % n_norm)
	for pair in [["to_melee_b", "melee"], ["to_ranged_b", "ranged"]]:
		var sh := _img(TwoHeadArt.DIR + pair[0] + ".png")
		var last := _frame(sh, sh.get_width() / FRAME - 1)
		var d2 := _same(last, _base(pair[1]))
		_ok("★归一: %s 末帧 == %s 立绘(变脸落定不跳)" % pair, d2 == 0, "差 %d 像素" % d2)
	# C 朝向
	for form in ["ranged", "melee"]:
		var dx := _face_dx(_base(form), form)
		_ok("★朝向(量脸): %s 立绘脸朝左(吻部在眼睛左边)" % form, dx < -1.0 and dx < 900.0, "dx=%.1f" % dx)
	## 出手方向: 关键帧 ±1 帧里, 包围盒往左伸出的量 > 往右伸出的量。
	##   ★吸收(近身攥取)例外: 手只比锤柄多伸 3 像素, 右边斗篷飘起来也 3 像素, 包围盒分不出 ⇒
	##     改量【比第 0 帧新长出来的像素】的重心在不在身体中线左边(实测 −8.2; 镜像 +8.2)。
	##   ★融合不能用重心(实测 +26: 推杖时紫斗篷向右甩, 新像素大半在右), 用包围盒(杖头往左伸 30+)。
	var reach_n := 0
	for k in ["ranged_attack", "melee_attack", "ranged_strike", "melee_strike", "ranged_disrupt", "melee_absorb", "fusion_cast"]:
		var sh2 := _img(TwoHeadArt.DIR + k + ".png")
		var f0 := _frame(sh2, 0)
		var b0 := _bbox(f0)
		var kk: int = int(TwoHeadArt.CLIPS[k][0])
		var best_l := 0; var best_r := 0
		var nx := 0.0; var nn := 0
		for i in range(maxi(0, kk - 1), mini(sh2.get_width() / FRAME, kk + 2)):
			var fk := _frame(sh2, i)
			var bk := _bbox(fk)
			best_l = maxi(best_l, b0.position.x - bk.position.x)
			best_r = maxi(best_r, bk.end.x - b0.end.x)
			for y in range(FRAME):
				for x in range(FRAME):
					if fk.get_pixel(x, y).a8 > 0 and f0.get_pixel(x, y).a8 == 0:
						nx += x; nn += 1
		var cdx: float = (nx / maxf(1.0, float(nn))) - (b0.position.x + b0.size.x * 0.5)
		var good: bool = (cdx < -4.0) if k == "melee_absorb" else (best_l > best_r)
		if good:
			reach_n += 1
		else:
			_ok("★朝向(出手方向): %s" % k, false, "包围盒 左 %d / 右 %d · 新像素重心 %.1f" % [best_l, best_r, cdx])
	_ok("★朝向: 7 条攻击/技能的关键帧都往左出手(= 原图朝左口径)", reach_n == 7, "%d/7" % reach_n)


# ═══════════════════════════════════════════════════════════════════
#  D 真对局
# ═══════════════════════════════════════════════════════════════════
func _vfx_names(s) -> Dictionary:
	var out := {}
	for c in s._world.get_children():
		if c is Sprite3D and (c as Sprite3D).texture != null:
			var p := str((c as Sprite3D).texture.resource_path)
			if p.contains("/vfx/twohead-"):
				out[c.get_instance_id()] = p.get_file().get_basename()
	return out


## 跑一场 REVIEW 单技能台, 逐步记录: 形态 / 状态 / 当前动作 / 帧号 / 新出现的特效 / 假人累计受伤。
func _run(skill: int, steps: int) -> Array:
	OS.set_environment("REVIEW", "1")
	OS.set_environment("REVIEW_TURTLE", "two_head")
	OS.set_environment("REVIEW_SKILL", str(skill))
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._deterministic = true
	var rec: Array = []
	var seen := {}
	var th = null
	for _n in range(steps):
		await get_tree().process_frame
		if th == null:
			for u in s._units:
				if str(u.get("id", "")) == "two_head":
					th = u
		if th == null:
			continue
		var taken := 0
		for u in s._units:
			if str(u.get("side", "")) == "right":
				taken += int(u.get("_st_taken", 0))
		var now := _vfx_names(s)
		var fresh: Array = []
		for id in now:
			if not seen.has(id):
				fresh.append(now[id])
				seen[id] = true
		var spr = th["sprite"]
		rec.append({"t": float(s._t), "form": str(th.get("two_form", "")), "state": str(th.get("state", "")),
			"pending": str(th.get("pending", "")), "clip": str(th.get("_tha_clip", "")),
			"tex": str((spr.texture as Texture2D).resource_path.get_file().get_basename()) if spr.texture != null else "",
			"frame": int(spr.frame), "px": float(spr.pixel_size), "offy": float(spr.offset.y), "idle_px": float(th.get("idle_px", 0.0)),
			"taken": taken, "fresh": fresh, "frozen": float(th.get("stun_until", 0.0)) > float(s._t), "slam": bool(th.get("_slam", false)), "melee": bool(th.get("melee", false))})
	s.queue_free()
	await get_tree().process_frame
	return rec


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	RB.DEBUG_EDIT = false
	_static_checks()

	print("── D 普攻(REVIEW 技0) ──")
	var r0: Array = await _run(0, 900)
	var rel := 0; var rel_ok := 0; var bolt := 0; var hit_n := 0; var hit_ok := 0; var norm_bad := 0
	var wu_steps := 0; var wu_back := 0; var frozen_steps := 0; var frozen_moved := 0
	for i in range(1, r0.size()):
		var a: Dictionary = r0[i - 1]; var b: Dictionary = r0[i]
		if b["tex"].begins_with("ranged_") or b["tex"].begins_with("melee_") or b["tex"].begins_with("to_"):
			if absf(float(b["px"]) - float(b["idle_px"])) > 1e-6 or absf(float(b["offy"]) - FRAME * 0.5) > 1e-3:
				norm_bad += 1
		if a["state"] == "windup" and b["state"] == "windup" and a["tex"] == b["tex"]:
			wu_steps += 1
			if int(b["frame"]) < int(a["frame"]):
				wu_back += 1                       # 同一段前摇里帧号倒退 = 动作被重开了
			if b["frozen"] and a["frozen"]:
				frozen_steps += 1
				if int(b["frame"]) != int(a["frame"]):
					frozen_moved += 1                  # 被钩住眩晕期间动作还在往前走 = 解冻后出手帧对不上
		if a["state"] == "windup" and a["pending"] == "B" and b["state"] != "windup":
			rel += 1
			if b["tex"] == b["form"] + "_attack" and int(b["frame"]) in _reach_set(b["form"] + "_attack"):
				rel_ok += 1
			else:
				print("    出手步: t=%.3f tex=%s frame=%d" % [b["t"], b["tex"], b["frame"]])
			if "twohead-psi-bolt" in b["fresh"]:
				bolt += 1
		## ★只数灵能弹那一档(≥5): 场上训龟大师每 1.5 秒有一发固定 1 点的伤害(实测 +1 / 1.52 秒), 它不是变脸龟打的
		if int(b["taken"]) - int(a["taken"]) >= 5 and b["form"] == "ranged":
			hit_n += 1
			if "twohead-psi-hit" in b["fresh"]:
				hit_ok += 1
			else:
				print("    掉血步无命中特效: t=%.3f +%d tex=%s frame=%d fresh=%s" % [b["t"], int(b["taken"]) - int(a["taken"]), b["tex"], b["frame"], str(b["fresh"])])
	_ok("分母: 普攻出手 ≥ 4 次", rel >= 4, "%d" % rel)
	_ok("★出手那一步立绘正好在攻击关键帧(掌心出手 / 锤落)", rel_ok == rel, "%d/%d" % [rel_ok, rel])
	_ok("★远程出手同一步飞出新灵能弹(twohead-psi-bolt)", bolt == rel and bolt > 0, "%d/%d" % [bolt, rel])
	_ok("分母: 灵能弹命中掉血 ≥ 3 次", hit_n >= 3, "%d" % hit_n)
	_ok("★命中掉血那一步出命中特效(twohead-psi-hit)", hit_ok == hit_n, "%d/%d" % [hit_ok, hit_n])
	_ok("分母: 前摇中被冻住(眩晕/钩住)的步 ≥ 30(审阅台的训龟大师会钩)", frozen_steps >= 30, "%d / 前摇步 %d" % [frozen_steps, wu_steps])
	_ok("★前摇被冻住时动作不重开(帧号不倒退)", wu_back == 0, "倒退 %d 次" % wu_back)
	_ok("★前摇被冻住时画面停在原帧(帧号不动)", frozen_moved == 0, "冻住中走了 %d 步" % frozen_moved)
	_ok("★运行期归一: 播动作时 pixel_size == 立绘 idle_px 且脚底偏移 == 帧高/2", norm_bad == 0, "违例 %d 步" % norm_bad)

	print("── D 技一(灵能冲击 / 锤击) + 切形态 ──")
	var r1: Array = await _run(1, 1500)
	var sw := 0; var sw_ok := 0; var land := 0; var land_ok := 0; var orb := 0; var orb_ok := 0; var blast := 0
	for i in range(1, r1.size()):
		var a: Dictionary = r1[i - 1]; var b: Dictionary = r1[i]
		if a["form"] != b["form"] and a["form"] != "":
			sw += 1
			var ka: String = "to_" + str(b["form"]) + "_a"
			if a["tex"] == ka and int(a["frame"]) >= int(TwoHeadArt.CLIPS[ka][0]) - 1:
				sw_ok += 1
			else:
				print("    切形态前一步: t=%.3f tex=%s frame=%d" % [a["t"], a["tex"], a["frame"]])
		if a["slam"] and not b["slam"] and b["form"] == "melee":
			land += 1
			if b["tex"] == "melee_strike" and absi(int(b["frame"]) - 6) <= 1 and "twohead-hammer-slam" in b["fresh"] and int(b["taken"]) > int(a["taken"]):
				land_ok += 1
			else:
				print("    落地步: t=%.3f tex=%s frame=%d fresh=%s dmg=%s" % [b["t"], b["tex"], b["frame"], str(b["fresh"]), str(int(b["taken"]) > int(a["taken"]))])
		if "twohead-psi-orb-grow" in b["fresh"]:
			orb += 1
			if b["tex"] == "ranged_strike" and int(b["frame"]) in _reach_set("ranged_strike"):
				orb_ok += 1
			else:
				print("    法球出手步: t=%.3f tex=%s frame=%d" % [b["t"], b["tex"], b["frame"]])
		if "twohead-psi-blast" in b["fresh"] and int(b["taken"]) > int(a["taken"]):
			blast += 1
	_ok("分母: 切形态 ≥ 2 次(远→近→远)", sw >= 2, "%d" % sw)
	_ok("★切形态那一刻斗篷挡满脸(变脸前半段走到关键帧)", sw_ok == sw, "%d/%d" % [sw_ok, sw])
	_ok("分母: 锤击落地 ≥ 1 次", land >= 1, "%d" % land)
	_ok("★锤击落地那一步: 立绘第6帧砸地 + 裂地特效 + 目标掉血 同一步", land_ok == land, "%d/%d" % [land_ok, land])
	_ok("分母: 灵能冲击出手 ≥ 1 次", orb >= 1, "%d" % orb)
	_ok("★法球出手那一步立绘在双臂推出帧", orb_ok == orb, "%d/%d" % [orb_ok, orb])
	_ok("★法球爆炸特效与 200 码内掉血同一步", blast >= 1, "%d" % blast)

	print("── D 技二(精神干扰 / 吸收) ──")
	var r2: Array = await _run(2, 1500)
	var dis := 0; var dis_ok := 0; var ab := 0; var ab_ok := 0
	for i in range(1, r2.size()):
		var a: Dictionary = r2[i - 1]; var b: Dictionary = r2[i]
		if "twohead-mind-burst" in b["fresh"]:
			dis += 1
			if "twohead-mind-crest" in b["fresh"] and int(b["taken"]) > int(a["taken"]) and b["tex"] == "ranged_disrupt" and absi(int(b["frame"]) - 5) <= 1:
				dis_ok += 1
			else:
				print("    精神干扰步: t=%.3f tex=%s frame=%d fresh=%s" % [b["t"], b["tex"], b["frame"], str(b["fresh"])])
		if "twohead-siphon-pull" in b["fresh"]:
			ab += 1
			if "twohead-siphon-wisp" in b["fresh"] and int(b["taken"]) > int(a["taken"]) and b["tex"] == "melee_absorb" and absi(int(b["frame"]) - 4) <= 1:
				ab_ok += 1
			else:
				print("    吸收步: t=%.3f tex=%s frame=%d fresh=%s" % [b["t"], b["tex"], b["frame"], str(b["fresh"])])
	_ok("分母: 精神干扰 ≥ 1 次 / 吸收 ≥ 1 次", dis >= 1 and ab >= 1, "%d / %d" % [dis, ab])
	_ok("★精神干扰: 精神波+头部冲击与真伤同一步, 立绘在瞪眼帧", dis_ok == dis, "%d/%d" % [dis_ok, dis])
	_ok("★吸收: 攥出生命+血流与伤害同一步, 立绘在攥拳回扯帧", ab_ok == ab, "%d/%d" % [ab_ok, ab])

	print("── D 技三(融合·魔法波) ──")
	var r3: Array = await _run(3, 1200)
	var fw := 0; var fw_first := 0; var fw_ok := 0
	for i in range(1, r3.size()):
		var a: Dictionary = r3[i - 1]; var b: Dictionary = r3[i]
		var n_w := 0
		for f in b["fresh"]:
			if f == "twohead-fusion-wave":
				n_w += 1
		fw += n_w
		if n_w > 0 and a["clip"] == "fusion_cast" and int(a["frame"]) < int(TwoHeadArt.CLIPS["fusion_cast"][0]):
			fw_first += 1
			if b["tex"] == "fusion_cast" and int(b["frame"]) in _reach_set("fusion_cast"):
				fw_ok += 1
			else:
				print("    首波步: t=%.3f tex=%s frame=%d" % [b["t"], b["tex"], b["frame"]])
	_ok("分母: 魔法波 ≥ 4 道", fw >= 4, "%d" % fw)
	_ok("分母: 融合施放 ≥ 1 次", fw_first >= 1, "%d" % fw_first)
	_ok("★第一道魔法波出手那一步立绘在双脸推出帧", fw_ok == fw_first, "%d/%d" % [fw_ok, fw_first])

	print("── E 死亡(按形态) ──")
	for form in ["ranged", "melee"]:
		var s = RB.new()
		add_child(s)
		await get_tree().process_frame
		await get_tree().process_frame
		var u: Dictionary = s._spawn._make_unit("two_head", "left", Vector2(300, 400))
		s._units.append(u)
		s._spawn._apply_spawn_passive_one(u)          # 真出生入口(变脸龟在这里挂死亡帧表)
		if form == "melee":
			s._two_head_sys._two_head_after_cast(u, null)
		s._vfx._play_action(u, "death")
		var tx := str((u["sprite"].texture as Texture2D).resource_path.get_file())
		_ok("★%s 形态死亡播 %s_death 帧表、像素尺寸 == 立绘" % [form, form], tx == form + "_death.png" and absf(float(u["sprite"].pixel_size) - float(u["idle_px"])) < 1e-6, tx)
		s.queue_free()
		await get_tree().process_frame

	print("ALL PASS — 变脸龟两套动作 + 技能特效" if _fails == 0 else "FAIL x%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
