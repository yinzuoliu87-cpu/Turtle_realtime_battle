class_name BattleSpawn
extends RefCounted
## 单位生成/生命周期: 造单位(_make_unit)+双路/单路布阵spawn+训龟大师+spawn被动+召唤物(summon/藏身小将/海盗船)
## 类内名不变;外部名加 battle.

## 召唤物默认移速 —— 对齐【近战法师/辅助】档(100)。用户2026-07-28 移速定位化:
## 原默认 120 会让无名召唤物比大多数龟都快, 与"近战>远程"的结构保证冲突。
## 有明确设计理由的召唤物照旧各自硬写(水晶球90 / 海盗船40 —— 注释里有出处)。
const SUMMON_DEFAULT_SPD := 100.0

var battle

func _init(b) -> void:
	battle = b

# ============================================================================
#  阵容 spawn — 读 GameState.season_leaders, 没有就 demo (1:1 复用 2D 解析)
# ============================================================================
func _spawn_teams() -> void:
	# 🛠 调试场: 空场进编辑模式 (不自动出生; 用户点击摆位). 默认关 → 走正常 spawn.
	if battle.DEBUG_EDIT:
		battle._edit_mode = true
		battle._hud._build_edit_palette()
		battle._hud._build_brush_bar()   # 底部常驻笔刷栏(取代模态选龟·用户2026-07-24)
		battle._debug._edit_set_status("编辑模式: 点空地摆兵 · 拖拽挪位 · 右键删")
		return
	if battle._is_dual_lane_mode():   # 双路: 读 dual_lineup 当前路 spawn 我方 leaders+小将 + 对手, 绕过评审/EQDEMO
		if GameState != null:   # 新一局(进场): 重置分路/蛋/幸存/结果 (dual_lineup/season_leaders 保留)
			GameState.current_lane = "top"
			if GameState.egg_hp is Dictionary:
				GameState.egg_hp = {"left": 0.0, "right": 0.0}
			if GameState.dual_survivors is Dictionary:
				GameState.dual_survivors = {"left": [], "right": []}
			# 魔法石叠层的跨路存档同样【每局重置】—— 跨的是"路"不是"局"
			if GameState.dual_ms_stacks is Dictionary:
				GameState.dual_ms_stacks = {"left": 0, "right": 0}
			GameState.lane_results = {}
		_spawn_dual_lane()
		return
	var left = battle._resolve_left()
	var right = battle._resolve_right()
	var _cx = battle.ARENA.position.x + battle.ARENA.size.x * 0.5    # 评审演示: 龟居中拉近(相机框得到)
	var _cy = battle.ARENA.position.y + battle.ARENA.size.y * 0.5
	for i in range(left.size()):
		# XZ 落点: 左队靠左 (battle.ARENA 内), 三龟纵向分布. 与 2D _spawn_teams 同口径像素坐标. 偏移走 @export 参数(#12)
		var pos = Vector2(battle.ARENA.position.x + battle.spawn_edge_margin, battle.ARENA.position.y + battle.spawn_front_margin + i * battle.spawn_row_spacing)
		if battle._review_demo() and left.size() == 1:
			pos = Vector2(_cx - 150.0, _cy)
		elif battle._review_demo():
			pos = Vector2(_cx - 200.0, _cy + (float(i) - float(left.size() - 1) / 2.0) * minf(150.0, 520.0 / float(maxi(1, left.size()))))
		if OS.has_environment("EQDEMO_EQUIP") and left.size() > 1:
			pos = Vector2(_cx - 250.0 + float(i) * 175.0, _cy)   # 携带者+友方假人 排在水平掠射线上(看火柱扫到友军回血)
		var _lu: Dictionary
		if str(left[i]) == "elite":
			_lu = _make_unit("__minion__", "left", pos, {"minion": true, "elite": true, "level": 6})
		elif str(left[i]) == "minion":
			_lu = _make_unit("__minion__", "left", pos, {"minion": true, "role": "front", "level": 6})
		else:
			_lu = _make_unit(str(left[i]), "left", pos)   # REVIEW_TURTLE="elite"→精英小将demo(虐杀原形改造)
		if battle._review_demo() and str(left[i]) == "fortune":
			_lu["gold"] = 30.0 if (battle._review_skill_idx() == 2 or battle._review_skill_idx() == 0) else 0.0   # demo: 审梭哈/被动时备30金币(梭哈看弹幕·被动看冒金币+普攻打得动看死亡涌币); 否则0看自然攒
		if battle._review_demo() and battle.REVIEW_DUMMY_ATTACKS:
			_lu["_review_dummy"] = true   # 假人会还手时受审龟免死(看完整被动循环)
		if battle._review_demo() and str(left[i]) == "dice" and battle._review_skill_idx() == 0:   # 被动赌徒之血: 起手40%血→看血色气焰+暴击拉满(巨血防死·不回满以维持低血)
			_lu["maxHp"] = float(_lu["maxHp"]) * 20.0
			_lu["hp"] = _lu["maxHp"] * 0.4
			_lu["_review_dummy"] = false
		if battle._review_demo() and str(left[i]) == "gambler" and battle._review_skill_idx() == 2:   # 赌注低血模式: 起手22%血(<40%)→触发低血分支(回8%maxHp+3秒多重·绿闪绿环)·随回血/消耗在阈值震荡(巨血防死)
			_lu["maxHp"] = float(_lu["maxHp"]) * 20.0
			_lu["hp"] = _lu["maxHp"] * 0.7   # 起手70%>40%→先正常模式(消耗40%+红字多重), 掉到40%以下再低血模式(回血)·两模式都看到
			_lu["_review_dummy"] = false
		if battle._review_demo() and str(left[i]) == "pirate" and battle._review_skill_idx() == 2:   # 朗姆酒: 海盗站桩(不攻击不移动·免假人盾/巨伤干扰)+35%残血血锁不死→放朗姆酒看船扔酒瓶+HoT绿回血把血顶上来(血条明显动)+暖色护光
			_lu["hp"] = float(_lu["maxHp"]) * 0.35
			_lu["deathfloor_until"] = 999999.0
			_lu["_review_dummy"] = false
			_lu["no_basic"] = true; _lu["no_move"] = true; _lu["move_spd"] = 0.0
		if battle._review_demo() and str(left[i]) == "pirate" and battle._review_skill_idx() == -1:   # 被动掠夺: 海盗40%残血+_pdeath_demo(被假人打死→放死亡钩索但不真死复位循环)·开场也看登场轰击
			_lu["hp"] = float(_lu["maxHp"]) * 0.4
			_lu["_review_dummy"] = false
			_lu["_pdeath_demo"] = true
		if battle._review_demo() and str(left[i]) == "headless" and battle._review_skill_idx() >= 1:   # 无头技能窗评审: 充能加速(demo看得到反复放技·实战原速)
			_lu["echarge_perm"] = 4.0
		if battle._review_demo() and str(left[i]) == "headless" and battle._review_skill_idx() == -1:   # 亡灵被动demo: 中血非血锁→假人打到濒死触发免死(_undead_demo: 免死窗过后回满+清undead_used循环)+看残血紫焰渐浓
			_lu["maxHp"] = 900.0; _lu["hp"] = 900.0
			_lu["_review_dummy"] = false
			_lu["_undead_demo"] = true
		if battle._review_demo() and str(left[i]) == "lava":   # 熔岩评审便利: 出生90怒气→打几下就变身火山(验火山形态技变体/被动不用干等攒怒气)
			_lu["rage"] = 90.0
		if battle._review_demo() and str(left[i]) == "crystal" and battle._review_skill_idx() == 1:   # 水晶壁垒demo: 固定不动(防近战追击漂移到场角→水晶刺朝场外放看不见)
			_lu["no_move"] = true
			_lu["move_spd"] = 0.0
		if battle._review_demo() and str(left[i]) == "cyber" and battle._review_skill_idx() == -1:   # 赛博被动demo(用户2026-07-16: 固定不动+1假人打): 攒编队→打死→自由飞散→齐射→组装→循环
			_lu["_review_dummy"] = false
			_lu["_cydeath_demo"] = true
			_lu["no_move"] = true
			_lu["move_spd"] = 0.0
		if battle._review_demo() and str(left[i]) == "bubble" and battle._review_skill_idx() == 3:   # 泡泡爆破: 预置满泡泡值(不用挨打攒·每帧回满)+站桩→反复放爆破看两门+泡沫墙清晰展开
			_lu["bubble_store"] = float(_lu["maxHp"])
			_lu["_bubble_burst_demo"] = true
			_lu["no_move"] = true; _lu["move_spd"] = 0.0
		if OS.has_environment("EQDEMO_EQUIP"):   # 装备演示
			if i == 0:   # === 携带者(持受审装备) ===
				_lu["_eqdemo_carrier"] = true
				if OS.has_environment("EQDEMO_ENEMY_ATTACKS"):
					_lu["deathfloor_until"] = 999999.0   # 挨打/叠层/反伤类: 真实血量+血锁不死(看层数/反伤/充能, HP非重点)
				elif OS.has_environment("EQDEMO_HURT"):
					_lu["hp"] = _lu["maxHp"] * clampf(float(OS.get_environment("EQDEMO_HURT")), 0.05, 1.0)   # 回血/自愈类: 真实血量起手受伤(静养看自回填血, 无敌人不锁血)
				else:
					_lu["deathfloor_until"] = 999999.0; _lu.erase("_review_dummy")   # 观察/召唤/自发/周期buff类: 真实血量(%maxHP伤害/回血不失真)+血锁不死站桩(观察模式无敌人打它)
				if OS.has_environment("EQDEMO_CAST_ONLY"):   # demo: 站桩只放技(看远程on_cast弹道从原地飞出, 不近身)
					_lu["no_move"] = true; _lu["no_basic"] = true; _lu["move_spd"] = 0.0
					_lu["active_skills"] = [OS.get_environment("EQDEMO_SKILL")] if OS.has_environment("EQDEMO_SKILL") else _lu["active_skills"]
				elif not OS.has_environment("EQDEMO_ATTACKER"):   # 默认: 站桩不攻击(召唤/自发/周期件); ATTACKER=普攻+技能
					_lu["no_move"] = true; _lu["no_basic"] = true; _lu["active_skills"] = []; _lu["move_spd"] = 0.0
				elif OS.has_environment("EQDEMO_SKILL"):
					_lu["active_skills"] = [OS.get_environment("EQDEMO_SKILL")]
			else:   # === 友方假人(EQDEMO_ALLIES; 团队增益/治疗类看队友受益) ===
				_lu["no_move"] = true; _lu["no_basic"] = true; _lu["active_skills"] = []; _lu["move_spd"] = 0.0
				_lu["maxHp"] = 4000.0; _lu["hp"] = 1600.0   # 起手40%血→看治疗/护盾刷到队友
		battle._units.append(_lu)
	var _rlay = battle._review_dummy_layout()   # 专属演示布局(相对受审龟 _cx-150)
	for i in range(right.size()):
		var pos = Vector2(battle.ARENA.end.x - battle.spawn_edge_margin, battle.ARENA.position.y + battle.spawn_front_margin + i * battle.spawn_row_spacing)
		if not _rlay.is_empty() and i < _rlay.size():
			var _d: Dictionary = _rlay[i]
			pos = Vector2(_cx - 150.0 + float(_d.get("dx", 150.0)), _cy + float(_d.get("dy", 0.0)))
		elif battle._review_demo() and right.size() == 1:
			pos = Vector2(_cx + 150.0, _cy)
		elif battle._review_demo():
			pos = Vector2(_cx + 100.0 + (float(i) - float(right.size() - 1) / 2.0) * 150.0, _cy + 40.0)   # 横排(用户)
		if OS.has_environment("EQDEMO_EQUIP"):
			var _d1: float = float(OS.get_environment("EQDEMO_ENEMY1")) if OS.has_environment("EQDEMO_ENEMY1") else 210.0
			var _gap: float = float(OS.get_environment("EQDEMO_GAP")) if OS.has_environment("EQDEMO_GAP") else 500.0
			pos = Vector2(_cx - 150.0 + _d1 + float(i) * _gap, _cy + (float(OS.get_environment("EQDEMO_ENEMY_Y")) if OS.has_environment("EQDEMO_ENEMY_Y") else 0.0))   # 装备演示: 敌1距携带者_d1码, 两敌相距_gap; ENEMY_Y=深度偏移(测浪覆盖)
		var ru = _make_unit(str(right[i]), "right", pos)
		if battle._review_demo():                          # 假人: 不放技/永不死训练靶; ATTACKS时会还手(动+普攻)
			if not battle.REVIEW_DUMMY_ATTACKS:
				ru["no_basic"] = true
				ru["no_move"] = true
			ru["active_skills"] = []
			ru["maxHp"] = battle.REVIEW_DUMMY_HP
			ru["hp"] = ru["maxHp"]
			if not battle.REVIEW_DUMMY_KILLABLE:
				ru["_review_dummy"] = true       # 不死沙包(受击回满); KILLABLE=会死(看换目标)
			if battle._review_turtle() == "hunter" and battle._review_skill_idx() == -1:   # 猎人被动猎杀demo靶: 钉12%残血(<14%斩杀线)→猎人扫场自动射强化箭处决; 血锁不死(普通箭伤打不死·只被强化箭处决触发VFX)循环看处决+窃取
				ru.erase("_review_dummy")
				ru["maxHp"] = 3500.0; ru["hp"] = ru["maxHp"] * 0.12
				ru["deathfloor_until"] = 999999.0   # 血锁不死(普通伤害floored at 1·只被强化箭处决路径复位)
				ru["_hunt_demo_victim"] = true
			if battle._review_turtle() == "elite" and battle._review_skill_idx() == -1:   # 吞噬demo靶: 18%残血非沙包+吞噬后复活循环+留技能看偷放
				ru.erase("_review_dummy")
				ru["maxHp"] = 3000.0; ru["hp"] = ru["maxHp"] * 0.18
				ru["_consume_demo"] = true
				ru["active_skills"] = battle._resolve_active_skills(str(right[i]), false)
		if OS.has_environment("EQDEMO_EQUIP"):   # 装备演示假人: 固定不动/5000血/30双抗/会掉血
			if OS.has_environment("EQDEMO_ENEMY_ATTACKS"):
				ru["no_basic"] = false; ru["no_move"] = false   # 敌逼近+普攻打携带者(演受伤/挨打类件)
			else:
				ru["no_basic"] = true; ru["no_move"] = true
			ru["active_skills"] = []
			var _dhp: float = float(OS.get_environment("EQDEMO_DUMMYHP")) if OS.has_environment("EQDEMO_DUMMYHP") else 5000.0
			ru["maxHp"] = _dhp; ru["hp"] = _dhp
			ru["base_def"] = 30.0; ru["base_mr"] = 30.0; battle._recalc_stats(ru)
			ru.erase("_review_dummy")
		if not _rlay.is_empty() and i < _rlay.size() and bool((_rlay[i] as Dictionary).get("fixed", false)):
			ru["no_move"] = true; ru["no_basic"] = true   # 演示专属: 该假人固定不动(如龟派气波远处靶)
			ru["_home_pos"] = ru["pos"]                   # 被击飞后缓步归位(评审板稳定·防连续击退推出画面)
		if not _rlay.is_empty() and i < _rlay.size() and (_rlay[i] as Dictionary).has("rarity"):
			ru["rarity"] = str((_rlay[i] as Dictionary)["rarity"])   # 演示专属: 指定假人稀有度(如平等审判光柱需A+目标)
		battle._units.append(ru)
	battle._inject_equipment()       # 装备注入 (玩家队读 persistent_equipped; demo队塞测试装备) — 须在被动之前
	_apply_spawn_passives()   # 登场被动 (开战即生效: 忍术暴击/怨灵诅咒/冰寒减攻/召唤等)
	battle._equip_sys._stats._eq_apply_all_stats()     # 开战: 全装备纯属性 / 永久 flag 加到携带者 (spawn 被动之后, 不被覆盖)
	battle._synergy.apply_all()   # ★类型羁绊(批4-1): 必须在单件属性【之后】—— 羁绊是加在单件属性上面的
	battle._bow_syn.apply_all()   # 弓箭【腐蚀·穿透】写进 armor_pen_pct/magic_pen_pct(休眠通道, 消费侧零改动)
	battle._gun_syn.apply_all()   # 枪【火控】(第三座炮台): 给带枪者标 _fire_ctrl
	battle._food_syn.apply_all()  # 食物【学院】: 队伍全体额外 +100/220 最大生命(只加一次)
	battle._relic_syn.apply_all() # 遗物【生死界】系数 + 龟蛋加固(+500/900/1500)
	for _pu in battle._units:        # 海盗: 开战即在后方显示持久海盗船(用户2026-07-14"战斗开始就在位置上")
		if str(_pu.get("id", "")) == "pirate" and not _pu.get("is_summon", false):
			battle._pirate_sys._pirate_get_ship(_pu)
	if OS.has_environment("EQDEMO_FORCE_HP50"):   # demo: 强制携带者<50%触发救命类(044/045), 便于验证特效
		for _fu in battle._units:
			if _fu["side"] == "left" and not _fu.get("equips", []).is_empty():
				_fu["hp"] = _fu["maxHp"] * 0.4
				battle._equip_sys._eq_check_hp_threshold(_fu)
	_spawn_trainers()         # 双方场外监视者(用户2026-07-22 需求3)
	battle._hud._build_team_panels()      # 局内 UI: 左右队头像框栏 (主龟; 召唤体不进) — 须在 equips 注入之后

