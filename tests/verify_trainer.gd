extends Node

## verify_trainer.gd — 训龟大师本体 (用户 2026-07-22 需求3)
##
## 用户逐字规格:
##   「500生命值，1ATK，0双抗的训龟大师，对面就是人机控制的训龟大师」
##   「在场上不会被主动索敌但会吃到aoe伤害」
##   「被动是受到的所有类型的伤害降低为1，包括真实伤害」
##   「射程2000，普攻为扔出石头造成1物理伤害」
##   「训龟大师不算(团灭)，其实就是个场外监视者」
##   「每次比如上，下终极战场都会重置他的血量」
##
## ★这些全是【行为】, 不是字符串。所以本测试真建场景、真造伤害、真查存活计数。
## ★立绘("像素风的冒险家")尚未拍板 —— 这里只断言"没真图时会 warning 而不是静默兜底"。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	var s = RTScene.new()
	get_tree().root.add_child(s)
	for i in 8:
		await get_tree().process_frame

	var trainers: Array = []
	var others: Array = []
	for u in s._units:
		if u.get("is_trainer", false):
			trainers.append(u)
		else:
			others.append(u)
	print("  [分母] 场上单位 %d 个, 其中训龟大师 %d 个" % [s._units.size(), trainers.size()])
	_ok("场上有单位(N=0 说明战斗没起来, 下面全是空检查)", s._units.size() > 0)
	_ok("★双方各一个训龟大师", trainers.size() == 2, "实际 %d 个" % trainers.size())
	if trainers.size() < 2:
		s.queue_free()
		_done()
		return

	var sides: Array = []
	for t in trainers:
		sides.append(str(t.get("side", "")))
	sides.sort()
	_ok("★左右各一个(己方玩家/对面人机)", sides == ["left", "right"], str(sides))

	var tr: Dictionary = trainers[0]

	# ── ① 属性 ──
	_ok("★500 生命", is_equal_approx(float(tr["maxHp"]), 500.0), "maxHp=%.1f" % float(tr["maxHp"]))
	_ok("★1 攻击力", is_equal_approx(float(tr["atk"]), 1.0), "atk=%.2f" % float(tr["atk"]))
	_ok("★0 护甲", is_equal_approx(float(tr["def"]), 0.0), "def=%.2f" % float(tr["def"]))
	_ok("★0 魔抗", is_equal_approx(float(tr["mr"]), 0.0), "mr=%.2f" % float(tr["mr"]))
	# ★字段名是 atk_range 不是 range(见 _make_unit: "atk_range": float(st[3]))。
	#   我第一版写成 range → 读到 0 → 报了假 FAIL, 差点去"修"一个没坏的地方。
	_ok("★射程 2000", float(tr.get("atk_range", 0.0)) >= 2000.0, "atk_range=%.0f" % float(tr.get("atk_range", 0.0)))

	# ── ② 所有类型伤害降为 1(含真伤) ──
	#    直接问公共减伤函数: 两条伤害路径都过它, 一处正确即全覆盖。
	var victim: Dictionary = tr
	var cases := [[999.0, false, "普通(物理/魔法)"], [999.0, true, "真实伤害(raw)"], [1.0e9, true, "极大真伤"]]
	for c in cases:
		var got: float = s._mitigate_incoming(victim, float(c[0]), bool(c[1]), false)
		_ok("★%s %.0f → 降为 1" % [str(c[2]), float(c[0])], got <= 1.0 + 1e-6, "实得 %.4f" % got)
	# 对照: 普通单位【不该】被降为 1, 否则是把全场都改坏了
	if others.size() > 0:
		var ov: Dictionary = others[0]
		var og: float = s._mitigate_incoming(ov, 999.0, false, false)
		print("  [对照] 普通单位 %s 受 999 → %.1f" % [str(ov.get("name", "?")), og])
		_ok("★★对照组: 普通单位不受此封顶(否则是把全场伤害都改坏了)", og > 1.0, "%.4f" % og)

	# ── ③ 不被主动索敌, 但吃 AOE ──
	var foe: Dictionary = {}
	for o in others:
		if o.get("alive", false) and str(o.get("side", "")) != str(tr.get("side", "")):
			foe = o
			break
	_ok("找得到一个敌方普通单位来做索敌测试", not foe.is_empty())
	if not foe.is_empty():
		# 把训龟大师挪到敌人脚边 —— 若会被索敌, 它就是最近的那个
		var saved_pos: Vector2 = tr["pos"]
		tr["pos"] = foe["pos"] + Vector2(5.0, 0.0)
		var picked = s._nearest_enemy(foe)
		var picked_is_trainer: bool = picked is Dictionary and (picked as Dictionary).get("is_trainer", false)
		print("  [实测] 把训龟大师放到敌人脚边(距离 5 码), _nearest_enemy 选中的是: %s"
			% ("训龟大师" if picked_is_trainer else str((picked as Dictionary).get("name", "?")) if picked is Dictionary else "null"))
		_ok("★贴脸也不会被主动索敌(_nearest_enemy 跳过它)", not picked_is_trainer)
		# AoE 走 _enemies_of —— 那条路必须【能】拿到它
		var aoe: Array = s._enemies_of(foe)
		var in_aoe := false
		for o in aoe:
			if o.get("is_trainer", false):
				in_aoe = true
		_ok("★但 AoE 打得到(_enemies_of 故意不跳过它)", in_aoe,
			"_enemies_of 返回 %d 个, 不含训龟大师" % aoe.size())
		tr["pos"] = saved_pos

	# ── ④ 不计团灭/胜负 ──
	var side := str(tr.get("side", "left"))
	var alive_before: int = s._dl_side_alive(side)
	var n_normal_alive := 0
	for o in others:
		if o.get("alive", false) and str(o.get("side", "")) == side and not o.get("_isEgg", false) and not o.get("is_summon", false):
			n_normal_alive += 1
	print("  [实测] %s 侧: _dl_side_alive=%d, 普通存活单位=%d(训龟大师不该被算进去)"
		% [side, alive_before, n_normal_alive])
	_ok("★训龟大师不计入存活数(否则打不死它 → 永远不会团灭)",
		alive_before <= n_normal_alive, "%d vs %d" % [alive_before, n_normal_alive])

	# ── ⑤ 扔石头 = 1 点物理 ──
	var spec: Dictionary = RTScene.BASIC_ATK.get("__trainer__", {})
	_ok("★普攻表里有训龟大师条目", not spec.is_empty())
	_ok("★扔石头是物理伤害", float(spec.get("phys", 0.0)) > 0.0)
	_ok("★1.0×ATK 而 ATK=1 → 恰好 1 点",
		is_equal_approx(float(spec.get("phys", 0.0)) * float(tr["atk"]), 1.0),
		"%.2f×%.2f" % [float(spec.get("phys", 0.0)), float(tr["atk"])])

	# ── ⑥ 场外监视者: 不移动 ──
	_ok("站着不动(no_move)", bool(tr.get("no_move", false)))
	_ok("暂无主动法术(用户: 法术技能待制作)", (tr.get("active_skills", []) as Array).is_empty())

	# ── ⑦ 每个战场重置血量(用户:「每次比如上, 下终极战场都会重置他的血量」) ──
	#    实现方式: 分路切换会 _dl_clear_units() 再 _spawn_dual_lane(), 训龟大师随之重建 = 天然重置。
	#    唯一会破坏它的是【被写进幸存名单】—— 那样终极战场会拿残血 spec 重建, 还会多 spawn 一个。
	#    ★所以这条必须直接测幸存快照, 不能只靠"我知道它会重建"(2026-07-22 反向验证抓到:
	#      不测的话, 把幸存排除那行拆掉照样全绿)。
	if GameState != null and (GameState.dual_survivors is Dictionary):
		tr["hp"] = 100.0                     # 打成残血
		GameState.dual_survivors = {"left": [], "right": []}
		s._dl_snapshot_survivors()
		var n_tr_in_snap := 0
		var n_snap := 0
		for sd in ["left", "right"]:
			for spec2 in GameState.dual_survivors.get(sd, []):
				n_snap += 1
				if str((spec2 as Dictionary).get("id", "")) == "__trainer__":
					n_tr_in_snap += 1
		print("  [实测] 幸存快照共 %d 条, 其中训龟大师 %d 条" % [n_snap, n_tr_in_snap])
		_ok("幸存快照非空(N=0 就测不出下面那条)", n_snap > 0)
		_ok("★训龟大师不进幸存名单 → 终极战场会重新 spawn 满血(而不是带着残血过去)",
			n_tr_in_snap == 0, "快照里混进了 %d 条训龟大师" % n_tr_in_snap)
		tr["hp"] = tr["maxHp"]

	# ── ⑧ 立绘未就绪要吭声, 不许静默兜底 ──
	var src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var body := _func_body(src, "_trainer_sprite_dict")
	_ok("★没真图时会 push_warning(形象待定, 不许静默当成做完了)",
		_code_only(body).contains("push_warning("), "函数体 %d 字符" % body.length())
	# ★★这条才是真正要守的: 占位图【必须真的能显示】。
	#   2026-07-22 翻车: 兜底路径写的是 pets/basic.png, 那个文件根本不存在
	#   (basic 的真立绘是 pets/animations/basic/idle.png) → tex=null → 训龟大师【场上完全看不见】,
	#   而我还对着窗口跟用户说"长得就是小龟的样子"。
	#   当时门禁只查了"会不会 push_warning" —— 守住了会吭声, 没守住看得见。
	var sd: Dictionary = s._trainer_sprite_dict()
	var stex = sd.get("tex")
	print("  [实测] 训龟大师立绘纹理 = %s" % ("null(场上会隐形!)" if stex == null else "%s" % stex.get_size()))
	_ok("★★立绘纹理不是 null(null = 单位在场上完全看不见)", stex != null)
	if stex != null:
		_ok("占位图有实际尺寸", stex.get_size().x > 0 and stex.get_size().y > 0, "%s" % stex.get_size())
	# 场上那两个的 Sprite3D 也必须真挂上了纹理
	var n_vis := 0
	for t2 in trainers:
		# ★键名是 "sprite" 不是 "spr"(见 _make_unit 的 "sprite": spr) —— 我第一版写 "spr" 拿到 null,
		#   报了 0/2 的假 FAIL。今天第二次栽在拿错字段名上(上次是 range vs atk_range)。
		var sp = t2.get("sprite")
		if sp != null and is_instance_valid(sp) and sp.texture != null:
			n_vis += 1
	print("  [分母] 场上 %d 个训龟大师中, Sprite3D 真有纹理的 %d 个" % [trainers.size(), n_vis])
	_ok("★★场上每个训龟大师都真的挂上了纹理(看得见)", n_vis == trainers.size(),
		"%d/%d" % [n_vis, trainers.size()])

	# ── ⑩ 扔石头: 动作 + 抛物线石头 + 1 点物理(用户2026-07-23:「射程2000扔石头1物理」「弹道是抛物线的」) ──
	# 找一个敌方普通单位当靶
	var rock_foe: Dictionary = {}
	for o in others:
		if o.get("alive", false) and s._is_hostile(tr, o) and not o.get("is_trainer", false) and not o.get("_isEgg", false):
			rock_foe = o
			break
	if not rock_foe.is_empty():
		var n0: int = s._projectiles.size()
		s._fire_trainer_rock(tr, rock_foe)
		_ok("★扔石头生成了一颗投射物", s._projectiles.size() == n0 + 1)
		if s._projectiles.size() > n0:
			var rock: Dictionary = s._projectiles[s._projectiles.size() - 1]
			print("  [实测] 石头 dmg=%s arc=%.2f米 dtype=%s" % [rock.get("dmg"), rock.get("arc", 0.0), str(rock.get("dtype"))])
			_ok("★石头伤害 = 1", int(rock.get("dmg", -1)) == 1)
			_ok("★★石头走抛物线(arc>0, 用户点名要的)", float(rock.get("arc", 0.0)) > 0.0, "arc=%.2f" % float(rock.get("arc", 0.0)))
			_ok("★石头是物理伤害", str(rock.get("dtype", "")) == "phys")
			_ok("★石头飞向敌方", s._is_hostile(tr, rock.get("tgt", {})))
	# ★不发默认子弹: 训龟大师【只】走扔石头, 不能同时跑 AI 默认普攻(BASIC_ATK 发子弹)。
	#   2026-07-23 用户:「为什么同时在扔石头和发射子弹」—— 单位字典漏了 no_basic,
	#   两条攻击并行。这里断言 no_basic=true(否则又会双重攻击)。
	_ok("★★训龟大师关掉了 AI 默认普攻(no_basic=true, 否则会同时扔石头+发子弹)",
		bool(tr.get("no_basic", false)), "no_basic=%s" % str(tr.get("no_basic", "(未设)")))

	# 扔石头动作能触发(anim_action=throw, 播完自动回)
	s._trainer_throw_anim(tr)
	_ok("★普攻播扔石头动作(anim_action=throw)", str(tr.get("anim_action", "")) == "throw")
	# 训龟大师自己会索敌开火(它不被别人锁, 但能锁别人 —— 两回事)
	if not rock_foe.is_empty():
		rock_foe["pos"] = tr["pos"] + Vector2(200.0, 0.0)
		var picked = s._nearest_enemy_for_trainer(tr)
		_ok("★训龟大师能锁到射程内的敌人开火", picked != null)
	# 减伤对【普通目标】必须恰好放行 1(之前探针随机挑到钻石龟被动减18%=0.82, 那是目标的锅不是石头的)
	var plain := {"id": "basic", "def": 0.0, "mr": 0.0, "hp": 100.0, "maxHp": 100.0, "alive": true}
	_ok("★1 点物理对普通目标不被削(=1)", is_equal_approx(s._mitigate_incoming(plain, 1.0, false), 1.0),
		"实得 %.3f" % s._mitigate_incoming(plain, 1.0, false))

	# ── ⑨ 朝向: 立绘【实际画的朝向】必须与 ART_FACES_RIGHT 登记的一致 ──
	#
	# ★2026-07-23 我第一版写成了【同义反复】: 用 art_faces_right 算 flip_h, 再用 flip_h
	#   反推"屏幕朝向", 代进去等于 face_right —— 跟图片画的什么毫无关系, 拿掉例外表条目照样绿。
	#   要真验, 必须【从像素测出图画的朝向】, 再和代码的登记对账。
	# 判据: 3/4 侧视角色的头部重心会偏向朝向侧(脸凸出去), 躯干/背包在后。
	#   判不出时【明确报"测不出"而不是默默通过】—— Q 版大圆盔那种左右对称的头就判不出。
	var tex2 = s._trainer_sprite_dict().get("tex")
	if tex2 != null:
		var img: Image = tex2.get_image()
		var W := img.get_width()
		var H := img.get_height()
		var x0 := W
		var x1 := -1
		var y0 := H
		var y1 := -1
		for y in H:
			for x in W:
				if img.get_pixel(x, y).a > 0.5:
					x0 = mini(x0, x); x1 = maxi(x1, x)
					y0 = mini(y0, y); y1 = maxi(y1, y)
		if x1 >= x0 and y1 >= y0:
			var cut: int = y0 + int(float(y1 - y0 + 1) * 0.35)
			var hs := 0.0
			var hn := 0
			var bs := 0.0
			var bn := 0
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					if img.get_pixel(x, y).a <= 0.5:
						continue
					if y < cut:
						hs += float(x); hn += 1
					else:
						bs += float(x); bn += 1
			if hn > 0 and bn > 0:
				var d: float = (hs / float(hn)) - (bs / float(bn))
				var registered: bool = RTScene.ART_FACES_RIGHT.has("__trainer__")
				print("  [实测] 立绘头部重心相对躯干 %+.2f px ; ART_FACES_RIGHT 登记为朝%s"
					% [d, ("右" if registered else "左")])
				if absf(d) < 0.3:
					print("  [跳过] 这张图左右太对称, 判不出朝向 —— 换形象后请人工确认(不当作通过)")
				else:
					var art_right_measured: bool = d > 0.0
					_ok("★★立绘实际朝向与 ART_FACES_RIGHT 登记一致(不一致 = 双方都背对战场)",
						art_right_measured == registered,
						"图画的是朝%s, 代码登记朝%s" % [("右" if art_right_measured else "左"), ("右" if registered else "左")])

	s.queue_free()
	_done()


func _done() -> void:
	print("ALL PASS — 训龟大师本体(属性/索敌/伤害封顶/不计团灭/扔石头)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _func_body(src: String, fname: String) -> String:
	var head := "\nfunc %s(" % fname
	var i := src.find(head)
	if i < 0:
		return ""
	var start := i + 1
	var j := src.find("\nfunc ", start)
	if j < 0:
		j = src.length()
	return src.substr(start, j - start)


func _strip_comment(line: String) -> String:
	var in_q := false
	var q := ""
	for i in line.length():
		var ch := line[i]
		if in_q:
			if ch == q and (i == 0 or line[i - 1] != "\\"):
				in_q = false
		elif ch == "\"" or ch == "'":
			in_q = true
			q = ch
		elif ch == "#":
			return line.substr(0, i)
	return line


func _code_only(block: String) -> String:
	var out := ""
	for l in block.split("\n"):
		out += _strip_comment(str(l)) + "\n"
	return out
