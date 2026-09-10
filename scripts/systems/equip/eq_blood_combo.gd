class_name EqBloodCombo
extends RefCounted
## eq_blood_combo.gd —— 011「饮血护符坠」的连斩效果本体 + 演出。
##
## ★为什么单独成文件而不是留在 `equip_system.gd`: 那份有架构预算(`arch_budget` 只减不增),
##   011 这一块加进去当场把它撑到 3003 > 3000。而按 CLAUDE.md「新代码放哪」这一块本来就该
##   自己一个文件 —— 它不在 `_sim_step` 调用链上, 是一件装备的效果 + 它自己的演出。
##   接线方式与 088~090(`EqArcaneBatch`)同: 主文件只留【声明 + 构造 + 一行派发】。

var battle


func _init(b) -> void:
	battle = b


## ═══════════════════════════════════════════════════════════════════════════
##  【011 饮血护符坠】连斩 —— 2026-09-10 照着现状实拍 100 帧重做
##  (逐帧凭据: docs/studies/20260910c-011饮血连斩现状逐帧.md;
##   方案书: docs/plans/20260910b-011饮血连斩整套重做.md)
##
##  ★重做前逐帧 + 探针看出来的五条真毛病, 每条对应下面一处:
##    ① 斩痕不是像素画(`VfxTex._make_slash_sheet` 程序生成 220×44, **92 色 / 1938 半透**)
##       ⇒ 新素材 `tools/gen_bloodslash.py` 烤 4 变体 × 5 帧, 锁定 blood 板 6 色 / 0 半透。
##    ② **淡出病** —— 逐帧含 alpha 平均亮度 49.5/81.6/81.6/49.4/**24.8**, 末帧只有峰值 30%、
##       最大 alpha 只有 71/255, 黑地上读成一抹暗棕。⇒ 消散**靠碎不靠淡**(与 009/010 同一条)。
##    ③ **5 帧只有 4 帧不同** —— 帧 1 与帧 2 逐像素相同。⇒ 五帧是画进去的五个阶段。
##    ④ **两条钟** —— 斩击走 `create_tween`(未钳制真实 delta), 连斩节拍走 `_wait_sim`(游戏时钟);
##       实拍看到同一张斩痕在游戏时钟上连续 4 个拍点不动。⇒ 全改 `_wait_sim`, 一条钟。
##    ⑤ **`from2d` 是死参数** —— 旧 `_blood_slash(from2d, to2d, delay)` 函数体一次都没读 from2d,
##       画面上没有「这一刀是携带者砍的」这条因果链。⇒ 落点朝携带者一侧退 BLOOD_ENTER 码。
##
##  ★另外补了一条**文案写着、画面上却读不出来**的: 「后续每发逐渐衰减」。
##    旧版八刀一模一样大, 衰减只活在数字里。⇒ 斩痕宽度 = BLOOD_SLASH_W × 衰减系数,
##    **画多大就是打多重**(与 010「画多远打多远」同一条口径)。
##
##  ★没有预警, 也不该有 —— 文案里 011 的触发是【法器法力条集满】, 而那条紫色法力条
##    本来就画在装备图标框里、玩家一直看得见。**预兆要有因**(memory
##    `fb-telegraph-needs-a-cause-not-a-flash`), 这个因已经在屏幕上了, 不必再加一次闪光。
## ═══════════════════════════════════════════════════════════════════════════
const BLOOD_SLASH_TEX := "res://assets/sprites/vfx/eq011-slash.png"  # 4 变体 × 5 帧
const BLOOD_SLASH_VARIANTS := 4
const BLOOD_SLASH_FRAMES := 5
const BLOOD_SLASH_CELL := 64.0     # 素材一格的边长(像素) —— 必须与 gen_bloodslash.py 的 CELL 一致
const BLOOD_SLASH_W := 130.0       # 第 0 刀斩痕在世界里的宽度(码)
## 每帧的游戏时长。★必须是 SIM_DT(1/60) 的整数倍 —— `_wait_sim` 只停在 sim 步边界上
##   (与 010 的 LASER_CHOP_STEP 同一条; 那一条上我踩过: 写 0.035 实际等 0.05)。
const BLOOD_SLASH_STEP := 2.0 / 60.0
const BLOOD_BEAT := 0.3            # 一刀接一刀的间隔(游戏秒) = 18 × SIM_DT
## 「后续每发逐渐衰减」的那个数 —— **伤害与斩痕尺寸共用它**, 所以画面上读得出衰减。
const BLOOD_DECAY := 0.85
const BLOOD_ENTER := 26.0          # 斩痕落点朝携带者一侧退多少码(刀是从他那边切进来的)


## ═══ 可量部分: 纯算术/纯几何, **不依赖任何演出** ═══
## (CLAUDE.md §3.5: 测数值的用例不该依赖演出跑完。演出调它们, 门禁也直接调它们。)

## 这一次连斩几刀(文案: 5/6/8)。★抽成函数是为了让门禁**真调它**——
##   原来门禁靠 `源码.contains("[5, 6, 8][si]")` 对字面量, 那是假判据: 代码一搬家就红,
##   而且它证明的是"源码里有这串字"不是"跑起来真的斩这么多刀"。
func combo_hits(si: int) -> int:
	return [5, 6, 8][si]


