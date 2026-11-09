"""龟壳复制 60% 跟着延后结算走(2026-11-09)。一次性改文件脚本: 二进制读写、保留行尾、每处替换断言恰命中一次。

探针 tests/probes/_probe_copy_ratio.gd: 81 个可抄技能里有伤害的 57 个, 36 个复制后照样 100%。两个根因:
  ① 延后结算(弹道命中 / sim 补间回调 / 不带 src 的延后子弹)时龟壳 dmg_out_mult 早已复位;
  ② _apply_damage(DoT / 真伤那条路)从来不乘 dmg_out_mult(CLAUDE.md §4.3 两条路都要改)。
"""
ROOT = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/"


def edit(rel, pairs):
    p = ROOT + rel
    b = open(p, "rb").read().decode("utf-8")
    crlf = "\r\n" in b
    s = b.replace("\r\n", "\n")
    for a, c in pairs:
        assert s.count(a) == 1, (rel, a[:100], s.count(a))
        s = s.replace(a, c)
    open(p, "wb").write((s.replace("\n", "\r\n") if crlf else s).encode("utf-8"))


# ── shell_system.gd: 上下文三件套 + 两发复制改走它 ──
edit("scripts/systems/skills/shell_system.gd", [
    ("""## 复制出来的技能里【延后结算】的那几段(蓄力 / 错峰 / 落点…)原来出了 _do_skill 就按 100% 结算 ——
## 60% 只管住了立即那一段(10-16 第二批核查)。⇒ 施放期间新入队的延后条目打上 _copy, 到点结算时再套 60%。
func _mark_copy_tail(from_idx: int) -> void:
	for i in range(from_idx, battle._pending_shots.size()):
		battle._pending_shots[i]["_copy"] = COPY_EFFECT
""", """## 复制出来的技能里【延后结算】的那几段(蓄力 / 错峰 / 落点…)原来出了 _do_skill 就按 100% 结算 ——
## 60% 只管住了立即那一段(10-16 第二批核查)。⇒ 施放期间新入队的延后条目打上 _copy, 到点结算时再套 60%。
## ★2026-11-09 扩成「复制期上下文」, 跟着所有延后结算走(探针 tests/probes/_probe_copy_ratio.gd:
##   81 个可抄技能里有伤害的 57 个, 36 个复制后照样 100% —— 冰封冰锥是弹道、墨水炸弹在 sim 补间回调里落地、
##   不少延后子弹不带 src(原来这条只认带 src 的), 结算那一刻龟壳的 dmg_out_mult 早已复位)。
##   做法同装备统计 tally: 建的那一刻 ctx_capture(弹道 / sim 补间 / 延后子弹), 结算那一刻 ctx_enter / ctx_exit。
##   tag = [倍率, 龟壳单位] —— 单位只存引用、从不当键(CLAUDE.md §4.2)。可嵌套: exit 还原成 enter 之前的值。
func ctx_capture():
	if battle._copy_fx_mult == 1.0 or not (battle._copy_src is Dictionary):
		return null
	return [battle._copy_fx_mult, battle._copy_src]


func ctx_enter(tag: Array) -> Array:
	var src: Dictionary = tag[1]
	var prev: Array = [battle._copy_fx_mult, battle._copy_src, float(src.get("dmg_out_mult", 1.0)), battle._pending_shots.size()]
	battle._copy_fx_mult = float(tag[0])
	battle._copy_src = src
	src["dmg_out_mult"] = float(tag[0])
	return prev


func ctx_exit(tag: Array, prev: Array) -> void:
	## 这段结算期间新排进去的延后子弹也带上(延后段里再排延后段: 蓄力 → 落点 → 余波)
	for i in range(int(prev[3]), battle._pending_shots.size()):
		if not battle._pending_shots[i].has("_copy"):
			battle._pending_shots[i]["_copy"] = tag
	battle._copy_fx_mult = float(prev[0])
	battle._copy_src = prev[1]
	(tag[1] as Dictionary)["dmg_out_mult"] = float(prev[2])
"""),
    ("""		_fx.copy_begin(u, pool.slice(0, 2), (COPY_SECOND_DELAY + 0.3) if two else 0.8)
		u["dmg_out_mult"] = COPY_EFFECT                                # 60%效果(封板)·即时伤害经_apply_damage_from乘数
		battle._copy_fx_mult = COPY_EFFECT                                    # 60%效果·护盾/治疗/DoT
		var s0: String = str(pool[0])
		## ★同一个坑的第一发: `_sk_shell_copy(u, tgt)` 的 tgt 无类型标注, 上游可能给 null。
		var t0 = tgt if (tgt is Dictionary and (tgt as Dictionary).get("alive", false)) else battle._targeting._nearest_enemy(u)
		if t0 == null:
			battle._copy_fx_mult = 1.0
			u["dmg_out_mult"] = 1.0
			return
""", """		_fx.copy_begin(u, pool.slice(0, 2), (COPY_SECOND_DELAY + 0.3) if two else 0.8)
		## 60%效果(封板): 即时伤害(龟壳 dmg_out_mult, 两条伤害路都乘)+ 护盾/治疗/DoT(battle._copy_fx_mult); 延后段见 ctx_capture
		var tag0: Array = [COPY_EFFECT, u]
		var prev0: Array = ctx_enter(tag0)
		var s0: String = str(pool[0])
		## ★同一个坑的第一发: `_sk_shell_copy(u, tgt)` 的 tgt 无类型标注, 上游可能给 null。
		var t0 = tgt if (tgt is Dictionary and (tgt as Dictionary).get("alive", false)) else battle._targeting._nearest_enemy(u)
		if t0 == null:
			ctx_exit(tag0, prev0)
			return
"""),
    ("""		var _ps0: int = battle._pending_shots.size()
		battle._do_skill(u, t0, s0)                                   # 第1个立即
		_mark_copy_tail(_ps0)
		SkillForms.unpin_form(u, s0)                                  # ★成对解钉, 否则形态卡住
		battle._copy_fx_mult = 1.0
		u["dmg_out_mult"] = 1.0
""", """		battle._do_skill(u, t0, s0)                                   # 第1个立即
		SkillForms.unpin_form(u, s0)                                  # ★成对解钉, 否则形态卡住
		ctx_exit(tag0, prev0)                                         # 施放期间排进去的延后子弹带上 tag0
"""),
    ("""		var fn = func():
			uu["dmg_out_mult"] = COPY_EFFECT
			battle._copy_fx_mult = COPY_EFFECT
""", """		var fn = func():
			var tag1: Array = [COPY_EFFECT, uu]
			var prev1: Array = ctx_enter(tag1)
"""),
    ("""			var t2 = battle._targeting._nearest_enemy(uu)
			if t2 == null:
				battle._copy_fx_mult = 1.0
				uu["dmg_out_mult"] = 1.0
				return
""", """			var t2 = battle._targeting._nearest_enemy(uu)
			if t2 == null:
				ctx_exit(tag1, prev1)
				return
"""),
    ("""			var _ps1: int = battle._pending_shots.size()
			battle._do_skill(uu, t2, p1)
			_mark_copy_tail(_ps1)
			SkillForms.unpin_form(uu, p1)
			battle._copy_fx_mult = 1.0
			uu["dmg_out_mult"] = 1.0
""", """			battle._do_skill(uu, t2, p1)
			SkillForms.unpin_form(uu, p1)
			ctx_exit(tag1, prev1)
"""),
])

