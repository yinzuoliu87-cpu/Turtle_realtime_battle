class_name HookBombSystem
extends RefCounted
## 靶向器 p2eq_055 ·【钩索炸弹】(用户 2026-08-01 整条重做)
##
## 用户原文:「携带者在首次造成了400点伤害后，会向最近的1/1/2名敌人发射钩索炸弹，
##   炸弹会附在敌人身上并每秒对该敌人造成2/4/4%物理伤害，持续到敌人死亡时，
##   如果敌人带有炸弹的时候死亡，则会朝所有敌方单位发射钩索，眩晕0.5秒后把他们拉向自己，
##   ★以上是 2026-08-01 的【原始需求原文】, 保留作记录。2026-08-02 用户调过两个数:
##     每秒百分比【整条翻倍】(一星原为 1、二三星原为 2, 现为 2/4/4);
##     眩晕由半秒提到 1.1 秒(「触手伸出去定住的时间还要久点」)。
##   ★上面那段原文里的数字已【就地更新为现行值】—— 不留过期字面量:
##     tooltip_number_audit 是【文本扫描】, 源码里留着旧三元组会被当成"代码值"判分歧;
##     更要紧的是下一个人可能反过来"照注释改代码"。历史用散文记, 不用数字记。
##     现行值一律以下面的常量为准, 别照这段原文改代码。
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
##   · 每秒 2/4/4% 物理伤害 → 按【宿主自身 maxHp】的百分比。与骷髅爆炸(032)同口径:
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
## 每秒对宿主造成其 maxHp 的 2/4/4%(用户 2026-08-02:「每秒损失2%生命值改为损失4%最大生命值」)。
## ★整条翻倍而不是只改 2★/3★ —— 用户报的是文案上那个 2%(=2★/3★ 档), 星级曲线保持原样。
const BOMB_DPS_PCT := [0.02, 0.04, 0.04]
const BOMB_TICK := 1.0                        # "每秒"
const BLAST_FLAT := [200.0, 400.0, 500.0]     # 聚爆固定段
const BLAST_MAXHP_PCT := 0.10                 # 聚爆额外 10% 最大生命
## 触须抓住后【定住】多久才开始拖。★0.5 → 1.1(用户 2026-08-02:「触手伸出去定住的时间还要久点」)。
## 这段是"缠住了但还没拉"的僵持, 拖拽本身另算(恒速, 见 PULL_SPEED)。
const PULL_STUN := 1.1
## ★★触须【收缩速度恒定】, 不是"所有人都用同一个时长"(用户 2026-08-01 追问 逻辑合不合理)。
##   我第一版写死 PULL_DUR=0.42 秒: 600 码外的走 515 码、100 码外的走 15 码, 都是 0.42 秒
##   ⇒ 同一条触须的收缩速度差 34 倍, 远的像被弹射、近的像飘过来。
##   绳子/触须往回收就是个恒速卷绕, 距离远只会【拉得更久】。
## ★钳位要【宽到实战距离用不上】: 第一版 900码/秒 + [0.14,0.60] 一测就露 ——
##   900 码撞上限、200 码撞下限, 两端全在钳位区, 实测收缩速度 1358 vs 821 码/秒,
##   "恒速"只存在于常量名里。现在 1400 码/秒 + [0.08,0.85] 覆盖到 1190 码位移
##   (≈整个战场), 钳位只兜住理论极值。
const PULL_SPEED := 1400.0                    # 码/秒 —— 触须收缩速度(恒定)
const PULL_DUR_MIN := 0.08                    # 贴脸时也别一帧到位
const PULL_DUR_MAX := 0.85                    # 理论极值兜底(实战距离到不了)
## 宿主 0 血后【抽搐】多久才炸开(人体炸弹的铺垫)。
## ★0.62 → 2.0(用户 2026-08-02:「抖动得2秒钟」)。抖动曲线是按 t01 归一化的, 拉长不用改幅度公式,
##   但【尸体在这 2 秒里会被 _kill 的死亡淡出收走】—— 见 _convulse 里那段 visible/alpha 覆写。
const CONVULSE_SEC := 2.0
## ★★聚拢半径必须【大于单位软分离半径 SEP_RADIUS(92 码)】。
##   85 < 92 ⇒ 拉到位的瞬间每只都嵌在别人的分离圈里, 拉力和分离力当场打架,
##   实拍出来四只龟糊成一坨、和爆炸糊在一起分不出谁是谁(用户 2026-08-01 截图指出)。
##   145 ≈ 1.6×分离半径: 围成一圈还各是各, 又全在爆炸火球(直径 300 码)内。
const PULL_GATHER_R := 145.0


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
##   位移走 tween 在【各自的】拉拽时长内推进(照 _pirate_death_grapple 那套 QUAD/EASE_IN = 越拉越快),
##   而【伤害结算】走 battle._pending_shots(sim 驱动·无头稳), 不挂在 tween 末尾 ——
##   CLAUDE.md §3.5: 数值不能依赖演出 tween 跑完。
##
## 返回被卷入的单位数(供门禁当分母; N=0 是空检查不是通过)。
func _hb_detonate(carrier: Dictionary, si: int, epicenter_in = null, husk_in = null) -> int:
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
	var slowest: float = PULL_DUR_MIN
	carrier["_hb_detonated_n"] = int(carrier.get("_hb_detonated_n", 0)) + 1   # 同步触发证据(供门禁)
	# ★静一拍(画面感第二条): 触须爆出的瞬间定格一下。冲击前的停顿比冲击本身更重要 ——
	#   没有它, "炸"会淹在持续的战斗噪音里; 有了它, 观众的眼睛会被强行拽到这一点上。
	#   0.14 秒: 比团灭(0.30)短、比开打起势(0.18)略短 —— 这是"一次装备触发"该有的量级, 不能喧宾夺主。
	battle._add_hitstop(0.14)
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	battle._skill_ring(epi, Color(1.0, 0.55, 0.22, 0.9), 90.0)
	for i in range(n):
		var o: Dictionary = list[i]
		var dest: Vector2 = _hb_pull_dest_at(epi, o["pos"] as Vector2)   # ★沿它自己的方位拖近
		var dur: float = _hb_pull_dur(o["pos"] as Vector2, dest)         # ★远的拉得久(恒速)
		slowest = maxf(slowest, dur)
		battle._damage._stun(o, PULL_STUN + dur, "hookbomb")         # 晕住整段: 抓住→拖回都不该乱跑
		# ① 触须高速爆出→抓住→【全程连着】直到炸开(hold 覆盖 眩晕+绷紧+拖拽)
		#   ★根部【扇开】: 全从同一点出发的话, n 条满宽触手在根部会叠成一整块紫板(实拍确认)。
		#     各自从伤口边缘偏出去一点, 方向按自己的朝向左右交替 —— 一蓬, 不是一坨。
		var away: Vector2 = ((o["pos"] as Vector2) - epi).normalized()
		if away.length() < 0.5:
			away = Vector2.RIGHT
		var root2d: Vector2 = epi + away.rotated(0.62 if (i % 2) == 0 else -0.62) * 17.0
		_tendril_shoot(root2d, o, i, PULL_STUN + 0.08 + dur)
		_pull_over_time(o, dest, dur)                                # ② 恒速拖回震中
	# ③ 聚拢后一次爆炸 —— 走 sim 定时器, 不是 tween
	var cc: Dictionary = carrier
	var lst: Array = list
	var sii: int = si
	var ep2: Vector2 = epi
	# ★等【最慢的那条触须】收完再炸 —— 否则最远那只还在半路上就爆了, 白拉一趟
	_pending.append({"t": PULL_STUN + slowest, "fn": func(): _hb_blast(cc, lst, sii, ep2)})
	# ★病毒巢: 触手的【来源物】, 活到爆炸那一刻(否则触手从虚空长出来)
	_virus_nest(epi, PULL_STUN + slowest)
	_husk_writhe(husk_in, PULL_STUN + slowest)
	return n


