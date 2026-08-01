class_name HookBombSystem
extends RefCounted
## 靶向器 p2eq_055 ·【钩索炸弹】(用户 2026-08-01 整条重做)
##
## 用户原文:「携带者在首次造成了400点伤害后，会向最近的1/1/2名敌人发射钩索炸弹，
##   炸弹会附在敌人身上并每秒对该敌人造成1/2/2%物理伤害，持续到敌人死亡时，
##   如果敌人带有炸弹的时候死亡，则会朝所有敌方单位发射钩索，眩晕0.5秒后把他们拉向自己，
##   聚在一起后产生一次爆炸造成200/400/500+10%最大生命值物理伤害。
##   记得排出训龟大师和龟蛋还有免控单位」
##
## ★旧效果(命中标记 +20% 受伤 5 秒)已整条删除, 不是叠加。
##
## ═══ 为什么把结算全做成纯函数 ═══
## CLAUDE.md §3.5 的血泪: `verify_pirate_hook` 连红三次(帧数→游戏时钟→墙钟), 根因是
## 【场景树 create_tween() 在无头 CI 下推进不稳】—— 伤害结算埋在"甩钩→拉回→callback"两层
## tween 链的最末尾, CI 上那条链跑不完, 等多久都是 0, 而本地永远复现不出来。
## 所以本文件的规矩是:
##   · `_hb_pull_dest(...)`   纯几何 —— 验落点, 不等 tween 跑到
##   · `_hb_detonate(...)`    纯结算 —— 演出末尾调它、门禁也直接调它
##   · `_hb_targets(...)`     纯筛选 —— 免控/大师/龟蛋的排除单独可验
## 一个测"数值对不对"的用例, 不该依赖任何动画 tween 跑完。
##
## ═══ 数值口径(已在方案书记录, 用户未逐条指定基数时的取法) ═══
##   · 每秒 1/2/2% 物理伤害 → 按【宿主自身 maxHp】的百分比。与骷髅爆炸(032)同口径:
##     那条也是"200码内敌各受【其自身】%最大生命"。
##   · 爆炸 200/400/500 + 10% 最大生命值 → 同样按【被炸目标自身 maxHp】。
##   · 两者都是【物理伤害】= 走 raw=false 的常规路径, 吃护甲。

var battle

## ★自己的延时队列 —— 【不能】用 battle._pending_shots: 它的推进 (_step_pending_shots)
##   卡在 `if not _over` 里, 而"抽搐 0.62 秒后引爆"很可能正好跨过战斗结束那一刻
##   (被炸的是最后一个敌人时, 杀掉它战斗就结束了) → 最高潮那一下的画面凭空消失。
##   这个队列由 battle._process 在 _over 门控【之外】推进, 所以一定会兑现。
var _pending: Array = []


## 由 RealtimeBattle3DScene._process 每帧调(在 _over 门控之外)。
func tick_pending(delta: float) -> void:
	if _pending.is_empty():
		return
	var keep: Array = []
	for it in _pending:
		it["t"] = float(it["t"]) - delta
		if float(it["t"]) <= 0.0:
			(it["fn"] as Callable).call()
		else:
			keep.append(it)
	_pending = keep


const TRIGGER_DMG := 400                      # 首次累计造成这么多伤害后触发(用户原文"首次造成了400点伤害")
const BOMB_COUNT := [1, 1, 2]                 # 挂弹敌人数(1/1/2)
const BOMB_DPS_PCT := [0.01, 0.02, 0.02]      # 每秒对宿主造成其 maxHp 的 1/2/2%
const BOMB_TICK := 1.0                        # "每秒"
const BLAST_FLAT := [200.0, 400.0, 500.0]     # 聚爆固定段
const BLAST_MAXHP_PCT := 0.10                 # 聚爆额外 10% 最大生命
const PULL_STUN := 0.5                        # 抓住后先眩晕 0.5 秒(参考作品: 触须缠住的停顿)
const PULL_DUR := 0.42                        # ★拖回震中的【时长】—— 拉拽是有速度的, 不是瞬移
const CONVULSE_SEC := 0.62                    # ★宿主 0 血后【抽搐】多久才炸开(人体炸弹的铺垫)
const PULL_GATHER_R := 85.0                   # 聚拢半径: 拉到震中周围这个圈上。★60 太挤(6 个单位挤成一坨,
                                              #   用户「都挤在一起」), 85 刚好围一圈还看得出各是各


