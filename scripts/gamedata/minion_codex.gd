class_name MinionCodex
extends RefCounted
## 深海小将的【单一文案源】(2026-08-20 建)。
##
## ★为什么要单独抽出来: 之前同一批小将技能说明**存在两份互相独立的手抄** ——
##   图鉴一份(CodexScene.MINION_INFO)、战斗信息面板一份(RealtimeBattle3DScene.MINION_SKILL_DESC),
##   而且**已经漂了**: 图鉴的铁锤写着"0.35 秒蓄力 / 60° 锥形 / 400% 攻击力", 战斗那份连伤害数字都没有;
##   反过来战斗那份写了"100/120 龟能", 图鉴又没有。两边各缺各的, 玩家在两个地方读到两套说法。
##   (memory: 手抄的副本必然落后)
## ⇒ 现在只有这一份, 图鉴与战斗都从这里取。
##
## ⚠ 这里的**数值仍然是从战斗代码抄来的**(`_make_unit` 的 is_minion 分支 + `_sk_minion_*` / `_elite_*`),
##   由 `tests/verify_minion_text_single_source.gd` 焊住"只有一份", 但"数字对不对"要靠改代码时同步。
##   注意 `scripts/gamedata/phase2_minion.gd` 是回合制遗留壳(名字"深海小将精英"、数值也不同), **不是事实源**。


## 战斗侧技能 type → 本表的 kind。战斗用 `minionBodysurf` 这类 type 名, 图鉴用 `front/back/elite`。
const TYPE_TO_KIND := {
	"minionBodysurf": "front",
	"minionRocket": "back",
	"eliteHammer": "elite",
	ReserveConsts.SKILL: "reserve",   # 援军小将·四面合围(2026-10-29)
}


## 战斗信息面板要的 {name, desc} —— 从同一张表现算, 不再另存一份。
static func skill_desc(stype: String) -> Variant:
	var k: String = str(TYPE_TO_KIND.get(stype, ""))
	if k == "" or not MINION_INFO.has(k):
		return null
	var d: Dictionary = info(k)
	## ★icon(2026-10-06): 信息面板技能格要图标 —— 原来小将两个技能没有图, 那一格是空的。
	## ★tpl(2026-11-04): 带占位符的原文 —— 信息面板拿它走 render_skill_text(算好数值 / 伤害上色 / 底部公式行),
	##   与龟技能同一条管线; desc 只展开了 {C:}, 留给没有单位上下文的地方。
	return {"name": str(d.get("skill_name", "")), "desc": str(d.get("skill_desc", "")),
		"icon": str(d.get("skill_icon", "")), "tpl": str((MINION_INFO[k] as Dictionary).get("skill_desc", ""))}


## 一种小将的整条图鉴信息, 给屏幕用的版本(图鉴详情 / 信息面板都走这里):
##   ① 文字里的 {C:类.常量} 展开 —— 援军小将的数字只写在 ReserveConsts, 这里不抄;
##   ② 整数值去掉「.0」(表里直接引 ReserveConsts 的浮点常量, str(1000.0) 会显示成「1000.0」);
##   ③ 技能图标文件还不在(美术没交)就给空串 —— 图鉴卡 / 信息面板技能格见空串就不画图, 不去 load 一个不存在的路径。
static func info(kind: String) -> Dictionary:
	var src: Variant = MINION_INFO.get(kind, null)
	if not (src is Dictionary):
		return {}
	var d: Dictionary = (src as Dictionary).duplicate(true)
	for k in ["skill_desc", "growth_tag"]:
		if d.has(k):
			d[k] = SkillText.render_consts(str(d[k]))
	for pv in d.get("passives", []):
		(pv as Dictionary)["desc"] = SkillText.render_consts(str((pv as Dictionary).get("desc", "")))
	for k in ["hp", "atk", "def", "mr", "range", "spd", "skill_cost"]:
		var v: Variant = d.get(k, null)
		if v is float and is_equal_approx(float(v), roundf(float(v))):
			d[k] = int(roundf(float(v)))
	var ic := str(d.get("skill_icon", ""))
	if ic != "" and not ResourceLoader.exists(SPRITE_ROOT + ic):
		d["skill_icon"] = ""
	return d


const SPRITE_ROOT := "res://assets/sprites/"