## 聚拢后的那一下爆炸(纯结算 —— 门禁直接调它, 不等任何演出)。
func _hb_blast(carrier: Dictionary, list: Array, si: int, epi: Vector2) -> int:
	var hit := 0
	for oi in range(list.size()):
		var o = list[oi]
		if not (o is Dictionary) or not o.get("alive", false):
			continue
		var dmg: int = maxi(1, int(round(BLAST_FLAT[si] + float(o["maxHp"]) * BLAST_MAXHP_PCT)))
		# ★no_popup: 聚拢后所有人挤在同一小片区域, 同帧四个 "800" 会精确叠成一团糊字
		#   (用户 2026-08-01 截图指出)。改成自己发飘字: 按序号【放射状错开 + 错峰半拍】。
		# 位置参数顺序: extra_ls, raw, from_equip, pre_crit, no_dodge, no_popup —— ★最后一个才是 no_popup。
		#   我少写一个 false, no_popup 落到了 no_dodge 上 ⇒ 通用红字根本没关, 和自发飘字【双份】
		#   (实拍: 4 个目标出了 5 个数字、大小还不一样)。
		battle._damage._apply_damage_from(carrier, o, dmg, Color("#ff5a2a"), 0.0, false, true, false, false, true)
		var ang: float = TAU * float(oi) / maxf(1.0, float(list.size())) - PI * 0.5
		var off := Vector2(cos(ang), sin(ang)) * 108.0 + Vector2(0.0, -30.0)   # ★108: 62 挡不住大字号的 800 互相压
		var pp: Vector2 = (o["pos"] as Vector2) + off
		var dd: int = dmg
		_pending.append({"t": 0.035 * float(oi), "fn": func():
			battle._vfx._float_text(pp, str(dd), Color("#ff8a3a"), false, "damage", "physical", ang)})
		hit += 1
	# ★真爆炸演出(用户 2026-08-01:「炸的特效？你啥都不做吗」——之前只有一个圆环+震屏+粒子)。
	#   三层叠: ①主爆火球(大·快胀快消) ②滞后半拍的第二团(错位=有体积) ③冲击环+震屏。
	# ★火球半径盖住整个聚拢圈(聚拢半径 145)。程序化, 不是贴图 —— 理由见 _fireball 头注。
	_fireball(epi, 228.0, 0.58)
	_pending.append({"t": 0.10, "fn": func(): _fireball(epi + Vector2(58.0, -40.0), 152.0, 0.42)})  # 错位第二团 = 有体积
	# 小尺寸的手绘火花贴在最亮那一刻 —— 尺寸小(110码≈2.6米)不会被地板切, 补一点像素颗粒感
	battle._burst_vfx(TEX_BLAST, epi, 110.0, 1.35)
	battle._skill_ring(epi, Color(1.0, 0.45, 0.2, 0.95), 250.0)
	_pending.append({"t": 0.13, "fn": func(): battle._skill_ring(epi, Color(1.0, 0.85, 0.45, 0.7), 340.0)})
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	battle._particle_burst(epi)
	return hit


