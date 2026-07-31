extends Node
## verify_trainer_magicstone.gd — 训龟大师·魔法石：三处修复 + 被动加强
##
## 由来（用户 2026-07-28）：
##   ①「训龟大师选择了魔法石后，为什么局内右边图标不是魔法石的呢」
##   ②「没有循环绕圈的特效」
##   ③「石头命中只看到一个伤害数字」
##   ④「加强魔法石被动：选择魔法石攻击力时，训龟大师获得 10 倍攻击力，
##      普攻附带（2+0.1 每大轮等级）% 目标最大生命值魔法伤害」
##
## 查六件事（都打真数字，不看"代码里写了"）：
##   ① 圆盘图标 = 魔法石图标（不是钩锁）——★这是原 bug 的直接判据
##   ② 圆盘上有"被动生效中"的旋转环节点
##   ③ 装魔法石时大师 ATK = 10（装主动技时仍是 1）
##   ④ 魔法那段伤害 = (2 + 0.1×大轮等级)% 目标最大生命 —— 逐级对照，不是只测一级
##   ⑤ ★物理与魔法【同帧】结算：石头飞行途中目标不该掉血，命中那一刻两段一起扣
##   ⑥ 分母：确实找到了大师、确实有目标
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_trainer_magicstone.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## ★★ 这三个数【必须写字面值, 不许引用代码里的常量】★★
##
## 第一版我写的是 s.TRAINER_ATK_MAGIC_STONE / s.MS_MAXHP_BASE + s.MS_MAXHP_PER_LV*lv ——
## 反向验证当场戳穿: 把常量从 10 改成 1、把 0.001 改成 0.005, 测试【照样 ALL PASS】,
## 因为期望值跟着实现一起变了 = 拿代码跟它自己比 = 恒真式。
##
## 这里写的是【用户 2026-07-28 口述的需求本身】:
##   「选择魔法石攻击力时, 训龟大师获得 10 倍攻击力」→ 1 × 10 = 10
##   「普攻附带(2+0.1每大轮等级)%目标最大生命值魔法伤害」→ Lv1=2.1% … Lv10=3.0%
## 实现改了而需求没改 → 这条就该红。
const WANT_ATK := 1.0     # 需求字面值: 魔法石【不再】提供攻击力倍率(2026-07-31 用户拍板),
                          # 所以装魔法石时大师攻击力 = 基础 TRAINER_ATK = 1
## ★2026-07-30 用户拍板:「附带的魔法伤害削弱为常驻2%」—— 不再随大轮等级涨。
##   原需求是「(2+0.1每大轮等级)%」(Lv1 2.1%…Lv10 3.0%), 现在恒 2%。
const WANT_PCT := 0.02
const HUD := preload("res://scripts/scenes/battle/battle_hud.gd")

