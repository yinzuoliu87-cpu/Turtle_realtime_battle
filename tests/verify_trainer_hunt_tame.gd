extends Node
## verify_trainer_hunt_tame.gd — 训龟大师两个新技能：猎龟令 / 驯服
##
## 需求原文（用户 2026-07-28）：
##   猎龟令 30 秒 CD，600 码内指定敌方目标，给它挂 15 秒「猎龟令」：
##     嘲讽 400 码内我方友军优先攻击它、它受到 15% 额外伤害，圈跟着目标走
##   驯服 60 秒 CD，600 码内指定敌方目标：它死后以 30% 最大生命重生并归顺我方，
##     重生 2.5 秒无敌不可选中，此后每秒损失 2% 最大生命，可跨入终极战场
##
## ★★ 期望值全部写【字面需求值】，不许引用 battle.HUNT_* / battle.TAME_* ★★
##    否则就是拿代码跟它自己比 = 恒真式（verify_trainer_magicstone 第一版就栽在这，
##    把常量改坏测试照样 ALL PASS）。实现改了而需求没改 → 这里就该红。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_trainer_hunt_tame.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

# ── 需求字面值 ──
const WANT_HUNT_CD := 30.0
const WANT_HUNT_RANGE := 600.0
const WANT_HUNT_SEC := 15.0
const WANT_HUNT_TAUNT_R := 400.0
const WANT_HUNT_VULN := 1.15        # 受到 15% 额外伤害
const WANT_TAME_CD := 60.0
const WANT_TAME_RANGE := 600.0
const WANT_TAME_REVIVE := 0.30      # 30% 最大生命重生
const WANT_TAME_INVULN := 2.5       # 重生演出 2.5 秒
const WANT_TAME_DECAY := 0.02       # 每秒 2% 最大生命