func _spawn_dual_lane() -> void:
	# ★战场不在此刻加载 —— 先走呈现(总览/预览), 预览结束才 battle._dl_sys._dl_build_lane_field() 真正 spawn.
	# 这样呈现时后面根本没有战场, 从源头杜绝上下路串场(用户2026-07-12「不能预览后再加载好战场吗，非要遮住是为啥」).
	if OS.has_environment("DL_AUTOFIGHT"):
		battle._dl_sys._dl_build_lane_field()
		battle._dl_state = "place"; battle._dl_sys._dl_enter_place()   # 测试: 跳呈现直接加载战场→放置→自动打
	elif not battle._dl_overview_shown:
		battle._dl_overview_shown = true
		battle._dl_sys._dl_enter_present("overview")   # 匹配后首次: 3路总览→预览→(加载战场)→放置
	else:
		battle._dl_sys._dl_enter_present("preview")    # 后续路: 对阵预览→(加载战场)→放置

## 大师攻击力: 装配【魔法石】时 ×10(用户 2026-07-28), 否则 1。
## ★这里只能看 GameState/ghost —— 单位字典的 _tr_passive 是 spawn 完之后才写的(见 _apply_trainer_loadout),
##   spawn 当下还没有。两处判据必须一致, 否则会出现"图标是魔法石但攻击力还是1"这种半吊子状态。
## 大师攻击力。★2026-07-31 用户拍板:「训龟大师的魔法石不再提供19倍攻击力」——
## 魔法石不再给攻击力倍率, 收益全部回到"每层攻速"上(见 trainer_system.MS_HASTE_PER_STACK)。
## (代码与文案原本写的是 ×10 不是 ×19; 按用户意图执行 = 取消倍率。)
## ★整个函数留着而不是内联成常量 —— 将来若有别的被动要改攻击力, 分派点在这儿。
func _trainer_atk_for(_side: String) -> float:
	return battle.TRAINER_ATK