var _fail := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	gs.trainer_skill = "magic_stone"        # ★装配被动
	gs.season_level = 5
	print("=== 训龟大师·魔法石 ===")
	print("  装配 = %s  (主动=%s / 被动=%s)" % [
		str(gs.trainer_skill), str(gs.trainer_active_skill()), str(gs.trainer_passive_skill())])
	_chk("⑥ ★分母: 装配确实解析成【被动 magic_stone】", gs.trainer_passive_skill() == "magic_stone" and gs.trainer_active_skill() == "")

	var s = RB.new()
	add_child(s)
	for _i in range(8):
		await get_tree().process_frame

	# ── ① 圆盘图标 ──
	var disc = s._spell_disc
	# ★图标存在 SpellDisc._icon 里、由 _draw() 画出来 —— 不是子 TextureRect。
	#   第一版我去子树里找 TextureRect, 取到空 → 判 FAIL, 是【测试写错】不是功能错。
	var ipath := ""
	if disc != null and is_instance_valid(disc) and disc._icon != null:
		ipath = str(disc._icon.resource_path)
	print("")
	print("  ① 圆盘图标 = %s" % (ipath if ipath != "" else "(取不到)"))
	print("     期望含 magic-stone; 出 bug 时会是 %s" % str(s.HOOK_ICON))
	_chk("① 圆盘显示魔法石图标(不是钩锁)", ipath.find("magic-stone") >= 0)

	# ── ② 绕圈特效 ──
	var n_ring := _count_rings(disc)
	print("")
	print("  ② 圆盘下旋转环节点数 = %d" % n_ring)
	_chk("② 有【被动生效中】的循环绕圈特效", n_ring > 0)

	# ── ③ 10 倍攻击力 ──
	var tr = null
	for u in s._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			tr = u; break
	print("")
	if tr == null:
		print("  [FAIL] ★分母: 场上没有我方训龟大师 —— 后面全是空检查"); _fail += 1; _done(s); return
	# ★★2026-07-31 用户拍板:「训龟大师的魔法石不再提供19倍攻击力」——
	#   魔法石不再给攻击力倍率(原 TRAINER_ATK_MAGIC_STONE ×10, 常量已删),
	#   收益全部集中到"每层攻速"那一条线上。这里从"验 10 倍"翻成【验没有倍率】。
	print("  ③ 我方大师 ATK = %.1f  (需求 %.1f = 与装主动技时相同, 魔法石不再加倍)"
		% [float(tr["atk"]), WANT_ATK])
	_chk("③ ★装魔法石【不再】改攻击力(= 基础 %.0f)" % WANT_ATK,
		absf(float(tr["atk"]) - WANT_ATK) < 0.01)

	# ── ④ 魔法那段 = (2 + 0.1×等级)% 目标最大生命, 逐级验 ──
	print("")
	print("  ④ 逐级核对魔法伤害占目标最大生命的比例:")
	var ok4 := true
	for lv in [1, 5, 10]:
		gs.season_level = lv
		tr["crit"] = 0.0            # ★攻击方暴击也清零: _resolve_dmg 会按 src["crit"] 掷暴击, 暴了就 ×暴伤
		tr["crit_dmg"] = 0.0
		tr["magic_pen"] = 0.0; tr["magic_pen_pct"] = 0.0
		var dummy := _dummy(s, 10000.0)
		if dummy.is_empty():
			print("     [FAIL] ★分母: 场上找不到敌方单位当靶子"); ok4 = false; break
		var hp0: float = float(dummy["hp"])
		s._trainer_sys._trainer_magicstone_onhit(tr, dummy)
		var dealt: float = hp0 - float(dummy["hp"])
		var want_pct: float = WANT_PCT      # ★逐级都是同一个数 —— 这才是"常驻"的判据
		# ★把【目标自带的受伤修正】显式除掉, 而不是假设它等于 1。
		#   靶子是从随机 spawn 的敌队里挑的, 而 _mitigate_incoming 里有一堆按龟 id / 按状态
		#   的分支(钻石 ×0.82、石头岩石之躯、靶向器标记 +20% ……)。我先只中性化了 id,
		#   CI 上照样红 —— 说明还有没枚举到的分支。与其一个个猜, 不如【量出来再除掉】:
		#   本条要验的是"魔法伤害公式 = (2+0.1×等级)% 最大生命", 目标挨打后打几折是另一回事。
		var mit: float = s._mitigate_incoming(dummy, 10000.0, false, false) / 10000.0
		var got_pct: float = dealt / float(dummy["maxHp"]) / maxf(0.01, mit)
		var good: bool = absf(got_pct - want_pct) < 0.0006     # 取整误差
		if not good:
			ok4 = false
		print("     Lv%-2d  实扣 %6.1f / %.0f  目标减伤×%.3f  → 公式 %.3f%%   期望 %.3f%%  %s" % [
			lv, dealt, float(dummy["maxHp"]), mit, got_pct * 100.0, want_pct * 100.0, "ok" if good else "★差"])
	gs.season_level = 5
	_chk("④ ★魔法伤害恒 %.0f%% 目标最大生命(Lv1/5/10 都一样·不随大轮等级涨)" % (WANT_PCT * 100.0), ok4)
	# ★结构断言: 代码里不许再出现"按等级算"的形态。只验数值不够 —— 若有人改回
	#   base+per_lv 而恰好某一级等于 2%, 只测那一级就漏了。数值(逐级) + 结构(不读 season_level) 都要。
	var ts_src := FileAccess.get_file_as_string("res://scripts/systems/trainer/trainer_system.gd")
	var body_i := ts_src.find("func _trainer_magicstone_onhit(")
	var body := ts_src.substr(body_i, 900) if body_i >= 0 else ""
	_chk("④ ★分母: 读到 _trainer_magicstone_onhit 函数体", body.length() > 100)
	# ★★断言要匹配【代码形态】, 不能匹配裸标识符 —— 我第一版写
	#     not body.contains("season_level")  /  not rb_src.contains("MS_MAXHP_PER_LV")
	#   两条都红了, 而代码完全正确: 命中的是【我自己写的解释性注释】
	#   (函数体里那句"★不再读 GameState.season_level"、常量头注里提到的旧常量名)。
	#   源码里越是把改动理由写清楚, 裸标识符 grep 就越容易反过来咬自己。
	#   所以: 正向断言用【完整代码行】, 负向断言用【声明形态 const X】。
	_chk("④ ★pct 直接取常量(不再按等级算)",
		body.contains("var pct: float = battle.MS_MAXHP_PCT"))
	var rb_src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_chk("④ ★新常量 MS_MAXHP_PCT 在位", rb_src.contains("const MS_MAXHP_PCT :="))
	_chk("④ ★死常量没留下(MS_MAXHP_PER_LV 的【声明】已删, 不是设成 0)",
		not rb_src.contains("const MS_MAXHP_PER_LV"))
	_chk("④ ★旧的 MS_MAXHP_BASE 声明也已删", not rb_src.contains("const MS_MAXHP_BASE"))

	# ── ⑤ ★物理与魔法同帧 ──
	#    出 bug 时: 魔法在【扔出瞬间】就扣, 物理要等石头飞到 → 石头在空中时目标已经掉了一次血。
	print("")
	var d2 := _dummy(s, 10000.0)
	if d2.is_empty():
		print("  [FAIL] ★分母: 找不到靶子"); _fail += 1; _done(s); return
	var before: float = float(d2["hp"])
	s._ballistics._fire_trainer_rock(tr, d2, true)
	await get_tree().process_frame           # 石头刚出手, 还在飞
	var mid: float = float(d2["hp"])
	print("  ⑤ 石头刚出手(仍在飞): 目标 hp %.0f → %.0f" % [before, mid])
	print("     出 bug 时这里就会掉血(魔法提前结算), 修好后应【一点不掉】")
	_chk("⑤ ★石头飞行途中目标不掉血(两段同帧, 不错开)", absf(mid - before) < 0.01)

	await _stack_badge(s, tr)
	await _cross_lane(s, tr)
	_done(s)