# ── 主文件: 上下文的龟壳引用 + sim 补间建时记、推时还原 ──
edit("scripts/scenes/RealtimeBattle3DScene.gd", [
    ("""var _copy_fx_mult: float = 1.0
""", """var _copy_fx_mult: float = 1.0
var _copy_src = null   # 复制期上下文里的龟壳(ShellSystem.ctx_*; 只在复制窗口里非空)
"""),
    ("""			_equip_sys.tally.use((tw.get_meta("_tl") if tw.has_meta("_tl") else null))   # ④ 演出链末尾的结算回调记回建 tween 时的装备
			tw.custom_step(dt)
""", """			_equip_sys.tally.use((tw.get_meta("_tl") if tw.has_meta("_tl") else null))   # ④ 演出链末尾的结算回调记回建 tween 时的装备
			if tw.has_meta("_copy"):   # 龟壳复制期建的补间: 回调里落地的伤害 / 护盾照样按 60%(ShellSystem.ctx_capture)
				var _ct: Array = tw.get_meta("_copy")
				var _cp: Array = _shell_sys.ctx_enter(_ct)
				tw.custom_step(dt)
				_shell_sys.ctx_exit(_ct, _cp)
			else:
				tw.custom_step(dt)
"""),
    ("""	t.set_meta("_tl", _equip_sys.tally.capture())   # ④ 装备统计: 记下建 tween 时的装备上下文
""", """	t.set_meta("_tl", _equip_sys.tally.capture())   # ④ 装备统计: 记下建 tween 时的装备上下文
	if _copy_fx_mult != 1.0:
		var _ct = _shell_sys.ctx_capture()
		if _ct != null:
			t.set_meta("_copy", _ct)   # 龟壳复制期: 推这条补间时还原 60%(见 _step_sim_tweens)
"""),
])