var _fail := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	gs.season_level = 5
	print("=== 训龟大师·猎龟令 / 驯服 ===")

	var s = RB.new()
	add_child(s)
	for _i in range(8):
		await get_tree().process_frame

	# ── ① 技能表参数 ──
	var h: Dictionary = s.TRAINER_SKILLS.get("hunt_order", {})
	var t: Dictionary = s.TRAINER_SKILLS.get("tame", {})
	print("")
	print("  ① 技能表:")
	print("     猎龟令 cd=%s range=%s aim=%s" % [str(h.get("cd")), str(h.get("range")), str(h.get("aim"))])
	print("     驯服   cd=%s range=%s aim=%s" % [str(t.get("cd")), str(t.get("range")), str(t.get("aim"))])
	_chk("① 猎龟令 CD=%.0f / 射程=%.0f / aim=target" % [WANT_HUNT_CD, WANT_HUNT_RANGE],
		absf(float(h.get("cd", 0.0)) - WANT_HUNT_CD) < 0.01
		and absf(float(h.get("range", 0.0)) - WANT_HUNT_RANGE) < 0.01
		and str(h.get("aim", "")) == "target")
	_chk("① 驯服 CD=%.0f / 射程=%.0f / aim=target" % [WANT_TAME_CD, WANT_TAME_RANGE],
		absf(float(t.get("cd", 0.0)) - WANT_TAME_CD) < 0.01
		and absf(float(t.get("range", 0.0)) - WANT_TAME_RANGE) < 0.01
		and str(t.get("aim", "")) == "target")

	var tr = _my_trainer(s)
	if tr == null:
		print("  [FAIL] ★分母: 场上没有我方训龟大师 —— 后面全是空检查"); _fail += 1; _done(s); return
	var foe = _foe(s)
	if foe.is_empty():
		print("  [FAIL] ★分母: 场上没有敌方单位"); _fail += 1; _done(s); return
	print("")
	print("  ★分母: 大师 @%s / 靶子「%s」maxHp=%.0f" % [str(tr["pos"].round()), str(foe.get("name", "?")), float(foe["maxHp"])])

	# ── ② 猎龟令: 标记 + 受伤放大 ──
	foe["pos"] = tr["pos"] + Vector2(300.0, 0.0)          # 放进 600 码射程
	tr["_active_cd"] = 0.0
	s._trainer_sys._hunt_mark(tr, foe)                     # 直接调纯效果, 不等弹道/演出
	var marked: bool = bool(foe.get("_hunt_marked", false))
	var left: float = float(foe.get("hunt_until", 0.0)) - s._t
	print("")
	print("  ② 标记证据 _hunt_marked=%s   剩余 %.2f 秒 (需求 %.0f)" % [str(marked), left, WANT_HUNT_SEC])
	_chk("② 猎龟令标记生效且持续 %.0f 秒" % WANT_HUNT_SEC, marked and absf(left - WANT_HUNT_SEC) < 0.3)

	# 受伤放大: 同一发伤害, 有标记 vs 无标记
	foe["def"] = 0.0; foe["mr"] = 0.0; foe["shield"] = 0.0; foe["flat_dr"] = 0.0
	foe["id"] = "_dummy_target"
	var base: float = s._mitigate_incoming(foe, 1000.0, false, false)
	foe["hunt_until"] = 0.0
	var plain: float = s._mitigate_incoming(foe, 1000.0, false, false)
	foe["hunt_until"] = s._t + WANT_HUNT_SEC
	print("")
	print("  ③ 同一发 1000 伤害: 无标记 %.1f → 有标记 %.1f  (比值 %.4f, 需求 %.2f)" % [
		plain, base, base / maxf(1.0, plain), WANT_HUNT_VULN])
	_chk("③ 被标记者受到伤害 ×%.2f (走 _mitigate_incoming 唯一入口)" % WANT_HUNT_VULN,
		absf(base / maxf(1.0, plain) - WANT_HUNT_VULN) < 0.005)

	# ── ④ 嘲讽: 圈内我方友军优先打它 ──
	var ally = _my_ally(s)
	if ally.is_empty():
		print("  [FAIL] ★分母: 场上没有我方非大师单位"); _fail += 1
	else:
		ally["pos"] = foe["pos"] + Vector2(200.0, 0.0)     # 圈内(200 < 400)
		s._trainer_sys._tick_hunt_taunt(0.016)
		var in_r: bool = s._t < float(ally.get("taunt_until", 0.0)) and is_same(ally.get("taunt_by", null), foe)
		ally["pos"] = foe["pos"] + Vector2(900.0, 0.0)     # 圈外(900 > 400)
		ally["taunt_until"] = 0.0; ally["taunt_by"] = null
		s._trainer_sys._tick_hunt_taunt(0.016)
		var out_r: bool = s._t < float(ally.get("taunt_until", 0.0))
		print("")
		print("  ④ 友军距目标 200 码(圈内 %.0f) → 被嘲讽=%s" % [WANT_HUNT_TAUNT_R, str(in_r)])
		print("     友军距目标 900 码(圈外)      → 被嘲讽=%s (应为 false)" % str(out_r))
		_chk("④ 嘲讽只对 %.0f 码内我方友军生效(圈随目标移动)" % WANT_HUNT_TAUNT_R, in_r and not out_r)

	# ── ⑤ 驯服: 死亡 → 30% 重生 + 归顺 ──
	var f2 = _foe(s)
	if f2.is_empty():
		print("  [FAIL] ★分母: 找不到第二个敌人做驯服测试"); _fail += 1; _done(s); return
	var orig_side := str(f2.get("side", ""))
	s._trainer_sys._tame_mark(tr, f2)
	print("")
	print("  ⑤ 驯服标记: _tamed_marked=%s  (标记【无 until】—— 持续到战斗结束或死亡)" % str(f2.get("_tamed_marked", false)))
	_chk("⑤ 驯服标记生效且不带定时", bool(f2.get("_tamed_marked", false)) and not f2.has("tame_until"))

	var mx: float = float(f2["maxHp"])
	f2["hp"] = 1.0
	s._kill(f2)                                            # 走真实死亡路径
	var alive_after: bool = bool(f2.get("alive", false))
	var hp_frac: float = float(f2["hp"]) / mx
	print("")
	print("  ⑥ 死亡后: alive=%s  hp=%.0f/%.0f = %.1f%% (需求 %.0f%%)" % [
		str(alive_after), float(f2["hp"]), mx, hp_frac * 100.0, WANT_TAME_REVIVE * 100.0])
	print("     阵营: side=%s(未改写) → 有效阵营 _eff_side=%s (需求 left)" % [orig_side, s._eff_side(f2)])
	_chk("⑥ 不真死, 以 %.0f%% 最大生命重生" % (WANT_TAME_REVIVE * 100.0), alive_after and absf(hp_frac - WANT_TAME_REVIVE) < 0.02)
	_chk("⑥ ★归顺我方且【没有改写 side】", s._eff_side(f2) == "left" and str(f2.get("side", "")) == orig_side)
	_chk("⑥ 对我方不再敌对(真换队, 不是赛博那种孤军)", not s._is_hostile(f2, tr) and not s._is_hostile(tr, f2))

	# ── ⑦ 重生演出期无敌 + 不可选中 ──
	var inv: float = float(f2.get("_tame_invuln_until", 0.0)) - s._t
	var untg: float = float(f2.get("untargetable_until", 0.0)) - s._t
	var mit: float = s._mitigate_incoming(f2, 1000.0, false, false)
	print("")
	print("  ⑦ 无敌剩余 %.2f 秒 / 不可选中剩余 %.2f 秒 (需求 %.1f)" % [inv, untg, WANT_TAME_INVULN])
	print("     演出期挨 1000 伤害 → 实际 %.1f (应为 0)" % mit)
	_chk("⑦ 重生 %.1f 秒内无敌且不可选中" % WANT_TAME_INVULN,
		absf(inv - WANT_TAME_INVULN) < 0.3 and absf(untg - WANT_TAME_INVULN) < 0.3 and mit < 0.01)

	# ── ⑦b 符文环: 重生后只能有【一个】, 且要转青(归顺色) ──
	# 探针实测的原始 bug: 施放落地建 1 个环, 重生时 _tame_revive_dramatize 又建 1 个 → 2 个。
	#   旧环自毁条件是 alive==false, 而 _kill 在驯服钩前【没置 alive=false】就 return 了
	#   → 旧环永远等不到 → 两个同贴图环叠着、rotate_y 相位还不同 = 糊成一团。
	# ★而那个函数的头注一直写着「符文环转青」—— 转青【也从来没实现过】。
	s._trainer_sys._tame_rune(f2)                # 补上施放落地那一环(⑤ 走的是纯效果, 没跑演出)
	await get_tree().process_frame
	var n1: int = _count_runes(s)
	s._trainer_sys._tame_revive_dramatize(f2)    # 再走一次重生演出
	await get_tree().process_frame
	var n2: int = _count_runes(s)
	var rune2 = f2.get("_tame_rune", null)
	var col: Color = (rune2 as Sprite3D).modulate if is_instance_valid(rune2) else Color.BLACK
	print("")
	print("  ⑦b 符文环: 施放后 %d 个 → 重生演出后 %d 个 (需求 1)  色=%s" % [n1, n2, col.to_html(false)])
	_chk("⑦b ★分母: 施放落地确实建出了环", n1 == 1)
	_chk("⑦b ★重生后仍只有 1 个环(原来叠成 2 个)", n2 == 1)
	_chk("⑦b ★环真的转青了(函数头注一直这么写, 但从没实现)",
		col.is_equal_approx(Color("#7de8c8")))

	# ── ⑧ 归顺后每秒掉 2%: 逐帧喂 × 多帧率 × 多血量 × 带满减伤 ──
	#
	# ★★这一组原来是【假绿灯】。旧写法只有一行:
	#       s._trainer_sys._tick_tame_decay(1.0)      # "模拟整 1 秒"
	#   而游戏里是【每帧调、delta≈1/60】。旧实现用 int(ceilf(maxHp*0.02*delta)) 逐帧扣,
	#   ceilf 让每帧至少扣 1 点 → 真实速率 = max(2%/秒, 帧率 ÷ maxHp):
	#       maxHp 200 @60fps = 30%/秒(×15)   ·  @600fps = 100%/秒(×50)
	#       maxHp 600 @60fps = 10%/秒(×5)
	#   「一次·delta=1秒」正好是取整误差【唯一消失】的调用方式 —— 它模拟的是游戏里
	#   永不发生的情形, 所以断言绿着, bug 却在线上跑了。
	#   教训: 逐帧机制的门禁必须【按逐帧喂】, 并至少验两种帧率(否则测不出帧率耦合)。
	#
	# ★带 def/mr/flat_dr: 掉血是【真实伤害】(bucket="tru", 用户 2026-07-30 指出) ——
	#   原来是 "dot" 桶, 会被钻石×0.82 / 石头岩石之躯 / 铁壁盾016 flat_dr 打折。
	#   所以这里【故意把减伤全拉满】: 打折的话倍率就不是 ×1.00, 当场红。
	print("")
	print("  ⑧ 归顺掉血(需求 每秒 %.0f%% · 真实伤害 · 与帧率无关):" % (WANT_TAME_DECAY * 100.0))
	var t_save: float = s._t
	for fps in [30, 60, 600]:
		for mh in [200.0, 2000.0]:
			var u: Dictionary = s._spawn._make_unit("basic", "right", Vector2(400, 0), {})
			u["maxHp"] = mh; u["hp"] = mh
			u["def"] = 60.0; u["mr"] = 60.0; u["flat_dr"] = 30.0; u["shield"] = 0.0
			u["tamed_side"] = "left"; u["_tame_invuln_until"] = 0.0
			u["_tame_decay_next"] = -1.0
			s._units.append(u)
			var t0: float = s._t
			var h0: float = -1.0
			# 同步推进 3 秒(第 1 秒建节拍, 后 2 秒真掉)。不 await → _process 不会插进来抢 _t。
			for f in range(fps * 3):
				s._t = t0 + float(f + 1) / float(fps)
				s._trainer_sys._tick_tame_decay(1.0 / float(fps))
				if h0 < 0.0 and s._t >= t0 + 1.0:
					h0 = float(u["hp"])
			var lost: float = (h0 - float(u["hp"])) / mh / 2.0
			s._t = t0
			print("     %3dfps / %4.0f血 → %.2f%%/秒 (×%.2f)" % [fps, mh, lost * 100.0, lost / WANT_TAME_DECAY])
			_chk("⑧ %3dfps·%4.0f血 每秒掉 %.0f%%(真伤穿满减伤·不随帧率变)" % [fps, mh, WANT_TAME_DECAY * 100.0],
				absf(lost - WANT_TAME_DECAY) < 0.002)
			u["alive"] = false      # 别留着干扰后面
	s._t = t_save
	# 真伤桶: 统计面板该把它算进"真实"而不是 DoT
	_chk("⑧ ★掉血走真实伤害桶(bucket=\"tru\")",
		FileAccess.get_file_as_string("res://scripts/systems/trainer/trainer_system.gd")
			.contains('Color("#8b2e4a"), null, "tru", true'))
	_chk("⑧ ★不再逐帧 ceilf 摊薄(那会让速率 = max(2%, 帧率÷血量))",
		not FileAccess.get_file_as_string("res://scripts/systems/trainer/trainer_system.gd")
			.contains("battle.TAME_DECAY_PCT * delta"))

	await _sigil_geometry(s)
	_done(s)


