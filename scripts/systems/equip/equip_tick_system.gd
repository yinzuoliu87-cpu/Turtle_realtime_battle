class_name EquipTickSystem
extends RefCounted
## 装备周期效果tick系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

# 数据驱动基础技能: 按 spec 算物/魔/真伤(含加成项)分段打出 + 附带/特殊机制 (1:1 原始 skillPool[0])
func _tick_doll(u: Dictionary, delta: float) -> void:   # 玩偶小熊: 每4s派小熊+攒层; 满层→蓄力→召大熊(不与末只小熊同帧)
	var es: Dictionary = u.get("eq_state", {})
	if not es.has("p2eq_034"): return
	var stt: Dictionary = es["p2eq_034"]
	if bool(stt.get("bear_done", false)) or bool(stt.get("bear_charging", false)): return
	var si: int = int(stt.get("doll_si", 0))
	var _iv: float = 1.0 if OS.has_environment("EQDEMO_FAST") else 4.0   # FAST=快速看波
	stt["doll_t"] = float(stt.get("doll_t", 0.0)) + delta
	if float(stt["doll_t"]) < _iv: return
	stt["doll_t"] = 0.0
	var mt = battle._targeting._nearest_enemy(u)
	if mt == null: return
	var bdm: int = battle._resolve_dmg(u, u["atk"] * [1.0, 2.0, 5.0][si] + [100.0, 210.0, 1000.0][si], mt, false)
	battle._summon_walking_bear(u, mt, bdm)
	stt["bear_layers"] = int(stt.get("bear_layers", 0)) + 1
	var _cap: int = 1 if OS.has_environment("EQDEMO_FAST") else [5, 3, 1][si]
	if int(stt["bear_layers"]) >= _cap:
		stt["bear_charging"] = true
		battle._big_bear_charge_and_spawn(u, si)

func _tick_bear_anim(u: Dictionary, delta: float) -> void:   # 大熊状态机: 移动→走路循环 / 停下→顿住 / 拍击→熊爪 / 冲击波→举手砸地
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr): return
	var ne = battle._targeting._nearest_enemy(u)                     # 朝向最近敌(熊默认朝左→敌在右则flip朝右; 迟滞防抖)
	if ne != null and absf(float(ne["pos"].x) - float(u["pos"].x)) > 40.0:
		spr.flip_h = float(ne["pos"].x) > float(u["pos"].x)
	u["bear_anim_t"] = float(u.get("bear_anim_t", 0.0)) + delta
	var anim = str(u.get("bear_anim", "walk"))
	var voff = Vector3.ZERO
	var ldir: Vector3 = u.get("_bear_ldir", Vector3.ZERO)
	if anim == "attack" or anim == "slam":
		if str(u.get("_bear_sheet", "")) != anim:
			battle._set_bear_sheet(spr, anim); u["_bear_sheet"] = anim; u["bear_anim_t"] = 0.0
		var per: float = 0.07 if anim == "attack" else 0.085
		var total: float = per * float(maxi(1, int(spr.hframes)))
		var prog: float = clampf(float(u["bear_anim_t"]) / maxf(0.01, total), 0.0, 1.0)
		var f: int = int(float(u["bear_anim_t"]) / per)
		if f >= int(spr.hframes):
			if u.get("_slam_manual", false):
				spr.frame = int(spr.hframes) - 1   # 手控砸地: 定住末帧(等波传完, 不回走路循环=修漂移)
			else:
				u["bear_anim"] = "walk"          # 播完回走路/待机
		else:
			spr.frame = f
		if anim == "attack":
			voff = ldir * (sin(prog * PI) * 0.55)          # 前扑扑击(前冲再回)
			voff.y += sin(prog * PI) * 0.14                # 略抬(挥爪)
		# slam 的位移由 _bear_shockwave 手控(_slam_manual), 这里只推进帧
	else:   # walk / idle: 移动→循环走路, 停下→站立顿住(frame0)
		if str(u.get("_bear_sheet", "")) != "walk":
			battle._set_bear_sheet(spr, "walk"); u["_bear_sheet"] = "walk"
		var pv: Vector2 = u.get("_bear_pp", u["pos"])
		var moving: bool = (u["pos"] - pv).length() > 0.6
		u["_bear_pp"] = u["pos"]
		if moving:
			spr.frame = int(float(u["bear_anim_t"]) * 9.0) % maxi(1, int(spr.hframes))
		else:
			spr.frame = 0
	if not u.get("_slam_manual", false):   # 砸地手控voff期间不覆盖
		u["_bear_voff"] = voff