func _init(b) -> void:
	battle = b


## 能不能被这套钩索【拉/晕】。用户点名排除: 训龟大师 / 龟蛋 / 免控单位。
## ★免控用的是通用窗口 cc_immune_until(battle_damage._stun 的唯一闸门), 不是自己再发明一个判据 ——
##   发明新判据 = 下一个加免控来源的人不会知道要同步这里。
func _hb_can_grab(o: Dictionary) -> bool:
	if not _hb_can_bomb(o):
		return false
	# ★免控只挡【拉/晕】这一段 —— 拉拽和眩晕才是控制效果。
	if battle._t < float(o.get("cc_immune_until", 0.0)):
		return false
	return true


## 能不能被【挂炸弹】。★不看免控 —— 用户 2026-08-01:「挂炸弹不包括免控的因为这不是控制技能」。
##   我第一版把挂弹和拉拽共用了同一条名单, 等于给免控单位白送一层"炸弹免疫", 而炸弹只是个持续伤害源。
##   仍然排除训龟大师与龟蛋: 前者是场外监视者、后者不动不攻击, 给它们挂弹这条效果整个作废。
func _hb_can_bomb(o: Dictionary) -> bool:
	if not (o is Dictionary) or not o.get("alive", false):
		return false
	if o.get("is_trainer", false):
		return false
	if o.get("_isEgg", false) or o.get("egg", false) or o.get("_eggImmune", false):
		return false
	return true


## 可挂弹的敌人(排除同上): 挂到蛋/大师身上等于把整条效果喂给一个永远不死或不该被拉的目标。
func _hb_targets(u: Dictionary, n: int) -> Array:
	var cand: Array = []
	for o in battle._targeting._enemies_of(u):
		if not _hb_can_bomb(o):                        # ★挂弹用 can_bomb(不看免控), 拉拽才用 can_grab
			continue
		if float(o.get("hookbomb_pct", 0.0)) > 0.0:
			continue                                   # 已经挂着弹, 不重复挂
		cand.append(o)
	cand.sort_custom(func(a, b): return (a["pos"] - u["pos"]).length_squared() < (b["pos"] - u["pos"]).length_squared())
	return cand.slice(0, maxi(0, n))


## 挂弹。★不拿单位字典当 Dictionary 的键(CLAUDE.md §3.2 会递归哈希成环→卡死);
##   这里是把【引用】存进字段, 与 summon_owner 同一做法, 合法。
func _hb_attach(u: Dictionary, o: Dictionary, si: int) -> void:
	# ★同一目标身上多颗炸弹【叠加】而不是覆盖(用户 2026-08-01:「要合并」)。
	#   正常情况下 _hb_targets 会跳过已挂弹的目标, 所以同一携带者不会重复挂;
	#   但【两个携带者】各自挑到同一个倒霉蛋是可能的 —— 那时该是两份 DoT 一起烧,
	#   而不是后一颗把前一颗的伤害覆盖掉(覆盖 = 第二颗白挂)。
	o["hookbomb_pct"] = float(o.get("hookbomb_pct", 0.0)) + BOMB_DPS_PCT[si]
	if not (o.get("hookbomb_src", null) is Dictionary):
		o["hookbomb_src"] = u          # 引爆归属给【第一颗】的携带者
	o["hookbomb_si"] = maxi(int(o.get("hookbomb_si", 0)), si)   # 聚爆按更高星级那颗
	o["hookbomb_t"] = float(o.get("hookbomb_t", 0.0))
	_bomb_vfx(o)
	battle._skill_ring(o["pos"], Color(1.0, 0.48, 0.24, 0.7), 44.0)