## 某种小将的立绘(图鉴列表 / 图鉴详情 / 对阵幕布 / 结算表 / 顶栏都用这一张)。文件还不在 ⇒ 空串, 调用方自己回落。
static func portrait_path(kind: String) -> String:
	var mi: Variant = MINION_INFO.get(kind, null)
	if not (mi is Dictionary):
		return ""
	var p: String = SPRITE_ROOT + "pets/" + str((mi as Dictionary).get("img", ""))
	return p if ResourceLoader.exists(p) else ""


## 单位字典(minion_role / is_elite)或阵容 spec(role / elite)→ front / back / elite / reserve。
## ★援军小将先判: 它的 role 是 "reserve", 走「是 front 否则远程」那种二分会被当成远程小将(方案书 D7)。
static func kind_of(x: Dictionary) -> String:
	var role := str(x.get("minion_role", x.get("role", "front")))
	if role == "reserve":
		return "reserve"
	if bool(x.get("is_elite", x.get("elite", false))):
		return "elite"
	return "front" if role == "front" else "back"


## 这个单位是不是援军小将(单位字典 / 阵容 spec / 结算快照行都认)。
## 结算快照行是纯标量、不带 minion_role ⇒ 认 id + 名字(名字只在 ReserveConsts.NAME 一处)。
static func is_reserve(x: Dictionary) -> bool:
	if kind_of(x) == "reserve":
		return true
	return str(x.get("id", "")) == "__minion__" and str(x.get("name", "")) == ReserveConsts.NAME


## ★2026-11-04 某种小将的【头像】= 头部特写, 与龟的 avatars/<id>.png 同一种东西(用户「头像不等于全身画啊」)。
##   凡是龟用 avatars/ 头像的地方(战斗信息面板 / 顶栏 / 左右队头像框 / 换路过场卡 / 结算表 / 排队页 /
##   图鉴列表行 / 状态来源图标), 小将都读这里; 立绘(portrait_path)只给图鉴详情大图这类「全身画」位置。
##   原来这些地方给的是全身立绘(远程小将在框里只剩一小团暗红), 换路过场与排队页还三种小将一律用近战那张。
##   文件由 tools/assetgen/build_minion_avatars.py 从各自立绘裁头部生成。文件不在 ⇒ 退回立绘。
const AVATAR := {
	"front": "res://assets/sprites/avatars/minion.png",
	"back": "res://assets/sprites/avatars/minion-back.png",
	"elite": "res://assets/sprites/avatars/minion-elite.png",
	"reserve": "res://assets/sprites/avatars/minion-reserve.png",
}


static func avatar_path(kind: String) -> String:
	var p: String = str(AVATAR.get(kind, ""))
	if p != "" and ResourceLoader.exists(p):
		return p
	return portrait_path(kind)


# 深海小将 (虚拟图鉴条目 — 非龟, pets.json 里没有)
#
# 【事实源】RealtimeBattle3DScene.gd `_make_unit` 的 is_minion 分支 + `_sk_minion_*` / `_elite_*`.
# 这里的每个数字都是从那段代码抄的, 改小将数值时【必须同步这张表】, 否则图鉴就开始骗人。
# 注意 scripts/gamedata/phase2_minion.gd 是回合制遗留壳(名字叫"深海小将精英", 数值也不同), 不是事实源。
# ══════════════════════════════════════════════════════════
const MINION_KINDS := [
	{"kind": "front", "name": "近战小将", "img": "minion.png"},
	{"kind": "back",  "name": "远程小将", "img": "minion-back.png"},
	{"kind": "elite", "name": "精英小将", "img": "minion-elite.png"},
	{"kind": "reserve", "name": ReserveConsts.NAME, "img": "minion-reserve.png"},
]