func _tick_fortress(u: Dictionary, delta: float) -> void:   # 深海堡垒甲p2eq_014: 硬化满20层后每8秒汲取全体敌(魔伤0.8/1.0/1.5×(护甲+魔抗))+每敌回血; 满层瞬间立即首次; 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_014": continue
		var stt: Dictionary = u["eq_state"].get("p2eq_014", {})
		if int(stt.get("harden_stacks", 0)) < int(stt.get("harden_cap", 25)):
			e["fortress_t"] = 8.0   # 未叠满→预置8(叠满瞬间立即首次汲取)
			continue
		e["fortress_t"] = float(e.get("fortress_t", 0.0)) + delta
		if float(e["fortress_t"]) < 8.0: continue
		e["fortress_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		var k2: float = [0.9, 1.6, 3.0][si]   # 用户2026-07-19: 0.8/1.0/1.5 -> 1/2/4 -> 0.9/1.6/3
		for o in battle._targeting._enemies_of(u):
			battle._bolt_line(o["pos"], u["pos"], Color("#bfe9ff"))
			battle._damage._apply_damage_from(u, o, battle._resolve_dmg(u, k2 * (u["def"] + u["mr"]), o, true), Color("#bfe9ff"), 0.0, false, true)   # 真·魔法伤害(走魔抗); 原 raw=true 是白字真伤·与文案"魔法伤害"不符(用户2026-07-19指出)
			battle._damage._heal(u, [60.0, 110.0, 250.0][si] + maxf(0.0, u["maxHp"] - u["hp"]) * 0.06)   # 用户2026-07-19: 60/110/250 + 已损生命6%(逐敌结算)

func _tick_ironwall(u: Dictionary, delta: float) -> void:   # 铁壁盾p2eq_016: 每5秒放一个总护盾池(100/250/400 + 携带者8%最大生命)由全队(含自己)均分(用户2026-07-19; 原每人固定15/20/25); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_016": continue
		e["ironwall_t"] = float(e.get("ironwall_t", 0.0)) + delta
		if float(e["ironwall_t"]) < 5.0: continue
		e["ironwall_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		var mates: Array = battle._targeting._allies_no_trainer(u)   # ★均分排除大师(不占盾份额·稀释)·用户2026-07-23 点4
		if mates.is_empty(): continue
		var pool: float = [100.0, 250.0, 400.0][si] + u["maxHp"] * 0.08   # 总池: 固定 + 携带者8%最大生命
		var each: float = pool / float(mates.size())                      # 全队(含自己·除大师)均分
		for o in mates:
			battle._damage._grant_shield(o, each)

func _tick_thunder(u: Dictionary, delta: float) -> void:   # 雷鸣贝壳p2eq_025: 每4秒降N道大雷(道间错峰0.3s), 各劈随机敌1×ATK真伤(伤害在闪电中段跳); 每件独立(用户2026-07-02: 原2.5s)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_025": continue
		e["thunder_t"] = float(e.get("thunder_t", 0.0)) + delta
		if float(e["thunder_t"]) < 4.0: continue
		e["thunder_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		for d in range([1, 2, 3][si]):                # 道间错峰
			var tw = battle._reg_tween()
			tw.tween_interval(float(d) * 0.3)
			tw.tween_callback(battle._thunder_bolt.bind(u))

# 029 冰封水母(布隆大招式): 每12秒→自身上盾→砸地→朝最近敌生成冰道(500x90)→命中魔法伤+击飞0.6s+冰封2.5s
func _tick_ice_fissure(u: Dictionary, delta: float) -> void:
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_029": continue
		e["fissure_t"] = float(e.get("fissure_t", 0.0)) + delta
		if float(e["fissure_t"]) < 12.0: continue
		e["fissure_t"] = 0.0
		battle._equip_sys._eq_ice_fissure(u, battle._equip_sys._eq_si(int(e.get("star", 1))))

func _tick_gear(u: Dictionary, delta: float) -> void:   # 黄铜齿轮035(用户2026-07-18改: 随时间铸币·每6秒左队携带者直接+1/2/3深海币+飘字·跟死亡无关·原"攒齿轮层战斗结束折币"改掉)
	if u.get("equips", []).is_empty(): return
	if str(u.get("side", "")) != "left": return   # 深海币=玩家侧meta货币, 只玩家(左队)携带者产币
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_035": continue
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get("p2eq_035", {})
		stt["gear_t"] = float(stt.get("gear_t", 0.0)) + delta
		if float(stt["gear_t"]) >= 6.0:
			stt["gear_t"] = float(stt["gear_t"]) - 6.0
			var coins: int = [1, 2, 3][si]
			var gs = battle.get_node_or_null("/root/GameState")
			if gs != null and gs.get("meta_deepsea_coins") != null:
				gs.set("meta_deepsea_coins", int(gs.get("meta_deepsea_coins")) + coins)
			battle._vfx._float_text(u["pos"], "+%d💠" % coins, Color("#5fd0e0"))   # 可见反馈(用户: 之前无反馈以为没生效)
			stt["coins_made"] = int(stt.get("coins_made", 0)) + coins   # 头像装备格徽章显示本局累计产币(用户2026-07-19)
		u["eq_state"]["p2eq_035"] = stt

func _tick_shell(u: Dictionary, delta: float) -> void:   # 守护贝壳p2eq_018: 每8秒自回(30/45/60+5/9/15%maxHP)生命(受治疗增幅); 每件独立(用户2026-07-02, 原2.5s)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_018": continue
		e["shell_t"] = float(e.get("shell_t", 0.0)) + delta
		if float(e["shell_t"]) < 8.0: continue
		e["shell_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		battle._damage._heal(u, [30, 45, 60][si] + u["maxHp"] * [0.05, 0.09, 0.15][si])
		battle._shell_sys._shell_guard_fx(u)   # 半壳合拢护罩演出(用户2026-07-19)

func _tick_anemone(u: Dictionary, delta: float) -> void:   # 海葵药膏p2eq_019: 每7秒奶自己+最低血友军(30/45/60+12/14/18%目标已损血)×海葵增幅; 累计200/180/150治疗+1海葵层(治疗&盾强度+8/9/10%/层); 每件独立(用户2026-07-02,原2.5s)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_019": continue
		e["anemone_t"] = float(e.get("anemone_t", 0.0)) + delta
		if float(e["anemone_t"]) < 7.0: continue
		e["anemone_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get("p2eq_019", {})
		# 海葵层的+治疗/护盾强度已经在获得层时真的加进 u.heal_amp/shield_amp (见下), battle._damage._heal 会自己乘, 这里不能再乘一遍
		var h1: float = [30, 45, 60][si] + (u["maxHp"] - u["hp"]) * [0.12, 0.14, 0.18][si]
		var prov19: float = battle._damage._heal(u, h1)                     # 按【实际】回血计数(同017口径·用户2026-07-19)
		var low = battle._lowest_hp_pct_ally(u)                     # 文案是"生命百分比最低"
		if low != null and not is_same(low, u):              # is_same: 单位字典深比较有卡死风险(同053)
			var h2: float = [30, 45, 60][si] + (low["maxHp"] - low["hp"]) * [0.12, 0.14, 0.18][si]
			prov19 += battle._damage._heal(low, h2)
		stt["anemone_heal"] = float(stt.get("anemone_heal", 0.0)) + prov19
		var thr19: float = [200.0, 180.0, 150.0][si]
		while float(stt["anemone_heal"]) >= thr19:
			stt["anemone_heal"] = float(stt["anemone_heal"]) - thr19
			stt["anemone_layers"] = int(stt.get("anemone_layers", 0)) + 1
			var inc19: float = [0.08, 0.09, 0.10][si]
			u["heal_amp"] = float(u.get("heal_amp", 0.0)) + inc19       # 海葵层原来只放大019自己的回血, 文案说的"治疗与护盾强度"根本没生效 → 真的加进全局(用户2026-07-19)
			u["shield_amp"] = float(u.get("shield_amp", 0.0)) + inc19   # 一局内累计不封顶, 单位每场重建 eq_state/heal_amp → 天然重置
			battle._skill_ring(u["pos"], Color(0.55, 0.9, 0.7, 0.5), 44.0)
		u["eq_state"]["p2eq_019"] = stt

func _tick_dumbbell(u: Dictionary, delta: float) -> void:   # 哑铃p2eq_020: 每8秒一套(原地锻炼锁攻锁充能→+锻炼层→蓄力掷哑铃击退); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_020": continue
		e["dumbbell_t"] = float(e.get("dumbbell_t", 0.0)) + delta
		if float(e["dumbbell_t"]) < 8.0: continue   # 每10秒→每8秒(用户2026-07-19)
		e["dumbbell_t"] = 0.0
		if u.get("_slam", false): continue   # 正在别的channel中→跳过本次
		battle._equip_sys._eq_dumbbell_routine(u, battle._equip_sys._eq_si(int(e.get("star", 1))))

# 027 电棍: 每3s就绪→下次普攻消耗1层(附魔法伤+眩晕); 就绪时身上冒电光
func _tick_baton(u: Dictionary, delta: float) -> void:
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_027": continue
		var bst: Dictionary = u["eq_state"].get("p2eq_027", {})
		if int(bst.get("baton_charges", 0)) <= 0:
			bst["baton_ready"] = false; u["eq_state"]["p2eq_027"] = bst; continue
		if not bst.get("baton_ready", false):
			bst["baton_cd"] = float(bst.get("baton_cd", 0.0)) + delta
			if float(bst["baton_cd"]) >= 3.0:
				bst["baton_ready"] = true
		else:
			bst["baton_spark_t"] = float(bst.get("baton_spark_t", 0.0)) + delta
			if float(bst["baton_spark_t"]) >= 0.16:
				bst["baton_spark_t"] = 0.0
				battle._baton_spark(u)
		u["eq_state"]["p2eq_027"] = bst

func _tick_barnacle(u: Dictionary, delta: float) -> void:   # 守护贝母p2eq_021: 持续绿色绑定线连全队最高攻友军; 每5秒重连并为自己+该友军 +10龟能+10%攻速(叠加/本场/每场重置); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_021": continue
		var stt: Dictionary = u["eq_state"].get("p2eq_021", {})
		e["barnacle_t"] = float(e.get("barnacle_t", 0.0)) + delta
		if stt.get("link_target", null) == null or float(e["barnacle_t"]) >= 5.0:   # 首次立即连 + 每5秒重连+给buff
			if float(e["barnacle_t"]) >= 5.0: e["barnacle_t"] = 0.0
			var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
			var prev = stt.get("link_target", null)   # 重连前清上个连接对象的伤害转移标记
			if prev is Dictionary: prev.erase("dmg_redirect_to")
			var best = null; var ba = -1.0
			for o in battle._targeting._allies_of(u):
				if is_same(o, u): continue   # is_same: 单位字典深比较有卡死风险(同053)
				if float(o["atk"]) > ba: ba = float(o["atk"]); best = o
			stt["link_target"] = best
			u["eq_state"]["p2eq_021"] = stt
			var benef: Array = [u]
			if best != null: benef.append(best)
			for o in benef:
				if battle._has_energy_system(o): battle._equip_sys._eq_grant_energy(o, 10.0)   # +10龟能(减冷却)
				o["aspd_perm"] = float(o.get("aspd_perm", 1.0)) + 0.10   # +10%攻速(永久本场,叠加)
				battle._skill_ring(o["pos"], Color(0.55, 1.0, 0.78, 0.5), 44.0)
			if best != null:   # 连接友军: 盾 + 伤害转移(25/40/60%受伤转给携带者); 不净化(用户)
				battle._damage._grant_shield(best, [60.0, 110.0, 180.0][si])   # 用户2026-07-19: 40/60/90→60/110/180
				best["dmg_redirect_to"] = {"carrier": u, "pct": [0.25, 0.40, 0.60][si], "until": battle._t + 5.5}
		battle._update_barnacle_line(u, stt.get("link_target", null))   # 每帧: 持续绿色绑定线(跟随移动/能量脉动)
		break   # 只处理一件(共享绑定线)

func _tick_jelly(u: Dictionary, delta: float) -> void:   # 龟苓膏块p2eq_012: 每4s自护盾(用户2026-07-02, 原走2.5s周期); 每件独立计时
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_012": continue
		e["jelly_t"] = float(e.get("jelly_t", 0.0)) + delta
		if float(e["jelly_t"]) < 4.0: continue
		e["jelly_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		battle._damage._grant_shield(u, [40.0, 60.0, 90.0][si] + u["maxHp"] * 0.04)   # 用户2026-07-19: 30/40/55 → 40/60/90 + 4%最大生命

func _tick_rustblade(u: Dictionary, delta: float) -> void:   # 锈蚀短剑p2eq_001: 每3s就绪, 射程2000(全场)内最近敌即甩飞斩剑气; 每件独立(多件各自触发)
	if u.get("equips", []).is_empty(): return
	var t = null; var got = false; var rng: float = 2000.0   # 射程2000(用户2026-07-19: 近战→远程「裂空飞斩」剑气全场覆盖)
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_001": continue
		e["rust_t"] = float(e.get("rust_t", 0.0)) + delta   # 计时存装备条目→每副本独立就绪
		if float(e["rust_t"]) < 3.0: continue               # 该件未就绪(每3s就绪一次)
		if not got:                                          # 目标懒求(多件共用同一最近敌)
			t = battle._targeting._nearest_enemy(u); got = true
		if t == null or (t["pos"] - u["pos"]).length() > rng: continue   # 射程内无敌→保持就绪等待
		e["rust_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		var dmg01: int = battle._resolve_dmg(u, u["atk"] * [0.6, 0.75, 1.0][si] + [40.0, 60.0, 100.0][si] * u["crit"], t, false)
		battle._weapon_flyslash(u, t, dmg01, Color("#ffd27a"))   # 剑气飞到目标才结算伤(命中判定在_projectiles arrival)


func _tick_coral(u: Dictionary, delta: float) -> void:   # 双穿珊瑚刺p2eq_008: 每9秒对最远敌射珊瑚尖刺(用户2026-07-19: 6→9); 命中才结算; 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_008": continue
		e["coral_t"] = float(e.get("coral_t", 0.0)) + delta
		if float(e["coral_t"]) < 9.0: continue
		var far = null; var fd = -1.0
		for o in battle._targeting._pick_enemies_of(u):   # ★单体定向(挑最远一个)必须走 battle._targeting._pick_enemies_of: 排除训龟大师(场外监视者·永远最远)+不可选中; 见 §PICK-TARGET 铁律。原用 battle._targeting._enemies_of → 珊瑚刺永远锁大师(用户2026-07-24)
			var dd2: float = (o["pos"] - u["pos"]).length_squared()
			if dd2 > fd: fd = dd2; far = o
		if far == null: continue
		e["coral_t"] = 0.0
		battle._fire_coral_spike(u, far, battle._equip_sys._eq_si(int(e.get("star", 1))))

func _tick_broadsword(u: Dictionary, delta: float) -> void:   # 锈蚀阔剑p2eq_007: 每6秒触发(用户); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_007": continue
		e["bsw_t"] = float(e.get("bsw_t", 0.0)) + delta
		if float(e["bsw_t"]) < 6.0: continue
		if battle._targeting._nearest_enemy(u) == null: continue
		e["bsw_t"] = 0.0
		battle._equip_sys._eq_broadsword(u, battle._equip_sys._eq_si(int(e.get("star", 1))))

func _tick_sword_storm(u: Dictionary, delta: float) -> void:   # 千刃风暴p2eq_006: 每7秒触发; 每件独立计时
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_006": continue
		e["storm_t"] = float(e.get("storm_t", 0.0)) + delta
		if float(e["storm_t"]) < 7.0: continue
		if battle._targeting._nearest_enemy(u) == null: continue
		e["storm_t"] = 0.0
		battle._equip_sys._eq_sword_storm(u, battle._equip_sys._eq_si(int(e.get("star", 1))))

func _tick_laser(u: Dictionary, delta: float) -> void:   # 激光长刃p2eq_010: 独立计时器(按携带者攻速)每次扇形斩(用户)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_010": continue
		e["laser_t"] = float(e.get("laser_t", 0.0)) + delta
		if float(e["laser_t"]) < maxf(0.3, float(u.get("atk_interval", 1.0))): continue
		var t = battle._targeting._nearest_enemy(u)
		if t == null: continue
		e["laser_t"] = 0.0
		battle._equip_sys._eq_laser_sweep(u, t, battle._equip_sys._eq_si(int(e.get("star", 1))))
