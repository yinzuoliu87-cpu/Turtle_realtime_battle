extends Node
## verify_axe_anim_runtime.gd — 斧头四条动作【真的播出来了没有】(2026-09-01)
##
## ══════════════════════════════════════════════════════════════════
##  ★为什么还要这一份(verify_summon_art 不是已经查过了吗)
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-01:「你都自己全部测了没」——**没有。**
##
## `verify_summon_art` 第④节查的是「这张素材登记在哪张表里」, 那是**源码断言**。
## 它证明不了动画**真的会播**。这与用户当天早些时候抓到的那个错**是同一个形状**:
##     素材在盘上   ≠ 引擎读得到     (那次: walk 表零引用)
##     登记在表里   ≠ 真的播出来     (这次: 没人验过)
## 中间可能断的地方多得很: 键名对不上 `_anim_key`、`_resolve_action` 解析失败返回空、
## committed 闸把它挡掉、切表时 frame 越界被吞……**每一条都不报错**。
##
## ⇒ 这份门禁**建真战斗场、真召唤、真移动**, 然后量 `u["anim_sd"]["tex"]` 的**资源路径**
##   到底是哪张图。判据落在"引擎此刻正拿哪张贴图画它", 不是落在源码文本上。
##
## ★等演出用**墙钟**不用帧数(CLAUDE.md §3.5): 无头 CI 每帧只推进 1ms。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")

## ★2026-09-15 换成悬空 3D 斧(AxeArt): 门禁默认档位 0 ⇒ 木斧那套; 按形态换表在 ⑥ 验。
const IDLE := "eq096-axe-wood-idle.png"
const WALK := "eq096-axe-wood-walk.png"
const ATK := "eq096-axe-wood-attack.png"
const CAST := "eq096-axe-wood-cast.png"

var _s = null
var _n := 0
## ══════════════════════════════════════════════════════════════════════
##  ★★2026-10-02 第三次换尺子: 帧数 → 【游戏时钟】(这次是 CI 专属红, 连红 4 轮)
## ══════════════════════════════════════════════════════════════════════
## 前两版的尺子都**跟机器快慢挂钩**, 只是挂的方向相反:
##   · 墙钟(2026-09-01): 并行门禁里进程被饿着, 3 秒墙钟只摸到几帧 ⇒ 动画根本没推进。
##   · 帧数(2026-09-27): 一帧推进 `rd = minf(delta, 0.1)` 秒动画 ⇒
##       900 帧在本机(无头高帧率)= **0.9 游戏秒**, 在 CI(一帧 ~0.06 秒)= **59 游戏秒**。
##       差 65 倍。而这只斧头是**在一场真打里站着的召唤物** —— 探针实测(本机 --max-fps 15,
##       把 900 帧跑满): hp 500 → 215(2.1 游戏秒) → **第 100 帧(5 游戏秒)就 0 血死了**。
##       斧头一死, `_render_step` 的 `if u["alive"]` 把它跳过 ⇒ `_advance_anim` 不再推帧 ⇒
##       **贴图永久冻在死的那一刻那张**。CI 日志里那句「实测 …-cast.png」就是这个:
##       不是动画坏了, 是**被测对象在量它的半路上被打死了**, 而判据把这说成了"贴图不对"。
##
## ⇒ 这一版两件事一起做, 缺一条都挡不住:
##   ① 尺子换成 `_s._t`(游戏时钟 = 一路累加的 Σ钳制delta, 正是喂给 `_advance_anim` 的那条钟)
##      ⇒ 「等 N 游戏秒」在任何机器上都是同样的 N 秒动画时间。帧数只剩一道宽松硬顶。
##   ② 把斧头/主人/对手的血**钉住**(对手早就钉了 1e8, 现在三个都钉) ——
##      本门禁量的是「四条动作播不播」, 不是「斧头能不能活过 60 秒」;
##      被测对象在量它的中途消失是**台子的毛病**, 不是产品的毛病。
##      并且新增两条分母断言: 量之前先问「它还活着吗 / 这条钟真的走了吗」,
##      再也不许一只死斧头伪装成"贴图不对"。(memory [[fb-gate-subject-never-constructed]])
const WAIT_GAME_S := 4.0     # 等一条动作播完最多等多少【游戏秒】(本机实测施法 0.40 秒播完)
const HARD_FRAMES := 6000    # 宽松帧数硬顶: 只防死循环, 不当尺子用