## 宿主身上的每秒跳伤。由 _tick_unit 每帧喂 delta。
func _hb_tick(o: Dictionary, delta: float) -> void:
	var pct: float = float(o.get("hookbomb_pct", 0.0))
	if pct <= 0.0 or not o.get("alive", false):
		return
	var src = o.get("hookbomb_src", null)
	if not (src is Dictionary):
		return
	o["hookbomb_t"] = float(o.get("hookbomb_t", 0.0)) + delta
	if float(o["hookbomb_t"]) < BOMB_TICK:
		return
	o["hookbomb_t"] = float(o["hookbomb_t"]) - BOMB_TICK
	var hp0: float = float(o["hp"])
	# no_popup=true → 不跳通用红字, 伤害只体现在宿主头上那个【累加滚动数字】里(用户指定的显示方式)
	battle._damage._apply_damage_from(src, o, maxi(1, int(round(float(o["maxHp"]) * pct))), Color("#ff8a3c"), 0.0, false, true, false, false, true)
	# ★累计【实际扣掉的血】而不是名义伤害 —— 有护盾/减伤时两者不等, 显示实际的才不骗人。
	o["hookbomb_total"] = float(o.get("hookbomb_total", 0.0)) + maxf(0.0, hp0 - float(o["hp"]))
	_hb_counter_refresh(o)
## ★★引爆全段。节奏参考《虐杀原型2》人体炸弹(用户 2026-08-01 指定):
##   植入皮下 → 短暂延迟 → 触须【高速】从宿主体内爆出 → 触须把碰到的一切【拖向震中】
##   → 震中是【被植入的那个人】→ 被拖者与爆心附近吃重伤。
##   (来源: prototype.fandom.com/wiki/Biobomb 与 /wiki/Tendrils)
##
## ★★震中 = 【宿主倒地处】, 不是携带者。
##   我第一版做成了"拉向携带者" —— 需求原文「把他们拉向自己」的"自己", 配合前半句
##   「朝所有敌方单位发射钩索」, 主语是【那颗炸弹/那具尸体】。参考作品也是以宿主为震中。
##
## ★★拉拽【有速度】, 不是瞬移(用户:「瞬移并不是拉拽，拉拽是有速度的吗」)。
##   位移走 tween 在 PULL_DUR 秒内推进(照 _pirate_death_grapple 那套 QUAD/EASE_IN = 越拉越快),
##   而【伤害结算】走 battle._pending_shots(sim 驱动·无头稳), 不挂在 tween 末尾 ——
##   CLAUDE.md §3.5: 数值不能依赖演出 tween 跑完。
##
## 返回被卷入的单位数(供门禁当分母; N=0 是空检查不是通过)。
func _hb_detonate(carrier: Dictionary, si: int, epicenter_in = null) -> int:
	if not (carrier is Dictionary):
		return 0
	var epi: Vector2 = (epicenter_in as Vector2) if epicenter_in != null else (carrier["pos"] as Vector2)
	var list: Array = []
	for o in battle._targeting._enemies_of(carrier):
		if _hb_can_grab(o):
			list.append(o)
	if list.is_empty():
		return 0
	var n: int = list.size()
	carrier["_hb_detonated_n"] = int(carrier.get("_hb_detonated_n", 0)) + 1   # 同步触发证据(供门禁)
	# ★静一拍(画面感第二条): 触须爆出的瞬间定格一下。冲击前的停顿比冲击本身更重要 ——
	#   没有它, "炸"会淹在持续的战斗噪音里; 有了它, 观众的眼睛会被强行拽到这一点上。
	#   0.14 秒: 比团灭(0.30)短、比开打起势(0.18)略短 —— 这是"一次装备触发"该有的量级, 不能喧宾夺主。
	battle._add_hitstop(0.14)
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	battle._skill_ring(epi, Color(1.0, 0.55, 0.22, 0.9), 90.0)
	for i in range(n):
		var o: Dictionary = list[i]
		battle._damage._stun(o, PULL_STUN + PULL_DUR, "hookbomb")   # 晕住整段: 抓住→拖回都不该乱跑
		_tendril_shoot(epi, o, i)                                    # ① 触须高速爆出→抓住
		var dest: Vector2 = _hb_pull_dest_at(epi, i, n)
		_pull_over_time(o, dest)                                     # ② 带速度拖回震中
	# ③ 聚拢后一次爆炸 —— 走 sim 定时器, 不是 tween
	var cc: Dictionary = carrier
	var lst: Array = list
	var sii: int = si
	var ep2: Vector2 = epi
	_pending.append({"t": PULL_STUN + PULL_DUR, "fn": func(): _hb_blast(cc, lst, sii, ep2)})
	return n