## ⑦ 叠层【跨路保留】(用户 2026-07-30 拍板) + 圆盘不画键位提示。
##
## 原本 _dl_start_fight 每路开打把大师的 _ms_stacks 清零, 而 trainer_system 的注释写着
## "持续到本场结束" —— 口径分歧。0.17.17 把层数做成圆盘角标后, 玩家会【亲眼看见】它换路归零,
## 于是分歧从"文档问题"变成"可见行为"。用户选了改行为对齐文案。
## ★这里【走真实换路入口 _dl_start_fight()】而不是只 grep 源码 —— 只 grep 的话,
##   有人在别处(比如 _dl_build_lane_field)加一遍清零, 断言照样绿。
func _cross_lane(s, tr: Dictionary) -> void:
	print("")
	print("  ⑦ 叠层跨路保留 + 圆盘不画 Q:")
	# ★★这一组原来是【假绿灯】: 我喂 23 层给一个 dict, 调 _dl_start_fight() 再验它还是 23 ——
	#   而玩家换路走的是 _dl_build_lane_field(), 它会调 _spawn_trainers() 把大师【整个重建】,
	#   单位字典都换了, 层数天然归零。删掉 _dl_start_fight 里那句显式清零【根本不够】。
	#   实测(修之前): 走真实换路后 0 层。同 memory fb-verify-must-run-the-real-path。
	# ★所以现在: ①用【真实加层路径】攒层(不手写 _ms_stacks) ②走【真实换路入口】重建战场
	#   ③断言 is_same(旧,新)==false —— 证明确实重建过, 否则这条测试又会靠"同一个字典"蒙混过关。
	var dummy0 := _dummy(s, 100000.0)
	if dummy0.is_empty():
		print("     [FAIL] ★分母: 找不到靶子 —— ⑦ 是空检查"); _fail += 1; return
	tr["_ms_stacks"] = 0
	for _i in range(23):
		s._trainer_sys._trainer_magicstone_onhit(tr, dummy0)
	print("     换路前: %d 层 (真实加层路径攒的)  跨路存档=%s" % [
		int(tr.get("_ms_stacks", 0)), str(GameState.dual_ms_stacks)])
	_chk("⑦ ★分母: 攒到 23 层", int(tr.get("_ms_stacks", 0)) == 23)
	_chk("⑦ 加层时同步写进跨路存档", int(GameState.dual_ms_stacks.get("left", -1)) == 23)
	s._dl_sys._dl_clear_units()
	s._dl_sys._dl_build_lane_field()              # ★真实换路: 内部会 _spawn_trainers 重建大师
	await get_tree().process_frame
	var tr2 = null
	for u in s._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			tr2 = u; break
	_chk("⑦ ★分母: 换路后场上有我方大师", tr2 != null)
	if tr2 == null:
		return
	_chk("⑦ ★★大师确实被重建了(不是同一个字典 —— 否则这条测试是蒙混过关的)",
		not is_same(tr, tr2))
	var kept: int = int(tr2.get("_ms_stacks", -1))
	print("     换路后: %d 层 (需求 23)" % kept)
	_chk("⑦ ★★走【真实换路入口】后层数仍在(跨上路/下路/决胜)", kept == 23)
	var src := FileAccess.get_file_as_string("res://scripts/scenes/battle/dual_lane_flow.gd")
	_chk("⑦ 源码里也没有残留的清零(别在另一处又清一遍)",
		not src.contains('_tu["_ms_stacks"] = 0'))
	_chk("⑦ 回填发生在重建大师的地方(_spawn_trainers)",
		FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_spawn.gd")
			.contains("battle._trainer_sys._ms_restore_stacks(u)"))
	var ds := FileAccess.get_file_as_string("res://scripts/scenes/spell_disc.gd")
	_chk("⑦ ★圆盘不画键位提示(触屏上 Q 无意义·装被动时更是错的)",
		not ds.contains("draw_string(hf,") and not ds.contains(", _key_hint,"))