func _spawn_lane_side(units: Array, side: String, lvl: int, base: Vector2) -> void:
	var lead_n = 0
	for u in units:
		if u is Dictionary and str(u.get("kind", "")) == "leader":
			lead_n += 1
	var minion_seen = 0
	var n: int = units.size()
	for i in range(n):
		var u: Dictionary = units[i] if units[i] is Dictionary else {}
		var pos = base + Vector2(0.0, (float(i) - float(n - 1) / 2.0) * 154.0)
		var made: Dictionary
		if str(u.get("kind", "")) == "leader":
			made = _make_unit(str(u.get("id", "basic")), side, pos)
		else:
			var elite: bool = (lead_n == 0 and minion_seen == 0)
			minion_seen += 1
			var mlv: int = lvl
			if side == "left": mlv += int(u.get("temp_lv", 0))   # 临时等级器用在小将身上(糖果罐战利品·记在阵容格子上)
			made = _make_unit("__minion__", side, pos, {"minion": true, "role": str(u.get("role", "front")), "elite": elite, "level": mlv})
		if u.has("hp_frac"):   # 幸存带血进终极
			made["hp"] = maxf(1.0, made["maxHp"] * clampf(float(u["hp_frac"]), 0.05, 1.0))
		if u.has("equips") and u["equips"] is Array and not (u["equips"] as Array).is_empty():
			made["_dl_equips"] = (u["equips"] as Array).duplicate(true)   # 局外dual_lineup配的装(leader/小将), battle._inject_equipment 优先用
		# ★★驯服归顺状态要【跟着进终极战场】(用户 2026-07-28:"可跨入终极战场, 掉血 buff 继续")。
		#   dual_lane_flow._dl_snapshot_survivors 早就把 tamed_side/tame_used 写进 spec 了,
		#   但【这里从来没读过】—— 归顺者会作为普通我方单位重生, 每秒 2% 的掉血 buff 整个丢掉
		#   (_tick_tame_decay 要求 tamed_side != "")。
		#   ★探针实测才发现: 光看快照那侧的代码(注释还写着"要跨路持久化")会以为是对的 ——
		#     写进去了没人读, 和没写一样。这就是"读代码以为对"的典型。
		if str(u.get("tamed_side", "")) != "":
			made["tamed_side"] = str(u["tamed_side"])
			made["tame_used"] = bool(u.get("tame_used", true))   # 已用掉复活机会, 别在决胜里再复活一次
			made["_tame_decay_next"] = -1.0                      # 掉血节拍重新起算(进场后整 1 秒才掉第一次)
		battle._units.append(made)

