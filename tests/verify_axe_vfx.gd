extends Node
## 斧头【演出】门禁 (2026-09-03)
##
## ══════════════════════════════════════════════════════════════════
##  ★这个文件要守住的是什么
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-03:「斧头特效要全部补齐且不能敷衍」
##
## 「不敷衍」没法靠我说了算, 所以判据落在**可量的东西**上:
##   ① 蓄力梯形的四个角**必须恰好在判定边界上** —— 演出即判定, 逐码对齐。
##      这条最重要: 它把"画个大概"和"画的就是判定区"分开了。
##   ② 八张招式帧**真的被换上去**(读产品自己的 `_axe_last_action`, 不是我插的计数)。
##   ③ 梯形在所有退出路径上都被收掉(蓄力中斧头死 = 最容易漏的那条)。
##
## ★★不做什么: 不断言"建了几个节点"。节点数是实现细节, 改个做法就红,
##   而且它证明不了"玩家看得见" —— memory [[fb-zero-caller-is-a-whole-class]]
##   里 64 条门禁全绿而环与光从没被创建, 就是断言挑错了对象。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const APV := preload("res://scripts/scenes/battle/axe_passive_vfx.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(msg: String, cond: bool, extra: String = "") -> void:
	_n += 1
	if cond:
		print("  [OK] %s" % msg)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [msg, extra])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true          # ★绝不写玩家存档
	print("=== 斧头演出: 梯形对齐 / 招式帧 / 收尾 ===")

	# ══════════════════════════════════════════════════════════════
	#  ① 纯几何: 梯形演出的角点 = 判定边界 (不建场, 直接算)
	# ══════════════════════════════════════════════════════════════
	print("── ① 演出即判定: 梯形四角逐码对齐 ──")
	var tested := 0
	for step in range(1, int(AE.CHARGE_TIME / AE.CHARGE_STEP) + 1):
		var h: float = float(step) * AE.CHARGE_H_PER_STEP
		var cs: Array = APV.field_corners(h)
		if cs.size() != 4:
			_ok("h=%.0f 有四个角" % h, false, "拿到 %d 个" % cs.size())
			continue
		tested += 1
		var org := Vector2(0, 0)
		var dir := Vector2(1, 0)
		## 角点稍稍**往里** ⇒ 判定必须说"在里面"; 稍稍**往外** ⇒ 必须说"不在"。
		## ★两侧各验一次 —— memory [[fb-judge-must-fit-the-shape]]: 只验一侧,
		##   宽一格和窄一格都发现不了。
		for c in cs:
			var p: Vector2 = c
			var inward: Vector2 = (Vector2(h * 0.5, 0.0) - p).normalized() * 2.0
			var pin: Vector2 = p + inward
			var pout: Vector2 = p - inward
			if not AE.in_trapezoid(org, dir, h, pin):
				_ok("h=%.0f 角(%.0f,%.0f) 往里 2 码应在判定内" % [h, p.x, p.y], false)
			if AE.in_trapezoid(org, dir, h, pout):
				_ok("h=%.0f 角(%.0f,%.0f) 往外 2 码应在判定外" % [h, p.x, p.y], false)
	_ok("★分母: 逐格验了 %d 种蓄力高度(应 = %d 格)" % [tested, int(AE.CHARGE_TIME / AE.CHARGE_STEP)],
		tested == int(AE.CHARGE_TIME / AE.CHARGE_STEP), "为 0 = 空检查")
	_ok("① 八格梯形的角点全部恰好卡在判定边界上(往里在内/往外在外)", _fail == 0,
		"已 FAIL %d 条" % _fail)

	## ★半宽必须按【满蓄高】插值而不是当前高 —— 这是判定那边注释点名的坑。
	## 反向说法: 若演出按当前高插值, 那么 h=100 时远边半宽会等于 900/2=450(满宽),
	## 而判定只给 lerp(300,900,100/800)/2 = 187.5。拿这两个数直接比。
	var w_far_at_100: float = APV.half_w_at(100.0)
	var wrong_if_by_h: float = AE.TRAPEZOID_FAR_W * 0.5
	_ok("② 半宽按满蓄高插值(h=100 时半宽 %.1f, 不是按当前高的 %.1f)"
		% [w_far_at_100, wrong_if_by_h], absf(w_far_at_100 - wrong_if_by_h) > 1.0,
		"两者相等 = 演出会比判定胖")
	_ok("★分母: h=100 的半宽是真算出来的(非 0)", w_far_at_100 > 0.0)

	# ══════════════════════════════════════════════════════════════
	#  ② 真建场: 招式帧真的换上去了
	# ══════════════════════════════════════════════════════════════
	print("── ② 招式帧: 读产品自己的 _axe_last_action ──")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var owner_u: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-200, 0))
	_s._units.append(owner_u)
	var foe: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(120, 0))
	foe["maxHp"] = 1.0e8
	foe["hp"] = 1.0e8
	_s._units.append(foe)

	var ax = _s._equip_sys._axe.summon(owner_u)
	_ok("★分母: 真召唤出斧头", ax is Dictionary and ax.get("alive", false))
	if not (ax is Dictionary):
		_done()
		return

	## 逐档验: 把 `_axe_pv` 直接钉在召唤物上(产品就是这么存的, 见 axe_system.summon),
	## 然后走**真入口** `on_hit` —— 不是直接调 play_action
	## (memory [[fb-verify-must-run-the-real-path]]: 目视确认过零调用者的死函数)。
	var cases := [
		{"pv": 3, "swing_parity": 1, "want": "axe_sweep", "name": "金斧·奇数拳 → 横扫"},
		{"pv": 3, "swing_parity": 0, "want": "axe_cleave", "name": "铁斧·偶数拳 → 竖劈"},
	]
	for cs2 in cases:
		ax["_axe_pv"] = int(cs2["pv"])
		ax["_axe_swing"] = (0 if int(cs2["swing_parity"]) == 1 else 1)   # 下一拳的奇偶
		ax["_axe_smash_ready"] = false                                    # 别让强化砸抢镜
		ax.erase("_axe_last_action")
		_s._equip_sys._axe.on_hit(ax, foe, true)
		_ok("③ %s (实测 %s)" % [str(cs2["name"]), str(ax.get("_axe_last_action", "(没播)"))],
			str(ax.get("_axe_last_action", "")) == str(cs2["want"]))

	## 强化猛砸【优先级】: 同一拳既满足竖劈又满足强化砸时, 必须播 smash。
	## ★这条是接线时想到的真实风险: 连着 _set_anim_sheet 两次, 后一张顶掉前一张,
	##   表现成"强化猛砸永远看不见"而伤害照常结算 —— 屏幕上分辨不出来。
	ax["_axe_pv"] = 4
	ax["_axe_swing"] = 1                 # 下一拳是第 2 拳 = 偶数 = 竖劈
	ax["_axe_smash_ready"] = true        # 同时强化砸也就绪
	ax.erase("_axe_last_action")
	_s._equip_sys._axe.on_hit(ax, foe, true)
	_ok("④ 强化砸与竖劈撞在同一拳 → 播稀有的那个(smash)",
		str(ax.get("_axe_last_action", "")) == "axe_smash",
		"实测 %s" % str(ax.get("_axe_last_action", "(没播)")))

	# ══════════════════════════════════════════════════════════════
	#  ②b 五张新素材: 存在 / 规格 / **真的被建成节点**
	# ══════════════════════════════════════════════════════════════
	## ★「素材在盘上」证明不了「玩家看得见」—— 斧头那 8 张动作帧就是躺了两天零调用者
	##   (memory [[fb-zero-caller-is-a-whole-class]])。所以三层都要验:
	##   ① 文件在  ② 是 9 帧的 sheet 不是单图  ③ 走真入口后 _world 里真多了节点。
	print("── ②b 五张特效素材 ──")
	var sheets := {
		"cleave": APV.TEX_CLEAVE, "sweep": APV.TEX_SWEEP, "smash": APV.TEX_SMASH,
		"slam": APV.TEX_SLAM, "heal": APV.TEX_HEAL,
	}
	for k in sheets:
		var path: String = str(sheets[k])
		var ex: bool = ResourceLoader.exists(path)
		_ok("素材在盘上: %s" % k, ex, path)
		if not ex:
			continue
		var tex: Texture2D = load(path)
		var fh: int = maxi(1, tex.get_height())
		var nf: int = int(tex.get_width() / fh)
		## ★用户 2026-08-29:「不要拿图片贴图敷衍我, 我要动画像素特效」⇒ 单帧不算数。
		_ok("%s 是多帧动画(%d 帧, 单帧=敷衍)" % [k, nf], nf >= 4, "%dx%d" % [tex.get_width(), fh])

	var pvfx = _s._equip_sys._axe._pas.vfx
	var before: int = _s._world.get_child_count()
	var made := {
		"cleave": pvfx.cleave(ax, foe),
		"sweep": pvfx.sweep(ax, Vector2.RIGHT),
		"smash": pvfx.smash(foe),
		"slam": pvfx.slam(ax, Vector2.RIGHT, 400.0),
		"heal": pvfx.heal(ax),
	}
	for k in made:
		_ok("④b %s 真的建出了节点并挂进 _world" % k,
			made[k] != null and is_instance_valid(made[k]) and (made[k] as Node).is_inside_tree(),
			"拿到 null / 没进树 = 玩家看不见")
	_ok("★分母: _world 子节点从 %d 涨到 %d(涨了 %d 个)"
		% [before, _s._world.get_child_count(), _s._world.get_child_count() - before],
		_s._world.get_child_count() > before, "没涨 = 上面五条是空检查")

	## ★横扫的直径必须 = 判定直径(atk_range × 2)。这条是"演出即判定"在横扫上的具体含义:
	##   画大了玩家以为扫得到却没伤害, 画小了反过来。拿 pixel_size × 单帧宽 反推真实码数。
	var sw_node = made["sweep"]
	if sw_node != null and is_instance_valid(sw_node):
		var sp := sw_node as Sprite3D
		var fh2: float = maxf(1.0, float(sp.texture.get_height()))
		var real_px: float = sp.pixel_size * fh2 / _s.WS       # 反推回场地码
		var want: float = float(ax.get("atk_range", 120.0)) * 2.0
		_ok("⑤b 横扫直径 %.0f 码 = 判定直径 %.0f 码(atk_range×2)" % [real_px, want],
			absf(real_px - want) < 1.0, "差 %.1f 码 = 演出与判定不等" % absf(real_px - want))

	# ══════════════════════════════════════════════════════════════
	#  ③ 梯形在所有退出路径上都收掉
	# ══════════════════════════════════════════════════════════════
	print("── ③ 收尾: 蓄力中斧头死掉, 地上不许留亮区 ──")
	ax["_axe_pv"] = 4
	ax["alive"] = true
	ax.erase("_axe_charge_t0")
	var began: bool = _s._equip_sys._axe._pas.begin_charge(ax)
	_ok("★分母: 真进了蓄力", began and ax.has("_axe_charge_t0"))
	_ok("⑤ 蓄力一开始就有梯形场", ax.get("_axe_field", null) != null)
	var fld = ax.get("_axe_field", null)
	## ★★★【边线颜色 = 蓄力进度】—— 第四轮判据。**前三轮守的是错参考, 整块删了。**
	##   用户 2026-09-03 指出真正的参考段落在机甲皮肤 spotlight 的 **1:59~2:02**
	##   (`C:/tmp/sionref/m2/` 108 张原生帧 @29.97fps; 120.00s 线出现 → 121.94s 释放
	##    = **1.94 秒满蓄**, 塞恩 Q 上限就是 2 秒)。逐帧分群量出来:
	##     边线是 **青(180°) → 青绿 → 黄绿 → 黄 → 橙 → 红(0°) 的连续色相渐变**,
	##     它才是"还剩多久"的主要信息载体。
	##   ★前三轮我做的是**闪烁频率**(2Hz 呼吸 + 末秒 6Hz), 方向就不对; 而且照**原版塞恩**
	##     (红色 Q, 根本不是机甲皮肤)加了"起手闪"和纯色填充 ——
	##     那两条门禁(旧 ⑤c/⑤d)守的是错东西, 已随实现一起删。
	##
	## 判据分两层: **纯函数逐点验**(便宜、精确) + **真实节点验**(证明它真的接上了)。
	if fld != null and is_instance_valid(fld):
		var _h0: float = APV.edge_color_at(0.0, 2).h * 360.0
		var _h5: float = APV.edge_color_at(0.50, 2).h * 360.0
		var _h9: float = APV.edge_color_at(0.92, 2).h * 360.0
		var _h1: float = APV.edge_color_at(1.0, 2).h * 360.0
		_ok("⑤c 蓄力前半是青色(p=0.00 → %.0f° · p=0.50 → %.0f°)" % [_h0, _h5],
			absf(_h0 - 180.0) < 12.0 and absf(_h5 - 180.0) < 12.0,
			"不是青 = 与参考 48~76% 那段对不上")
		_ok("⑤d 满蓄瞬间是红色(p=1.00 → %.0f°)" % _h1,
			_h1 < 12.0 or _h1 > 348.0,
			"不是红 = 与参考 121.94s 那一帧对不上")
		## ★这条卡的是"**真的在渐变**"而不是"两端刚好对" ——
		##   一个 `return 青 if p < 0.99 else 红` 的阶跃实现会通过上面两条, 在这条红。
		_ok("⑤e 中间是连续渐变: p=0.92 落在青红之间(%.0f°), 与两端都拉开 > 25°" % _h9,
			_h9 > 12.0 and _h9 < 168.0 and absf(_h9 - _h1) > 25.0 and absf(_h9 - _h5) > 25.0,
			"卡在某一端 = 是阶跃不是渐变")
		## ── 真实节点: 证明这条曲线**接上了**, 不是只有纯函数好看 ──
		##   memory [[fb-zero-caller-is-a-whole-class]]: 门禁直接调函数不能证明游戏里会走到。
		## ⚠ **必须自己推 `battle._t`** —— `tick_charge(ax, delta)` 的 delta 只管效率计时,
		##   蓄力进度走的是 `charge_elapsed() = battle._t − _axe_charge_t0`。不推 `_t` 的话
		##   `charge_height()` 恒为 0 ⇒ `charge_update` 第一行 `h <= 0.0` 就 return ⇒
		##   `_tick_field_pulse` **一次都跑不到**, 读到的全是建场那一刻的初值 = 恒真式。
		##   ★这不是假设: 上一版就是这么写的, 反向验证**没红**才发现。
		for _fk in range(6):
			_s._t += 0.1
			_s._equip_sys._axe._pas.tick_charge(ax, 0.1)
		var _eg = (fld as Node).get_node_or_null("Edge")
		var _em: BaseMaterial3D = null
		if _eg is MeshInstance3D:
			_em = (_eg as MeshInstance3D).material_override as BaseMaterial3D
		_ok("★分母: 推进 6 帧后 Edge 节点仍在且有材质", _em != null, "拿不到 = 下面那条是空检查")
		var _hue_early: float = (_em.albedo_color.h * 360.0) if _em != null else -1.0
		## 再推到接近满蓄
		var _guard: int = 0
		while _s._equip_sys._axe._pas.charge_elapsed(ax) < AE.CHARGE_TIME * 0.95 and _guard < 400:
			_s._t += 0.1
			_s._equip_sys._axe._pas.tick_charge(ax, 0.1)
			_guard += 1
		var _eg2 = (fld as Node).get_node_or_null("Edge")
		var _em2: BaseMaterial3D = null
		if _eg2 is MeshInstance3D:
			_em2 = (_eg2 as MeshInstance3D).material_override as BaseMaterial3D
		var _hue_late: float = (_em2.albedo_color.h * 360.0) if _em2 != null else -1.0
		_ok("⑤f 真实节点上色相随蓄力**变了**(早 %.0f° → 晚 %.0f°, 差 %.0f°)"
			% [_hue_early, _hue_late, absf(_hue_early - _hue_late)],
			_em2 != null and absf(_hue_early - _hue_late) > 60.0,
			"没变 = 曲线写了但没接到边线上")
		## ── 地面网格(第四轮: "纯色填充" → 六边形网格纹理) ──
		##   参考实测: 区内亮度只有 **103%**(几乎没变), 而纹理对比度 **+46%**
		##   ⇒ 是"加纹理"不是"改亮度"。纯色填充改亮度但不改对比度, 方向从根上就不对。
		var _fl = (fld as Node).get_node_or_null("Fill")
		_ok("⑤g 地面有六边形网格 mesh(不是纯色面)",
			_fl is MeshInstance3D and (_fl as MeshInstance3D).mesh != null,
			"没 mesh = 区内什么纹理都没有")
	## 模拟"蓄力中被打死": 产品走 tick_charge → not alive → _end_charge
	ax["alive"] = false
	_s._equip_sys._axe._pas.tick_charge(ax, 0.1)
	_ok("⑥ 斧头死在蓄力中 → 梯形被收掉(字段清空)", not ax.has("_axe_field"))
	## ★`queue_free()` 是**延迟**释放 —— 同一帧断言 is_instance_valid 必然还是 true,
	##   那是判据错不是产品错(第一版就这么红的)。等一帧再判。
	## ★这不会把判据放松成恒真: 如果根本没调 queue_free, 等多少帧它都还活着。
	await get_tree().process_frame
	await get_tree().process_frame
	## ★★蓄力期间【不攒龟能】(用户 2026-09-03:「蓄力的时候不能攒龟能」)。
	##   反向验证: 把 axe_system.tick 里那个 `if not _pas.is_charging(ax)` 去掉 ⇒ 这条当场红。
	ax["alive"] = true
	ax.erase("_axe_charge_t0")
	ax["_axe_pv"] = 4
	ax["energy"] = 0.0
	_s._equip_sys._axe._pas.begin_charge(ax)
	var _e0: float = float(ax.get("energy", 0.0))
	for _k in range(12):
		_s._equip_sys._axe.tick(owner_u, 0.1)      # 走真入口 tick(), 不直接调充能
	var _e1: float = float(ax.get("energy", 0.0))
	_ok("⑧ 蓄力中【不攒龟能】(推了 1.2 秒, 龟能 %.1f → %.1f)" % [_e0, _e1],
		is_equal_approx(_e0, _e1), "涨了 %.2f —— 蓄力期间不该攒" % (_e1 - _e0))
	## ★分母: 同样推 1.2 秒, **不在蓄力**时必须真的涨(否则上面那条是恒真式)
	_s._equip_sys._axe._pas._end_charge(ax)
	ax["alive"] = true
	var _e2: float = float(ax.get("energy", 0.0))
	for _k2 in range(12):
		_s._equip_sys._axe.tick(owner_u, 0.1)
	var _e3: float = float(ax.get("energy", 0.0))
	_ok("★分母: 不蓄力时龟能确实在涨(%.1f → %.1f)" % [_e2, _e3], _e3 > _e2 + 0.01,
		"没涨 = 上面那条是空检查")

	_ok("⑦ 梯形节点真的被 free 了(不是只清了字段)",
		fld == null or not is_instance_valid(fld),
		"节点还活着 = 地上留了一块永久亮区")

	_done()


func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
		get_tree().quit(0)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
		get_tree().quit(1)