## 聚拢后的那一下爆炸(纯结算 —— 门禁直接调它, 不等任何演出)。
func _hb_blast(carrier: Dictionary, list: Array, si: int, epi: Vector2) -> int:
	var hit := 0
	for o in list:
		if not (o is Dictionary) or not o.get("alive", false):
			continue
		var dmg: int = maxi(1, int(round(BLAST_FLAT[si] + float(o["maxHp"]) * BLAST_MAXHP_PCT)))
		battle._damage._apply_damage_from(carrier, o, dmg, Color("#ff5a2a"), 0.0, false, true)
		hit += 1
	# ★真爆炸演出(用户 2026-08-01:「炸的特效？你啥都不做吗」——之前只有一个圆环+震屏+粒子)。
	#   三层叠: ①主爆火球(大·快胀快消) ②滞后半拍的第二团(错位=有体积) ③冲击环+震屏。
	battle._burst_vfx(TEX_BLAST, epi, 220.0, 0.55)
	_pending.append({"t": 0.09, "fn": func(): battle._burst_vfx(TEX_BLAST, epi + Vector2(26.0, -18.0), 150.0, 0.8)})
	battle._skill_ring(epi, Color(1.0, 0.45, 0.2, 0.95), 170.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	battle._particle_burst(epi)
	return hit


## 聚拢落点(纯几何 —— 门禁验这个, 不等拉拽跑完)。均匀铺在震中周围一圈, 不叠成一个点
## (叠一起会被分离力当场弹开, 看着像"拉了个寂寞")。
func _hb_pull_dest_at(epi: Vector2, idx: int, total: int) -> Vector2:
	var a: float = TAU * float(idx) / maxf(1.0, float(total))
	return epi + Vector2(cos(a), sin(a)) * PULL_GATHER_R


## 兼容旧签名(以携带者为震中) —— 门禁与老调用点还在用。
func _hb_pull_dest(carrier: Dictionary, idx: int, total: int) -> Vector2:
	return _hb_pull_dest_at(carrier["pos"] as Vector2, idx, total)


## 宿主死亡钩子。由 battle._kill 调。★把"带弹"的判据放在这里而不是 _kill 里散着写,
## 是为了让"谁在触发引爆"只有一个答案。
func _hb_on_death(o: Dictionary) -> void:
	if float(o.get("hookbomb_pct", 0.0)) <= 0.0:
		return
	var src = o.get("hookbomb_src", null)
	var si: int = int(o.get("hookbomb_si", 0))
	o["hookbomb_pct"] = 0.0
	o["hookbomb_src"] = null
	if not (src is Dictionary):
		return
	# ★★人体炸弹的死亡节拍(用户 2026-08-01:「目标以0血条整个身体开始抖动一段时间,
	#   然后整个炸开, 以病毒的身体发射触手」)。
	#   原来是【死亡当帧立刻甩钩】—— 没有铺垫, 观众来不及理解"这个人要炸了"。
	#   现在拆成两拍: ①尸体抽搐 CONVULSE_SEC 秒(越抖越狠+越涨越红) ②炸开+从尸体射触手。
	#   ★中间那段等待走 _pending_shots(sim 驱动·无头稳), 不挂 tween —— 结算不能依赖演出。
	_convulse(o)
	var srcd: Dictionary = src
	var epi: Vector2 = o["pos"]
	_pending.append({"t": CONVULSE_SEC, "fn": func(): _hb_detonate(srcd, si, epi)})


## ① 抽搐: 尸体原地高频颤抖, 幅度与红度随时间升到顶, 最后一下猛涨 —— "它要炸了"。
## ★这一段【纯演出】。伤害/拉拽全在 CONVULSE_SEC 之后由 _hb_detonate 结算, 与抖动无关。
func _convulse(o: Dictionary) -> void:
	var spr = o.get("sprite", null)
	if not is_instance_valid(spr):
		return
	var base_pos: Vector3 = (spr as Node3D).position
	var base_sc: Vector3 = (spr as Node3D).scale
	var tw = battle._reg_tween()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(spr):
			return
		# 抖动频率与幅度都随 t 升高: 前半段是"痉挛", 后半段是"绷不住了"
		var amp: float = lerpf(1.2, 7.0, t * t) * battle.WS
		var freq: float = lerpf(26.0, 64.0, t)
		var ph: float = battle._t * freq
		(spr as Node3D).position = base_pos + Vector3(sin(ph) * amp, absf(cos(ph * 1.7)) * amp * 0.6, 0.0)
		# 越来越胀、越来越红(生物质在里面涨)
		var g: float = lerpf(1.0, 1.34, t * t)
		(spr as Node3D).scale = Vector3(base_sc.x * g, base_sc.y * g, base_sc.z)
		if spr is GeometryInstance3D:
			(spr as Sprite3D).modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.30, 0.26), t)
	, 0.0, 1.0, CONVULSE_SEC)
	tw.tween_callback(func() -> void:
		# ② 整个炸开: 尸体本体消失(被生物质撑爆), 位置留给触须当发射点
		if is_instance_valid(spr):
			(spr as Node3D).visible = false)