func _make_unit(id: String, side: String, pos: Vector2, spec: Dictionary = {}) -> Dictionary:
	var is_minion: bool = bool(spec.get("minion", false))
	var is_egg: bool = bool(spec.get("egg", false))
	var is_trainer: bool = bool(spec.get("trainer", false))
	var d: Dictionary
	var st: Array
	var sd: Dictionary
	if is_minion:   # 深海小将: 非龟, 自带立绘/数值(750血·45攻·双抗7 ×1.05^级; 前排挥砍范围70/后排射击400), 无技能被动
		var _mf: bool = str(spec.get("role", "front")) == "front"
		var _me: bool = bool(spec.get("elite", false))
		var _mm: float = pow(1.05, maxf(0.0, float(int(spec.get("level", 1)) - 1)))
		if _me:   # 精英小将定制属性(用户2026-07-18): 1000HP/50ATK/16DEF/20MR (HP/ATK随等级复利·双抗定值)
			d = {"name": "精英小将", "rarity": "C", "crit": 0.0,
				"hp": 1000.0 * _mm, "atk": 50.0 * _mm, "def": 16.0, "mr": 20.0}
		else:     # 普通小将: 750HP·前排1.4/后排1.5系数ATK·7双抗
			d = {"name": "小将", "rarity": "C", "crit": 0.0,
				"hp": 250.0 * _mm * 3.0, "atk": 30.0 * _mm * (1.4 if _mf else 1.5),
				"def": (13.0 if _mf else 7.0), "mr": (13.0 if _mf else 7.0)}   # 近战(前排)双抗 7→13(用户2026-07-19); 远程保持7
		if _me:
			st = [true, 105.0, 1.0 / 0.65, 90.0]   # 精英(虐杀原形改造2026-07-16): 近战长手刃·攻速0.65次/s
		else:
			st = [_mf, 105.0, 0.85, (70.0 if _mf else 400.0)]
		sd = battle._hiding_sys._minion_sprite_dict(_me, not _mf)
	elif is_trainer:   # 训龟大师: 500血/1攻/0双抗; 站着不动(速度0)·射程2000·扔石头1物理
		d = {"name": "训龟大师", "rarity": "C", "crit": 0.0,
			"hp": battle.TRAINER_HP, "atk": _trainer_atk_for(side), "def": 0.0, "mr": 0.0}
		# ★move_spd 给真值但 no_move 仍为 true —— 两者不矛盾:
		#   no_move 挡住的是【AI 自动追击】(_do_move)与【分离推挤】(_apply_separation_pass),
		#   正是"场外监视者不该被战线卷进去"想要的; 玩家操控走的是下面 battle._trainer_sys._trainer_move_by 这条独立路径。
		st = [false, battle.TRAINER_MOVE_SPD, battle.TRAINER_ATK_INTERVAL, battle.TRAINER_RANGE]   # [近战?, 移速, 攻击间隔, 射程]
		var _appear: String = OS.get_environment("TRAINER_APPEAR") if OS.has_environment("TRAINER_APPEAR") else str(GameState.trainer_appearance)   # dev: TRAINER_APPEAR=mage 可强制预览某形象
		if side != "left":
			_appear = "default"   # 敌方大师用通用立绘(敌形象未跟踪)
		sd = battle._trainer_sys._trainer_sprite_dict(_appear)   # 玩家侧用配置选的形象; 敌侧用通用立绘
		sd["_appearance"] = _appear   # 传给 u["_appearance"] → battle_render._update_trainer_anim(4方向)
	elif is_egg:   # 龟蛋: 纯血包 fighter(atk/def/mr=0), 不动不攻击, 免控/斩/嘲讽, 走完整伤害管线; 围栏未破不可主动索敌(AoE穿栏)
		d = {"name": "龟蛋", "rarity": "SSS", "crit": 0.0, "hp": maxf(1.0, float(spec.get("hp_max", spec.get("hp", 2100)))), "atk": 0.0, "def": 60.0, "mr": 60.0}   # maxHp=原始满血; 当前hp在下方按累积受损值覆盖(用户2026-07-12: 跨路掉血要可见); 60双抗
		st = [true, 0.0, 99.0, 0.0]
		sd = battle._egg_sprite_dict()
	else:
		d = battle._data_by_id.get(id, {})
		st = battle.STATS.get(id, battle.DEFAULT_STAT)
		sd = battle._resolve_pet_sprite(id)
	var hp = float(d.get("hp", 1350))  # hp已是最终值
	# --- 立绘 billboard sprite: 全身图 + idle sprite-sheet 动画 (接地软渐隐 shader 在单帧 UV 上做底淡) ---
	var tex: Texture2D = sd["tex"]
	var frame_h: int = int(sd.get("frame_h", 64))
	# pixel_size: 让单帧高度 = battle.TARGET_BODY_H 米 (全身图归一, 不论 64px 还是 500px 都同样大小)
	var px: float = (battle.TARGET_BODY_H / float(maxi(1, frame_h))) if tex != null else battle.PIXEL_SIZE
	var spr = Sprite3D.new()
	spr.name = "Unit_" + id
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.pixel_size = px
	spr.shaded = false
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var grounded_mat: ShaderMaterial = null
	if tex != null:
		spr.hframes = int(sd.get("hframes", 1))
		spr.vframes = int(sd.get("vframes", 1))
		spr.frame = 0
		spr.offset = Vector2(0.0, frame_h * 0.5)             # 脚底贴地: 单帧上抬半帧高
		grounded_mat = battle._make_grounded_material(tex, sd)      # 接地软渐隐 (单帧 UV 上做底淡)
		spr.material_override = grounded_mat
	spr.position = battle._world_pos(pos, battle.GROUND_LIFT)
	battle._world.add_child(spr)

	# --- blob 暗影 (外圈柔影, 跟 XZ 不跟 Y) ---
	var shadow = Sprite3D.new()
	shadow.name = "Shadow_" + id
	shadow.texture = VfxTex._make_blob_texture()
	shadow.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	shadow.axis = Vector3.AXIS_Y
	shadow.pixel_size = 0.01
	shadow.shaded = false
	shadow.transparent = true
	shadow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	shadow.modulate = Color(1, 1, 1, battle.SHADOW_BASE_A)
	shadow.scale = battle.SHADOW_BASE
	shadow.position = battle._world_pos(pos, 0.02)
	battle._world.add_child(shadow)

	# --- 接触核影 (脚下深实小影, 盖立绘/地面交界 → 锚定"踩在地上", §GROUNDING 接地三件套之一) ---
	var contact = Sprite3D.new()
	contact.name = "Contact_" + id
	contact.texture = VfxTex._make_contact_texture()
	contact.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	contact.axis = Vector3.AXIS_Y
	contact.pixel_size = 0.012
	contact.shaded = false
	contact.transparent = true
	contact.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	contact.modulate = Color(1, 1, 1, 0.0)   # 隐藏接触波纹(用户"只留影子")
	contact.scale = battle.CONTACT_BASE
	contact.position = battle._world_pos(pos, 0.028)
	battle._world.add_child(contact)

	# --- 队伍底色环 (脚下, 区分敌我) ---
	var ring = Sprite3D.new()
	ring.texture = VfxTex._make_ring_texture(Color("#3fa9ff") if side == "left" else Color("#ff5a5a"))
	ring.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	ring.axis = Vector3.AXIS_Y
	ring.pixel_size = 0.011
	ring.shaded = false
	ring.transparent = true
	ring.modulate = Color(1, 1, 1, 0.0)   # 隐藏队色环(_make_ring_texture忽略色=白; 用户"只留影子")
	ring.position = battle._world_pos(pos, 0.015)
	battle._world.add_child(ring)

	# --- HP / 龟能 overlay (CanvasLayer 上, 每帧 unproject 定位) ---
	var bar = battle._make_status_bar(side, battle._unit_level(side))
	battle._ui_layer.add_child(bar["root"])

	var u = {
		"id": id, "name": str(d.get("name", id)), "rarity": str(d.get("rarity", "C")), "side": side, "passive": d.get("passive", {}),
		"pos": pos, "vel": Vector2.ZERO,
		"height": 0.0, "vy": 0.0, "vx": 0.0, "vz": 0.0, "airborne": false,
		"hp": hp, "maxHp": hp,
		"atk": float(d.get("atk", 40)), "def": float(d.get("def", 12)), "mr": float(d.get("mr", 12)),
		"base_atk": float(d.get("atk", 40)), "base_def": float(d.get("def", 12)), "base_mr": float(d.get("mr", 12)),
		"crit": float(d.get("crit", 0.25)), "crit_dmg": 1.5, "lifesteal": 0.0,
		"armor_pen": 0.0, "armor_pen_pct": 0.0, "magic_pen": 0.0, "magic_pen_pct": 0.0,
		"heal_amp": 0.0, "shield_amp": 0.0, "damage_reduction": 0.0, "damage_amp": 0.0, "reflect": 0.0, "tenacity": 0.0,
		"melee": bool(st[0]), "move_spd": float(st[1]),
		"atk_interval": float(st[2]), "atk_range": (maxf(float(st[3]), battle.MELEE_ATK_RANGE_MIN) if bool(st[0]) else float(st[3])),   # 近战射程抬到≥100(用户: 修贴脸重叠·远程不动)
		"atk_cd": 0.0, "energy": 0.0, "alive": true,
		# 选3 多技能: loadout 的非基础技(physical/magic 是普攻=自动) → 主动技轮转, 龟能满放下一个
		"active_skills": ([] if (is_minion or is_egg) else battle._resolve_active_skills(id, side == "left")), "skill_idx": 0,
		"skill_cd": {}, "skill_gcd_until": 0.0,   # 逐技各自冷却剩余秒(懒填) + 同龟连放最小间隔
		# 永久护盾 / 控制 / 旧式灼烧(保留兼容) ----
		"shield": 0.0, "stun_until": 0.0, "slow_until": 0.0,
		# 层数式 DoT (灼烧/中毒/流血, 1:1 dot.gd 层数衰减模型) ----
		"dot_stacks": {}, "_dottimer": 0.0, "dot_src": {}, "true_fire_until": 0.0, "_dot_float": {},
		# 效果积木状态 ----
		"buffs": [], "dots": [],
		"taunt_until": 0.0, "taunt_by": null,
		"dodge_bonus": 0.0, "ls_bonus": 0.0,
		"stacks": {}, "rage": 0.0, "star_energy": 0.0, "store_energy": 0.0, "gold": 0.0,
		"dmg_dealt": 0.0, "reborn_used": false, "untargetable_until": 0.0,
		"summons": [],
		# 装备 (Phase 3b: 恒空, 不触发钩子) ----
		"equips": [], "eq_state": {}, "hp50_fired": false,
		# 节点引用
		"sprite": spr, "shadow": shadow, "ring": ring, "shadow_base_scale": battle.SHADOW_BASE,
		"contact": contact, "contact_base_scale": battle.CONTACT_BASE,
		"bar_root": bar["root"], "hp_bar": bar["hp_bar"], "en_fill": bar["en"], "level_badge": bar.get("level_badge", null),
		"spr_base_offy": spr.offset.y,
		# 立绘动画态 (idle sprite-sheet 循环 + attack/hurt/death 动作覆盖一次) ----
		"grounded_mat": grounded_mat,       # 接地 shader 材质 (设 frame uniform 切帧)
		"idle_sd": sd,                      # idle 帧字典 {tex,frames,fps,frame_h,hframes,vframes}
		"idle_px": px,                      # idle 全身图 pixel_size (动作切回时复原)
		"idle_offy": (frame_h * 0.5) if tex != null else 0.0,
		"anim_t": 0.0,                      # 当前动画累计时间 (驱动帧)
		"anim_sd": sd,                      # 当前正播的帧字典 (idle 或动作)
		"anim_action": "",                  # 非空=正在播动作 (attack/hurt/death), 播完回 idle
		# Phase4 juice 态 (每帧从这些字段重建 scale/modulate/bob, 不叠 tween → 精确复原) ----
		"spr_base_scale": spr.scale,        # billboard 基准 scale (复原锚点; Sprite3D 默认 (1,1,1))
		"flash_t": 0.0,                     # 受击闪白剩余秒 (>0 提白, 线性淡回)
		"hitsq_t": 0.0,                    # 受击压扁剩余秒
		"land_t": 0.0,                     # 落地压扁剩余秒
		"swing_t": 0.0,                    # 出招挥出(伸)剩余秒
		"windup_t": 0.0,                   # 出招预备(缩)剩余秒
		"bob_phase": randf() * TAU,        # idle bob 起始相位 (错峰, 不齐刷)
	}
	# 等级缩放: 主属性 +5%/级, 攻速 +2%/级 (吃等级表见 战斗基础-策划焊死.md §三). 小将自带×1.05缩放, 跳过龟式缩放.
	var _lvl: int = maxi(1, battle._unit_level(side))
	if side == "left" and not is_minion and not is_egg and not is_trainer and GameState != null:   # 临时等级器(糖果罐战利品·封板L402): 玩家方该龟本大轮永久+N级(切轮重置)
		_lvl += GameState.temp_level_bonus(id)
	# ★训龟大师不吃等级缩放: 用户给的 500/1/0/0 是【定值】, 缩放会让"伤害降为1"之外的
	#   血量随大轮涨, 与"场外监视者"的设定不符。
	if _lvl > 1 and not is_minion and not is_egg and not is_trainer:
		var _m: float = UnitScaling.level_multiplier(_lvl)
		u["maxHp"] *= _m; u["hp"] = u["maxHp"]
		u["atk"] *= _m; u["base_atk"] *= _m
		u["def"] *= _m; u["base_def"] *= _m
		u["mr"] *= _m; u["base_mr"] *= _m
		u["atk_interval"] /= (1.0 + 0.02 * float(_lvl - 1))   # 攻速+2%/级 → 间隔变短
	var _ec = {}                                    # 数据驱动龟能: 该龟各技 type→energyCost
	for _sk in d.get("skillPool", []):
		var _e = _sk.get("energyCost", null)
		if _e != null:
			_ec[str(_sk.get("type", ""))] = float(_e)
	u["energy_cost"] = _ec
	u["level"] = _lvl
	if is_minion:
		u["_isMinion"] = true
		u["minion_role"] = str(spec.get("role", "front"))
		u["is_elite"] = bool(spec.get("elite", false))
		if u["is_elite"]:                              # 精英小将(虐杀原形改造2026-07-16): 唯一技能铁锤100龟能+被动计数器
			u["active_skills"] = ["eliteHammer"]
			u["energy_cost"]["eliteHammer"] = 100.0
			u["_eb_n"] = 0
			u["_hammer_n"] = 0
			u["_whip_cd"] = 0.0
		elif str(spec.get("role", "front")) == "front":   # 近战小将·人体浪板(120龟能·射程2000·用户2026-07-18)
			u["active_skills"] = ["minionBodysurf"]
			u["energy_cost"]["minionBodysurf"] = 120.0
		else:                                           # 远程小将·追踪火箭筒(120龟能·射程2000·用户2026-07-18)
			u["active_skills"] = ["minionRocket"]
			u["energy_cost"]["minionRocket"] = 120.0
	if is_trainer:
		u["is_trainer"] = true
		u["_appearance"] = str(sd.get("_appearance", "default"))   # R6-B: 4方向渲染器读它选帧表
		u["no_move"] = true              # 场外监视者: 站着不动
		u["no_basic"] = true             # ★关掉 AI 默认普攻(BASIC_ATK 发子弹) —— 训龟大师【只】走
		#   battle._trainer_sys._tick_trainer_attacks 扔石头这一条。不关的话两条并行 = 同时扔石头又发子弹
		#   (用户 2026-07-23:「为什么同时在扔石头和发射子弹」)。
		u["active_skills"] = []          # 法术 5 选 1 待设计(用户: "法术技能待制作")
	if is_egg:
		u["_isEgg"] = true
		u["_eggImmune"] = true          # 免控/斩/嘲讽
		u["_egg_fence"] = true           # 围栏未破: 单体+AoE都不可锁(用户2026-07-12) + 屏障+200双抗(用户2026-07-19: 80→200)
		# 蛋双抗 = 60 + 15×大轮等级 (用户2026-07-19; 原为定值60不随等级)
		var _egg_res: float = 60.0 + 15.0 * float(int(spec.get("level", u.get("level", 1))))
		u["def"] = _egg_res + battle.EGG_FENCE_RES; u["mr"] = _egg_res + battle.EGG_FENCE_RES
		u["base_def"] = _egg_res + battle.EGG_FENCE_RES; u["base_mr"] = _egg_res + battle.EGG_FENCE_RES
		u["egg_side_lr"] = str(spec.get("egg_side", "left"))   # 该蛋归属方(left/right), 写回 GameState.egg_hp
		# ★当前血=跨路累积受损值(maxHp保持原始满血) → 血条显示 累积伤害 1800/2500 而非满条(用户2026-07-12「明明蛋掉血了到第二战场还满血」)
		u["hp"] = clampf(float(spec.get("hp", u["maxHp"])), 1.0, float(u["maxHp"]))
		u["no_move"] = true; u["no_basic"] = true
	return u

