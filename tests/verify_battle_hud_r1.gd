extends Node
## verify_battle_hud_r1.gd — 顶部双方总血量 PK 条 (用户 2026-07-30 需求1)
##
## 方案书: docs/plans/20260730b-局内HUD改造+大师审核+地图提升.md §4.1 / §6 / §8
##
## ★第二版(用户逐条审核后重做)。本门禁焊死的是审核里改掉的那六条 ——
##   尤其【① 那个真 bug】: 排除龟蛋原本写的是 u.get("egg"), 而单位字典上【没有这个键】,
##   蛋带的是 _isEgg(battle_spawn.gd:439)。所以"不含龟蛋"根本没生效, 蛋的 3300 血
##   (有围栏 +200 双抗、早期几乎不掉血)占了条里约 56% 的【不动的血】。
##
## ★全程用【干净合成单位】, 不 spawn 真队伍 ——
##   memory fb-ci-vs-local-divergence: 拿随机 spawn 的单位测精确数值会 CI 偶发红。
##
## 查八组:
##   ① 几何: 两段【各贴自己外端】、不越中线、端点精确、"都剩10%"必须比满血明显短
##   ② ★计入口径: 龟✓ 小将✓ / 龟蛋✗(用 _isEgg 不是 egg) 大师✗ 召唤体✗
##   ③ 分母 = 本路开场基线, 死人不改它(否则比例反向回升)
##   ④ 换路重算基线 + 两条回满
##   ⑤ 平滑 + damage trail(残影不低于填充; 掉血瞬间高于填充)
##   ⑥ 读数: 百分比【开场 100%】(用户最初的疑问就是这个) + 绝对血量小字
##   ⑦ VS 徽标: 在位 + 染色随优势变(不用数字也读得出谁占优) + 受伤脉冲
##   ⑧ 副条: 按龟蛋自己的 hp/maxHp, 与主条口径独立
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_battle_hud_r1.tscn

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
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
	print("=== 顶部双方总血量 PK 条 (需求1·第二版) ===")
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

	_geometry(s)
	_scope(s)
	_denominator(s)
	_lane_reset(s)
	_smooth_and_trail(s)
	_readout(s)
	_vs_badge(s)
	_egg_bar(s)
	_btn_vs_bar(s)

	print("  ★分母: 本测试共 %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 顶部双方总血量 PK 条")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)