## Lv1 数值 + 说明. hp/atk 随等级 ×1.05^(lv-1) 复利, 双抗定值(与 _make_unit 一致).
## ★`range` 写的是【实际生效】的射程: 近战单位在 `_make_unit` 里被抬到 ≥ MELEE_ATK_RANGE_MIN(100),
##   原表照抄 `st` 里的 70 / 90 ⇒ 图鉴比战斗少报(2026-10-07 体检 H)。
##   守卫: tests/verify_codex_battle_parity.gd 拿真生成的小将逐项比(血/攻/双抗/攻击间隔/射程)。
const MINION_INFO := {
	"front": {
		"name": "近战小将", "img": "minion.png", "role": "前排 · 近战",
		"hp": 750, "atk": 42, "def": 13, "mr": 13, "interval": 0.85, "range": 100, "spd": 105,
		"skill_name": "人体浪板", "skill_cost": 120, "skill_icon": "skills/minion-bodysurf.png",
		"skill_desc": "近战小将锁定一个敌人并跃起，起跳时回复（{C:HidingSystem.SURF_HEAL_COEF%}%×攻击力({ATK}) = {E:HidingSystem.SURF_HEAL_COEF*ATK}）生命值，距离过近时先向后跳开。随后射出铁链，将该敌人眩晕 {C:HidingSystem.SURF_STUN_SEC} 秒并将自身拉向目标，接触时造成其 {C:HidingSystem.SURF_CONTACT_MAXHP_PCT%}% 最大生命值的物理伤害。之后踩着目标滑行，对其持续造成（{C:HidingSystem.SURF_RIDE_ATK_COEF%}%×攻击力({ATK}) = {N:HidingSystem.SURF_RIDE_ATK_COEF*ATK}）物理伤害，并对沿途敌人造成（{C:HidingSystem.SURF_PASS_ATK_COEF%}%×攻击力({ATK}) = {N:HidingSystem.SURF_PASS_ATK_COEF*ATK}）物理伤害并将其击退，最后跳下。",
		## ★2026-11-04 补「普通攻击」(用户「能力排被动，攻击，技能呢」): 近战 / 远程 / 援军小将的普攻在代码里走通用普攻
		##   (RealtimeBattle3DScene.DEFAULT_BASIC, 系数 BasicConsts.DEFAULT_BASIC_COEF, 单体物理) —— 原来这张表只有精英写了「长手刃」,
		##   面板与图鉴都缺这一条。写法与长手刃同一句式。
		"passives": [
			{"name": "普通攻击", "slot": "basic", "icon": "skills/minion-front-basic.png", "desc": "近战小将的攻击造成（{C:BasicConsts.DEFAULT_BASIC_COEF%}%×攻击力({ATK}) = {N:BasicConsts.DEFAULT_BASIC_COEF*ATK}）物理伤害。"},
		],
	},
	"back": {
		"name": "远程小将", "img": "minion-back.png", "role": "后排 · 远程",
		"hp": 750, "atk": 45, "def": 7, "mr": 7, "interval": 0.85, "range": 400, "spd": 105,
		"skill_name": "追踪火箭筒", "skill_cost": 120, "skill_icon": "skills/minion-rocket.png",
		"skill_desc": "远程小将锁定一名敌人，蓄力 {C:HidingSystem.ROCKET_CHARGE_SEC} 秒后发射一枚慢速追踪导弹，命中时引发核爆，对附近的敌人造成（{C:HidingSystem.ROCKET_ATK_COEF%}%×攻击力({ATK}) = {N:HidingSystem.ROCKET_ATK_COEF*ATK}）物理伤害，并施加 {C:HidingSystem.ROCKET_HEALCUT_PCT%}% 治疗削减，持续 {C:HidingSystem.ROCKET_HEALCUT_SEC} 秒。",
		"passives": [
			{"name": "普通攻击", "slot": "basic", "icon": "skills/minion-back-basic.png", "desc": "远程小将的攻击造成（{C:BasicConsts.DEFAULT_BASIC_COEF%}%×攻击力({ATK}) = {N:BasicConsts.DEFAULT_BASIC_COEF*ATK}）物理伤害。"},
		],
	},
	"elite": {
		"name": "精英小将", "img": "minion-elite.png", "role": "精英 · 近战",
		"hp": 1000, "atk": 50, "def": 16, "mr": 20, "interval": 1.54, "range": 100, "spd": 105,
		"skill_name": "铁锤", "skill_cost": 100, "skill_icon": "skills/elite-hammer.png",
		## 战斗信息面板被动格(三条合一格)的图标: 两道斜杠切三段 = 旋刃左 / 铁锁中 / 吞噬右(用户 11-05, tools/assetgen/build_elite_passive_combo.py)
		"passive_icon": "passive/elite-passive-combo.png",
		"skill_desc": "精英小将在附近有敌人时举拳蓄力 0.35 秒，随后砸向地面，对前方锥形范围内的敌人造成（{C:EliteSystem.HAMMER_ATK_COEF%}%×攻击力({ATK}) = {M:EliteSystem.HAMMER_ATK_COEF*ATK}）魔法伤害。每 3 次施放时转而高高跃起，在空中蓄力 1 秒后砸下，对附近的全部敌人造成（{C:EliteSystem.HAMMER_BIG_ATK_COEF%}%×攻击力({ATK}) = {M:EliteSystem.HAMMER_BIG_ATK_COEF*ATK}）魔法伤害。",
		## `slot` = 图鉴龟页同一套右栏里放哪: basic → 普通攻击条 / passive → 被动条 / skill → 技能卡(签「被动」)。
		## `icon`(2026-11-04, 相对 assets/sprites/): 战斗信息面板能力排与图鉴普通攻击条 / 被动条用同一张; 铁锁合进被动格, 不单独出图。
		## ★2026-11-05 用户「他的被动应该是有三个啊…每五次攻击之后…旋刃…钩子…斩杀…这都是被动，所以你还是按照规矩来写被动普攻技能」:
		##   被动 3 条(旋刃 / 铁锁 / 吞噬, 用户说的顺序) · 攻击 1 条(长手刃, 只写普通攻击本身) · 技能 1 张(铁锤)。
		##   原来旋刃塞在长手刃里、铁锁是签「被动」的技能卡(图鉴里一块没图标没框的字), 与龟页不是一个结构。
		##   代码里铁锁本来就是「被动2」(RealtimeBattle3DScene._tick_elite_whip 头注), 吞噬完成时目标被击杀(EliteSystem 吞噬回调)。
		"passives": [
			{"name": "旋刃", "slot": "passive", "icon": "passive/elite-whirl-icon.png", "desc": "精英小将每第 {C:EliteSystem.WHIRL_EVERY} 次攻击挥出旋刃，对周围的敌人造成（{C:EliteSystem.WHIRL_ATK_COEF%}%×攻击力({ATK}) = {N:EliteSystem.WHIRL_ATK_COEF*ATK}）物理伤害，并回复相当于所造成伤害 {C:EliteSystem.WHIRL_HEAL_PCT%}% 的生命值。"},
			{"name": "铁锁", "slot": "passive", "icon": "passive/elite-whip-icon.png", "desc": "精英小将每 {C:EliteSystem.WHIP_CD_SEC} 秒锁定一个不贴身的敌人，射出锁链，命中后将其眩晕 {C:EliteSystem.WHIP_STUN_SEC} 秒并拉至自身后方，造成（{C:EliteSystem.WHIP_ATK_COEF%}%×攻击力({ATK}) = {M:EliteSystem.WHIP_ATK_COEF*ATK}）魔法伤害。"},
			{"name": "吞噬", "slot": "passive", "icon": "passive/elite-consume-icon.png", "desc": "精英小将的攻击、铁锁或铁锤命中生命值低于 {C:EliteSystem.CONSUME_HP_PCT%}% 的敌人时发动吞噬，持续 {C:EliteSystem.CONSUME_SEC} 秒，期间获得 {C:EliteSystem.CONSUME_DR%}% 减伤。吞噬完成时击杀该敌人，回复相当于其剩余生命值 {C:EliteSystem.CONSUME_HEAL_MULT} 倍的生命值，获得 {C:EliteSystem.CONSUME_ASPD_BONUS%}% 攻击速度，持续 {C:EliteSystem.CONSUME_HASTE_SEC} 秒，并窃取该敌人的主动技能。"},
			{"name": "长手刃", "slot": "basic", "icon": "skills/elite-blade.png", "desc": "精英小将的攻击造成（{C:EliteSystem.BLADE_ATK_COEF%}%×攻击力({ATK}) = {N:EliteSystem.BLADE_ATK_COEF*ATK}）物理伤害。"},
		],
	},
	## 援军小将(用户 2026-10-29, 方案书 docs/plans/20261029-终极战场援军小将.md):
	##   终极战场里一方没有任何幸存单位时代替出战。不按等级、按所属玩家本周已打场数成长(每场 +4%, 生命 / 攻击 / 双抗都长)。
	##   ★数字全部引 ReserveConsts(数值常量与 {C:ReserveConsts.X} 文案占位符), 本表不抄任何一个; 屏幕上读 info("reserve")。
	##   `growth_tag` = 图鉴签牌那一格(其余三种小将是「每级 ×1.05」)。
	"reserve": {
		"name": ReserveConsts.NAME, "img": "minion-reserve.png", "role": "援军 · 远程",
		"hp": ReserveConsts.HP, "atk": ReserveConsts.ATK, "def": ReserveConsts.DEF, "mr": ReserveConsts.MR,
		"interval": ReserveConsts.ATK_INTERVAL, "range": ReserveConsts.RANGE, "spd": ReserveConsts.MOVE,
		"skill_name": ReserveConsts.SKILL_NAME, "skill_cost": ReserveConsts.ENERGY, "skill_icon": "skills/reserve-converge.png",
		"growth_tag": "每场 +{C:ReserveConsts.GROWTH_PER_BATTLE%}%",
		"skill_desc": "援军小将锁定一名敌人，在其前后左右各出现一道气波，同时追向该敌人。每道气波对命中的第一个敌人造成（{C:ReserveConsts.ATK_COEF%}%×攻击力({ATK}) = {N:ReserveConsts.ATK_COEF*ATK}）物理伤害，外加相当于该敌人 {C:ReserveConsts.MAXHP_PCT%}% 最大生命值的魔法伤害。",
		"passives": [
			{"name": "援军", "slot": "passive", "icon": "passive/reserve-reinforce-icon.png", "desc": "终极战场中，若一方没有任何幸存单位，由援军小将代替该方出战。所属玩家本周每进行一场对局，援军小将的生命值、攻击力、护甲和魔抗提升 {C:ReserveConsts.GROWTH_PER_BATTLE%}%。"},
			{"name": "普通攻击", "slot": "basic", "icon": "skills/reserve-basic.png", "desc": "援军小将的攻击造成（{C:BasicConsts.DEFAULT_BASIC_COEF%}%×攻击力({ATK}) = {N:BasicConsts.DEFAULT_BASIC_COEF*ATK}）物理伤害。"},
		],
	},
}