func _spawn_trainers() -> void:
	# NO_TRAINER: 胜率对照实验要干净环境(见 RealtimeBattle3DScene.NO_TRAINER 的注释)
	if OS.has_environment("VFXPREVIEW") or OS.has_environment("NO_TRAINER") or battle.DEBUG_EDIT or battle.NO_TRAINER:
		return
	for u in battle._units:
		if u.get("is_trainer", false):
			return
	# ★站位: 各自【蛋的后上方】。蛋在左右两侧的中间高度(_cy), 所以这里也用中间高度,
	#   只在纵向让开一点免得和蛋重叠。
	#   2026-07-22 截图复盘: 初版写的是 battle.ARENA.position.y + 60 = 战场【上边缘角落】,
	#   而蛋在左侧中间 —— 于是他既不在基地后面也不在战斗附近, 视觉上完全不成立。
	#   (这类"位置对不对"只有真截图才看得出来, 门禁 100% 绿也照样是错的。)
	var _tcy: float = battle.ARENA.position.y + battle.ARENA.size.y * 0.5
	var back_y: float = _tcy - 150.0
	battle._units.append(_make_unit(battle.TRAINER_ID, "left", Vector2(battle.ARENA.position.x + 40.0, back_y), {"trainer": true}))
	battle._units.append(_make_unit(battle.TRAINER_ID, "right", Vector2(battle.ARENA.end.x - 40.0, back_y), {"trainer": true}))
	# 装配(用户2026-07-23): 我方(left)读 GameState 局外配置; 敌方(right)默认钩锁(将来接快照 loadout)。
	for u in battle._units:
		if not u.get("is_trainer", false):
			continue
		if str(u.get("side", "")) == "left":
			# 单技能装配(2026-07-26): GameState.trainer_skill 派生出【主动或空】+【被动或空】。
			var _act: String = GameState.trainer_active_skill()   # 主动 id, 或 ""(装配的是被动)
			u["_tr_active"] = battle._valid_active(_act) if _act != "" else ""
			u["_tr_passive"] = GameState.trainer_passive_skill()  # "magic_stone" 或 ""
		else:
			# ★2026-07-27 接上原注释里的「将来接快照 loadout」: 敌方大师读【对手快照】装配的技能。
			#   原来恒为 "hook" —— 玩家能选五种, 对手永远只会钩锁, 是系统性不对称;
			#   队列模拟里更致命(左侧用自选技能、右侧恒钩锁 → 左侧系统性占优, 胜负数据失真)。
			#   老快照没有 trainer_skill 字段 → 仍回落 "hook", 向后兼容。
			var _gsk := ""
			if GameState != null and GameState.dual_ghost is Dictionary:
				_gsk = str((GameState.dual_ghost as Dictionary).get("trainer_skill", ""))
			if _gsk == "":
				_gsk = "hook"
			u["_tr_active"] = "" if _gsk == "magic_stone" else battle._valid_active(_gsk)
			u["_tr_passive"] = "magic_stone" if _gsk == "magic_stone" else ""
	# ★★回填魔法石叠层(用户 2026-07-30"跨路保留")。
	#   本函数【每路都被 _dl_build_lane_field 调一次】, 大师是全新字典 → 层数天然归零。
	#   0.17.18 只删掉了 _dl_start_fight 里的显式清零, 根本不够 —— 真正的丢失点在这里。
	#   双方都回填: 对面大师也在攒层。
	for u in battle._units:
		if u.get("is_trainer", false):
			battle._trainer_sys._ms_restore_stacks(u)
	battle._hud._build_trainer_joystick()
	battle._hud._build_spell_disc()

