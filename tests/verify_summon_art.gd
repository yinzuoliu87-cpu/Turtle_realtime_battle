extends Node
## verify_summon_art.gd — 召唤物立绘的【朝向 / 帧数 / 尺寸】三条(2026-09-01)
##
## ══════════════════════════════════════════════════════════════════
##  ★为什么要有这份门禁
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-01 只说了两个字「方向」。查下来斧头召唤物同时有三个错:
##   ① 素材四套动画**全部脸朝右**, 而 `ART_FACES_RIGHT` 里没登记它
##      ⇒ 引擎按"原图朝左"翻转 ⇒ 场上朝向与实际相反。
##   ② 6 帧的乒乓表只播了 **5 帧**, 首尾接不上。
##      ★根因是 `drop_last=true`, **不是**那个写死的 `"frames": 16` ——
##      这一条是反向验证纠正我的: 我先归咎于 16, 但 `_sprite_dict_from` 里有
##      `mini(declared, frame_total)` 把它钳住, 单改 16 变异**一条都不红**(行为没变)。
##      真正砍掉一帧的是 drop_last, 而三张表实测**末帧都有内容**
##      (手铳 577 / 急救塔 2090 / 斧头 2506 个不透明像素) ⇒ 它一直在丢真帧。
##      (帧数改成由贴图算是顺手做的可读性改进, 不是修复 —— 别把功劳记错地方。)
##   ③ `col_size=26` 让它的世界身高只有 **0.708 m**, 而 28 只龟的中位是 1.40 m
##      ⇒ 它只有龟的一半高。
##
## 这三条我**都有 memory 记着**该怎么查(「验特效要建干净调试场」「验收级自查清单: 朝向/单帧立绘」),
## 却还是漏了 —— 因为 memory 不会自己跑。**焊进门禁的才会。** 这份门禁就是那个转换。
##
## ★判据落在【素材本身与代码常量】上, 不落在截图上 —— 截图要人眼看, 而人眼看会判反
##   (memory [[fb-clean-vfx-stage-not-squint]]: 我把地图海草当成甲片, 结论方向整个反了)。
##
## ★这份门禁是**通用的**, 不是给斧头一件写的: 以后任何召唤物进 `_EQ_BODY_SPR`
##   都自动被这三条盖住。
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const RBS := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RBSRC := "res://scripts/scenes/RealtimeBattle3DScene.gd"
const SPAWNSRC := "res://scripts/scenes/battle/battle_spawn.gd"