## 聚拢落点(纯几何 —— 门禁验这个, 不等拉拽跑完)。
##
## ★★2026-08-01 修(用户:「你硬要把目的地摆出上下左右是吗，这在你觉得逻辑上是没有任何问题是吗」):
##   我第一版按【序号】把人均匀摆到震中周围一圈(0号在右、1号在右上…)——
##   那意味着一个站在【左边】的敌人会被"拽"到【右边】去。那不是拉拽, 那是排队站位。
##   触须抓住你往回拖, 你只会【沿着你自己所在的方向】被拖近, 不会绕到对面。
##   正解: 沿【它自己相对震中的方位】拖到聚拢半径, 谁从哪来就留在哪一侧。
## ★"别叠成一坨"不需要靠分配槽位来解决 —— 战场每帧跑 _apply_separation_pass 软分离,
##   同方位的两只会自然被推开。用槽位去解决重叠, 是拿逻辑错误换一个本来就不存在的问题。
## ★★触须只把人【拽近】, 不会把人【顶开】(同一次追问查出来的第二个):
##   原来无条件 `epi + 方向×85` = 摆到半径 85 的圈上。站在震中 40 码的敌人会被往【外】推 45 码。
##   已经比聚拢半径近的, 就该原地不动。
func _hb_pull_dest_at(epi: Vector2, from_pos: Vector2) -> Vector2:
	var d: Vector2 = from_pos - epi
	var dist: float = d.length()
	if dist <= PULL_GATHER_R:
		return from_pos            # 已经够近 —— 触须不会把你往外顶
	return epi + (d / dist) * PULL_GATHER_R


## 这一拉要花多久 = 实际位移 / 恒定收缩速度。
func _hb_pull_dur(from_pos: Vector2, dest: Vector2) -> float:
	return clampf(from_pos.distance_to(dest) / PULL_SPEED, PULL_DUR_MIN, PULL_DUR_MAX)





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
	var husk = o.get("sprite", null)      # ★尸壳 = 宿主自己的立绘, 触手的来源物
	_pending.append({"t": CONVULSE_SEC, "fn": func(): _hb_detonate(srcd, si, epi, husk)})


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
		# ★★压住 _kill 的死亡淡出(用户 2026-08-02:「尸体应该在那里啊」)。
		#   _kill 里有一条【独立】的 tween: sprite.modulate:a → 0 (0.4 秒) 然后 hide()。
		#   我原来每帧只写 modulate 的 RGB, 压不住那个 hide() ⇒ 抽搐没演完尸体就没了。
		#   (之前截图里根部那团紫是【病毒巢】不是尸体, 我把它当成尸体在场了。)
		#   每帧强制 visible=true + alpha=1 是确定性的: 后写的赢, 与两条 tween 的先后无关。
		(spr as Node3D).visible = true
	, 0.0, 1.0, CONVULSE_SEC)
	tw.tween_callback(func() -> void:
		# ★★② 撑爆 —— 但【尸体不消失】(用户 2026-08-01 截图:「压根和人物中心没配合」)。
		#   我第一版在这里 visible=false, 于是触手是从【地面一个空点】长出来的, 没有来源物, 像贴图。
		#   人体炸弹的来源就是【那具尸体】: 现在留下一具深紫色的瘪壳, 触手从它身上抽出去,
		#   它一路抽动到爆炸才和它一起没。
		if is_instance_valid(spr):
			(spr as Sprite3D).modulate = Color(0.42, 0.16, 0.56)      # 病毒化: 整只染成紫黑
			(spr as Node3D).scale = Vector3(base_sc.x * 1.16, base_sc.y * 0.60, base_sc.z)  # 泄了气的壳
			(spr as Node3D).position = base_pos)