## 校验装配的主动 id 合法(旧档/脏数据兜底为 hook)。
func _apply_spawn_passives() -> void:
	for u in battle._units.duplicate():
		_apply_spawn_passive_one(u)
	# 选中被动技开局生效 (不进主动轮转): 凤凰强化涅槃 等 (寒冰极寒已改常驻被动, 见ice分支)
	for u in battle._units:
		if "phoenixEnhancedRebirth" in battle._chosen_skill_types(u["id"], u["side"] == "left"):
			u["_enh_rebirth"] = true   # 强化涅槃: 复活100%血+永久+20%攻击(见_kill)
		if "angelBless" in battle._chosen_skill_types(u["id"], u["side"] == "left"):
			u["_angel_revive"] = true  # 天使祝福绑定: 选祝福→自身首死25%复活(见_kill)
		if "angelAscend" in battle._chosen_skill_types(u["id"], u["side"] == "left"):
			u["_ascend_growth"] = true  # 天使飞升打包被动(用户2026-07-28): 每次普攻命中 +5龟能 +1%攻击力(见_on_basic_hit)
		if "rainbowReflect" in battle._chosen_skill_types(u["id"], u["side"] == "left"):
			u["_enh_prism"] = true      # 彩虹反射打包强化棱镜4色(每5s抽色·见_tick_periodic)

## 单个单位的登场被动(2026-07-17抽出: 缩头随从=实体完整龟, 它对应的被动也要正常·用户"什么被动什么显示和动画都得正常")
func _apply_spawn_passive_one(u: Dictionary) -> void:
	match u["id"]:
		"rainbow":
			u["prism_color"] = battle._juice_rng.randi() % 3   # 开局即给棱镜色(修: 原-1致前6秒普攻无附色)
		"stone":
			if "rockShockwave" in battle._chosen_skill_types(u["id"], u["side"] == "left") or (battle._review_demo() and u["id"] == battle._review_turtle()):
				u["stone_rockbody"] = true   # 岩石之躯(实战: 选rockShockwave技2才有·打包被动); 特效验收时给受审石头强制开→单独看被动体型增长
		"ninja":
			u["crit"] += 0.20; u["crit_dmg"] += 0.15; u["armor_pen"] += 10.0   # 忍术(基础被动·用户2026-07-29 第四轮: 暴击30→20 / 暴伤20→15 / 护穿8→10)
			if "ninjaShuriken" in battle._chosen_skill_types(u["id"], u["side"] == "left"):   # 忍者足(技三打包·选中才有): +15%闪避+30%暴击
				# ★用户2026-07-29 第四轮: 25%/40% → 15%/30%。叠上忍术后暴击总量 95% → 75%。
				battle._damage._buff(u, "dodge", 0.15, false, 9999.0); u["crit"] += 0.30
		"ghost":
			for o in battle._targeting._enemies_of(u):
				battle._damage._add_curse(o, GhostSystem.SPAWN_CURSE_SEC, u)   # 登场诅咒(用户2026-07-28: BUFF_SEC 5s → 4s; 死亡诅咒仍 5s)
		"ice":
			u["_vs_fire_bonus"] = 0.2          # 寒域: 对熔岩/凤凰 +20%伤害
			u["_burnImmune"] = true            # 极寒(用户设计L162: 改常驻被动): 免疫灼烧
			battle._ice_sys._ice_chill_vfx(u["pos"], true)     # 寒冰自身登场寒爆(大)
			battle._vfx._flash(u, Color(0.6, 0.86, 1.0))   # 自身蓝闪
			for o in battle._targeting._enemies_of(u):
				o["spd_aspd_mult"] = 0.7        # -30% 攻速
				o["spd_echarge_mult"] = 0.7     # -30% 龟能充能速度
				o["spd_move_mult"] = 0.7        # -30% 移速
				o["spd_dbf_until"] = battle._t + 12.0   # 登场全场敌减速【12秒】(用户2026-07-11: 原永久改12秒)
				battle._ice_sys._ice_chill_vfx(o["pos"])        # 敌人寒气蓝环
				battle._vfx._flash(o, Color(0.6, 0.86, 1.0))   # 敌蓝闪
		"headless":
			u["lifesteal"] += 0.22
			u["headless_base_atk"] = float(u.get("base_atk", u.get("atk", 0.0)))   # 亡灵怒: 损血加攻的基准(每帧按损血重算, 见 _tick_periodic_passive)
		"dice":
			u["dice_base_crit"] = u["crit"]   # 基准(供损血暴击率算); 暴伤那半已删 —— 全局已有"暴击率溢出100%每1%→1.5%暴伤"(_resolve_dmg), 不需要单独基准(用户2026-07-19)
			if "diceFlashStrike" in battle._chosen_skill_types(u["id"], u["side"] == "left"):
				u["armor_pen"] += u["base_def"] + u["base_mr"]   # 真正的赌徒(打包稳定骰子): 登场双抗全转等量护穿(纯物理)
				u["base_def"] = 0.0; u["base_mr"] = 0.0; battle._recalc_stats(u)
		"gambler":
			if "gamblerFateWheel" in battle._chosen_skill_types(u["id"], u["side"] == "left"):   # 命运之轮(技三打包被动·选中才有)·用户2026-07-09重设计
				u["hp"] = maxf(1.0, u["hp"] - u["maxHp"] * 0.30)   # 登场损30%当前血(=30%maxHp·上限不变)
				u["multi_base"] = 0.60                              # 永久基础多重概率40%→60%(与赌注+20%叠加可到80%)
				battle._vfx._float_text(u["pos"] + Vector2(0, -64), "命运之轮 -30%HP", Color("#ff5566"))
				if u["side"] == "left": battle._gambler_sys._gambler_apply_wheel_stacks(u)   # 跨场累积: 登场套用本大轮已抽花色(切轮重置·方案B·只玩家)
		"pirate":
			var es = battle._targeting._pick_enemies_of(u)
			if not es.is_empty():
				var v = es[battle._battle_rng.randi() % es.size()]
				var pship = battle._pirate_sys._pirate_get_ship(u)   # 掠夺·登场轰击: 从海盗船发炮弹弹道→命中才跳25%目标最大生命真实伤害(用户2026-07-14加弹道·2026-07-10订死数值)
				var ps2d: Vector2 = (pship.get_meta("ship2d") if pship != null else u["pos"] + Vector2(0.0, -260.0))
				var psh: float = (pship.get_meta("ship_h") if pship != null else 5.5)
				battle._pirate_sys._pirate_ship_muzzle(ps2d, psh)
				var uu2: Dictionary = u; var vv2: Dictionary = v
				battle._pirate_sys._pirate_cannonball(ps2d, psh, v["pos"], func() -> void:
					if not vv2.get("alive", false): return
					battle._damage._apply_damage_from(uu2, vv2, int(float(vv2["maxHp"]) * 0.25), Color("#ffd07a"), 0.0, true)
					battle._burst_vfx("res://assets/sprites/vfx/cannon-blast.png", vv2["pos"], 180.0, 0.4)
					battle._shake(0.05))
		"candy":
			# 甜蜜掠夺·甜蜜吸取(用户2026-07-15改"第8秒生效"): 登场不触发→改由 _tick_unit 战斗第8秒调 _candy_sys._candy_sweet_drain 一次
			# 【用户2026纠错】普攻自愈=我自造的(原话普攻只有1.1A+5%maxHp+攻击-15%·无自愈)→删除; 自我回血在焦糖铠/甜蜜吸取
			if "candyBomb" in battle._chosen_skill_types(u["id"], u["side"] == "left"):   # 糖果炸弹(技三·选中才召): HP=50%糖果龟maxHp·每秒衰减8%·死亡爆炸100%
				_spawn_summon(u, "candybomb", u["maxHp"] * 0.50, 0.0, {
					"label": "糖果炸弹", "spr_id": "candy-bomb", "col_size": 20.0, "hp_w": 24.0,
					"no_basic": true, "no_move": true, "self_decay": 0.08,
					"death_aoe": battle._candy_sys.BOMB_DEATH_AOE,
				})
		"chest":
			if (not battle._review_demo()) and str(u.get("side", "")) == "left" and GameState != null:
				for _tw0 in GameState.chest_treasures_won:     # 大轮已开战利品→开局回装(常驻整轮·用户2026-07-16)
					battle._chest_sys._chest_apply_treasure(u, str(_tw0))
			if "chestCannon" in battle._chosen_skill_types(u["id"], u["side"] == "left"):   # 贪婪(技三打包被动)选中才有
				u["chest_greed"] = true
				u["chest_greed_atk_unit"] = u["base_atk"] * 0.04
				u["chest_greed_hp_unit"] = u["maxHp"] * 0.07
				battle._chest_sys._chest_greed_apply(u, (u.get("equips", []) as Array).size())   # 登场先按已带装备数结算
		"hiding":
			_spawn_hiding_minion(u)
		"cyber":
			if "cyberSmartAI" in battle._chosen_skill_types(u["id"], u["side"] == "left"):
				u["move_spd"] = float(u.get("move_spd", 105.0)) * 1.2   # 智能AI(技三·选中): 登场+20%移速(常驻走位)
				u["cyber_ai_charge"] = 3   # 用户2026-07-07逐字"赛博龟登场时拥有3层充能" (此前漏做, 从0起算)
				# ⚠ 充能的【消耗方式与收益】用户从未定义 → 现仅作计数(_cyber_sys._sk_cyber_smart 每次释放+1), 不猜、不自造。
		"crystal":
			if "crystalBall" in battle._chosen_skill_types(u["id"], u["side"] == "left"):   # 水晶球(技三·选中才召): 登场召唤实体水晶球(2026-07-16加大+特效)
				var _orb = _spawn_summon(u, "crystalball", u["maxHp"] * 0.50, u["atk"], {
					"label": "水晶球", "spr_id": "crystal-ball", "col_size": 38.0, "hp_w": 40.0, "melee": false,
					"move_spd": 90.0, "atk_range": 2000.0, "no_basic": true,   # 射程2000(用户2026-07-16)
					"special": "ray", "special_cd": 5.0, "special_scale": 0.5,   # 攻速0.2≈5s一发(封板)·每发2段共1.0A魔法
				})
				if _orb != null:                              # 登场爆闪+常驻脉动光环(用户2026-07-16: 球太小没特效)
					battle._skill_ring(_orb["pos"], Color(0.72, 0.92, 1.0, 0.8), 46.0)
					battle._vfx._flash(_orb, Color(1.5, 1.8, 2.0))
					battle._crystal_sys._crystal_orb_halo(_orb)
		"two_head":
			u["two_form"] = "ranged"; u["melee"] = false; u["atk_range"] = 400.0   # 双生: 远程起手
			if "twoHeadFusion" in battle._chosen_skill_types(u["id"], u["side"] == "left"):
				u["two_fused"] = true                          # 融合: 锁形态(保持远程)+坚韧+合体近战属性
				battle._two_head_sys._two_head_apply_melee(u, true)
				battle._two_head_sys._two_head_fusion_onset(u)                      # 融合登场VFX(用户2026-07-11): 合体爆发+持续融合态光环
		"diamond":                                    # 钻石结构(封板): 全队护甲/魔抗加成+50%(简化=开局全队+50%pct); 选钻石冲撞→强化结构(自身额外+100%·"受击再减20甲10抗"近似折进护甲留F5)
			for o in battle._targeting._allies_of(u):
				battle._damage._buff(o, "def", 0.5, true, 9999.0)
				battle._damage._buff(o, "mr", 0.5, true, 9999.0)
			if "diamondSmash" in battle._chosen_skill_types(u["id"], u["side"] == "left"):   # 强化钻石结构(技三打包·选中才有): 自身护甲/魔抗额外+100%
				battle._damage._buff(u, "def", 1.0, true, 9999.0)
				battle._damage._buff(u, "mr", 1.0, true, 9999.0)

