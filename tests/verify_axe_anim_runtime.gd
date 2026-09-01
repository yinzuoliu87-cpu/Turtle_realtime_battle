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

const IDLE := "eq-axe-idle.png"
const WALK := "eq-axe-walk.png"
const ATK := "eq-axe-attack.png"
const CAST := "eq-axe-cast.png"

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


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
	var ax = _s._equip_sys._axe.summon(owner_u)
	_ok("★分母: 真召唤出了斧头(走 AxeSystem.summon)", ax is Dictionary and ax.get("alive", false))
	if not (ax is Dictionary):
		print("FAIL x%d" % maxi(1, _fail))
		get_tree().quit(1)
		return
	_ok("★分母: 它有立绘节点(没有的话下面全是空检查)",
		is_instance_valid(ax.get("sprite", null)))

	# ── ① 待机 ──
	for _i in range(6):
		await get_tree().process_frame
	_ok("① 待机: 引擎正拿 %s 画它" % IDLE, _cur_tex(ax) == IDLE, "实测 %s" % _cur_tex(ax))

	# ── ② 走路: 真让它跑起来, 等换表 ──
	## ★不能靠"设一次 pos" —— `_update_run_anim` 是按【0.1 秒时间窗累计位移】测速的,
	##   一次瞬移在窗内只有一帧有位移, 平均速度不够。要**持续**推它。
	var t0 := Time.get_ticks_msec()
	var seen_walk := false
	var seen_speed := 0.0
	while Time.get_ticks_msec() - t0 < 2500:
		ax["pos"] = (ax["pos"] as Vector2) + Vector2(6.0, 0.0)
		ax["pos"].x = clampf(ax["pos"].x, _s.ARENA.position.x, _s.ARENA.end.x - 10.0)
		await get_tree().process_frame
		if _cur_tex(ax) == WALK:
			seen_walk = true
			break
	seen_speed = float(ax.get("_run_acc", 0.0))
	_ok("★★② 走路: 真的跑起来之后, 引擎换成了 %s" % WALK, seen_walk,
		"实测 %s（跑了 %d 毫秒墙钟）" % [_cur_tex(ax), Time.get_ticks_msec() - t0])
	## ★分母: 停下来必须换回 idle —— 只验"切到走路"会漏掉"再也回不去"
	## ★等窗放到 9 秒: `_update_run_anim` 是按【0.1 秒时间窗累计位移】测速的,
	##   而 run-tests.sh 并行跑时这个进程被饿着 —— 2.5 秒墙钟里可能只推进十几帧,
	##   凑不够几个完整的测速窗 ⇒ 单跑绿、全套红(2026-09-01 实测)。
	##   等条件成立的循环, 上限给宽一点不花钱(成立就立刻 break)。
	var t1 := Time.get_ticks_msec()
	var back_idle := false
	while Time.get_ticks_msec() - t1 < 9000:
		await get_tree().process_frame
		if _cur_tex(ax) == IDLE:
			back_idle = true
			break
	_ok("★② 停下来换回 %s(只验切走路会漏掉「再也回不去」)" % IDLE, back_idle,
		"实测 %s" % _cur_tex(ax))

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
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 3000 and _cur_tex(ax) != IDLE:
		await get_tree().process_frame
	_ok("★分母: 施法播完自己回了 %s(回不去的话下一条量不到攻击)" % IDLE, _cur_tex(ax) == IDLE,
		"实测 %s" % _cur_tex(ax))
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

	if _n < 12:
		print("  [FAIL] ★分母: 断言只有 %d 条(<12) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 斧头动作真的会播(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