# ============================================================================
#  演出 (2026-08-01 用户:「靶向器…特效你肯定是没做吧」—— 之前确实只有一个通用标记圈)
# ============================================================================
## ★素材是【新生成】的, 不复用现有的 grapple-hook / hook-chain / ninja-bomb ——
##   那三张分别属于海盗钩索、训龟大师钩锁、忍者炸弹(用户定的规矩: 只有背包/商店图标可复用)。
const TEX_MINE := "res://assets/sprites/vfx/hookbomb-mine.png"
const TEX_CHAIN := "res://assets/sprites/vfx/hookbomb-chain.png"
const TEX_BLAST := "res://assets/sprites/vfx/hookbomb-blast.png"   # 聚爆(新生成, 不复用 fx_explosion)

## 挂在宿主身上的炸弹: 贴图跟着宿主走 + 呼吸脉动, 宿主一死就撤。
## ★挂在【宿主的 sprite 之下】而不是自己每帧同步位置 —— 少一条要维护的跟随逻辑,
##   宿主被 queue_free 时它自然一起没。
func _bomb_vfx(o: Dictionary) -> void:
	var host = o.get("sprite", null)
	if not is_instance_valid(host):
		return
	# ★尺寸单位是【米】不是游戏像素 —— WS=0.024(像素→米)。我第一版传 22.0 当成了"22 像素",
	#   实际是 22 米 ≈ 战场高度的 1.8 倍, 屏幕左上角糊了一大块橙色(用户:「你自己验过吗？大小什么的」)。
	#   参照: 地图道具用 1.5~3.0 米, 龟身约 32px×WS≈0.77 米。炸弹取 0.55 米 ≈ 龟头大小。
	var spr: Sprite3D = battle._map_billboard(TEX_MINE, o["pos"], 0.62, false)
	if spr.texture == null:
		return
	spr.name = "HookBomb"
	spr.position = Vector3(0.0, 26.0 * battle.WS, 0.0)   # 顶在宿主头上一点
	spr.no_depth_test = true
	spr.render_priority = 6
	# ★必须显式开 billboard —— _map_billboard 只在 additive 分支里设 billboard_mode,
	#   非 additive 走的是普通 Sprite3D, 挂到【已经在朝向相机的宿主 sprite】底下会侧着看不见。
	#   自查第一版就是这样: 门禁数得到节点(=挂上了), 画面里一个都看不见。
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	(host as Node3D).add_child(spr)
	o["_hb_bomb_spr"] = spr
	_hb_pulse(o)