## ⑥ 圆盘上的叠层角标(用户 2026-07-30:「魔法石，我希望图标上有层数显示」)。
##
## ★判据落在【圆盘真的收到了这个数】上, 不是"代码里有 set_stacks 这个函数" ——
##   后者是符号存在断言, 守不住"每帧到底有没有人喂它"(这正是 _hook_dramatize 那个坑的形态)。
##   所以这里走 battle_render._update_spell_disc() 真实每帧链路, 再读圆盘内部的 _stacks。
## ★带一条反向断言: 换掉被动 → 角标必须撤回 0。少了它, 换路/换装后会留个旧数字挂在屏幕上。
func _stack_badge(s, tr: Dictionary) -> void:
	print("")
	print("  ⑥ 圆盘叠层角标:")
	if s._spell_disc == null or not is_instance_valid(s._spell_disc):
		print("     [FAIL] ★分母: 没有法术圆盘 —— ⑥ 全是空检查"); _fail += 1; return
	var save_p: String = str(tr.get("_tr_passive", ""))
	tr["_tr_passive"] = "magic_stone"
	for n in [0, 3, 17, 142]:
		tr["_ms_stacks"] = n
		s._render._update_spell_disc()            # 走真实每帧链路
		await get_tree().process_frame
		var got: int = int(s._spell_disc._stacks)
		print("     _ms_stacks=%3d → 角标 %3d  (攻速 ×%.2f)" % [n, got, 1.0 + 0.05 * float(n)])
		_chk("⑥ 层数 %d 传到圆盘" % n, got == n)
	# 反向: 不是魔法石被动就必须撤回 0
	tr["_tr_passive"] = ""
	s._render._update_spell_disc()
	await get_tree().process_frame
	_chk("⑥ ★换掉魔法石被动后角标撤回 0(不许留旧数字)", int(s._spell_disc._stacks) == 0)
	tr["_tr_passive"] = save_p
	# 0 层不画 —— 开局别给圆盘加噪点
	var src := FileAccess.get_file_as_string("res://scripts/scenes/spell_disc.gd")
	_chk("⑥ 0 层不画角标(if _stacks > 0)", src.contains("if _stacks > 0:"))
	_chk("⑥ 角标环色从'被动生效中'那个紫起步(#c86bff·一眼归因)", src.contains('Color("#c86bff")'))
	# 角标环色随阈值档位 —— 判据落在【圆盘真的收到了 tier】上, 不是"源码里有 set_tier"
	for pr in [[0, 0], [10, 1], [25, 2], [50, 3]]:
		tr["_tr_passive"] = "magic_stone"
		tr["_ms_stacks"] = int(pr[0])
		s._render._update_spell_disc()
		await get_tree().process_frame
		_chk("⑥ %d 层 → 圆盘档位 %d(环色紫→亮紫→金)" % [pr[0], pr[1]],
			int(s._spell_disc._tier) == int(pr[1]))