## ⑨ 地面印记/符文环的【几何】—— 2026-07-30 逐技目视审核抓到的两个问题, 焊死不许回来。
##
## ★问题①: 猎龟令印记原本 pixel_size = HUNT_TAUNT_R*2*WS/128 → 直径 19.20 m,
##    而战场 ARENA 只有 38.3×17.5 m —— 圈占战场宽 50%、【比纵深还长 110%】。
##    两层后果: ⓐ这一技的核心信息"哪只龟被标了"完全读不出;
##              ⓑ128px 铺 19.2m = 0.150 m/texel = 龟像素格(≈0.05)的 3 倍粗 → 糊成红板砖。
##    ★根因是【把"效果半径"当成了"贴片尺寸"】。这两个概念必须分开, 所以下面既验尺寸在
##      合理带内, 也验它【不再由 HUNT_TAUNT_R 推导】—— 只验数字的话, 有人换个半径就又崩。
##
## ★问题②: 两个环建节点时【没设初始 position】, 靠 .set_delay(0.03) 的循环 tween 归位
##    → 探针实测头 2 帧待在世界原点、与目标脚下偏差 16.21 m = 地图正中先闪一下再跳过来。
##    ★这条【必须在建出的同一帧就验】(第 0 帧偏差=0), 隔几帧再看就被 tween 补上了 = 假绿灯。
func _sigil_geometry(s) -> void:
	print("")
	print("  ⑨ 地面印记几何(尺寸 / 首帧位置):")
	var src := FileAccess.get_file_as_string("res://scripts/systems/trainer/trainer_system.gd")
	_chk("⑨ ★印记尺寸不再由嘲讽半径推导(效果半径 ≠ 贴片尺寸)",
		not src.contains("battle.HUNT_TAUNT_R * 2.0 * battle.WS"))
	_chk("⑨ 尺寸走显式常量 SIGIL_D_M / TAME_RUNE_D_M",
		src.contains("const SIGIL_D_M :=") and src.contains("const TAME_RUNE_D_M :="))

	var ts = s._trainer_sys
	var tr = _my_trainer(s)
	var tgt: Dictionary = _foe(s)
	if tr == null or tgt.is_empty():
		print("     [FAIL] ★分母: 没有大师或可用敌人 —— ⑨ 是空检查"); _fail += 1; return
	# ── 印记: 直接调 _hunt_sigil(不等锁头弹), 建出【同一帧】就验位置 ──
	tgt["hunt_until"] = s._t + 99.0
	ts._hunt_sigil(tgt)
	var sig = tgt.get("_hunt_sigil", null)
	_chk("⑨ ★分母: 印记节点真的建出来了(缺素材会静默不画)", sig is Sprite3D)
	if not (sig is Sprite3D):
		return
	var sp: Sprite3D = sig
	var d: float = sp.texture.get_width() * sp.pixel_size
	var mpt: float = sp.pixel_size          # 每贴图像素多少米
	var turtle_px: float = s.TARGET_BODY_H / 48.0   # 龟立绘 ≈48px 高 → 约 0.042 m/texel
	print("     印记直径 %.2f m (龟身高 %.2f m·战场 %.1f×%.1f m) / %.3f m per texel (龟 ≈%.3f)" % [
		d, s.TARGET_BODY_H, s.ARENA.size.x * s.WS, s.ARENA.size.y * s.WS, mpt, turtle_px])
	# 带内: 0.75×~2× 龟身高。原来的 19.20 m 会红(9.6 倍), 缩得看不见也会红。
	_chk("⑨ ★印记直径在 [1.5, 4.0] m 内(原来 19.20 m = 比战场纵深还长)",
		d >= 1.5 and d <= 4.0, )
	_chk("⑨ ★印记像素密度不比龟粗(否则破坏全局像素单位·糊成板砖)", mpt <= turtle_px)
	# ★★朝向: "贴地印记"必须真的平铺 —— 实测它一直是【竖环】。
	#   Sprite3D.axis=AXIS_Y 语义是"面垂直于该轴" = 已经平铺(法线 +Y);
	#   代码里却又写了 rotation_degrees.x=-90, 把法线掰到 -Z → 两者抵消 = 立起来。
	#   |法线·上| 改前 0.000 / 改后 1.000。这条同时是"驯服环看不见"和"猎龟令环横穿龟腿"的根因。
	_chk("⑨ ★★印记真的平铺在地上(|法线·上|≈1·别再叠 -90 旋转)", _flat(sp))
	var want: Vector3 = s._world_pos(tgt["pos"], 0.06)
	var off: float = (sp.position - want).length()
	print("     首帧偏差 %.2f m (原来 16.21 m = 在世界原点闪一下)" % off)
	_chk("⑨ ★★印记建出的【同一帧】就在目标脚下(不许先在世界原点闪)", off < 0.01)
	# ── 符文环: 同一批修的同一个毛病 ──
	var tgt2: Dictionary = _foe(s)
	if tgt2.is_empty():
		print("     [FAIL] ★分母: 找不到第二个敌人验符文环"); _fail += 1; return
	ts._tame_rune(tgt2)
	var rune: Sprite3D = null
	for c in s._world.get_children():
		if c is Sprite3D and (c as Sprite3D).texture != null \
			and str((c as Sprite3D).texture.resource_path).ends_with("tame-rune.png"):
			rune = c
	_chk("⑨ ★分母: 符文环节点真的建出来了", rune != null)
	if rune == null:
		return
	var rd: float = rune.texture.get_width() * rune.pixel_size
	var roff: float = (rune.position - s._world_pos(tgt2["pos"], 0.05)).length()
	print("     符文环直径 %.2f m / 首帧偏差 %.2f m" % [rd, roff])
	_chk("⑨ 符文环直径在 [1.5, 4.5] m 内", rd >= 1.5 and rd <= 4.5)
	_chk("⑨ ★符文环建出的同一帧就在目标脚下(与印记同一个毛病·同批修)", roff < 0.01)
	_chk("⑨ ★★符文环真的平铺在地上(与印记同一个毛病·同批修)", _flat(rune))