## 受检的召唤物立绘表(与 `_EQ_BODY_SPR` 同口径; 那是个函数内 const, 外面读不到 ⇒
## 这里列一份, 并配一条"源码里确实有这三行"的断言把它焊住)。
const SHEETS := [
	["pistol", "vfx/eq-pistol-idle.png", 40],
	["coraltower", "vfx/eq-coraltower-idle.png", 64],
	["axe", "vfx/eq-axe-idle.png", 80],
]
## 斧头的四套动作 —— 朝向必须**四套一致**(一部分朝左一部分朝右是用户 2026-08-31 抓过的)
const AXE_ANIMS := ["vfx/eq-axe-idle.png", "vfx/eq-axe-walk.png",
	"vfx/eq-axe-attack.png", "vfx/eq-axe-cast.png"]

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== 召唤物立绘: 朝向 / 帧数 / 尺寸 ===")
	_t_facing()
	_t_frames()
	_t_size()
	_t_channels()
	if _n < 19:
		print("  [FAIL] ★分母: 断言只有 %d 条(<19) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 召唤物立绘(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════
#  ① 朝向: 素材朝哪边 ↔ ART_FACES_RIGHT 登记了没有
# ══════════════════════════════════════════════════════════════
## 一帧里【护目镜(青色高光)】的横向重心相对身体中心的偏移。
## ★为什么用护目镜而不是"像素重心": 重心量的是身体胖瘦, 对朝向根本不敏感 ——
##   实测斧头四套的重心全部偏左(因为它左手垂着), 而脸其实朝右。**尺子要匹配被测概念。**
func _visor_off(img: Image, x0: int, fw: int) -> Array:
	var body: Array = []
	var vs: Array = []
	for y in range(img.get_height()):
		for x in range(fw):
			var c: Color = img.get_pixel(x0 + x, y)
			if c.a < 0.04:
				continue
			body.append(x)
			if c.g > 0.55 and c.b > 0.55 and c.r < c.g - 0.12:
				vs.append(x)
	if body.is_empty() or vs.is_empty():
		return [vs.size(), 0.0]
	var bmin: int = body.min()
	var bmax: int = body.max()
	var bc: float = float(bmin + bmax) * 0.5
	var vsum := 0.0
	for v in vs:
		vsum += float(v)
	return [vs.size(), vsum / float(vs.size()) - bc]


func _t_facing() -> void:
	print("--- ① 朝向 ---")
	var per_sheet: Array = []
	var measured := 0
	for rel in AXE_ANIMS:
		var p: String = "res://assets/sprites/" + rel
		if not ResourceLoader.exists(p):
			_ok("★素材在盘上: " + rel, false)
			continue
		var img: Image = (load(p) as Texture2D).get_image()
		var fw: int = img.get_height()
		var right := 0
		var left := 0
		for i in range(img.get_width() / fw):
			var r: Array = _visor_off(img, i * fw, fw)
			if int(r[0]) < 8:
				continue        # 这一帧看不见护目镜, 不投票
			measured += 1
			if float(r[1]) > 0.0:
				right += 1
			else:
				left += 1
		per_sheet.append([rel.get_file(), left, right])
	_ok("★分母: 真的量到了帧(护目镜可见的帧数 = %d, 0 就是空检查)" % measured, measured >= 16,
		str(per_sheet))
	## 四套必须**朝同一边** —— 一部分朝左一部分朝右是用户 2026-08-31 亲自抓过的形态
	var all_right := true
	var all_left := true
	for row in per_sheet:
		if int(row[1]) > 0:
			all_right = false
		if int(row[2]) > 0:
			all_left = false
	_ok("★斧头四套动作朝向【一致】(不许一部分朝左一部分朝右)", all_right or all_left,
		str(per_sheet))
	## 素材朝右 ⇒ 必须登记进 ART_FACES_RIGHT; 朝左 ⇒ 必须**不**登记。两个方向都卡。
	var src: String = FileAccess.get_file_as_string(RBSRC)
	var re := RegEx.create_from_string("const ART_FACES_RIGHT := \\[([^\\]]*)\\]")
	var m := re.search(src)
	_ok("★分母: 读得到 ART_FACES_RIGHT 这张表(读不到 = 下面是空检查)", m != null)
	var listed: bool = m != null and m.get_string(1).contains("\"axe\"")
	if all_right:
		_ok("★素材朝右 ⇒ axe 必须登记在 ART_FACES_RIGHT(不登记 = 场上左右反)", listed,
			"登记=%s" % str(listed))
	else:
		_ok("★素材朝左 ⇒ axe 不该登记在 ART_FACES_RIGHT(登记了 = 场上左右反)", not listed,
			"登记=%s" % str(listed))
	## 反过来也要有分母: 表里那几个老成员还在(整张表被清空时上面那条会假绿)
	_ok("★分母: 表里原有的 hiding/headless/mech 还在(被清空会让上面那条变成空检查)",
		m != null and m.get_string(1).contains("hiding") and m.get_string(1).contains("mech"))


# ══════════════════════════════════════════════════════════════
#  ② 帧数: 声明的 ↔ 贴图里真有的
# ══════════════════════════════════════════════════════════════
func _t_frames() -> void:
	print("--- ② 帧数 ---")
	var src: String = FileAccess.get_file_as_string(RBSRC)
	## ★★判据【走真代码路径】, 不匹配源码字符串。
	##   第一版我写的是 `not src.contains("{\"frames\": 16, \"frameW\": _fw")` ——
	##   反向验证当场证明它是假的: 改回写死的 16 之后源码换了行, 子串匹配不上, 一条都没红。
	##   字符串判据永远只卡住"我写它时那一种排版"。
	##   现在改成: 真的调 `_resolve_summon_sprite()`, 量它吐出来的 frames 等不等于
	##   贴图里数出来的帧数。★这条对【drop_last 被改回 true】会红(实测: 手铳 15≠16、
	##   斧头 5≠6), 对【把 frames 写回 16】**不会**红 —— 因为那个数被 mini() 钳着,
	##   改它行为不变。这不是判据松, 是那个变异本来就不改变任何东西。
	var rb = RBS.new()
	var wrong: Array = []
	for row in SHEETS:
		var p2: String = "res://assets/sprites/" + str(row[1])
		if not ResourceLoader.exists(p2):
			wrong.append("%s 缺图" % str(row[0]))
			continue
		var img2: Image = (load(p2) as Texture2D).get_image()
		var real: int = img2.get_width() / int(row[2])
		var sd: Dictionary = rb._resolve_summon_sprite(str(row[0]))
		if int(sd.get("frames", -1)) != real:
			wrong.append("%s: 引擎给 %d 帧 / 贴图里有 %d 帧"
				% [str(row[0]), int(sd.get("frames", -1)), real])
	rb.free()
	_ok("★★引擎解析出的帧数 == 贴图里真实的帧数(分母: 走真 _resolve_summon_sprite 查了 %d 张)"
		% SHEETS.size(), wrong.is_empty(), str(wrong))
	var bad: Array = []
	var tail_blank: Array = []
	for row in SHEETS:
		var p: String = "res://assets/sprites/" + str(row[1])
		if not ResourceLoader.exists(p):
			bad.append("%s 缺图" % str(row[0]))
			continue
		var img: Image = (load(p) as Texture2D).get_image()
		var fw: int = int(row[2])
		if img.get_height() != fw:
			bad.append("%s 帧高%d != 帧宽%d(不是方帧)" % [str(row[0]), img.get_height(), fw])
		if img.get_width() % fw != 0:
			bad.append("%s 表宽%d 除不尽帧宽%d" % [str(row[0]), img.get_width(), fw])
		## 末帧是不是空的 —— 空的话 drop_last=false 会多播一帧空白
		var n: int = img.get_width() / fw
		var cnt := 0
		for y in range(img.get_height()):
			for x in range(fw):
				if img.get_pixel((n - 1) * fw + x, y).a >= 0.04:
					cnt += 1
		if cnt == 0:
			tail_blank.append(str(row[0]))
	_ok("★三张召唤物立绘表都是方帧且宽度整除(分母: 查了 %d 张)" % SHEETS.size(),
		bad.is_empty(), str(bad))
	_ok("★没有一张表的末帧是空的(有空末帧就得把 drop_last 开回来)",
		tail_blank.is_empty(), str(tail_blank))
	## 源码里那三行还在(表被删/改名时上面全变空检查)
	for row in SHEETS:
		_ok("★分母: _EQ_BODY_SPR 里仍有 %s 这一行" % str(row[0]),
			src.contains("\"%s\": [\"%s\", %d]" % [str(row[0]), str(row[1]), int(row[2])]))


# ══════════════════════════════════════════════════════════════
#  ③ 尺寸: 斧头小将不该比龟矮一半
# ══════════════════════════════════════════════════════════════
func _t_size() -> void:
	print("--- ③ 尺寸 ---")
	var spawn: String = FileAccess.get_file_as_string(SPAWNSRC)
	## ★口径自检: 公式必须与产品一致, 否则量的是我脑子里的公式(手抄的副本必然落后)
	_ok("★分母: battle_spawn 里的 pixel_size 公式仍是 (TARGET_BODY_H × col/56) / 帧高",
		spawn.contains("(battle.TARGET_BODY_H * (col_size / 56.0)) / float(maxi(1, fh))"))
	var target_h := 2.0
	var p: String = "res://assets/sprites/vfx/eq-axe-idle.png"
	var img: Image = (load(p) as Texture2D).get_image()
	var fh: int = img.get_height()
	var y0 := 99999
	var y1 := -1
	for y in range(fh):
		for x in range(fh):
			if img.get_pixel(x, y).a >= 0.04:
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	var content: int = y1 - y0 + 1
	var px: float = (target_h * (AE.MINION_COL_SIZE / 56.0)) / float(fh)
	var body_m: float = float(content) * px
	## 龟的真实身高分布 —— 判据落在**它**上面, 不是我拍的一个数
	var hs: Array = []
	for e in DataRegistry.all_pets:
		var im2 := str((e as Dictionary).get("img", ""))
		if im2 == "" or not ResourceLoader.exists("res://assets/sprites/" + im2):
			continue
		var t2: Image = (load("res://assets/sprites/" + im2) as Texture2D).get_image()
		var sp = (e as Dictionary).get("sprite", null)
		var fh2: int = int((sp as Dictionary).get("frameH", t2.get_height())) if sp is Dictionary else t2.get_height()
		var fw2: int = int((sp as Dictionary).get("frameW", t2.get_width())) if sp is Dictionary else t2.get_width()
		var a := 99999
		var b := -1
		for y in range(mini(fh2, t2.get_height())):
			for x in range(mini(fw2, t2.get_width())):
				if t2.get_pixel(x, y).a >= 0.04:
					a = mini(a, y)
					b = maxi(b, y)
		if b >= a:
			hs.append(target_h * float(b - a + 1) / float(fh2))
	hs.sort()
	_ok("★分母: 量到了 %d 只龟的身高(0 只 = 空检查)" % hs.size(), hs.size() >= 20)
	var med: float = float(hs[hs.size() / 2]) if not hs.is_empty() else 0.0
	## 判据: 斧头小将的身高落在【龟中位的 70%~130%】—— 它是个人形小将, 与龟同框,
	## 不该矮一半(0.51 倍是改之前的实测值), 也不该反过来比龟还高一大截。
	_ok("★斧头小将身高 %.2f m 落在龟中位 %.2f m 的 70%%~130%% 内(实测 %.0f%%)"
		% [body_m, med, 100.0 * body_m / maxf(0.01, med)],
		body_m >= med * 0.70 and body_m <= med * 1.30,
		"col_size=%.0f · 内容 %dpx / 帧 %dpx" % [AE.MINION_COL_SIZE, content, fh])


# ══════════════════════════════════════════════════════════════
#  ④ 四条动作真的接线了 —— 而且**只有**四条(没有 death / 没有 hurt)
# ══════════════════════════════════════════════════════════════
## ★这一节是在还一笔账。方案书里曾经写着
##     - [x] 召唤物动画: 待机／走路／攻击／技能释放 四条
##   我打这个勾是因为**生成了四张精灵表**, 不是因为它们真的被引擎读到了 ——
##   实际上 walk 与 cast 两张**在盘上躺着、引擎里零引用**, 而我还写下了
##   「引擎没有 walk 通道」这句**错的**结论(ACTION_RUN 一直都在, 只是斧头没登记)。
##   用户 2026-09-01:「怎么可以没通道啊, 小将动画就有攻击待机走路等」。
## ★所以判据必须是「**这四张表各自被哪张表引用了**」, 不是「文件在不在盘上」。
func _t_channels() -> void:
	print("--- ④ 动作通道 ---")
	var src: String = FileAccess.get_file_as_string(RBSRC)
	## 四条各自的落点(表名 → 这张表里该出现的素材)
	var want := [
		["待机", "_EQ_BODY_SPR", "eq-axe-idle.png"],
		["走路", "ACTION_RUN", "eq-axe-walk.png"],
		["攻击", "ACTION_ATTACK", "eq-axe-attack.png"],
		["技能释放", "ACTION_ELITE", "eq-axe-cast.png"],
	]
	## ★★2026-09-03 改判法: 原来是**从主文件源码里 grep `const XXX := {`**,
	##   于是 `ACTION_ELITE` 一搬到 `scripts/gamedata/action_elite.gd`(主文件超预算,
	##   按 CLAUDE.md §5 落位表挪走), 这条就报「表解析到 0 字」—— **误报**。
	##   CLAUDE.md §2 早写过同一个坑:「审计器读战斗源码找装备数值, 函数外迁到新文件后
	##   它找不到 = 误报」。
	## ⇒ 改成**读真实的常量字典**(`RBS.ACTION_ELITE` 等)。它跟着引擎实际读到的那份走,
	##   表放在哪个文件都不影响; 而且这才是 memory [[fb-weld-visual-lessons-into-gate]]
	##   说的「源码子串匹配是假判据, 要走真函数」。
	## ★按名字取 const 要走 `get_script_constant_map()` —— `Script.get(名字)` 读的是
	##   **属性**, const 不在其中(第一版这么写, 测试直接崩)。
	var consts: Dictionary = (RBS as Script).get_script_constant_map()
	for row in want:
		var tbl: String = str(row[1])
		var d = consts.get(tbl, null)
		var body := ""
		var n_items := 0
		if d is Dictionary:
			n_items = (d as Dictionary).size()
			for k in (d as Dictionary):
				body += "%s=%s;" % [str(k), str((d as Dictionary)[k])]
		else:
			## `_EQ_BODY_SPR` 是 **var** 不是 const ⇒ 不在 constant_map 里,
			## 只能回退到源码解析。★这条回退**只对 var 生效**: const 一律走上面那条,
			## 表搬到哪个文件都不影响(这正是本次改判法的目的)。
			var i: int = src.find("%s := {" % tbl)
			var j: int = src.find("}", i) if i >= 0 else -1
			body = src.substr(i, j - i) if (i >= 0 and j > i) else ""
			n_items = body.length()
		_ok("★%s 真的登记在 %s 里(素材在盘上 ≠ 引擎读得到)" % [str(row[0]), tbl],
			body != "" and body.contains(str(row[2])),
			"表拿到 %d 项/字(0 = 取不到, 空检查)" % n_items)
	## ★★没有 death / 没有 hurt —— 用户两次点名。两张表里一个 axe 键都不许有。
	for tbl2 in ["ACTION_HURT", "ACTION_DEATH"]:
		var i2: int = src.find("const %s := {" % tbl2)
		var j2: int = src.find("}", i2) if i2 >= 0 else -1
		var body2: String = src.substr(i2, j2 - i2) if (i2 >= 0 and j2 > i2) else ""
		_ok("★★%s 里【没有】斧头(用户点名: 不要死亡、不要受伤)" % tbl2,
			body2 != "" and not body2.contains("axe"),
			"分母: 表解析到 %d 字(0 就是空检查)" % body2.length())
	## 施法动画要能"播到一半不被普攻打断" —— 靠的是键在 ACTION_ELITE 里
	## (`_play_action` 的 committed 闸认的就是那张表)。
	var vfx: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_vfx.gd")
	_ok("★施法动画不被普攻打断(committed 闸认 ACTION_ELITE, 而 axe_cast 就登记在那)",
		vfx.contains("battle.ACTION_ELITE.has(_cur_act)"))