## ★★程序化火球(2026-08-01 实拍换掉贴图版)。
## 换掉的理由是【实拍量出来的】, 不是审美偏好:
##   `_burst_vfx(TEX_BLAST, epi, 320.0, 0.55)` 把一张 320 码(=7.68 米)的竖直公告板挂在 y=0.55 米,
##   下半截 3.3 米【埋进地板里】→ 截图上火球有一条笔直的底边和左边, 一眼就是贴上去的方块。
##   把高度抬上去能解决裁切, 但 7.68 米高的竖板会像一堵墙立在 0.77 米高的龟旁边。
## 现在: 和触手/病毒巢同一套【朝向镜头的网格】——
##   · 6 团错位的不规则火舌(极径扰动, 不是正圆) + 一颗白心, 各自胀开速度不同 ⇒ 有体积、有翻滚
##   · 整体压成【扁椭圆】(纵向 0.66) 并把底边坐在地面上 ⇒ 是"贴地炸开"不是"竖着一张画"
##   · 颜色随时间走 白心 → 黄 → 橙 → 暗烟, 边缘先冷下来(真实火球就是这么熄的)
const FIRE_LOBES := 6
const FIRE_SIDES := 26
const FIRE_SQUASH := 0.66        # 纵向压扁 = 贴地感(地面在镜头里本来就被压到 0.595)
func _fireball(epi: Vector2, r_yards: float, life: float) -> void:
	if battle._world == null or battle._cam == null:
		return
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD      # 加色: 火是发光的, 不是不透明颜料
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true                             # ★不参与深度 = 不会被地板/台阶切掉
	mat.render_priority = 9
	im.material_override = mat
	battle._world.add_child(im)
	var R: float = r_yards * battle.WS
	var tw = battle._reg_tween()
	tw.tween_method(func(q: float) -> void:
		if not is_instance_valid(im):
			return
		imesh.clear_surfaces()
		var t: float = q * life
		# 胀开: 极快起势(0.12 秒到八成)再缓慢外扩 —— 爆炸的力量感全在这条曲线上
		var grow: float = (1.0 - pow(1.0 - clampf(t / 0.12, 0.0, 1.0), 3.0)) * 0.80 + q * 0.34
		var fade: float = clampf(1.0 - pow(q, 1.35), 0.0, 1.0)   # 收得快一点: 爆炸是一瞬, 不是一直烧
		var cy: float = R * grow * FIRE_SQUASH * 0.92      # 球心抬到半高 ⇒ 底边刚好坐在地上
		var c0: Vector3 = battle._world_pos(epi, cy)
		var to_cam: Vector3 = (battle._cam.global_position - c0).normalized()
		var ax: Vector3 = Vector3.UP.cross(to_cam)
		if ax.length() < 0.0001:
			ax = Vector3.RIGHT
		ax = ax.normalized()
		var ay: Vector3 = to_cam.cross(ax).normalized() * FIRE_SQUASH
		# 由外向内画: 暗烟 → 橙 → 黄 → 白心 (后画的盖在前面 = 层次)
		for li in range(FIRE_LOBES + 1):
			var inner: bool = li == FIRE_LOBES
			var la: float = TAU * float(li) / float(FIRE_LOBES) + t * 0.9
			var lr: float = 0.0 if inner else R * grow * 0.44
			var lc: Vector3 = c0 + (ax * cos(la) + ay * sin(la)) * lr
			var rad: float = R * grow * (0.30 if inner else lerpf(0.62, 0.50, q))
			# 颜色: 内核最亮最久, 外圈先冷
			var col: Color
			if inner:
				col = Color(1.0, 0.97, 0.80).lerp(Color(1.0, 0.62, 0.16), clampf(q * 1.6, 0.0, 1.0))
			else:
				var heat: float = clampf(q * 1.25 + float(li) * 0.045, 0.0, 1.0)
				col = Color(1.0, 0.52, 0.09).lerp(Color(0.40, 0.08, 0.02), heat)   # 更橙: 加色下才不会一叠就白
			# ★★径向剖面分三层, 不是"中心不透明→边缘 0"的线性衰减。
			#   线性衰减(我第一版)= 亮度铺得又宽又淡 ⇒ 实拍只看得见中间那颗白心, 外层火舌全是
			#   一层薄雾, 还把底下的紫色触手加色染成了粉红(截图确认)。
			#   现在: 0~62% 满亮(实心火) / 62~86% 半亮 / 86~100% 收到 0(软边)。
			# ★alpha 要按"6 团加色会互相叠加"来定, 不是单团好看就行。
			#   0.80 那版实拍整片过曝成白, 把龟都冲没了(截图确认)。
			var a_core: float = fade * (0.82 if inner else 0.42)
			var BANDS := [0.0, 0.62, 0.86, 1.0]
			var ALPHA := [a_core, a_core, a_core * 0.55, 0.0]
			imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
			for bi in range(BANDS.size() - 1):
				var r0: float = float(BANDS[bi])
				var r1: float = float(BANDS[bi + 1])
				var cA := col; cA.a = float(ALPHA[bi])
				var cB := col; cB.a = float(ALPHA[bi + 1])
				var p0l := Vector3.ZERO
				var p0r := Vector3.ZERO
				for k in range(FIRE_SIDES + 1):
					var a: float = TAU * float(k) / float(FIRE_SIDES)
					# 极径扰动: 火舌。相位随时间滚 ⇒ 在翻滚, 不是一个静止的圆
					var wob: float = 1.0 + sin(a * 3.0 + t * 5.5 + float(li)) * 0.26 						+ sin(a * 6.0 - t * 3.4 + float(li) * 2.1) * 0.13
					var dirv: Vector3 = ax * cos(a) + ay * sin(a)
					var q0: Vector3 = lc + dirv * (rad * wob * r0)
					var q1: Vector3 = lc + dirv * (rad * wob * r1)
					if k > 0:
						imesh.surface_set_color(cA); imesh.surface_add_vertex(p0l)
						imesh.surface_set_color(cB); imesh.surface_add_vertex(p0r)
						imesh.surface_set_color(cB); imesh.surface_add_vertex(q1)
						imesh.surface_set_color(cA); imesh.surface_add_vertex(p0l)
						imesh.surface_set_color(cB); imesh.surface_add_vertex(q1)
						imesh.surface_set_color(cA); imesh.surface_add_vertex(q0)
					p0l = q0
					p0r = q1
			imesh.surface_end()
	, 0.0, 1.0, maxf(0.1, life))
	tw.tween_callback(im.queue_free)