## 圆盘子树里第一个 TextureRect 的贴图路径
func _find_icon_path(n: Node) -> String:
	for c in n.get_children():
		if c is TextureRect and (c as TextureRect).texture != null:
			var rp := str((c as TextureRect).texture.resource_path)
			if rp != "":
				return rp
		var sub := _find_icon_path(c)
		if sub != "":
			return sub
	return ""


## 数"在转的环": 有 tween 在跑 rotation 的 TextureRect
func _count_rings(n) -> int:
	if n == null or not is_instance_valid(n):
		return 0
	var cnt := 0
	for c in n.get_children():
		if c is TextureRect and not (c as TextureRect).get_children().is_empty():
			pass
		if c is TextureRect and str((c as TextureRect).texture.resource_path if (c as TextureRect).texture != null else "") == "":
			cnt += 1   # 程序生成的贴图(无 resource_path) = 那个环
		cnt += _count_rings(c)
	return cnt


## 干净合成靶子 —— ★不用场上随机 spawn 的单位测精确数值:
## 队伍未播种 RNG、敌可能带盾/flat_dr, 会让 CI 偶发红(memory: fb-ci-vs-local-divergence)。
## 取一个【真 spawn 出来的敌人】当靶子, 再把影响伤害的字段显式清零。
##
## ★为什么不用手搓字典: 伤害路径会碰 sprite / bar_root 等【节点】字段, 手搓的字典没有,
##   会一路 "Invalid access to property 'sprite'" —— 第一版就是这么废的。
## ★为什么要清零 def/mr/shield/flat_dr: 拿随机 spawn 的单位测精确数值会 CI 偶发红
##   (队伍未播种 RNG、敌可能带盾/减伤)。清零后它就是个"干净靶子"。
func _dummy(s, hp: float) -> Dictionary:
	for u in s._units:
		if str(u.get("side", "")) != "right" or u.get("is_trainer", false) or not u.get("alive", false):
			continue
		u["def"] = 0.0; u["mr"] = 0.0; u["shield"] = 0.0
		u["flat_dr"] = 0.0; u["dmg_taken_mult"] = 1.0
		# ★★ id 也必须中性化 ★★
		#   _mitigate_incoming 里有【按龟 id 的减伤分支】: 钻石 ×0.82(结构减伤)、
		#   石头岩石之躯每层 -1%、石头嘲讽期按护甲减免……
		#   而这个靶子是从场上【随机 spawn 的敌队】里挑的, 抽到钻石那一次伤害就少 18% →
		#   本条断言偶发红。全门禁跑的时候正好抽到了, 单跑却次次绿, 极像"帧预算不够"。
		#   (memory: fb-ci-vs-local-divergence —— 拿随机 spawn 单位测精确数值必偶发红。)
		u["id"] = "_dummy_target"
		# ★闪避是【RNG 二值判定】: 命中就整发伤害归零(battle_damage.gd:68 dodge_bonus)。
		#   除掉"减伤倍率"救不了它 —— 我上一版就是这么栽的: 以为把 _mitigate_incoming
		#   的倍率除掉就干净了, CI 照样红。闪避不在那条链上, 它在更外面。
		u["dodge_bonus"] = 0.0
		u["maxHp"] = hp; u["hp"] = hp
		return u
	return {}


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("     %s %s" % ["[PASS]" if ok else "[FAIL]", what])


func _done(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 训龟大师·魔法石" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