## ★预兆(画面感第一条): 越接近引爆, 脉动越快、越红。
##   原来是恒定 0.45 秒一次的呼吸 —— 玩家看不出"要炸了", 引爆就成了没有铺垫的突发。
##   现在按宿主剩余血量收紧节拍(满血 0.5 秒/次 → 濒死 0.11 秒/次)并染红,
##   最后那段几乎在抖 = 观众能【预判】到要出事, 这才是紧张感的来源。
## ★每次脉动完自己排下一次(而不是 set_loops) —— 这样才能【每一拍都重新按当前血量算节奏】。
func _hb_pulse(o: Dictionary) -> void:
	var spr = o.get("_hb_bomb_spr", null)
	if not is_instance_valid(spr) or not o.get("alive", false):
		return
	if float(o.get("hookbomb_pct", 0.0)) <= 0.0:
		return
	var frac: float = clampf(float(o["hp"]) / maxf(1.0, float(o["maxHp"])), 0.0, 1.0)
	var period: float = lerpf(0.11, 0.50, frac)          # 血越少拍越急
	var hot: Color = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.42, 0.30), 1.0 - frac)
	var big: float = lerpf(1.40, 1.16, frac)             # 血越少胀得越狠
	var uu: Dictionary = o
	var tw = battle._reg_tween()
	tw.tween_property(spr, "scale", Vector3(big, big, big), period * 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(spr, "modulate", hot, period * 0.45)
	tw.tween_property(spr, "scale", Vector3.ONE, period * 0.55).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): _hb_pulse(uu))


## ① 触须/钩索【高速甩出】: 钩头从震中飞向目标, 一路留链节。
## ★参考作品的关键手感是"tentacles force themselves out at HIGH velocity" —— 所以是
##   一个真的在飞的钩头 + 拖尾, 不是原地闪一条线(我第一版就是后者, 看着像几段孤立的碎块)。
## ★钩头要【朝向飞行方向】—— billboard 贴片不会自己转, 用 _face_screen_dir(海盗钩索同款)。
## ★纯演出, 不做任何结算(结算在 _hb_blast, 走 sim 定时器)。
func _tendril_shoot(from2d: Vector2, tgt: Dictionary, idx: int) -> void:
	var to2d: Vector2 = tgt["pos"]
	var dist: float = from2d.distance_to(to2d)
	if dist < 6.0:
		return
	var tex: Texture2D = load(TEX_MINE) if ResourceLoader.exists(TEX_MINE) else null
	var hook: Sprite3D = null
	if tex != null:
		hook = Sprite3D.new()
		hook.texture = tex
		hook.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		hook.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		hook.shaded = false
		hook.transparent = true
		hook.no_depth_test = true
		hook.render_priority = 7
		hook.pixel_size = (26.0 * battle.WS) / float(maxi(1, tex.get_height()))
		hook.position = battle._world_pos(from2d, 0.95)
		battle._world.add_child(hook)
	# 飞行时长按距离算, 但夹在 [0.10, 0.22] —— 参考作品是"高速爆出", 不能慢悠悠飘过去
	var dur: float = clampf(dist / 2600.0, 0.10, 0.22)
	var acc = [0.0]
	var tw = battle._reg_tween()
	tw.tween_interval(0.02 * float(idx))          # 逐条错峰 = 一蓬触须炸开, 不是齐刷刷一条
	tw.tween_method(func(p: float) -> void:
		var cur: Vector2 = from2d.lerp(to2d, p)
		if is_instance_valid(hook):
			hook.position = battle._world_pos(cur, 0.95)
			battle._face_screen_dir(hook, from2d, to2d)
		acc[0] += 0.02
		if acc[0] >= 0.03:                         # 节流: 每隔一小段重画一次触手(它在"抽出去")
			acc[0] = 0.0
			_tendril_draw(from2d, to2d, p, battle._t * 9.0 + float(idx))
	, 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		battle._skill_ring(to2d, Color(1.0, 0.72, 0.30, 0.75), 34.0)   # 抓住的一下
		if is_instance_valid(hook):
			(hook as Node).queue_free())