func _my_trainer(s):
	for u in s._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			return u
	return null


## 一个还没被标记过的敌方单位(每次调返回不同的)
func _foe(s) -> Dictionary:
	for u in s._units:
		if str(u.get("side", "")) != "right" or u.get("is_trainer", false) or not u.get("alive", false):
			continue
		if u.get("_hunt_marked", false) or u.get("_tamed_marked", false):
			continue
		return u
	return {}


func _my_ally(s) -> Dictionary:
	for u in s._units:
		if str(u.get("side", "")) == "left" and not u.get("is_trainer", false) and u.get("alive", false):
			return u
	return {}


## Sprite3D 的贴图面是否平铺地面: axis 决定局部法线轴, 再过节点 basis 变世界法线。
func _flat(sp: Sprite3D) -> bool:
	var local_n := Vector3.BACK
	match sp.axis:
		Vector3.AXIS_X: local_n = Vector3.RIGHT
		Vector3.AXIS_Y: local_n = Vector3.UP
	var world_n: Vector3 = (sp.global_transform.basis * local_n).normalized()
	var d: float = absf(world_n.dot(Vector3.UP))
	print("        |法线·上| = %.3f  (平铺该 ≈1.000·竖立是 0.000)  axis=%d rot=%s" % [
		d, sp.axis, str(sp.rotation_degrees)])
	return d > 0.99


func _count_runes(s) -> int:
	var n := 0
	for c in s._world.get_children():
		if c is Sprite3D and (c as Sprite3D).texture != null 			and str((c as Sprite3D).texture.resource_path).ends_with("tame-rune.png"):
			n += 1
	return n


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("     %s %s" % ["[PASS]" if ok else "[FAIL]", what])


func _done(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 猎龟令 / 驯服" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