# ── 弹道: 发射时记、命中时还原; 延后子弹改认 tag ──
edit("scripts/scenes/battle/battle_ballistics.gd", [
    ("""	if not d.has("_sk"):
		d["_sk"] = battle._audio_sys.skill_ctx         # 技能章(只管声音): 技能射出的弹道落地时播这个技能的命中声
	battle._projectiles.append(d)
""", """	if not d.has("_sk"):
		d["_sk"] = battle._audio_sys.skill_ctx         # 技能章(只管声音): 技能射出的弹道落地时播这个技能的命中声
	if battle._copy_fx_mult != 1.0 and not d.has("_copy"):
		var _ct = battle._shell_sys.ctx_capture()
		if _ct != null:
			d["_copy"] = _ct                           # 龟壳复制期射出的弹道: 命中时照样按 60%(冰封冰锥等)
	battle._projectiles.append(d)
"""),
    ("""			node.queue_free()
			if tgt["alive"]:
				if pr.has("dtype"):
""", """			node.queue_free()
			var _cp: Array = battle._shell_sys.ctx_enter(pr["_copy"]) if pr.get("_copy") is Array else []
			if tgt["alive"]:
				if pr.has("dtype"):
"""),
    ("""				if pr.get("star_true", 0) > 0 and tgt.get("alive", false):
					battle._damage._apply_damage_from(pr["src"], tgt, int(pr["star_true"]), Color("#ffffff"), 0.0, true)   # 星能追加真伤(白字·附普攻命中同帧·用户2026-07-16)
			continue
""", """				if pr.get("star_true", 0) > 0 and tgt.get("alive", false):
					battle._damage._apply_damage_from(pr["src"], tgt, int(pr["star_true"]), Color("#ffffff"), 0.0, true)   # 星能追加真伤(白字·附普攻命中同帧·用户2026-07-16)
			if not _cp.is_empty():
				battle._shell_sys.ctx_exit(pr["_copy"], _cp)
			continue
"""),
    ("""				if s.has("_copy") and s.get("src") is Dictionary:   # 龟壳复制出来的技能的延后段: 照样按 60% 结算(见 ShellSystem._mark_copy_tail)
					var _cs: Dictionary = s["src"]
					battle._copy_fx_mult = float(s["_copy"]); _cs["dmg_out_mult"] = float(s["_copy"])
					fn.call()
					battle._copy_fx_mult = 1.0; _cs["dmg_out_mult"] = 1.0
				else:
""", """				if s.get("_copy") is Array:   # 龟壳复制出来的技能的延后段: 照样按 60% 结算(ShellSystem.ctx_*; 不带 src 的也算)
					var _cp: Array = battle._shell_sys.ctx_enter(s["_copy"])
					fn.call()
					battle._shell_sys.ctx_exit(s["_copy"], _cp)
				else:
"""),
])

# ── 伤害: DoT / 真伤那条路也乘 ──
edit("scripts/scenes/battle/battle_damage.gd", [
    ("""		dmg = int(round(float(dmg) * (1.0 + battle._BASIC_RARITY_BONUS.get(str(u.get("rarity", "C")), 0.20))))
	# ★2026-07-22 全量对齐: 过与 _apply_damage_from 同一套受害者减伤(见 §MITIGATE)。
""", """		dmg = int(round(float(dmg) * (1.0 + battle._BASIC_RARITY_BONUS.get(str(u.get("rarity", "C")), 0.20))))
	## 龟壳复制 60%(同 _apply_damage_from 那一段, 同样排在小龟增伤之后、减伤之前; CLAUDE.md §4.3 两条路都要加)。
	##   2026-11-09 探针: 原来这条路不乘 ⇒ 复制来的真伤 / %生命值伤害照样 100%。DoT 跳伤不受影响: 层数在施加那一刻
	##   已按 _copy_fx_mult 缩(_apply_dot_stacks), 之后每跳在复制窗口之外结算、龟壳 dmg_out_mult = 1。扣自己的血(is_self)不缩。
	if src is Dictionary and not is_self and float((src as Dictionary).get("dmg_out_mult", 1.0)) != 1.0:
		dmg = int(round(float(dmg) * float((src as Dictionary).get("dmg_out_mult", 1.0))))
	# ★2026-07-22 全量对齐: 过与 _apply_damage_from 同一套受害者减伤(见 §MITIGATE)。
"""),
])
print("ok")