## 尸壳抽动: 触手在往外抽, 壳会跟着一颤一颤地泄下去。活到爆炸那一刻。
func _husk_writhe(spr, life: float) -> void:
	if not is_instance_valid(spr):
		return
	var base_sc: Vector3 = (spr as Node3D).scale
	var tw = battle._reg_tween()
	tw.tween_method(func(q: float) -> void:
		if not is_instance_valid(spr):
			return
		var t: float = q * life
		var jolt: float = sin(t * 21.0) * 0.09 + sin(t * 7.0) * 0.05     # 一颤一颤
		var deflate: float = lerpf(1.0, 0.88, q)   # 轻微泄气 —— 用户要"尸体还在那", 瘪成 0.72 就不像尸体了
		(spr as Node3D).scale = Vector3(base_sc.x * (deflate + jolt * 0.6), base_sc.y * (deflate - jolt), base_sc.z)
		(spr as Sprite3D).modulate = Color(0.42, 0.16, 0.56).lerp(Color(0.16, 0.05, 0.22), q)
		(spr as Node3D).visible = true        # ★同上: 压住死亡淡出的 hide(), 尸体要留到聚拢引爆
	, 0.0, 1.0, maxf(0.1, life))
	tw.tween_callback(func() -> void:
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
## ★★hold = 甩出去【之后】还要连多久(眩晕 + 绷紧 + 拖拽)。
##   我第一版抓住那一下就 queue_free + 停止重画 ⇒ 后面近 1 秒的拖拽【全程没有触须】,
##   人是自己滑向震中的 —— 那正是"被吸走"而不是"被拽走"。
##   触须必须一直连着, 并且【跟着目标当前位置】重画: 目标被拖近 ⇒ 带子自然变短 = 收缩。
func _tendril_shoot(from2d: Vector2, tgt: Dictionary, idx: int, hold: float) -> void:
	var tip_h: float = TENT_ANCHOR_H + float(tgt.get("height", 0.0))
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
		hook.position = battle._world_pos(from2d, TENT_ANCHOR_H)
		battle._world.add_child(hook)
	# 飞行时长按距离算, 但夹在 [0.10, 0.22] —— 参考作品是"高速爆出", 不能慢悠悠飘过去
	var dur: float = clampf(dist / 2600.0, 0.10, 0.22)
	var acc = [0.0]
	var tw = battle._reg_tween()
	tw.tween_interval(0.02 * float(idx))          # 逐条错峰 = 一蓬触须炸开, 不是齐刷刷一条
	tw.tween_method(func(p: float) -> void:
		var cur: Vector2 = from2d.lerp(to2d, p)
		if is_instance_valid(hook):
			hook.position = battle._world_pos(cur, tip_h)
			battle._face_screen_dir(hook, from2d, to2d)
		acc[0] += 0.02
		if acc[0] >= 0.03:                         # 节流: 每隔一小段重画一次触手(它在"抽出去")
			acc[0] = 0.0
			_tendril_draw(from2d, to2d, p, battle._t * 9.0 + float(idx), tip_h)
	, 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		battle._skill_ring(to2d, Color(1.0, 0.72, 0.30, 0.75), 34.0))  # 抓住的一下
	# ★缠住期 + 收缩期: 始终画到目标的【实时位置】。钩头钉在目标身上一起被拖回来。
	var tt: Dictionary = tgt
	tw.tween_method(func(p: float) -> void:
		var cur: Vector2 = tt.get("pos", to2d)
		if is_instance_valid(hook):
			hook.position = battle._world_pos(cur, TENT_ANCHOR_H + float(tt.get("height", 0.0)))
			battle._face_screen_dir(hook, from2d, cur)
		acc[0] += 0.016
		if acc[0] >= 0.03:
			acc[0] = 0.0
			_tendril_draw(from2d, cur, 1.0, battle._t * 9.0 + float(idx), TENT_ANCHOR_H + float(tt.get("height", 0.0)))
	, 0.0, 1.0, maxf(0.05, hold))
	tw.tween_callback(func() -> void:
		if is_instance_valid(hook):
			(hook as Node).queue_free())


## ② 带速度把目标拖回震中(照 _pirate_death_grapple: QUAD/EASE_IN = 越拉越快)。
## ★位移写回 _home_pos —— 不写的话归位逻辑会当场把人拽回原位(memory: fb-review-dummy-homing)。
func _pull_over_time(o: Dictionary, dest: Vector2, dur: float) -> void:
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
	, 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


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
## ★★2026-08-01 重做(用户:「太粗了吧，而且压根和人物中心没配合，就像个贴图，颜色也像个贴图」)。
## 三条批评根因【是同一个】: 老实现把宽度加在【地面 2D 垂线】上再整条抬到固定高 0.85 ——
## 那是一条【平躺在地板上的带子】。实测摄像机在 (0,18.9,25.5)、地面仰角 36.5° ⇒
##   · 斜视角看平带 = 一张贴在地上的图(「像贴图」)
##   · z 方向被压扁到 0.595 倍 ⇒ 同一条触手【横着画和竖着画粗细不一样】
##   · 两端钉在脚下投影点的固定高度 ⇒ 和龟的身体中心对不上(「没配合」)
## 现在: 朝向摄像机的【管状带】—— 宽度方向 = tangent × 指向相机, 永远正对镜头,
##   横截面 5 条(暗边→肉→高光脊→肉→暗边)造出圆柱感, 两端锚在【身体中心高度】,
##   中段在 Y 上拱起 ⇒ 它是一根穿过空间的立体物件, 不是地面贴纸。
const TENT_W_ROOT := 9.5       # 根部半宽(码)。★正对镜头后不再被压扁, 22 码全宽 ≈ 龟身(92)的 24%
const TENT_W_TIP := 3.0         # 梢部半宽(码)
const TENT_SEGS := 22           # 取样段数(拱起+鼓包要够密才顺滑)
const TENT_BEND := 30.0         # 侧向弯曲振幅(码)
const TENT_ARCH := 0.62         # ★中段在【Y 轴】拱起(米) —— 平面弯曲救不了"贴图感", 立体拱起可以
const TENT_BULGE := 0.22        # 粗细沿长度的有机鼓包比例(肌肉节)
const TENT_ANCHOR_H := 1.05     # 两端锚定高度(米) = 龟身体中心(血条头顶 2.4 的中段)
# 横截面配色: 边缘几乎全黑 → 紫黑肉 → 一条偏亮的病毒高光脊。纯色带 = 贴纸, 有横截面梯度 = 管子
const TENT_EDGE := Color(0.045, 0.010, 0.075)   # 暗边(轮廓)
const TENT_BODY := Color(0.175, 0.035, 0.255)   # 紫黑肉
const TENT_RIDGE := Color(0.475, 0.165, 0.700)  # 高光脊(病毒紫)。★压暗: 0.615/0.88 那版通体发亮
const TENT_RIM := Color(0.70, 0.28, 0.95)       # 梢部/钩头辉光

## 画一条从 from2d 抽向 to2d 的触手。t01 = 触手伸出的进度(0..1), 用来做"正在抽出去"。
## tip_h: 梢部锚定高度(米)。★要带上目标自己的 height —— 被击飞/浮空的单位若按 0 算,
##   触手会连到它【脚底下的空气】里。锚定高度取值遵循项目既定口径(打在身上 = 0.6~1.0 米)。
func _tendril_draw(from2d: Vector2, to2d: Vector2, t01: float, phase: float, tip_h: float = TENT_ANCHOR_H) -> void:
	if battle._world == null or battle._cam == null:
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
	var cam_p: Vector3 = battle._cam.global_position

	# ── ① 先把【脊线】采出来(世界坐标), 顺带记录每点的半宽
	var spine: Array[Vector3] = []
	var half: Array[float] = []
	for i in range(TENT_SEGS + 1):
		var f: float = float(i) / float(TENT_SEGS)
		# 侧向蠕动: 根梢两端收紧(钉在两个身体上), 中段摆幅最大
		var bend: float = sin(f * PI * 1.6 + phase) * TENT_BEND * (1.0 - f) * f * 4.0
		var p2: Vector2 = from2d + dir * (f * reach) + perp * bend
		# ★Y 方向拱起 —— 这一条是"立体"与"贴纸"的分界。两端锚在身体中心高度。
		var h: float = lerpf(TENT_ANCHOR_H, tip_h, f) + sin(f * PI) * TENT_ARCH + sin(f * 9.0 + phase * 1.3) * 0.05
		spine.append(battle._world_pos(p2, h))
		# 有机鼓包: 粗细不是平滑锥形, 一节一节像肌肉
		var bulge: float = 1.0 + sin(f * 11.0 + phase * 1.7) * TENT_BULGE
		# ★出口【收颈】: 从伤口钻出来的那一小段是最细的, 出来一点才鼓成最粗。
		#   不收颈 ⇒ 几条触手在根部都是满宽, 叠成一整块紫板(实拍确认)。
		var neck: float = 1.0 if f > 0.12 else lerpf(0.42, 1.0, f / 0.12)
		half.append(lerpf(TENT_W_ROOT, TENT_W_TIP, f * f) * bulge * neck * battle.WS)

	# ── ② 沿脊线铺【正对镜头】的管状带: 横截面 5 条, 暗边→肉→高光脊→肉→暗边
	#     偏移方向 = 切线 × 指向相机 ⇒ 无论触手朝哪个方向, 看上去都一样粗(不再被 z 压扁)
	# ★★横截面 7 条, 高光脊【很窄】(0.02~0.30 之间那一小条)。
	#   第一版 5 条、高光从 -0.45 一路插值到 0.62 = 半条触手都在发亮 ⇒ 通体亮紫, 像塑料管,
	#   不是用户要的"紫黑"。真实的湿肉只有一道细窄反光, 其余全是暗部。
	var OFF := [-1.0, -0.74, -0.26, 0.02, 0.30, 0.70, 1.0]
	var COL := [TENT_EDGE, TENT_EDGE.lerp(TENT_BODY, 0.6), TENT_BODY, TENT_RIDGE,
				TENT_BODY, TENT_BODY.lerp(TENT_EDGE, 0.55), TENT_EDGE]
	var rings: Array = []
	for i in range(spine.size()):
		var tang: Vector3 = (spine[mini(i + 1, spine.size() - 1)] - spine[maxi(i - 1, 0)])
		if tang.length() < 0.0001:
			tang = Vector3(dir.x, 0.0, dir.y)
		var to_cam: Vector3 = (cam_p - spine[i]).normalized()
		var side: Vector3 = tang.normalized().cross(to_cam)
		if side.length() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var ring: Array = []
		for k in range(OFF.size()):
			ring.append(spine[i] + side * (half[i] * float(OFF[k])))
		rings.append(ring)
	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for i in range(1, rings.size()):
		var f: float = float(i) / float(TENT_SEGS)
		var a_fade: float = 0.97 * (1.0 - f * 0.18)
		for k in range(OFF.size() - 1):
			var c0: Color = COL[k];      c0.a = a_fade
			var c1: Color = COL[k + 1];  c1.a = a_fade
			var pl: Vector3 = rings[i - 1][k]
			var pr: Vector3 = rings[i - 1][k + 1]
			var nl: Vector3 = rings[i][k]
			var nr: Vector3 = rings[i][k + 1]
			imesh.surface_set_color(c0); imesh.surface_add_vertex(pl)
			imesh.surface_set_color(c1); imesh.surface_add_vertex(pr)
			imesh.surface_set_color(c1); imesh.surface_add_vertex(nr)
			imesh.surface_set_color(c0); imesh.surface_add_vertex(pl)
			imesh.surface_set_color(c1); imesh.surface_add_vertex(nr)
			imesh.surface_set_color(c0); imesh.surface_add_vertex(nl)
	imesh.surface_end()
	# ── ③ 沿高光脊描一条细亮线 = 湿润的反光(管子最后一点体积感)
	imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for i in range(rings.size()):
		var f3: float = float(i) / float(TENT_SEGS)
		var cr := TENT_RIDGE.lerp(TENT_RIM, f3)
		cr.a = 0.55 * (1.0 - f3 * 0.5)
		imesh.surface_set_color(cr)
		imesh.surface_add_vertex(rings[i][2])
	imesh.surface_end()
	var tw = battle._reg_tween()
	tw.tween_interval(0.06)
	tw.tween_property(im, "transparency", 1.0, 0.16)
	tw.tween_callback(im.queue_free)


## ★★病毒巢(用户 2026-08-01 截图:「压根和人物中心没配合」的另一半)。
## 宿主炸开后尸体就没了 ⇒ 实拍里触手是【从地面一个空点长出来的】, 没有来源物, 像贴图。
## 现在在震中留一团搏动的病毒肉块: 触手从它身上抽出去, 它随时间搏动/长大, 爆炸时一起消失。
## 形状用【非圆】的极径扰动(3 次谐波 + 5 次谐波, 相位随时间滚) —— 正圆一眼假。
const NEST_R := 22.0            # 基准半径(码)。★46 太大(扰动后直径 136 > 龟身 92),
                                #   实拍是"地上一大坨紫"。它只是尸壳上的【爆口】, 主体是尸壳本身。
const NEST_SIDES := 30
func _virus_nest(epi: Vector2, life: float) -> void:
	if battle._world == null or battle._cam == null:
		return
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 5          # 比触手(6)低一档 → 触手压在巢上面, 像从里面抽出来
	im.material_override = mat
	battle._world.add_child(im)
	var tw = battle._reg_tween()
	tw.tween_method(func(q: float) -> void:
		if not is_instance_valid(im):
			return
		imesh.clear_surfaces()
		var t: float = q * life
		var grow: float = clampf(t / 0.14, 0.0, 1.0)                       # 破体而出: 瞬间涨开
		var pulse: float = 1.0 + sin(t * 12.0) * 0.10 + sin(t * 5.0) * 0.05  # 搏动
		var rr: float = NEST_R * grow * pulse * battle.WS
		var c: Vector3 = battle._world_pos(epi, TENT_ANCHOR_H)
		var to_cam: Vector3 = (battle._cam.global_position - c).normalized()
		var ax: Vector3 = Vector3.UP.cross(to_cam)
		if ax.length() < 0.0001:
			ax = Vector3.RIGHT
		ax = ax.normalized()
		var ay: Vector3 = to_cam.cross(ax).normalized()
		var pts: Array[Vector3] = []
		for k in range(NEST_SIDES):
			var a: float = TAU * float(k) / float(NEST_SIDES)
			var wob: float = 1.0 + sin(a * 3.0 + t * 2.4) * 0.30 + sin(a * 5.0 - t * 1.9) * 0.17
			pts.append(c + (ax * cos(a) + ay * sin(a)) * (rr * wob))
		var a_f: float = 0.95 * clampf((life - t) / 0.18, 0.0, 1.0)
		var cc := TENT_EDGE;  cc.a = a_f
		var ce := TENT_BODY;  ce.a = a_f
		imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
		for k in range(NEST_SIDES):
			imesh.surface_set_color(cc); imesh.surface_add_vertex(c)
			imesh.surface_set_color(ce); imesh.surface_add_vertex(pts[k])
			imesh.surface_set_color(ce); imesh.surface_add_vertex(pts[(k + 1) % NEST_SIDES])
		imesh.surface_end()
		imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)          # 湿润的边
		var cr := TENT_RIDGE; cr.a = a_f * 0.8
		for k in range(NEST_SIDES + 1):
			imesh.surface_set_color(cr); imesh.surface_add_vertex(pts[k % NEST_SIDES])
		imesh.surface_end()
	, 0.0, 1.0, maxf(0.1, life))
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