func _spawn_hiding_minion(u: Dictionary) -> void:
	var pool: Array = battle._hiding_sys._hiding_pool()
	var pick: String = pool[battle._battle_rng.randi() % pool.size()]
	var d: Dictionary = battle._data_by_id.get(pick, {})
	var st: Array = battle.STATS.get(pick, battle.DEFAULT_STAT)
	var _lm: float = battle._lvl_mult_for(u)                # 固定值召唤吃等级
	# ★2026-07-10订正: 旧注释写"召唤=主人最终hp×40%"是错的。d = 【被召唤那只龟】的数据 → HP/ATK 都按【它自己】的基础值算。
	#   HP = 该龟 hp × 40% (×等级);  ATK = 该龟 atk × 80% (×等级);  def/mr/crit 照该龟原值 (见下)。
	var hp: float = float(d.get("hp", 1350)) * 0.40 * _lm
	var minion = _spawn_summon(u, "minion", hp, float(d.get("atk", 40)) * 0.8 * _lm, {
		"label": "随从", "spr_id": pick, "col_size": 36.0, "hp_w": 30.0,
		"melee": bool(st[0]), "move_spd": float(st[1]), "atk_interval": float(st[2]), "atk_range": float(st[3]),
		"crit": float(d.get("crit", 0.2)),
	})
	if minion != null:
		minion["minion_kind"] = pick
		# (2026-07-17用户"除了血量以外其他东西应该和该龟一模一样"→撤掉曾加的评审场充能×4, 随从充能=真身原速)
		# A方案·完整乌龟随从: 真·某龟种(id-keyed普攻/被动/技能触发) + 带自己技能/龟能/AI
		minion["id"] = pick
		minion["rarity"] = str(d.get("rarity", "C"))
		minion["base_def"] = float(d.get("def", 10)) * _lm; minion["def"] = minion["base_def"]   # 属性正常(补def/mr·原召唤=0)
		minion["base_mr"] = float(d.get("mr", 10)) * _lm; minion["mr"] = minion["base_mr"]
		minion["crit_dmg"] = 1.5
		minion["level"] = int(u.get("level", 1))
		minion["active_skills"] = battle._resolve_active_skills(pick, false)   # 带自己技能(默认3选1·resolve为1个active)
		minion["skill_cd"] = {}                                         # 施法需(防u["skill_cd"][stype]崩)
		minion["skill_gcd_until"] = 0.0
		battle._recalc_stats(minion)
		var _enf = minion.get("en_fill", null)                          # A方案随从带自己技能→龟能条恢复显示(通用召唤体在_spawn_summon里hide·用户2026-07-17"随从我都没看到技能龟能")
		if _enf != null and is_instance_valid(_enf): _enf.visible = true
		minion["passive"] = d.get("passive", null)                      # 被动数据(特殊资源条/口径跟真龟一致)
		_apply_spawn_passive_one(minion)                                # 实体完整龟: 对应登场被动正常生效(用户2026-07-17"什么被动什么显示和动画都得正常")
		battle._hiding_sys._hiding_summon_vfx(minion["pos"])                               # 召唤法阵+光柱+星粒+落地尘(2026-07-17·原无演出)

func _spawn_pirate_ship(u: Dictionary, tgt = null) -> void:   # 首次: 后方持久演出船俯冲冲锋→撞击点转变为实体海盗船参战(用户2026-07-14设计)
	var aim = tgt if (tgt != null and tgt.get("alive", false)) else battle._targeting._nearest_enemy(u)
	if aim == null:
		return
	var impact2d: Vector2 = aim["pos"]
	var deco = battle._pirate_sys._pirate_get_ship(u)                        # 后方持久演出船=这次冲锋的船
	var from2d: Vector2 = (deco.get_meta("ship2d") if deco != null else u["pos"] + Vector2(0.0, -320.0))
	var from_h: float = (deco.get_meta("ship_h") if deco != null else 6.0)
	if deco != null:                                       # 杀掉驻场轻摇tween(要冲锋了)
		var bt = deco.get_meta("bob_tw", null)
		if bt != null and is_instance_valid(bt) and bt is Tween: bt.kill()
	battle._pirate_sys._pirate_ship_muzzle(from2d, from_h); battle._pirate_sys._pirate_ship_muzzle(from2d + Vector2(30, 0), from_h)   # 蓄力: 炮口全闪
	var uu: Dictionary = u
	battle._pirate_sys._pirate_ship_charge(deco, from2d, from_h, impact2d, func() -> void:   # 俯冲到撞击点→结算+转变实体
		battle._pirate_sys._pirate_ship_splash(impact2d)                     # 大水花爆
		battle._skill_ring(impact2d, Color(0.9, 0.7, 0.4, 0.6), 200.0)
		battle._shake(battle.JUICE_SHAKE_HEAVY)
		var ship = _spawn_pirate_ship_entity(uu, impact2d)   # 撞击点淡入实体海盗船(pirate-ship.png)
		var src: Dictionary = ship if ship != null else uu
		for e in battle._targeting._enemies_of(uu):                         # 撞击: 200码内1.0A魔法+击飞2秒(封板)
			if not e.get("alive", false): continue
			if e["pos"].distance_to(impact2d) > 200.0: continue
			battle._damage._apply_damage_from(src, e, battle._atk_dmg(uu, 1.0, e, true), Color("#e8c07a"), 0.0, true)
			battle._damage._knockback(src, e, 40.0, 3.667, 1.0)
			battle._damage._stun(e, 2.0, "_spawn_pirate_ship")
		if deco != null and is_instance_valid(deco): deco.queue_free()   # 演出船"化作"实体→消失
		uu["_perf_ship"] = null)

