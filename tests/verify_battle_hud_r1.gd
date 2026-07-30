extends Node
## verify_battle_hud_r1.gd — 顶部双方总血量 PK 条 (用户 2026-07-30 需求1)
##
## 方案书: docs/plans/20260730b-局内HUD改造+大师审核+地图提升.md §4.1 / §6
##
## 用户逐字:「对局内的顶部左右新加一个双方血条的pk，表示双方总血量实时变化，需要详细设计下」
##   拍板 U1 =【小将和龟统领的】(比我建议的更窄 —— 训龟大师也排除)
##   拍板 U2 =【中央对撞条】
##
## ★全程用【干净合成单位】, 不 spawn 真队伍 ——
##   memory fb-ci-vs-local-divergence: 拿随机 spawn 的单位测精确数值会 CI 偶发红
##   (队伍未播种 RNG / CI 默认队 vs 本地存档队 / 敌带盾或 flat_dr 破坏预期)。
##
## 版式: 蓝占左半从左端往中间长, 红占右半从右端往中间长, 中间暗缝 = 双方已损失总量。
##   ★每侧长度按【自己的开场基线】归一化 —— 不是按"双方当前血之和"的相对比。
##   我第一版写成纯相对比, 结果基线字段存了没人用, 且双方都剩 10% 血时条和满血长得一样,
##   丢掉了"总血量"这个绝对信息(需求原文要的正是它)。相对优势改由中间的百分比读。
##
## 查五组:
##   ① 条建起来了; 两段长度各不超过半宽, 且 0/1 两个端点精确
##   ② 计入口径: 龟 ✓ / 小将 ✓ / 龟蛋 ✗ / 训龟大师 ✗ / 召唤体 ✗
##   ③ 分母是【本路开场基线】且死人不改它(否则比例会反向回升) + 中间百分比是相对优势
##   ④ 换路重算基线(全局 _t 跨路累加, 按本场计的东西必须自己存基线·CLAUDE.md §3.4)
##   ⑤ 平滑收敛: 逐帧向目标插值, 且收敛后【吸附】不留半像素缝
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_battle_hud_r1.tscn

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
var _n_chk := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n_chk += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 干净合成单位。只带 PK 条真正读的字段 —— 多余字段会引入噪声。
func _mk(side: String, hp: float, mx: float, extra: Dictionary = {}) -> Dictionary:
	var u := {"id": "basic", "name": "合成", "side": side,
		"alive": hp > 0.0, "hp": hp, "maxHp": mx}
	for k in extra:
		u[k] = extra[k]
	return u


func _ready() -> void:
	print("=== 顶部双方总血量 PK 条 (需求1) ===")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var s = RTScene.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)          # 停战斗 tick: 本测试自己喂 _units 并手动调 _pk_*
	s.set_physics_process(false)

	_built(s)
	_scope(s)
	_denominator(s)
	_lane_reset(s)
	_smooth(s)

	print("  ★分母: 本测试共 %d 条断言" % _n_chk)
	if _fail == 0:
		print("ALL PASS — 顶部双方总血量 PK 条")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)