## 远程小将的非标准动作(技能)。★放这里不放主战斗文件: 项目规矩「纯数据/常量表 → gamedata/」,
## 而且主文件有行数预算(arch_budget), 加表会被拦。
const ACTION_RANGED := {
	"skill": ["pets/animations/ranged/skill.png", 4.6667],   # 7 帧 ÷ 4.6667fps = 1.5 秒 == 火箭蓄力节拍(门禁焊死)
}

## 原始立绘【朝右】的动画键(全项目默认朝左)。
##
## ★2026-08-21 按【动画键】而不是 id 登记(用户 2026-08-20 拍板方案 b):
##   三种小将**共用 id `"__minion__"`** ⇒ 按 id 登记会把三种一起翻,
##   而实测只有精英小将的 idle 立绘朝右(reach +37, 另两张 -28/-34)。
##   后果: 精英小将**站着不动时背对敌人, 一跑动/一出招又正对敌人**。
##   ⇒ 只翻精英那一个; **不动素材**(动素材会连带翻图鉴/背包/头像, 那三处不翻转直接贴 png)。
## ★2026-08-21 清空: 原来登记精英小将=朝右, 是为了绕开"idle 立绘朝右而动作图朝左"。
##   但逐帧量面罩位置后发现**动作图之间本身就不一致**(attack/hammer 朝右、hammer_big 朝左),
##   光改查表救不了 ⇒ 直接把 idle/attack/hammer **逐帧镜像**成朝左, 整套回归全局约定。
##   表留着(机制还在), 但现在是空的 —— 没有单位需要例外。
const ART_FACES_RIGHT_KEY: Array = []