var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 等到引擎拿 `want` 这张图画它, 或者**游戏时钟**走完 `budget` 秒。
## ★尺子是 `_s._t` 不是帧数、不是墙钟 —— 见顶上「第三次换尺子」。
## 返回 {ok, g(走掉的游戏秒), fr(用掉的帧)} —— 三个数都打出来, 红的时候一眼看出是哪一维不对。
func _wait_tex(u: Dictionary, want: String, budget: float) -> Dictionary:
	var g0: float = float(_s._t)
	var fr := 0
	while _cur_tex(u) != want and float(_s._t) - g0 < budget and fr < HARD_FRAMES:
		await get_tree().process_frame
		fr += 1
	return {"ok": _cur_tex(u) == want, "g": float(_s._t) - g0, "fr": fr}


## 引擎【此刻】拿哪张贴图画它 —— 这是本门禁唯一的尺子。
func _cur_tex(u: Dictionary) -> String:
	var sd = u.get("anim_sd", null)
	if not (sd is Dictionary):
		return "(没有 anim_sd)"
	var tex = (sd as Dictionary).get("tex", null)
	if tex == null:
		return "(anim_sd 里没有 tex)"
	return str(tex.resource_path).get_file()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 斧头四条动作: 真的播出来了没有 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	## ── 真召唤一只斧头(走 AxeSystem.summon, 不手搓) ──
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var owner_u: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-260, 0))
	_s._units.append(owner_u)
	var foe: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(260, 0))
	_s._units.append(foe)
	foe["maxHp"] = 1.0e8
	foe["hp"] = 1.0e8
	## ★主人也钉住: 它一死, 左边就空了 ⇒ `_over=true` ⇒ **游戏时钟从此冻结**(CLAUDE.md §3.5),
	##   而本门禁的尺子就是那条钟。探针实测它确实会死(_t 冻在 11.55 秒不动了)。
	owner_u["maxHp"] = 1.0e8
	owner_u["hp"] = 1.0e8
	var ax = _s._equip_sys._axe.summon(owner_u)
	_ok("★分母: 真召唤出了斧头(走 AxeSystem.summon)", ax is Dictionary and ax.get("alive", false))
	if not (ax is Dictionary):
		print("FAIL x%d" % maxi(1, _fail))
		get_tree().quit(1)
		return
	_ok("★分母: 它有立绘节点(没有的话下面全是空检查)",
		is_instance_valid(ax.get("sprite", null)))
	## ★钉住被测对象的血: 它是在一场真打里站着的召唤物, 探针实测 5 游戏秒就被打死,
	##   死了之后 `_advance_anim` 不再推它的帧 ⇒ 贴图永久冻住。见顶上「第三次换尺子」②。
	ax["maxHp"] = 1.0e8
	ax["hp"] = 1.0e8

	# ── ① 待机 ──
	## ★★2026-09-03 修不稳定: 原来是"等 6 帧再断言待机", 实测 3 次里红 2 次
	##   (「实测 eq-axe-walk.png」)。根因不是动画坏了 —— 斧头是召唤物, **一出生就朝敌人走**,
	##   6 帧够不够它起步纯看那一跑的时序。这是判据在赌时序, 不是产品的问题
	##   (memory [[fb-make-the-noise-deterministic]]: 别跟随机较劲, 把判据改成对它不敏感)。
	## ⇒ 先把它钉住(no_move), 再**轮询等它回到 idle**(上限防死循环), 拿到确定态才断言。
	##   ★用墙钟不用帧数(CLAUDE.md §3.5): 无头 CI 帧率极高, 固定帧数在那边等于没等。
	ax["no_move"] = true
	var r_idle: Dictionary = await _wait_tex(ax, IDLE, WAIT_GAME_S)
	_ok("① 待机: 引擎正拿 %s 画它" % IDLE, bool(r_idle["ok"]),
		"实测 %s (已钉住 no_move 并等了 %.2f 游戏秒 / %d 帧)" % [
			_cur_tex(ax), float(r_idle["g"]), int(r_idle["fr"])])
	ax["no_move"] = false      # ★还原 —— 下面 ② 要真的让它跑起来

	# ── ② 走路: 真让它跑起来, 等换表 ──
	## ★不能靠"设一次 pos" —— `_update_run_anim` 是按【0.1 秒时间窗累计位移】测速的,
	##   一次瞬移在窗内只有一帧有位移, 平均速度不够。要**持续**推它。
	## ★同样按游戏钟: `_update_run_anim` 测速用的是【0.1 秒时间窗】, 那个窗走的也是 `rd`。
	var g_walk0: float = float(_s._t)
	var fr_walk := 0
	var seen_walk := false
	var seen_speed := 0.0
	while float(_s._t) - g_walk0 < WAIT_GAME_S and fr_walk < HARD_FRAMES:
		ax["pos"] = (ax["pos"] as Vector2) + Vector2(6.0, 0.0)
		ax["pos"].x = clampf(ax["pos"].x, _s.ARENA.position.x, _s.ARENA.end.x - 10.0)
		await get_tree().process_frame
		fr_walk += 1
		if _cur_tex(ax) == WALK:
			seen_walk = true
			break
	seen_speed = float(ax.get("_run_acc", 0.0))
	_ok("★★② 走路: 真的跑起来之后, 引擎换成了 %s" % WALK, seen_walk,
		"实测 %s（推了 %.2f 游戏秒 / %d 帧）" % [_cur_tex(ax), float(_s._t) - g_walk0, fr_walk])
	## ★分母: 停下来必须换回 idle —— 只验"切到走路"会漏掉"再也回不去"
	## ★★★2026-09-27 尺子从【墙钟】换成【帧数】。根因:
	##   立绘动画由 `_render_step(rd, …)` 推进, 而 `rd = minf(delta, 0.1)` ——
	##   **每帧最多推进 0.1 秒动画**。run-tests.sh 并行跑时这个进程被饿着,
	##   3~9 秒墙钟里可能只有几帧 ⇒ 动画只走了零点几秒, 根本播不完。
	##   ⇒ 拿墙钟等一件**按帧推进**的事, 尺子和被测的钟对不上(CLAUDE.md §3.5 同族)。
	##   2026-09-01 那次把墙钟从 2.5 秒拉到 9 秒是治标 —— 机器再忙一点照样红,
	##   而 2026-09-27 CI 上第 ④ 段(3 秒那个)就真的红了。
	## ★帧数上限给宽: 每帧至少推进一个渲染步, WAIT_FRAMES 帧足够任何一条动作播完;
	##   成立就立刻 break, 宽上限不花钱。
	var r_back: Dictionary = await _wait_tex(ax, IDLE, WAIT_GAME_S)
	_ok("★② 停下来换回 %s(只验切走路会漏掉「再也回不去」)" % IDLE, bool(r_back["ok"]),
		"实测 %s（等了 %.2f 游戏秒 / %d 帧）" % [_cur_tex(ax), float(r_back["g"]), int(r_back["fr"])])

	# ── ③ 技能释放: 攒满龟能放主动 ──
	ax["energy"] = AE.ACTIVE_ENERGY
	var cast_ok: bool = _s._equip_sys._axe.cast_heal(ax)
	_ok("★分母: 主动真的放出去了(cast_heal 返回 true)", cast_ok)
	_ok("★★③ 技能释放: 引擎换成了 %s 且动作名是 axe_cast" % CAST,
		_cur_tex(ax) == CAST and str(ax.get("anim_action", "")) == "axe_cast",
		"实测 贴图=%s 动作=%s" % [_cur_tex(ax), str(ax.get("anim_action", ""))])
	## ★施法期间普攻【不许打断】—— 靠的是 axe_cast 登记在 ACTION_ELITE(committed 闸)
	_s._vfx._play_action(ax, "attack")
	_ok("★★③ 施法播到一半, 普攻打断不了它(仍是 %s)" % CAST, _cur_tex(ax) == CAST,
		"实测 %s" % _cur_tex(ax))

	# ── ④ 攻击 ──
	## 先让施法播完回 idle, 再打一次普攻
	## ★同上: 按帧等, 不按墙钟(2026-09-27 CI 就是在这一处红的 —— 3 秒墙钟里帧数不够)
	var r_cast: Dictionary = await _wait_tex(ax, IDLE, WAIT_GAME_S)
	## ★★两条新分母 —— 它们是为了【把 2026-10-02 那次 CI 红诊断成它真实的样子】:
	##   斧头死了 / 游戏钟根本没走, 都会让下面那条"贴图不对"红得莫名其妙。先把这两维问清。
	_ok("★分母: 量它的时候斧头还活着(死了 `_advance_anim` 就不推它的帧, 贴图会永久冻住)",
		bool(ax.get("alive", false)), "hp=%.1f/%.1f" % [float(ax.get("hp", 0.0)), float(ax.get("maxHp", 0.0))])
	_ok("★分母: 这条钟真的走了(游戏钟冻住=根本没等, 不是「等过了」)",
		float(r_cast["g"]) > 0.0 or bool(r_cast["ok"]),
		"走了 %.2f 游戏秒 / %d 帧" % [float(r_cast["g"]), int(r_cast["fr"])])
	_ok("★分母: 施法播完自己回了 %s(回不去的话下一条量不到攻击)" % IDLE, bool(r_cast["ok"]),
		"实测 %s（等了 %.2f 游戏秒 / %d 帧）" % [_cur_tex(ax), float(r_cast["g"]), int(r_cast["fr"])])
	_s._vfx._play_action(ax, "attack")
	_ok("★★④ 攻击: 引擎换成了 %s" % ATK, _cur_tex(ax) == ATK, "实测 %s" % _cur_tex(ax))

	# ── ⑤ 没有 death / 没有 hurt(用户两次点名) ──
	## ★这两条**必须走真入口** `_play_action` —— 源码断言只能证明表里没有键,
	##   证明不了"调了也不会播"。
	var before: String = _cur_tex(ax)
	_s._vfx._play_action(ax, "hurt")
	_ok("★★⑤ 调 _play_action(hurt) 什么都不该发生(贴图仍是 %s)" % before,
		_cur_tex(ax) == before, "实测 %s" % _cur_tex(ax))
	_s._vfx._play_action(ax, "death")
	_ok("★★⑤ 调 _play_action(death) 什么都不该发生(贴图仍是 %s)" % before,
		_cur_tex(ax) == before, "实测 %s" % _cur_tex(ax))

	# ── ⑥ 九把斧按形态各用各的帧表(2026-09-15) ──
	## 用户 2026-09-15「应该要九把吧，因为9种形态」。判据仍是「引擎此刻拿哪张图画它」, 走真召唤。
	## ★GameState 的档位 / 造物是真存档字段: 本门禁开头已置 test_mode(不落盘), 用完仍原样还原。
	var gs2 = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState(换形态要靠它)", gs2 != null)
	if gs2 != null:
		var stage0 = gs2.get("axe_stage")
		var final0 = gs2.get("axe_final")
		gs2.set("axe_stage", 2)
		gs2.set("axe_final", "")
		var o2: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-260, 120))
		_s._units.append(o2)
		var ax_iron = _s._equip_sys._axe.summon(o2)
		_ok("★★⑥ 铁斧档召唤出来画的是铁斧待机表",
			ax_iron is Dictionary and _cur_tex(ax_iron) == "eq096-axe-iron-idle.png",
			"实测 %s" % (_cur_tex(ax_iron) if ax_iron is Dictionary else "(没召唤出来)"))
		if ax_iron is Dictionary and is_instance_valid(ax_iron.get("sprite", null)):
			var px_idle: float = float((ax_iron["sprite"] as Sprite3D).pixel_size)
			var played: bool = _s._equip_sys._axe.play_action(ax_iron, "axe_cleave")
			_ok("★★⑥ 铁斧的竖劈招式帧也是铁斧那张(实测 %s)" % _cur_tex(ax_iron),
				played and _cur_tex(ax_iron) == "eq096-axe-iron-cleave.png")
			var px_act: float = float((ax_iron["sprite"] as Sprite3D).pixel_size)
			_ok("★★⑥ 招式帧与待机同一个像素尺寸(按帧高归一的话招式一播斧头就缩)",
				px_idle > 0.0 and absf(px_act - px_idle) < 1e-6, "待机 %.5f / 招式 %.5f" % [px_idle, px_act])
		gs2.set("axe_final", "seraph")
		var o3: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-260, -120))
		_s._units.append(o3)
		var ax_ser = _s._equip_sys._axe.summon(o3)
		_ok("★★⑥ 选了炽天使造物, 画的是炽天使那把(不是档位那把)",
			ax_ser is Dictionary and _cur_tex(ax_ser) == "eq096-axe-seraph-idle.png",
			"实测 %s" % (_cur_tex(ax_ser) if ax_ser is Dictionary else "(没召唤出来)"))
		if ax_ser is Dictionary and is_instance_valid(ax_ser.get("sprite", null)):
			## ★普攻走 battle_vfx._play_action(不是斧头系统) —— 单位自带 `_act_rows` 与统一尺寸那两个口在那边, 单独量
			var px_ser_idle: float = float((ax_ser["sprite"] as Sprite3D).pixel_size)
			_s._vfx._play_action(ax_ser, "attack")
			_ok("★★⑥ 炽天使普攻走的是它自己的普攻表(单位自带 _act_rows, 不是全局兜底的木斧)",
				_cur_tex(ax_ser) == "eq096-axe-seraph-attack.png", "实测 %s" % _cur_tex(ax_ser))
			var px_ser_atk: float = float((ax_ser["sprite"] as Sprite3D).pixel_size)
			_ok("★★⑥ 普攻帧与待机同一个像素尺寸(battle_vfx 的统一尺寸口)",
				px_ser_idle > 0.0 and absf(px_ser_atk - px_ser_idle) < 1e-6,
				"待机 %.5f / 普攻 %.5f" % [px_ser_idle, px_ser_atk])
		gs2.set("axe_stage", stage0)
		gs2.set("axe_final", final0)

	if _n < 14:
		print("  [FAIL] ★分母: 断言只有 %d 条(<14) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 斧头动作真的会播(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