## ① 几何: 两段各贴自己外端, 掉血从内端往外退
func _geometry(s) -> void:
	print("  ── ① 两段各贴自己外端 + 不越中线 ──")
	var h = s._hud
	_ok("① PK 条节点已建", s._hud._pk_bar != null and is_instance_valid(s._hud._pk_bar))
	_ok("① 两段填充 + 两段残影都在",
		s._hud._pk_fill_l != null and s._hud._pk_fill_r != null
		and s._hud._pk_trail_l != null and s._hud._pk_trail_r != null)
	_ok("① 条是【顶部居中锚点】不是写死坐标(手机分辨率不同不会跑偏出屏)",
		absf(s._hud._pk_bar.anchor_left - 0.5) < 0.001 and absf(s._hud._pk_bar.anchor_right - 0.5) < 0.001)
	_ok("① 条不吃鼠标事件(纯显示·别挡战场点击)",
		s._hud._pk_bar.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	# ★核心不变量: 左段左缘恒定贴 x=2; 右段【右缘】恒定贴总宽-2; 两段都不超过自己那半
	var inner: float = h.PK_SEG - 4.0
	var worst_l := 0.0
	var worst_r := 0.0
	var worst_over := 0.0
	for fl in [0.0, 0.001, 0.5, 0.999, 1.0]:
		for fr in [0.0, 0.001, 0.5, 0.999, 1.0]:
			s._hud._pk_shown_l = float(fl); s._hud._pk_shown_r = float(fr)
			s._hud._pk_trail_vl = float(fl); s._hud._pk_trail_vr = float(fr)
			h._pk_apply()
			worst_l = maxf(worst_l, absf(s._hud._pk_fill_l.position.x - 2.0))
			var r_right: float = s._hud._pk_fill_r.position.x + s._hud._pk_fill_r.size.x
			worst_r = maxf(worst_r, absf(r_right - (h.PK_SEG + h.PK_VS + 2.0 + inner)))
			worst_over = maxf(worst_over,
				maxf(s._hud._pk_fill_l.size.x - inner, s._hud._pk_fill_r.size.x - inner))
	_ok("① ★25 组比例下左段恒贴左端(最大偏差 %.4f px)" % worst_l, worst_l < 0.001)
	_ok("① ★25 组比例下右段右缘恒贴右端(最大偏差 %.4f px)" % worst_r, worst_r < 0.001)
	_ok("① ★两段都不超出自己那一段的内宽(最大超出 %.4f px)" % worst_over, worst_over < 0.001,
		"段内宽 %.1f" % inner)
	# ★两段【不许重叠】: 左段右缘 ≤ 右段左缘(中间至少隔着 VS 槽)
	s._hud._pk_shown_l = 1.0; s._hud._pk_shown_r = 1.0
	s._hud._pk_trail_vl = 1.0; s._hud._pk_trail_vr = 1.0
	h._pk_apply()
	var l_right: float = s._hud._pk_fill_l.position.x + s._hud._pk_fill_l.size.x
	_ok("① ★两段满血也不重叠(中间留着 VS 槽)", l_right <= s._hud._pk_fill_r.position.x + 0.001,
		"左缘至 %.1f, 右段起 %.1f" % [l_right, s._hud._pk_fill_r.position.x])
	var full_l: float = s._hud._pk_fill_l.size.x
	s._hud._pk_shown_l = 0.1; s._hud._pk_shown_r = 0.1
	h._pk_apply()
	_ok("① ★双方都剩 10% 时明显更短(不是纯相对比 —— 那样会和满血一样长)",
		s._hud._pk_fill_l.size.x < full_l * 0.2,
		"满血 %.1f px vs 都剩10%% %.1f px" % [full_l, s._hud._pk_fill_l.size.x])


## ② ★计入口径 —— 这一组守的是那个真 bug
func _scope(s) -> void:
	print("  ── ② 计入口径: 龟+小将; 蛋/大师/召唤体都不算 ──")
	var h = s._hud
	_ok("② 龟本体计入", h._pk_counts(_mk("left", 100, 100)))
	_ok("② 小将计入", h._pk_counts(_mk("left", 100, 100, {"is_minion": true, "minion": true})))
	# ★真 bug 的回归守卫: 单位字典上蛋的键是 _isEgg / _eggImmune, 【不是】egg
	_ok("② ★龟蛋不计入(_isEgg —— 这是单位字典上真实存在的键)",
		not h._pk_counts(_mk("left", 3300, 3300, {"_isEgg": true})))
	_ok("② ★龟蛋不计入(_eggImmune 兜一层)",
		not h._pk_counts(_mk("left", 3300, 3300, {"_eggImmune": true})))
	_ok("② ★训龟大师不计入(用户口径比【含大师】更窄)",
		not h._pk_counts(_mk("left", 500, 500, {"is_trainer": true})))
	_ok("② ★召唤体不计入(与 _check_over 胜负判定同口径)",
		not h._pk_counts(_mk("left", 100, 100, {"is_summon": true})))

	# 端到端: 蛋满血 + 龟全死 → 主条必须是 0(而不是被蛋撑成半满)
	s._units.clear()
	s._units.append(_mk("left", 0, 1000))                              # 我方龟死光
	s._units.append(_mk("left", 3300, 3300, {"_isEgg": true, "egg_side_lr": "left"}))
	s._units.append(_mk("left", 500, 500, {"is_trainer": true}))       # 我方大师满血
	s._units.append(_mk("right", 800, 1000))
	s._hud._pk_lane = ""     # ★2026-07-31: 换路判据从"计数单位数变了"改成"路 id 变了"(见 _pk_refresh)
	h._pk_refresh()
	_ok("② ★龟死光但蛋/大师满血 → 我方主条 0(不是被蛋撑起来)",
		absf(s._hud._pk_target_l) < 0.0001, "实际 %.4f" % s._hud._pk_target_l)
	_ok("② ★基线也没把蛋/大师算进去(左基线应为 1000 只算那只龟)",
		absf(s._hud._pk_base_l - 1000.0) < 0.01, "实际 %.0f" % s._hud._pk_base_l)


## ③ 分母 = 开场基线, 死人不改它
func _denominator(s) -> void:
	print("  ── ③ 分母是开场基线(死人不让比例反向回升) ──")
	var h = s._hud
	s._units.clear()
	var a := _mk("left", 1000, 1000)
	var b := _mk("left", 1000, 1000)
	var c := _mk("right", 1000, 1000)
	var d := _mk("right", 1000, 1000)
	for u in [a, b, c, d]:
		s._units.append(u)
	s._hud._pk_lane = ""     # ★2026-07-31: 换路判据从"计数单位数变了"改成"路 id 变了"(见 _pk_refresh)
	h._pk_refresh()
	_ok("③ 开场 4 只满血 → 两侧比例都是 1.0",
		absf(s._hud._pk_target_l - 1.0) < 0.0001 and absf(s._hud._pk_target_r - 1.0) < 0.0001)
	_ok("③ 基线记下了左 2000 / 右 2000",
		absf(s._hud._pk_base_l - 2000.0) < 0.01 and absf(s._hud._pk_base_r - 2000.0) < 0.01,
		"左 %.0f 右 %.0f" % [s._hud._pk_base_l, s._hud._pk_base_r])
	a["hp"] = 0.0; a["alive"] = false
	h._pk_refresh()
	_ok("③ ★我方死一只 → 我方比例降到 0.5(不是回升到 1.0)",
		absf(s._hud._pk_target_l - 0.5) < 0.0001, "%.4f" % s._hud._pk_target_l)
	_ok("③ ★对方比例一动不动(仍 1.0)", absf(s._hud._pk_target_r - 1.0) < 0.0001)
	# ★直接量载荷属性: _pk_sum 的分母项必须含【已死单位】
	var sum_l: Vector2 = h._pk_sum("left")
	_ok("③ ★_pk_sum 的分母项含已死单位(死了 1 只仍报 2000)",
		absf(sum_l.y - 2000.0) < 0.01, "分母 %.0f (当前血 %.0f)" % [sum_l.y, sum_l.x])
	_ok("③ _pk_sum 的分子项只算存活(1000)", absf(sum_l.x - 1000.0) < 0.01)
	for u in [b, c, d]:
		u["hp"] = 0.0; u["alive"] = false
	h._pk_refresh()
	_ok("③ 双方全灭 → 两侧比例都是 0(不除零/不 NaN)",
		absf(s._hud._pk_target_l) < 0.0001 and absf(s._hud._pk_target_r) < 0.0001)


## ④ 换路重算基线
func _lane_reset(s) -> void:
	print("  ── ④ 换路重算基线(_t 跨路累加·必须自己存基线) ──")
	var h = s._hud
	s._units.clear()
	s._units.append(_mk("left", 1000, 1000))
	s._units.append(_mk("right", 1000, 1000))
	# ★★2026-07-31 换路判据改了: 原来是"计入 PK 的单位数变了"(_pk_count), 现在是"路 id 变了"。
	#   由来(用户「怎么有时候莫名增加或减少」): 按单位数判会被【任何中途增减计数单位】误触发,
	#   一触发两条就拉回 100% —— 玩家看到的就是血条莫名满格。
	#   所以本组也要跟着改: 换路必须【真的改 GameState.current_lane】, 光换单位不算换路
	#   (换单位不换路【本来就不该重置】—— 这正是新设计要的)。
	GameState.current_lane = "top"
	s._hud._pk_lane = ""     # 哨兵: 逼下一次 refresh 当作换路
	h._pk_refresh()
	_ok("④ 第一路基线 = 1000", absf(s._hud._pk_base_l - 1000.0) < 0.01)
	# 反向: 只换单位【不换路】→ 不该重置(否则就是老 bug 的形态)
	s._hud._pk_shown_l = 0.3; s._hud._pk_shown_r = 0.4
	s._units.append(_mk("left", 500, 500))
	h._pk_refresh()
	_ok("④ ★只增减单位而不换路 → 【不】重置(老 bug: 一增减就满格)",
		absf(s._hud._pk_shown_l - 0.3) < 0.0001, "左 %.4f" % s._hud._pk_shown_l)
	# 真换路: 改 lane id + 重建单位
	s._units.clear()
	s._units.append(_mk("left", 3000, 3000))
	s._units.append(_mk("left", 3000, 3000))
	s._units.append(_mk("right", 3000, 3000))
	GameState.current_lane = "bot"          # ★真的换路
	h._pk_refresh()
	_ok("④ ★换路后基线重算成 6000(没沿用上一路的 1000)",
		absf(s._hud._pk_base_l - 6000.0) < 0.01, "%.0f" % s._hud._pk_base_l)
	_ok("④ ★换路后两段复位到满(不从上一路的长度滑过来)",
		absf(s._hud._pk_shown_l - 1.0) < 0.0001 and absf(s._hud._pk_shown_r - 1.0) < 0.0001,
		"左 %.4f 右 %.4f" % [s._hud._pk_shown_l, s._hud._pk_shown_r])
	_ok("④ ★换路后残影也复位(否则会留一截上一路的亮条)",
		absf(s._hud._pk_trail_vl - 1.0) < 0.0001 and absf(s._hud._pk_trail_vr - 1.0) < 0.0001)
	# ★原来这条验的是"计数单位数 _pk_count 更新成 3"。那个字段已删 ——
	#   按单位数判换路会被【任何中途增减计数单位】误触发, 表现就是两条莫名满格。
	#   现在按路 id 判, 所以这里改验"路 id 已记下"。
	_ok("④ 换路后已记下当前路 id", s._hud._pk_lane != "", "lane=%s" % s._hud._pk_lane)


## ⑤ 平滑 + damage trail
func _smooth_and_trail(s) -> void:
	print("  ── ⑤ 平滑收敛 + damage trail ──")
	var h = s._hud
	s._units.clear()
	s._units.append(_mk("left", 1000, 1000))
	s._units.append(_mk("right", 200, 1000))
	s._hud._pk_lane = ""     # ★2026-07-31: 换路判据从"计数单位数变了"改成"路 id 变了"(见 _pk_refresh)
	h._pk_refresh()
	_ok("⑤ 右剩 200/1000 → 目标 0.2", absf(s._hud._pk_target_r - 0.2) < 0.0001)
	s._hud._pk_shown_r = 1.0
	s._hud._pk_trail_vr = 1.0
	s._hud._pk_acc = 0.0
	h._pk_tick(1.0 / 60.0)
	_ok("⑤ ★单帧不直接跳到目标(有平滑)",
		s._hud._pk_shown_r < 1.0 and s._hud._pk_shown_r > s._hud._pk_target_r + 0.001,
		"一帧后 %.4f (目标 %.4f)" % [s._hud._pk_shown_r, s._hud._pk_target_r])
	# ★残影: 必须【落后于】填充 —— 这才看得出"刚掉了这一段"
	_ok("⑤ ★掉血瞬间残影高于填充(看得出刚掉的那一段)",
		s._hud._pk_trail_vr > s._hud._pk_shown_r + 0.001,
		"残影 %.4f vs 填充 %.4f" % [s._hud._pk_trail_vr, s._hud._pk_shown_r])
	for _i in range(600):
		h._pk_tick(1.0 / 60.0)
	_ok("⑤ ★跑够帧数填充精确吸附到目标(不留半像素缝)",
		s._hud._pk_shown_r == s._hud._pk_target_r and s._hud._pk_shown_l == s._hud._pk_target_l,
		"右 %.8f vs %.8f" % [s._hud._pk_shown_r, s._hud._pk_target_r])
	_ok("⑤ ★残影最终追上填充(不会永远留一截亮条)",
		absf(s._hud._pk_trail_vr - s._hud._pk_shown_r) < 0.002,
		"残影 %.6f vs 填充 %.6f" % [s._hud._pk_trail_vr, s._hud._pk_shown_r])
	_ok("⑤ ★残影永不低于填充(低了就会露出填充边缘外的亮边)",
		s._hud._pk_trail_vr >= s._hud._pk_shown_r - 0.0001)
	_ok("⑤ 采样间隔 0.1s(别每帧扫 _units·主文件热路径预算 <0.2%)",
		absf(h.PK_SAMPLE - 0.1) < 0.0001, "%.3f" % h.PK_SAMPLE)
	_ok("⑤ 残影追赶【慢于】填充(否则看不出残影)", h.PK_TRAIL_SMOOTH < h.PK_SMOOTH,
		"trail %.1f vs fill %.1f" % [h.PK_TRAIL_SMOOTH, h.PK_SMOOTH])


## ⑥ 读数: 百分比开场 100% + 绝对血量小字
func _readout(s) -> void:
	print("  ── ⑥ 读数: 百分比(开场100%) + 绝对血量小字 ──")
	var h = s._hud
	s._units.clear()
	s._units.append(_mk("left", 3448, 3448))
	s._units.append(_mk("right", 2857, 2857))
	s._hud._pk_lane = ""     # ★2026-07-31: 换路判据从"计数单位数变了"改成"路 id 变了"(见 _pk_refresh)
	h._pk_refresh()
	# ★用户最初的疑问就是这个: 第一版中间显示相对占比, 开场必然是 50%, 被读成"我只有一半血"
	_ok("⑥ ★开场双方读数都是 100%(不是 50%)",
		s._hud._pk_lab_l.text == "100%" and s._hud._pk_lab_r.text == "100%",
		"左 %s 右 %s" % [s._hud._pk_lab_l.text, s._hud._pk_lab_r.text])
	_ok("⑥ ★绝对血量小字带千分位", s._hud._pk_lab_l2.text == "3,448" and s._hud._pk_lab_r2.text == "2,857",
		"左 %s 右 %s" % [s._hud._pk_lab_l2.text, s._hud._pk_lab_r2.text])
	_ok("⑥ ★中间那个会被读错的相对百分比已移除", not ("_pk_lab_mid" in s._hud))
	# 掉一半血 → 50%
	(s._units[0] as Dictionary)["hp"] = 1724.0
	h._pk_refresh()
	_ok("⑥ 掉一半 → 50%", s._hud._pk_lab_l.text == "50%", s._hud._pk_lab_l.text)
	_ok("⑥ 小字跟着走", s._hud._pk_lab_l2.text == "1,724", s._hud._pk_lab_l2.text)
	_ok("⑥ 千分位: 1000000 → 1,000,000", h._pk_num(1000000.0) == "1,000,000", h._pk_num(1000000.0))
	_ok("⑥ 千分位: 999 → 999", h._pk_num(999.0) == "999")


## ⑦ VS 徽标
func _vs_badge(s) -> void:
	print("  ── ⑦ VS 徽章: 像素画 + 光晕随优势染色 + 受伤脉冲 ──")
	var h = s._hud
	# ★第二版把"圆角方框 + VS 文字"换成了【像素徽章 + 背后染色光晕】
	#   (用户 2026-07-30:「不要这框呢，或者设计好点的」)。所以这组断言的是徽章与光晕。
	_ok("⑦ VS 容器 + 徽章 + 光晕都在",
		s._hud._pk_vs != null and s._hud._pk_vs_em != null and s._hud._pk_vs_glow != null)
	_ok("⑦ ★原来那个圆角方框已删(不再有 Panel 底片)", not ("_pk_vs_bg" in s._hud))
	_ok("⑦ ★徽章素材在磁盘上", FileAccess.file_exists(h.PK_VS_EMBLEM), h.PK_VS_EMBLEM)
	_ok("⑦ ★徽章真的拿到了贴图(不是空 TextureRect)",
		s._hud._pk_vs_em != null and s._hud._pk_vs_em.texture != null)
	_ok("⑦ 徽章用 NEAREST(像素画不许插值成糊)",
		s._hud._pk_vs_em.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	# ★徽章故意超出条高 —— 格斗游戏的中央徽章都是破出血条框的, 这样才是焦点。
	#   ★这条曾经是【恒真式】: TextureRect 默认 EXPAND_KEEP_SIZE, 最小尺寸被贴图(76×56)顶住,
	#     代码里设的 size 被无声钳上去 → 56 > 32 永远成立, 把高度改成 PK_H 也不红。
	#     现在代码设了 EXPAND_IGNORE_SIZE, 这条才真的在量【配置的】高度。
	_ok("⑦ ★徽章按配置尺寸渲染(expand_mode 必须 IGNORE_SIZE, 否则被贴图最小尺寸钳住)",
		s._hud._pk_vs_em.expand_mode == TextureRect.EXPAND_IGNORE_SIZE,
		"expand_mode=%d" % s._hud._pk_vs_em.expand_mode)
	_ok("⑦ ★徽章高度超出主条(破框 = 视觉焦点)", s._hud._pk_vs_em.size.y > h.PK_H,
		"徽章 %.0f vs 条高 %.0f" % [s._hud._pk_vs_em.size.y, h.PK_H])
	# 优势方染色: 染的是【光晕】
	s._hud._pk_shown_l = 1.0; s._hud._pk_shown_r = 0.05
	s._hud._pk_hit_l = 0.0; s._hud._pk_hit_r = 0.0
	h._pk_vs_tick(0.016)
	var col_adv: Color = s._hud._pk_vs_glow.modulate
	s._hud._pk_shown_l = 0.05; s._hud._pk_shown_r = 1.0
	h._pk_vs_tick(0.016)
	var col_dis: Color = s._hud._pk_vs_glow.modulate
	_ok("⑦ ★优劣两态光晕颜色明显不同(不用数字也读得出谁占优)",
		col_adv.r != col_dis.r or col_adv.g != col_dis.g or col_adv.b != col_dis.b)
	_ok("⑦ ★我方大优时光晕偏绿(g 更高)", col_adv.g > col_dis.g,
		"优势 g=%.3f 劣势 g=%.3f" % [col_adv.g, col_dis.g])
	_ok("⑦ ★敌方大优时光晕偏紫(b 更高)", col_dis.b > col_adv.b,
		"优势 b=%.3f 劣势 b=%.3f" % [col_adv.b, col_dis.b])
	_ok("⑦ 光晕常态可见(alpha>0)", col_adv.a > 0.05, "a=%.3f" % col_adv.a)
	# 受伤脉冲
	s._hud._pk_shown_l = 1.0; s._hud._pk_target_l = 0.5
	s._hud._pk_hit_l = 0.0
	s._hud._pk_acc = 0.0
	h._pk_tick(1.0 / 60.0)
	_ok("⑦ ★掉血触发受伤脉冲", s._hud._pk_hit_l > 0.5, "%.3f" % s._hud._pk_hit_l)
	var before: float = s._hud._pk_hit_l
	s._hud._pk_shown_l = s._hud._pk_target_l    # 真正停止掉血(只设 target 会被 _pk_refresh 覆写)
	for _i in range(30):
		h._pk_tick(1.0 / 60.0)
	_ok("⑦ ★脉冲会衰减(不会一直亮着)", s._hud._pk_hit_l < before,
		"%.3f → %.3f" % [before, s._hud._pk_hit_l])
	# 呼吸 + 结算后停
	var s1: float = s._hud._pk_vs.scale.x
	for _i in range(40):
		h._pk_tick(1.0 / 60.0)
	_ok("⑦ 徽章在呼吸(缩放会变)", absf(s._hud._pk_vs.scale.x - s1) > 0.001,
		"%.4f → %.4f" % [s1, s._hud._pk_vs.scale.x])
	s._settled = true
	h._pk_vs_tick(0.016)
	_ok("⑦ ★结算后停呼吸(停在中性尺寸·结果屏上别一直动)",
		is_equal_approx(s._hud._pk_vs.scale.x, 1.0), "%.4f" % s._hud._pk_vs.scale.x)
	_ok("⑦ ★结算后光晕收掉", s._hud._pk_vs_glow.modulate.a < 0.01,
		"a=%.3f" % s._hud._pk_vs_glow.modulate.a)
	s._settled = false


## ⑧ 副条(龟蛋): 口径与主条独立
func _egg_bar(s) -> void:
	print("  ── ⑧ 副条: 龟蛋按自己的 hp/maxHp ──")
	var h = s._hud
	_ok("⑧ 副条两段都在", s._hud._pk_egg_l != null and s._hud._pk_egg_r != null)
	s._units.clear()
	s._units.append(_mk("left", 1000, 1000))            # 龟(只进主条)
	s._units.append(_mk("right", 1000, 1000))
	s._units.append(_mk("left", 1650, 3300, {"_isEgg": true, "egg_side_lr": "left"}))
	s._units.append(_mk("right", 3300, 3300, {"_isEgg": true, "egg_side_lr": "right"}))
	s._hud._pk_lane = ""     # ★2026-07-31: 换路判据从"计数单位数变了"改成"路 id 变了"(见 _pk_refresh)
	h._pk_refresh()
	_ok("⑧ ★我方蛋掉一半 → 副条 0.5", absf(s._hud._pk_egg_tl - 0.5) < 0.0001, "%.4f" % s._hud._pk_egg_tl)
	_ok("⑧ 敌方蛋满血 → 副条 1.0", absf(s._hud._pk_egg_tr - 1.0) < 0.0001, "%.4f" % s._hud._pk_egg_tr)
	# ★口径独立: 蛋掉血【不影响主条】
	_ok("⑧ ★蛋掉一半不影响主条(主条仍 1.0)",
		absf(s._hud._pk_target_l - 1.0) < 0.0001, "%.4f" % s._hud._pk_target_l)
	# 无蛋模式(单路/评审): 不许除零
	s._units.clear()
	s._units.append(_mk("left", 1000, 1000))
	s._units.append(_mk("right", 1000, 1000))
	s._hud._pk_lane = ""     # ★2026-07-31: 换路判据从"计数单位数变了"改成"路 id 变了"(见 _pk_refresh)
	h._pk_refresh()
	_ok("⑧ 无蛋模式 → 副条 0(不除零/不 NaN)",
		absf(s._hud._pk_egg_tl) < 0.0001 and absf(s._hud._pk_egg_tr) < 0.0001)
	# 副条颜色必须与主条明显不同(用户: 原来同色"像装饰下划线")
	var src := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_hud.gd")
	_ok("⑧ ★副条用蛋壳色而不是队色", src.contains("PK_EGG_COL"))
	_ok("⑧ ★副条两端有蛋图标", src.contains("_make_egg_icon_texture()") and src.contains("_pk_egg_icon("))
	_ok("⑧ 蛋图标是程序生成的(不复用现有素材)",
		FileAccess.get_file_as_string("res://scripts/util/vfx_textures.gd").contains("func _make_egg_icon_texture"))
	# 配色: 我方绿 / 敌方紫(用户 2026-07-30 拍板"只换 PK 条")
	_ok("⑦⑧ ★我方色是绿(不是全局那套蓝)", h.PK_BLUE.g > h.PK_BLUE.b and h.PK_BLUE.g > h.PK_BLUE.r,
		str(h.PK_BLUE))
	_ok("⑦⑧ ★敌方色是紫(不是全局那套红)", h.PK_RED.b > h.PK_RED.g,
		str(h.PK_RED))


## ⑨ 右上按钮 与 PK 条【不许相交】(用户 2026-07-30:「手机上看的投降键重合在血条上了」)。
##
## ★根因是 project.godot 的 stretch/aspect="expand": 高固定 720, 【宽随手机宽高比变】。
##   而原来两个键写死 x=1148/1208、PK 条却是"顶部居中·宽 960" —— 比例一宽, 居中的条
##   向右扩、写死的键不动 → 撞上。实算: 19.5:9 视口 1560 → 重叠 112 px; 20:9 → 132 px。
##   ★16:9(我在 PC 上看的那个) 恰好不重叠 —— 所以【本机永远复现不出来】, 只有手机上看得见。
##
## ★判据是【矩形相交】这个几何事实, 不是"看着不重叠"。多个宽高比各验一次。
func _btn_vs_bar(s) -> void:
	print("")
	print("  ⑨ 右上按钮 vs PK 条(多宽高比):")
	var h = s._hud
	var src := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_hud.gd")
	_ok("⑨ ★按钮不再写死坐标(改按右边缘+安全区反算)",
		not src.contains("Vector2(1208, 12)") and not src.contains("var _x := 1148.0"))
	_ok("⑨ 按钮走 SafeArea", src.contains("SafeArea.margins(_vp, 12.0)"))
	_ok("⑨ PK 条宽度自适应(给按钮区让位)", src.contains("PK_BTN_ZONE"))
	# ★★先读【真实按钮】的位置, 再验公式 —— 否则下面那圈多宽高比只是在"模拟公式",
	#   改了代码里的坐标它看不见。我第一版就是这样: 把按钮改回写死 1208, 门禁【照样绿】。
	#   现在: ①量真实矩形不相交 ②证明真实 x 就是"右边缘-按钮宽-安全区" → 模拟才站得住。
	var vp0: Vector2 = Vector2(s.get_viewport().get_visible_rect().size)
	var sb = s._surrender_btn
	_ok("⑨ ★分母: 投降键真的建出来了", sb != null and is_instance_valid(sb))
	if sb != null and is_instance_valid(sb):
		var real_sur := Rect2(sb.position, sb.size)
		# ★用 get_global_rect() 而不是自己按 position+offset 拼 —— PK 条是【锚定居中】的 Control,
		#   position 已经含了锚点解算, 我第一版又加了一次 offset_left+vp/2 → 算出 x[320..1280](错的),
		#   把一条本来不相交的判成相交。要量就量引擎给的最终矩形。
		var real_bar := (h._pk_bar as Control).get_global_rect()
		print("     [真实测量] 视口 %.0f  投降键 x[%.0f..%.0f]  PK条 x[%.0f..%.0f]" % [
			vp0.x, real_sur.position.x, real_sur.end.x, real_bar.position.x, real_bar.end.x])
		_ok("⑨ ★★真实按钮与真实 PK 条不相交(当前视口)", not real_bar.intersects(real_sur))
		var m0: Vector4 = SafeArea.margins(vp0, 12.0)
		var want_x: float = vp0.x - sb.size.x - m0.z
		_ok("⑨ ★★投降键 x 就是「右边缘-按钮宽-安全区」(证明下面的公式模拟站得住)",
			absf(sb.position.x - want_x) < 0.5, "实际 %.0f / 公式 %.0f" % [sb.position.x, want_x])
	var bw := 52.0
	var gap := 8.0
	for pair in [["16:9", 16.0 / 9.0], ["18:9", 2.0], ["19.5:9", 19.5 / 9.0], ["20:9", 20.0 / 9.0], ["4:3", 4.0 / 3.0]]:
		var vw: float = 720.0 * float(pair[1])
		var w: float = minf(h.PK_W, maxf(h.PK_MIN_W, vw - h.PK_BTN_ZONE * 2.0))
		var bar := Rect2(vw * 0.5 - w * 0.5, h.PK_Y, w, h.PK_H + h.PK_EGG_GAP + h.PK_EGG_H)
		var sur := Rect2(vw - bw - 12.0, 12.0, bw, 38.0)
		var sta := Rect2(sur.position.x - bw - gap, 12.0, bw, 38.0)
		var hit: bool = bar.intersects(sur) or bar.intersects(sta)
		print("     %-7s 视口 %6.0f  条 x[%.0f..%.0f]  统计 x[%.0f..%.0f]  投降 x[%.0f..%.0f]  %s" % [
			str(pair[0]), vw, bar.position.x, bar.end.x,
			sta.position.x, sta.end.x, sur.position.x, sur.end.x,
			"★相交" if hit else "ok"])
		_ok("⑨ %s 按钮与 PK 条不相交" % str(pair[0]), not hit)