## 第 k 刀的衰减系数。★伤害和斩痕宽度**都**乘它 ⇒ 画多大就是打多重。
func blood_decay(k: int) -> float:
	return pow(BLOOD_DECAY, k)


## 第 k 刀打多少。★抽出来是为了让门禁不必重算一遍公式(手抄的副本必然落后)。
func blood_hit_dmg(u: Dictionary, si: int, o: Dictionary, k: int) -> int:
	var raw: int = battle._resolve_dmg(u, u["atk"] * [0.5, 0.7, 1.0][si] + [40.0, 50.0, 70.0][si], o, false)
	return int(float(raw) * blood_decay(k))


## 第 k 刀的斩痕**落点**: 目标位置朝【携带者那一侧】退 BLOOD_ENTER 码。
## ★★这就是把 `from2d` 从死参数变成真参数的那一步。旧版 `_blood_slash(from2d, to2d, delay)`
##   签名里有 from2d、函数体一次都没读它 —— 于是斩痕凭空出现在敌人身上,
##   画面上没有「这一刀是携带者砍过来的」。现在把携带者的方位画进落点里, 门禁量得到
##   (把携带者放到目标的左边/右边各跑一次, 偏移方向必须跟着翻)。
func blood_slash_at(from2d: Vector2, to2d: Vector2) -> Vector2:
	var d: Vector2 = from2d - to2d
	if d.length() < 1.0:
		return to2d
	return to2d + d.normalized() * BLOOD_ENTER


## 一刀的斩痕精灵。宽度由调用方给(= BLOOD_SLASH_W × 衰减系数)。
func _blood_slash_sprite(vi: int, at: Vector2, w: float) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = load(BLOOD_SLASH_TEX)
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.transparent = true
	sp.hframes = BLOOD_SLASH_VARIANTS
	sp.vframes = BLOOD_SLASH_FRAMES
	sp.frame = vi
	sp.pixel_size = w * battle.WS / BLOOD_SLASH_CELL
	sp.position = battle._world_pos(at, 1.0)
	return sp


## 一刀的演出: 五帧逐帧走 **`_wait_sim`**(与连斩节拍同一条钟)。
## ★不 await 它 —— 让它作为协程自己跑完, 连斩的 0.3 秒节拍才不会被这 0.167 秒顶开。
##   两边都走游戏时钟 ⇒ 仍然是**一条钟**(memory `fb-second-clock-drops-events`)。
func _blood_slash_play(vi: int, at: Vector2, w: float) -> void:
	var sp := _blood_slash_sprite(vi, at, w)
	battle._world.add_child(sp)
	for f in range(BLOOD_SLASH_FRAMES):
		if is_instance_valid(sp):
			sp.frame = f * BLOOD_SLASH_VARIANTS + vi
		await battle._wait_sim(BLOOD_SLASH_STEP)
		if not is_instance_valid(battle):
			return
	if is_instance_valid(sp):
		sp.queue_free()   # 有开就有合: 一个都不许留在场上


## 连斩本体。★入口只有一个: `EquipSystem.fire_equip_effect` 在【法器法力条集满】时调。   # 饮血护符坠(011): 一段一段连斩(每刀 0.3s 顺序打出,各命中随机敌,衰减0.85^k); 吸血溢出转盾结尾汇总
## ★函数名带 `_eq_` 前缀是**有原因的**(不是风格洁癖): `tools/tooltip_number_audit.py` 靠
##   `"p2eq_NNN": (_\w+_sys\.)?(_\w+)\(` 这条正则把【派发口】锚到【效果函数定义处】,
##   再判断文案里的三元组数值离锚点多远。叫 `combo` 它锚不到 ⇒ 40/50/70 这些数会被报成
##   「远处命中·人工核」。2026-09-10 搬家时踩过一次。
func _eq_blood_combo(u: Dictionary, si: int) -> void:
	var n: int = combo_hits(si)
	var sh0: float = u["shield"]
	for k in range(n):
		if not u.get("alive", false): break
		var es = battle._targeting._pick_enemies_of(u)
		if es.is_empty(): break
		var o = es[battle._battle_rng.randi() % es.size()]
		var decay: float = blood_decay(k)
		## 这一刀: 斩痕落在【目标朝携带者那一侧】, 宽度 = 基准 × 衰减 ⇒ 画多大就是打多重;
		## 变体按刀序轮换 ⇒ 读起来是「一刀接一刀」而不是同一张图闪八次。
		_blood_slash_play(k % BLOOD_SLASH_VARIANTS, blood_slash_at(u["pos"], o["pos"]),
			BLOOD_SLASH_W * decay)
		battle._damage._apply_damage_from(u, o, blood_hit_dmg(u, si, o, k),
			Color("#ff8aa0"), 0.33, false, true)
		await battle._wait_sim(BLOOD_BEAT)   # 一段一段: 每 0.3s 一刀
		if not is_instance_valid(battle): return   ## await 回来 battle 可能已被 queue_free(战斗结束)
	if not is_instance_valid(self): return
	var shg: int = int(u["shield"] - sh0)   # 连斩吸血溢出转的盾, 结尾汇总一次
	if shg > 0: battle._vfx._float_text(u["pos"] + Vector2(28, -46), "护盾+" + str(shg), Color("#8ad7ff"), false, "shield")