## ★★2026-08-02 修(用户:「你这个数字怎么没放头顶上呢，和现有dot一样的规则」):
##   原来把 Label3D 挂在【宿主立绘之下】、局部偏移只有 44 码(≈1.06 米) ⇒ 数字贴在身上不在头顶,
##   而且【会跟着立绘一起被缩放】—— 抽搐时立绘涨到 1.34 倍、尸壳期泄到 0.88 倍, 数字跟着一起变形。
##   现在照项目既定规则走:
##     · 高度 2.2 米 = _float_text 用的头顶口径(battle_vfx.gd:134), 和现有 DoT 飘字同一条线
##     · 跟随走 battle._follow_vfx(每帧贴 u.height + h) —— 被击飞/浮空时数字跟着抬起来,
##       宿主一死自动回收。这是全项目"跟着单位走"的唯一机制, 不自己再写一套跟随。
## ★2.2(飘字口径)会和【血条】打架: 血条挂在 u.height+2.4, 而这个数字是【常驻】的、
##   字高 0.58 米 ⇒ 中心放 2.2 时上半截正好插进血条里
##   (实拍确认: 标签在、可见、屏幕坐标也对 —— 就是被血条压住了)。
##   飘字能用 2.2 是因为它一出来就往上飘走; 常驻标签不行。
##   2.95 取在血条之上, 参照 battle_render.gd:300 那条「比伤害飘字高一截、不挡血条」的 2.7。
const NUM_HEAD_H := 2.95
func _hb_counter_refresh(o: Dictionary) -> void:
	if battle._world == null:
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
		# ★字号要和现有 DoT 飘字【看上去一个量级】: 那些是 UI 层字号(约 22~30 屏幕像素),
		#   而 Label3D 是世界尺寸。64 × 0.0042 = 0.27 米 ⇒ 屏幕上只有约 12 像素, 实拍完全看不见
		#   (探针确认标签本身是好的: text=60、世界高 2.20、跟随正常 —— 纯粹是太小)。
		#   64 × 0.0090 = 0.58 米 ⇒ 约 25 屏幕像素, 与 DoT 飘字齐平。
		lbl.pixel_size = 0.0090
		lbl.position = battle._world_pos(o["pos"], NUM_HEAD_H)
		battle._world.add_child(lbl)
		battle._follow_vfx.append({"spr": lbl, "unit": o, "h": NUM_HEAD_H})
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