## 小将开战那一刻的底子(名字 / 稀有度 / 暴击 / 生命 / 攻击 / 双抗) —— `battle_spawn._make_unit` 与背包属性小卡共用这一个。
##   (2026-10-22 从 _make_unit 原样抽出, 表达式逐字未改 ⇒ 跨平台金标不动。)
## ★等级复利用连乘, 不用 `pow`(2026-10-05): `pow` 是各平台 libm 自己的近似, Windows(MSVC) 与
##   Linux(glibc) 末位不同 —— 探针实测同一只小将开局 hp 469946.8475140407 / 469946.8475140425,
##   第 0 步就分叉(verify_determinism_cross ⑥)。`*` 是 IEEE-754 保证逐位一致的。
static func base_stats(elite: bool, front: bool, level: int) -> Dictionary:
	var mm: float = 1.0
	for _lv_i in range(maxi(0, level - 1)):
		mm *= 1.05
	if elite:   # 精英小将定制属性(用户2026-07-18): 1000HP/50ATK/16DEF/20MR (HP/ATK随等级复利·双抗定值)
		return {"name": "精英小将", "rarity": "C", "crit": 0.0,
			"hp": 1000.0 * mm, "atk": 50.0 * mm, "def": 16.0, "mr": 20.0}
	# 普通小将: 750HP·前排1.4/后排1.5系数ATK; 近战(前排)双抗 7→13(用户2026-07-19), 远程保持7
	return {"name": "小将", "rarity": "C", "crit": 0.0,
		"hp": 250.0 * mm * 3.0, "atk": 30.0 * mm * (1.4 if front else 1.5),
		"def": (13.0 if front else 7.0), "mr": (13.0 if front else 7.0)}