## ② 带速度把目标拖回震中(照 _pirate_death_grapple: QUAD/EASE_IN = 越拉越快)。
## ★位移写回 _home_pos —— 不写的话归位逻辑会当场把人拽回原位(memory: fb-review-dummy-homing)。
func _pull_over_time(o: Dictionary, dest: Vector2) -> void:
	var start: Vector2 = o["pos"]
	var uu: Dictionary = o
	var tw = battle._reg_tween()
	# ★"先纹丝不动一下, 再猛地拽走" —— 纯加速拉缺了【阻力感】, 看着像被吸走而不是被拽走。
	#   抓住(PULL_STUN) → 再多顿 0.08 秒(绳子绷紧) → 才起拖。
	tw.tween_interval(PULL_STUN + 0.08)
	tw.tween_method(func(q: float) -> void:
		if not uu.get("alive", false):
			return
		uu["pos"] = start.lerp(dest, q)
		uu["_home_pos"] = uu["pos"]
		if int(q * 100.0) % 10 == 0:
			_tendril_draw(dest, uu["pos"], 1.0, battle._t * 9.0)   # 拖拽途中触手持续连着
	, 0.0, 1.0, PULL_DUR).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## ★★病毒触手(用户 2026-08-01:「这个钩索也做的不好，干脆做成那种病毒触手的吧」)。
##
## 之前用一节节链条贴片拼 —— 方向就错了: 参考作品(《虐杀原型2》)是【生物触须】不是铁链,
## 而且贴片拼出来的东西没有"根粗梢细"的生物感, 只能是一串等宽小方块。
##
## 现在用 ImmediateMesh 画【锥形有机带】:
##   · 沿路径取样, 宽度从根部 W_ROOT 渐收到梢部 W_TIP → 天然的触手轮廓
##   · 路径带一条正弦弯曲(振幅随进度衰减) → 甩出去时是【抽】的弧线, 不是直线
##   · 暗红肉色 + 边缘一条亮色描边 → 有体积, 不是一条色带
##   · 相位随时间滚动 → 触手在蠕动, 不是死的
## ★弯曲相位用【确定性函数】(位置+时间), 不用随机 —— 项目有 rng_discipline 门禁。
const TENT_W_ROOT := 17.0       # 根部半宽(码) —— 用户 2026-08-01:「尽量粗一点」
const TENT_W_TIP := 3.2         # 梢部半宽(码)
const TENT_SEGS := 16           # 取样段数
const TENT_BEND := 34.0         # 弯曲振幅(码) —— 粗了之后弯度也得跟上, 否则像根棍子
const TENT_BODY := Color(0.17, 0.04, 0.26)      # 紫黑肉(用户指定偏紫黑)
const TENT_RIM := Color(0.70, 0.28, 0.95)       # 边缘: 病毒紫辉