func _spawn_pirate_ship_entity(u: Dictionary, at2d: Vector2):   # 实体海盗船(封板值·pirate-ship.png立绘)落在撞击点·淡入
	var ship = _spawn_summon(u, "ship", u["maxHp"] * 1.5, u["atk"], {
		"label": "海盗船", "spr_id": "pirate-ship", "col_size": 54.0, "hp_w": 58.0, "melee": true,   # 近战(用户2026-07-14)
		"move_spd": 40.0, "atk_range": 110.0, "no_basic": true,                 # 重船慢移(用户"再慢一点"·40)+近战射程110(用户2026-07-14)
		"special": "ship_shot", "special_cd": 1.25, "special_scale": 0.4,       # 攻速0.8≈1.25s/发·近身0.4A(封板伤害)
	})
	if ship == null:
		return null
	ship["pos"] = at2d
	ship["bar_head_h"] = 4.2   # 血条抬高(用户2026-07-14·大船血条不压船身)
	var spr = ship.get("sprite", null)
	if spr != null and is_instance_valid(spr):             # 立绘调大到船尺度(比召唤体大·船该大) + 落场淡入砸落回弹
		if spr.texture != null:
			spr.pixel_size = (165.0 * battle.WS) / float(maxi(1, spr.texture.get_height()))
			spr.offset = Vector2(0.0, spr.texture.get_height() * 0.42)   # 底对齐(船底贴地)
		ship["_ship_big"] = true
		spr.modulate.a = 0.0
		var tw = battle._reg_tween(); tw.set_parallel(true)
		tw.tween_property(spr, "modulate:a", 1.0, 0.25)
		tw.tween_property(spr, "scale", spr.scale, 0.2).from(spr.scale * 1.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return ship

func _spawn_summon(owner: Dictionary, kind: String, hp: float, atk: float, behavior: Dictionary = {}):
	var pos: Vector2 = owner["pos"] + Vector2(randf_range(-40, 40), randf_range(30, 60))
	pos.x = clampf(pos.x, battle.ARENA.position.x, battle.ARENA.end.x)
	pos.y = clampf(pos.y, battle.ARENA.position.y, battle.ARENA.end.y)
	var col = Color("#3fa9ff") if owner["side"] == "left" else Color("#ff5a5a")
	var spr_id: String = str(behavior.get("spr_id", ""))
	var col_size: float = float(behavior.get("col_size", 22.0))

	# --- 立绘/色块 billboard ---
	var spr = Sprite3D.new()
	spr.name = "Summon_" + kind
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var su_sd: Dictionary = battle._resolve_summon_sprite(spr_id)
	var tex: Texture2D = su_sd.get("tex", null)
	var su_grounded: ShaderMaterial = null
	if tex != null:
		var fh: int = int(su_sd.get("frame_h", tex.get_height()))
		# 召唤体按 col_size 缩放 (相对全身龟略小): 帧高归一到 ~col_size*battle.WS 的世界高
		spr.texture = tex
		spr.hframes = int(su_sd.get("hframes", 1))
		spr.vframes = int(su_sd.get("vframes", 1))
		spr.frame = 0
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED    # 接地 shader 自管 alpha (软渐隐), 不硬切
		spr.pixel_size = (battle.TARGET_BODY_H * (col_size / 56.0)) / float(maxi(1, fh))
		spr.offset = Vector2(0.0, fh * 0.5)
		su_grounded = battle._make_grounded_material(tex, su_sd)   # §GROUNDING 软渐隐 (动画召唤体)
		spr.material_override = su_grounded
	else:
		spr.texture = VfxTex._make_fire_glow_tex()                  # 无专属立绘: 软发光球(队色)替硬色块 — 不留 ColorRect 占位感
		spr.modulate = Color(col.r, col.g, col.b, 0.95)
		spr.pixel_size = (col_size * 1.4 * battle.WS) / 96.0
		spr.offset = Vector2(0.0, 30.0)
	spr.position = battle._world_pos(pos, battle.GROUND_LIFT)
	battle._world.add_child(spr)

	# --- blob 暗影 ---
	var shadow = Sprite3D.new()
	shadow.texture = VfxTex._make_blob_texture()
	shadow.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	shadow.axis = Vector3.AXIS_Y
	shadow.pixel_size = 0.008
	shadow.shaded = false
	shadow.transparent = true
	shadow.modulate = Color(1, 1, 1, battle.SHADOW_BASE_A)
	shadow.scale = battle.SHADOW_BASE * 0.6
	shadow.position = battle._world_pos(pos, 0.02)
	battle._world.add_child(shadow)

	# --- HP overlay (召唤体只有血条, 无等级牌) ---
	var bar = battle._make_status_bar(owner["side"], 0)
	bar["en"].visible = false
	battle._ui_layer.add_child(bar["root"])

	var hp_w: float = float(behavior.get("hp_w", 28.0))
	var su = {
		"id": "_summon_" + kind, "name": str(behavior.get("label", kind)), "rarity": "C", "side": owner["side"],
		"pos": pos, "vel": Vector2.ZERO,
		"height": 0.0, "vy": 0.0, "vx": 0.0, "vz": 0.0, "airborne": false,
		"hp": hp, "maxHp": hp,
		"atk": atk, "def": 0.0, "mr": 0.0, "base_atk": atk, "base_def": 0.0, "base_mr": 0.0,
		"crit": float(behavior.get("crit", 0.0)), "crit_dmg": 1.5, "lifesteal": 0.0,
		"armor_pen": 0.0, "armor_pen_pct": 0.0, "magic_pen": 0.0, "magic_pen_pct": 0.0,
		"heal_amp": 0.0, "shield_amp": 0.0, "damage_reduction": 0.0, "damage_amp": 0.0, "reflect": 0.0, "tenacity": 0.0,
		"melee": bool(behavior.get("melee", kind != "drone")),
		"move_spd": float(behavior.get("move_spd", 0.0 if behavior.get("no_move", false) else SUMMON_DEFAULT_SPD)),
		"atk_interval": float(behavior.get("atk_interval", 1.2)),
		"atk_range": float(behavior.get("atk_range", 280.0 if kind == "drone" else 70.0)),
		"atk_cd": 0.0, "energy": 0.0, "alive": true, "is_summon": true,
		"shield": 0.0, "stun_until": 0.0, "slow_until": 0.0,
		"dot_stacks": {}, "_dottimer": 0.0, "dot_src": {}, "true_fire_until": 0.0, "_dot_float": {},
		"buffs": [], "dots": [], "taunt_until": 0.0, "taunt_by": null,
		"dodge_bonus": 0.0, "ls_bonus": 0.0,
		"stacks": {}, "rage": 0.0, "star_energy": 0.0, "store_energy": 0.0, "gold": 0.0,
		"dmg_dealt": 0.0, "reborn_used": false, "untargetable_until": 0.0, "summons": [],
		# 召唤 AI 行为字段 ----
		"summon_kind": kind, "summon_owner": owner, "hp_w": hp_w,
		"no_basic": bool(behavior.get("no_basic", false)),
		"no_move": bool(behavior.get("no_move", false)),
		"summon_special": str(behavior.get("special", "")),
		"special_cd": float(behavior.get("special_cd", 0.0)),
		"special_timer": 0.0,
		"special_scale": float(behavior.get("special_scale", 1.0)),
		"death_aoe": float(behavior.get("death_aoe", 0.0)),
		"self_decay": float(behavior.get("self_decay", 0.0)),
		"equips": [], "eq_state": {}, "hp50_fired": false,
		# 节点引用
		"sprite": spr, "shadow": shadow, "ring": null, "shadow_base_scale": battle.SHADOW_BASE * 0.6,
		"bar_root": bar["root"], "hp_bar": bar["hp_bar"], "en_fill": bar["en"], "level_badge": bar.get("level_badge", null),
		"spr_base_offy": spr.offset.y,
		# 立绘动画态 (召唤体若有 sheet 也循环 idle) ----
		"grounded_mat": su_grounded,
		"idle_sd": su_sd, "idle_px": spr.pixel_size, "idle_offy": spr.offset.y,
		"anim_t": 0.0, "anim_sd": su_sd, "anim_action": "",
		# Phase4 juice 态 (召唤体同享 squash/闪白/bob) ----
		"spr_base_scale": spr.scale,
		"flash_t": 0.0, "hitsq_t": 0.0, "land_t": 0.0, "swing_t": 0.0, "windup_t": 0.0,
		"bob_phase": randf() * TAU,
	}
	battle._units.append(su)
	return su