## ① 条本体 + 接缝无缝隙
func _built(s) -> void:
	print("  ── ① 条已建 + 接缝无缝隙 ──")
	var h = s._hud
	_ok("① PK 条节点已建", s._pk_bar != null and is_instance_valid(s._pk_bar))
	_ok("① 两段填充都在", s._pk_fill_l != null and s._pk_fill_r != null)
	_ok("① 条是【顶部居中锚点】不是写死坐标(手机分辨率不同不会跑偏出屏)",
		absf(s._pk_bar.anchor_left - 0.5) < 0.001 and absf(s._pk_bar.anchor_right - 0.5) < 0.001)
	_ok("① 条不吃鼠标事件(纯显示·别挡战场点击)",
		s._pk_bar.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	# ★几何不变量(任何比例组合下都要成立):
	#   · 蓝段从左端(x=2)起, 红段右缘紧贴右端 → 两段都贴自己那一端, 中间才是缝
	#   · 两段各不超过半宽 → 永不越过中线互相重叠
	var inner: float = h.PK_W - 4.0
	var half: float = inner * 0.5
	var worst_l := 0.0
	var worst_r := 0.0
	var worst_over := 0.0
	for fl in [0.0, 0.001, 0.5, 0.999, 1.0]:
		for fr in [0.0, 0.001, 0.5, 0.999, 1.0]:
			h._pk_apply(float(fl), float(fr))
			worst_l = maxf(worst_l, absf(s._pk_fill_l.position.x - 2.0))
			var r_right: float = s._pk_fill_r.position.x + s._pk_fill_r.size.x
			worst_r = maxf(worst_r, absf(r_right - (2.0 + inner)))
			worst_over = maxf(worst_over, maxf(s._pk_fill_l.size.x - half, s._pk_fill_r.size.x - half))
	_ok("① ★25 组比例下蓝段恒贴左端(最大偏差 %.4f px)" % worst_l, worst_l < 0.001)
	_ok("① ★25 组比例下红段右缘恒贴右端(最大偏差 %.4f px)" % worst_r, worst_r < 0.001,
		"内宽 %.1f" % inner)
	_ok("① ★两段都不越过中线(最大超出 %.4f px)" % worst_over, worst_over < 0.001,
		"半宽 %.1f" % half)
	# 端点精确
	h._pk_apply(1.0, 1.0)
	_ok("① 双方满血 → 两段各吃满半宽(条看起来是满的)",
		absf(s._pk_fill_l.size.x - half) < 0.001 and absf(s._pk_fill_r.size.x - half) < 0.001)
	h._pk_apply(0.0, 0.0)
	_ok("① 双方全灭 → 两段都是 0(条全空)",
		s._pk_fill_l.size.x < 0.001 and s._pk_fill_r.size.x < 0.001)
	# ★这条是第一版设计缺陷的回归守卫: 纯相对比会让"都剩10%"和"都满血"画得一样
	h._pk_apply(1.0, 1.0)
	var full_l: float = s._pk_fill_l.size.x
	h._pk_apply(0.1, 0.1)
	_ok("① ★双方都剩 10% 时条【明显更短】(不是纯相对比 —— 那样会和满血长得一样)",
		s._pk_fill_l.size.x < full_l * 0.2,
		"满血 %.1f px vs 都剩10%% %.1f px" % [full_l, s._pk_fill_l.size.x])


## ② 计入口径 —— 用户拍板"小将和龟统领的"
func _scope(s) -> void:
	print("  ── ② 计入口径: 龟+小将; 蛋/大师/召唤体都不算 ──")
	var h = s._hud
	_ok("② 龟本体计入", h._pk_counts(_mk("left", 100, 100)))
	_ok("② 小将计入", h._pk_counts(_mk("left", 100, 100, {"is_minion": true, "minion": true})))
	_ok("② ★龟蛋不计入(egg)", not h._pk_counts(_mk("left", 100, 100, {"egg": true})))
	_ok("② ★龟蛋不计入(has_egg)", not h._pk_counts(_mk("left", 100, 100, {"has_egg": true})))
	_ok("② ★训龟大师不计入(用户口径比【含大师】更窄)",
		not h._pk_counts(_mk("left", 500, 500, {"is_trainer": true})))
	_ok("② ★召唤体不计入(与 _check_over 胜负判定同口径)",
		not h._pk_counts(_mk("left", 100, 100, {"is_summon": true})))

	# 端到端: 蛋满血 + 龟全死 → 条必须是 0(而不是被蛋撑成半满)
	s._units.clear()
	s._units.append(_mk("left", 0, 1000))                         # 我方龟死光
	s._units.append(_mk("left", 9000, 9000, {"egg": true}))       # 我方蛋满血
	s._units.append(_mk("left", 500, 500, {"is_trainer": true}))  # 我方大师满血
	s._units.append(_mk("right", 800, 1000))                      # 敌方龟还活着
	s._pk_count = -1
	h._pk_refresh()
	_ok("② ★龟死光但蛋/大师满血 → 我方段长 0(不是被蛋撑起来)",
		absf(s._pk_target_l - 0.0) < 0.0001, "实际 %.4f" % s._pk_target_l)
	_ok("② ★基线也没把蛋/大师算进去(左基线应为 1000 只算那只龟)",
		absf(s._pk_base_l - 1000.0) < 0.01, "实际 %.0f" % s._pk_base_l)
	_ok("② 左端数字显 0(算的是龟不是蛋)", s._pk_lab_l.text == "0", "实际 %s" % s._pk_lab_l.text)
	_ok("② 右端数字显 800", s._pk_lab_r.text == "800", "实际 %s" % s._pk_lab_r.text)

	# 千分位
	_ok("② 千分位: 12480 → 12,480", h._pk_num(12480.0) == "12,480", h._pk_num(12480.0))
	_ok("② 千分位: 999 → 999", h._pk_num(999.0) == "999")
	_ok("② 千分位: 1000000 → 1,000,000", h._pk_num(1000000.0) == "1,000,000", h._pk_num(1000000.0))


## ③ 分母 = 开场基线, 死人不改它
func _denominator(s) -> void:
	print("  ── ③ 分母是开场基线(死人不让百分比反向回升) ──")
	var h = s._hud
	s._units.clear()
	var a := _mk("left", 1000, 1000)
	var b := _mk("left", 1000, 1000)
	var c := _mk("right", 1000, 1000)
	var d := _mk("right", 1000, 1000)
	for u in [a, b, c, d]:
		s._units.append(u)
	s._pk_count = -1
	h._pk_refresh()
	_ok("③ 开场 4 只满血 → 两侧比例都是 1.0",
		absf(s._pk_target_l - 1.0) < 0.0001 and absf(s._pk_target_r - 1.0) < 0.0001,
		"左 %.4f 右 %.4f" % [s._pk_target_l, s._pk_target_r])
	_ok("③ 基线记下了左 2000 / 右 2000",
		absf(s._pk_base_l - 2000.0) < 0.01 and absf(s._pk_base_r - 2000.0) < 0.01,
		"左 %.0f 右 %.0f" % [s._pk_base_l, s._pk_base_r])
	_ok("③ 开场中间百分比 = 50%(势均力敌)", s._pk_lab_mid.text.contains("50%"),
		s._pk_lab_mid.text)
	# ★我方死一只 → 我方比例必须降到 0.5, 且【右侧比例一动不动】。
	#   这是"分母若跟着当前存活缩会反向回升"的反例: 若分母是"当前存活 maxHp 之和",
	#   死一只后左边会变成 1000/1000 = 1.0, 条反而涨回满 —— 完全反直觉。
	a["hp"] = 0.0; a["alive"] = false
	h._pk_refresh()
	_ok("③ ★我方死一只 → 我方比例降到 0.5(不是回升到 1.0)",
		absf(s._pk_target_l - 0.5) < 0.0001, "%.4f" % s._pk_target_l)
	_ok("③ ★对方比例一动不动(仍 1.0)", absf(s._pk_target_r - 1.0) < 0.0001,
		"%.4f" % s._pk_target_r)
	_ok("③ ★基线没被死亡改动(仍 2000/2000)",
		absf(s._pk_base_l - 2000.0) < 0.01 and absf(s._pk_base_r - 2000.0) < 0.01,
		"左 %.0f 右 %.0f" % [s._pk_base_l, s._pk_base_r])
	# ★直接断言载荷属性: _pk_sum 的分母项必须把【已死单位】也算进去。
	#   固定基线这个行为其实被【两道独立机制】保护 —— ①换路才重算的守卫 ②分母含已死单位。
	#   任一单独破坏都被另一道兜住, 所以上面那条"基线没被死亡改动"单点破坏抓不到。
	#   这条直接量 _pk_sum 的返回值, 让"改成只算存活"这个具体退化一次就红。
	var sum_l: Vector2 = h._pk_sum("left")
	_ok("③ ★_pk_sum 的分母项含已死单位(死了 1 只仍报 2000)",
		absf(sum_l.y - 2000.0) < 0.01, "分母 %.0f (当前血 %.0f)" % [sum_l.y, sum_l.x])
	_ok("③ _pk_sum 的分子项只算存活(1000)", absf(sum_l.x - 1000.0) < 0.01,
		"%.0f" % sum_l.x)
	_ok("③ 中间百分比变成相对劣势 33%(1000 : 2000)",
		s._pk_lab_mid.text.contains("33%") and s._pk_lab_mid.text.contains("▼"),
		s._pk_lab_mid.text)
	# 双方全灭 → 不许除零/NaN
	for u in [b, c, d]:
		u["hp"] = 0.0; u["alive"] = false
	h._pk_refresh()
	_ok("③ 双方全灭 → 两侧比例都是 0(不除零/不 NaN)",
		absf(s._pk_target_l) < 0.0001 and absf(s._pk_target_r) < 0.0001,
		"左 %.4f 右 %.4f" % [s._pk_target_l, s._pk_target_r])
	_ok("③ 双方全灭 → 中间百分比回 50%(不 NaN)", s._pk_lab_mid.text.contains("50%"),
		s._pk_lab_mid.text)


## ④ 换路重算基线
func _lane_reset(s) -> void:
	print("  ── ④ 换路重算基线(_t 跨路累加·必须自己存基线) ──")
	var h = s._hud
	s._units.clear()
	s._units.append(_mk("left", 1000, 1000))
	s._units.append(_mk("right", 1000, 1000))
	s._pk_count = -1
	h._pk_refresh()
	var base1_l: float = s._pk_base_l
	_ok("④ 第一路基线 = 1000", absf(base1_l - 1000.0) < 0.01, "%.0f" % base1_l)
	# 模拟换路: _dl_clear_units() 会清空 _units 再重新 spawn(dual_lane_flow:719-724),
	# 所以"计入 PK 的单位数变了"是可靠的换路信号 —— 死亡不会改这个数(只置 alive=false)。
	s._units.clear()
	s._units.append(_mk("left", 3000, 3000))
	s._units.append(_mk("left", 3000, 3000))
	s._units.append(_mk("right", 3000, 3000))
	h._pk_refresh()
	_ok("④ ★换路后基线重算成 6000(没沿用上一路的 1000)",
		absf(s._pk_base_l - 6000.0) < 0.01, "%.0f" % s._pk_base_l)
	_ok("④ ★换路后两段复位到满(不从上一路的长度滑过来)",
		absf(s._pk_shown_l - 1.0) < 0.0001 and absf(s._pk_shown_r - 1.0) < 0.0001,
		"左 %.4f 右 %.4f" % [s._pk_shown_l, s._pk_shown_r])
	_ok("④ 换路计数已更新", s._pk_count == 3, "%d" % s._pk_count)


## ⑤ 平滑收敛
func _smooth(s) -> void:
	print("  ── ⑤ 逐帧平滑 + 收敛吸附 ──")
	var h = s._hud
	s._units.clear()
	s._units.append(_mk("left", 1000, 1000))
	s._units.append(_mk("right", 200, 1000))
	s._pk_count = -1
	h._pk_refresh()
	_ok("⑤ 左满血 → 目标 1.0", absf(s._pk_target_l - 1.0) < 0.0001, "%.4f" % s._pk_target_l)
	_ok("⑤ 右剩 200/1000 → 目标 0.2", absf(s._pk_target_r - 0.2) < 0.0001,
		"%.4f" % s._pk_target_r)
	# 一次 tick 不该直接跳到目标(否则群伤瞬间会抽搐)
	s._pk_shown_r = 1.0
	s._pk_acc = 0.0
	h._pk_tick(1.0 / 60.0)
	_ok("⑤ ★单帧不直接跳到目标(有平滑)",
		s._pk_shown_r < 1.0 and s._pk_shown_r > s._pk_target_r + 0.001,
		"一帧后 %.4f (目标 %.4f)" % [s._pk_shown_r, s._pk_target_r])
	# 跑够帧数必须收敛并【吸附】
	for _i in range(240):
		h._pk_tick(1.0 / 60.0)
	_ok("⑤ ★跑 240 帧后精确吸附到目标(不留半像素缝)",
		s._pk_shown_r == s._pk_target_r and s._pk_shown_l == s._pk_target_l,
		"右 %.8f vs %.8f" % [s._pk_shown_r, s._pk_target_r])
	_ok("⑤ 采样间隔 0.1s(别每帧扫 _units·主文件热路径预算 <0.2%)",
		absf(h.PK_SAMPLE - 0.1) < 0.0001, "%.3f" % h.PK_SAMPLE)