## 画一条从 from2d 抽向 to2d 的触手。t01 = 触手伸出的进度(0..1), 用来做"正在抽出去"。
func _tendril_draw(from2d: Vector2, to2d: Vector2, t01: float, phase: float) -> void:
	if battle._world == null:
		return
	var d: Vector2 = to2d - from2d
	var dist: float = d.length()
	if dist < 6.0:
		return
	var dir: Vector2 = d / dist
	var perp := Vector2(-dir.y, dir.x)
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 6      # ★render_priority 在【材质】上, MeshInstance3D 没有这个属性
	im.material_override = mat
	battle._world.add_child(im)
	var reach: float = dist * clampf(t01, 0.0, 1.0)
	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in range(TENT_SEGS + 1):
		var f: float = float(i) / float(TENT_SEGS)
		var along: float = f * reach
		# 弯曲: 越靠梢部摆得越小(根部固定在震中), 相位随时间滚 → 蠕动
		var bend: float = sin(f * PI * 1.6 + phase) * TENT_BEND * (1.0 - f) * f * 4.0
		var p: Vector2 = from2d + dir * along + perp * bend
		var w: float = lerpf(TENT_W_ROOT, TENT_W_TIP, f)
		var l3: Vector3 = battle._world_pos(p + perp * w, 0.85)
		var r3: Vector3 = battle._world_pos(p - perp * w, 0.85)
		if i > 0:
			var cb := TENT_BODY.lerp(TENT_RIM, f * 0.55)
			cb.a = 0.95 * (1.0 - f * 0.25)
			imesh.surface_set_color(cb); imesh.surface_add_vertex(prev_l)
			imesh.surface_set_color(cb); imesh.surface_add_vertex(prev_r)
			imesh.surface_set_color(cb); imesh.surface_add_vertex(r3)
			imesh.surface_set_color(cb); imesh.surface_add_vertex(prev_l)
			imesh.surface_set_color(cb); imesh.surface_add_vertex(r3)
			imesh.surface_set_color(cb); imesh.surface_add_vertex(l3)
		prev_l = l3
		prev_r = r3
	imesh.surface_end()
	# 沿两侧各描一条亮边 = 体积感(纯色带看着是贴纸)
	for side in [1.0, -1.0]:
		imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for i in range(TENT_SEGS + 1):
			var f2: float = float(i) / float(TENT_SEGS)
			var bend2: float = sin(f2 * PI * 1.6 + phase) * TENT_BEND * (1.0 - f2) * f2 * 4.0
			var p2: Vector2 = from2d + dir * (f2 * reach) + perp * bend2
			var w2: float = lerpf(TENT_W_ROOT, TENT_W_TIP, f2)
			var cr := TENT_RIM
			cr.a = 0.85 * (1.0 - f2 * 0.4)
			imesh.surface_set_color(cr)
			imesh.surface_add_vertex(battle._world_pos(p2 + perp * (w2 * side), 0.87))
		imesh.surface_end()
	var tw = battle._reg_tween()
	tw.tween_interval(0.06)
	tw.tween_property(im, "transparency", 1.0, 0.16)
	tw.tween_callback(im.queue_free)


# ============================================================================
#  累加滚动计数器 (用户 2026-08-01 指定的显示方式)
# ============================================================================
## 用户原话:「每秒这个数字不断增大…第一秒跳到20，然后0.几秒数字逐渐滚动到40」+「跟着走」「要合并」。
## 即: 宿主头上【常驻一个数字】= 这颗(或多颗)炸弹到目前为止的累计伤害; 每秒不是蹦新字, 是滚动到新值。
## ★不用 _float_text: 那是一次性弹出就消失的飘字, 语义是"这一下多少"; 这里要"到现在一共多少"。
## ★用 Label3D: 挂在宿主 sprite 之下【自动跟随】, 宿主没了它一起没, 不留孤儿。
const NUM_ROLL_SEC := 0.32
const NUM_COL := Color(1.0, 0.62, 0.24)

func _hb_counter_refresh(o: Dictionary) -> void:
	var host = o.get("sprite", null)
	if not is_instance_valid(host):
		return
	var lbl: Label3D = o.get("_hb_num", null)
	if not is_instance_valid(lbl):
		lbl = Label3D.new()
		lbl.name = "HookBombNum"
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.render_priority = 9
		lbl.modulate = NUM_COL
		lbl.outline_modulate = Color(0.10, 0.03, 0.0, 0.95)
		lbl.outline_size = 8
		lbl.font_size = 64
		lbl.pixel_size = 0.0042
		lbl.position = Vector3(0.0, 44.0 * battle.WS, 0.0)
		(host as Node3D).add_child(lbl)
		o["_hb_num"] = lbl
		o["hookbomb_shown"] = 0.0
	var from_v: float = float(o.get("hookbomb_shown", 0.0))
	var to_v: float = float(o.get("hookbomb_total", 0.0))
	if to_v <= from_v:
		return
	var uu: Dictionary = o
	var tw = battle._reg_tween()
	tw.tween_method(func(v: float) -> void:
		if not is_instance_valid(lbl):
			return
		uu["hookbomb_shown"] = v
		lbl.text = str(int(round(v)))
	, from_v, to_v, NUM_ROLL_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "scale", Vector3(1.22, 1.22, 1.22), NUM_ROLL_SEC * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "scale", Vector3.ONE, NUM_ROLL_SEC * 0.5).set_trans(Tween.TRANS_SINE)
