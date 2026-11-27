class_name SummonCodex
extends RefCounted
## 图鉴「角色」栏 · 召唤物 / 战场单位的【单一文案 / 数值源】(2026-11-27 · 方案书 docs/plans/20261127d-图鉴角色栏收全部单位.md)。
##
## 用户 11-27:「对于矛这个羁绊，核心是召唤物并强化技能，所以图鉴里最好龟换成角色，及游戏里的可能出现的单位，这里去描述属性，
##   所以对于羁绊里的召唤去描述可以换种方式」「百夫长没有等级，收所有单位」「(登场击飞) 这个应该作为角色的被动吧」。
## 用户 11-27 看过百夫长 / 炮台两页「可以过了，那就把全部都搞好吧」⇒ 其余全部照这两页的模板铺开。
##
## ★数字一律读战斗代码里的常量(SpearSynergySystem / EquipSystem / EqBombBatch …), 不手抄 —— 同 minion_codex.gd 的教训(两份手抄已经漂过)。
##   原来写在召唤行里的字面量 11-27 统一提成具名常量(tools/oneoff/summon_consts_1127.py, 值不变)。门禁 verify_codex_summon 对着常量逐个核。
## ★属性跟着什么变, 列就是什么: 百夫长 / 亡魂 = 羁绊件数; 装备召唤物 = 装备星级; 机甲 = 浮游炮数; 小木斧 = 进化形态; 训龟大师 = 携带技能。
##   不跟着任何东西变的(糖果炸弹 / 水晶球 / 海盗船 / 随从 / 龟蛋)没有选择牌。
## ★左栏只写基础值; 从主人 / 携带者来的那部分写成被动(用户 11-27「左边就写一千四百生命，然后右边被动写这个炮台额外获得多少」)。
##   整只按比例继承、没有自己底子的(蛋糕礼盒 / 亡魂 / 随从)左栏写比例, 小字写「携带者生命」之类, 被动里再说一遍。
##   按主人比例、主人是固定某只龟的(糖果炸弹 / 水晶球 / 海盗船 / 机甲)左栏按 1 级主人算 —— 同龟页 / 小将页按 1 级显示。
## ★登场效果算被动(用户 11-27); 「什么时候召唤」是召唤它的羁绊 / 装备 / 龟的规则, 这里只在「来源」带过。
## ★文案照小将模板(minion_codex.gd): 伤害写「（倍率×攻击力({ATK}) = 结果）」, 物理 {N:}、魔法 {M:}, 倍率读 {C:} 常量;
##   图鉴按左栏当前属性现算(SkillText.render_bbcode, ctx 的 ATK = 选中那一列的攻击力)。攻击力是比例的条目不写「= 结果」。
## ★图标: 每个攻击 / 技能 / 被动一张(用户 11-27「没有图标」), tools/assetgen/summon_icons_*.py 出图, 源文件 tools/assetgen/ase/summon_icons/。
##
## 一页的形状 info(id, 列号):
##   name / avatar(列表头像) / portrait(立绘, 同龟页 _add_pet_portrait 认的形状) / kinds(战斗里 _spawn_summon 的种类名)
##   source {text, tab, key}(来源: 点了跳到哪一栏哪一条; tab 空 = 不跳) / tags(签牌) / col_title / cols(列名)
##   stats [{key, label, disp}](与龟页属性方块同一套键) / basic {name, icon, desc} / skill {name, icon, desc, energy}(没有就空)
##   passives [{name, icon, desc}]

const _EQ := preload("res://scripts/gamedata/summon_codex_equip.gd")
const _MISC := preload("res://scripts/gamedata/summon_codex_misc.gd")
const _P2T := preload("res://scripts/gamedata/phase2_types.gd")

## 列表分组(图鉴「角色」栏, 排在 28 只龟之后): [组名, [条目 id…]]。「战场单位」组排在深海小将四种后面(同一组)。
const GROUPS := [
	["战场单位", ["egg", "trainer"]],
	["召唤物 · 龟技能", ["candybomb", "crystalball", "ship", "mech"]],
	["召唤物 · 装备", ["skeleton", "worm", "bear", "turret", "cakebox", "pistol", "medtower", "axe",
		"cannon", "remote_bomb", "katana", "shadow_ninja", "skel_warrior", "skel_mage", "skel_priest", "mask_lion"]],
	["召唤物 · 羁绊", ["centurion", "wraith"]],
]

## 战斗里有、图鉴里有意不单列的种类(门禁 verify_codex_summon 认这张白名单):
##   shadow_clone = 暗影忍者的影分身(写在暗影忍者的被动里); 面具复制体不走 _spawn_summon(用户 11-27「面具复制体不算吧」)。
const KIND_ALIASES := {"shadow_clone": "shadow_ninja"}

## 有意不单列、也不归到别的页的种类: 随从就是一只真龟(用户 11-27「随从不需要在这个图鉴里面去专门列一个随从」), 看原龟的页。
const UNLISTED_KINDS := ["minion"]


static func all_ids() -> Array:
	var out: Array = []
	for g in GROUPS:
		out.append_array(g[1])
	return out


static func cols(id: String) -> Array:
	if id == "centurion":
		var out: Array = []
		for t in (_P2T.TYPES.get("长矛", {}) as Dictionary).get("tiers", []):
			out.append("(%d)" % int(t))
		return out
	var c: Array = _EQ.cols(id)
	return c if not c.is_empty() else _MISC.cols(id)


static func info(id: String, ci: int) -> Dictionary:
	var n: int = cols(id).size()
	var k: int = clampi(ci, 0, maxi(0, n - 1))
	if id == "centurion":
		return _centurion(k)
	var d: Dictionary = _EQ.info(id, k)
	return d if not d.is_empty() else _MISC.info(id, k)


## 战斗里会出现的召唤物种类名 → 图鉴条目 id(门禁拿它对全仓 _spawn_summon 调用点)。
static func id_of_kind(kind: String) -> String:
	if KIND_ALIASES.has(kind):
		return str(KIND_ALIASES[kind])
	for id in all_ids():
		if (info(id, 0).get("kinds", []) as Array).has(kind):
			return id
	return ""


## 名字 → 条目 id(羁绊 / 装备文案里的【名字】点了跳到这一页)。
static func id_of_name(nm: String) -> String:
	for id in all_ids():
		if str(info(id, 0).get("name", "")) == nm:
			return id
	return ""


# ─── 公用 ─────────────────────────────────────────────────────────
static func _pct(x: float) -> String:
	var v: float = snappedf(x * 100.0, 0.01)
	return str(int(v)) if is_equal_approx(v, roundf(v)) else str(v)


static func _n(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else str(snappedf(x, 0.01))


## 一列属性方块(与龟页同一套键与顺序)。disp 可以是数字串, 也可以是「20%」「同携带者」这类说明(方块只画数字)。
static func stats(hp, atk, def, mr, move, aspd, rng, labels: Dictionary = {}) -> Array:
	var out: Array = []
	for row in [["hp", "生命", hp], ["atk", "攻击", atk], ["def", "护甲", def], ["mr", "魔抗", mr],
			["move", "移速", move], ["aspd", "每秒攻击", aspd], ["range", "射程", rng]]:
		var v = row[2]
		var disp: String = (_n(float(v)) if (v is float or v is int) else Lang.t(str(v)))   # 「未知」「同携带者」这类说明要翻
		if row[0] == "aspd" and (v is float or v is int):
			disp = "%.2f" % float(v)
		## 生命 / 攻击 / 双抗按主人比例算出来会带小数(海盗船 989 × 1.5 = 1483.5): 取整显示(战斗里血条 / 面板也是取整)
		if row[0] in ["hp", "atk", "def", "mr"] and (v is float or v is int):
			disp = str(int(roundf(float(v))))
		out.append({"key": row[0], "label": Lang.t(str(labels.get(row[0], row[1]))), "disp": disp})
	return out


## 普攻一句(默认普攻 = BasicConsts.DEFAULT_BASIC_COEF × 攻击力 物理, 所有没登记专属普攻的召唤物都走它)。
## ★先翻译句式再填名字(英文版: 渲染时 Lang.t 认的是整句, 拼好的句子在 en.po 里找不到)。
static func basic_line(who: String) -> String:
	return Lang.t("%s的攻击造成（{C:BasicConsts.DEFAULT_BASIC_COEF%%}%%×攻击力({ATK}) = {N:BasicConsts.DEFAULT_BASIC_COEF*ATK}）物理伤害。") % Lang.t(who)


## 攻击力取决于主人(未知)的单位用这一句: 算式写「= 未知」(用户 11-27「你这都填未知，我觉得也可以」)。
static func basic_line_unknown(who: String) -> String:
	return Lang.t("%s的攻击造成（{C:BasicConsts.DEFAULT_BASIC_COEF%%}%%×攻击力(未知) = 未知）物理伤害。") % Lang.t(who)


static func star_cols() -> Array:
	return ["★1", "★2", "★3"]


## 1 级主人的属性(pets.json 底子)。按主人比例的召唤物左栏用它算(同龟页 / 小将页按 1 级显示)。
static func owner_base(pet_id: String) -> Dictionary:
	var p = DataRegistry.pet_by_id.get(pet_id, {})
	return p if p is Dictionary else {}


# ─── 百夫长(长矛羁绊) ─────────────────────────────────────────────
## 用户 11-27: 被动 / 攻击 / 技能要照模板、有图标; 「从天而降」名字不好; 加成写成被动, 不要左下那行说明。
const _SP := "SpearSynergySystem"


static func _centurion(ci: int) -> Dictionary:
	var S := SpearSynergySystem
	var tier: int = ci + 1   # 第几档(1~4), 攻击 / 技能逐档叠加
	var basic: String = basic_line("百夫长")
	if tier >= 2:
		basic += Lang.t("刺击时沿刺击方向推出一道冲击波，贯穿目标身后的敌人，造成（{C:%s.PIERCE_BEHIND%%}%%×攻击力({ATK}) = {N:%s.PIERCE_BEHIND*ATK}）物理伤害。") % [_SP, _SP]
	if tier >= 3:
		basic += Lang.t("每次刺中使敌人失去 1 点护甲和魔抗，每个敌人至多 {C:%s.SHRED_CAP} 点。") % _SP
	if tier >= 4:
		basic += Lang.t("每第 {C:%s.THROW_EVERY} 次攻击转而掷出长矛，飞向最远的敌人，贯穿沿途敌人，造成（{C:%s.THROW_COEF%%}%%×攻击力({ATK}) = {N:%s.THROW_COEF*ATK}）物理伤害。") % [_SP, _SP, _SP]
	var skill: String = Lang.t("百夫长举盾 {C:%s.SHIELD_SEC} 秒，受到的伤害降低 {C:%s.SHIELD_DR%%}%%。") % [_SP, _SP]
	if tier >= 3:
		skill += Lang.t("举盾期间每 {C:%s.POKE_IV} 秒刺击周围敌人，造成（{C:%s.POKE_COEF%%}%%×攻击力({ATK}) = {M:%s.POKE_COEF*ATK}）魔法伤害。") % [_SP, _SP, _SP]
	if tier >= 2:
		skill += Lang.t("放下盾时横扫周围敌人，造成（{C:%s.SWEEP_COEF%%}%%×攻击力({ATK}) = {M:%s.SWEEP_COEF*ATK}）魔法伤害。") % [_SP, _SP]
	if tier >= 4:
		skill += Lang.t("横扫后，我方身后冲出 {C:%s.CAV_N} 名持矛骑兵，各冲向一名随机敌人，撞到的每个敌人受到（{C:%s.CAV_COEF%%}%%×攻击力({ATK}) = {N:%s.CAV_COEF*ATK}）物理伤害并被击飞。") % [_SP, _SP, _SP]
	return {
		"name": "百夫长", "kinds": ["centurion"],
		"avatar": "res://assets/sprites/avatars/summon-centurion.png",
		"portrait": {"id": "__summon_centurion", "img": "vfx/eq-centurion-idle.png",
			"sprite": {"frameW": 192, "frameH": 192, "frames": 4}},
		## 待机帧 192×192 里人物只占中间约 68×123 ⇒ 按龟的 160 框放显得小一圈: 框放大到 230、中心上移到 76(脚底约 190, 不压属性方块 196)
		"portrait_box": 230.0, "portrait_cy": 76.0,
		"source": {"text": Lang.t("长矛羁绊"), "tab": "synergies", "key": "长矛"},
		"tags": [Lang.t("近战斗士"), Lang.t("不可编入")],   # 定位用龟的十种叫法(turtle_stats.ROLE_SPEC); 用户 11-26「高血量中等输出的战士」
		"col_title": Lang.t("长矛件数"), "cols": cols("centurion"),
		"stats": stats(S.HP[ci], S.ATK[ci], S.RES[ci], S.RES[ci], BattleSpawn.SUMMON_DEFAULT_SPD, 1.0, S.RANGE),
		"basic": {"name": "突刺", "icon": "skills/summon-cent-thrust.png", "desc": basic},
		"skill": {"name": "龟甲阵", "icon": "skills/summon-cent-guard.png", "desc": skill, "energy": int(S.EN_MAX)},
		"passives": [
			{"name": "军团天降", "icon": "passive/summon-cent-land-icon.png",
				"desc": Lang.t("百夫长登场时从高空落下，落地时击飞全场敌人 {C:%s.KNOCK_SEC} 秒，造成（{C:%s.ENTRY_COEF%%}%%×攻击力({ATK}) = {M:%s.ENTRY_COEF*ATK}）魔法伤害。") % [_SP, _SP, _SP]},
			{"name": "众矛之力", "icon": "passive/summon-cent-spears-icon.png",
				"desc": Lang.t("我方每有一件不同的长矛，按其星级每星使百夫长生命值与攻击力提高 {C:%s.STAR_PCT%%}%%。") % _SP},
		],
	}


# ─── 文案里的召唤物名字链接(2026-11-27 方案书 20261127d U4: 图鉴、商店说明卡里能点, 战斗中只显示不跳转) ───
## 羁绊 / 装备文案里写成「【百夫长】」的名字 → [url=summon:<id>]…[/url]。只认登记表里的名字, 其它【关键词】不动。
## 名字长的先换(「骷髅战士」不会被「骷髅…」误伤; 现在没有互为前缀的名字, 留着防以后)。
static func linkify(bb: String) -> String:
	if not (bb.contains("【") or bb.contains("[lb]")):
		return bb
	var names: Array = []
	for id in all_ids():
		var cn: String = str(info(id, 0).get("name", ""))
		names.append(["【%s】" % cn, str(id)])
		## 英文版写成 [Axe], 渲染成 BBCode 时左括号转义成 [lb](SkillText.html_to_bbcode)
		var en: String = Lang.t(cn)
		if en != cn:
			names.append(["[lb]%s]" % en, str(id)])
	names.sort_custom(func(a, b): return str(a[0]).length() > str(b[0]).length())
	for nm in names:
		var key: String = str(nm[0])
		if bb.contains(key) and not bb.contains("[url=summon:%s]" % str(nm[1])):
			bb = bb.replace(key, "[url=summon:%s]%s[/url]" % [str(nm[1]), key])
	return bb


## 给一个 RichTextLabel 接上名字链接: 点了调 on_open(条目 id)。标签原来不收鼠标的改成 PASS(点链接之外照旧往下传)。
static func attach_links(rtl: RichTextLabel, on_open: Callable) -> void:
	if rtl == null or not rtl.text.contains("[url=summon:"):
		return
	rtl.mouse_filter = Control.MOUSE_FILTER_PASS
	rtl.meta_underlined = true
	rtl.meta_clicked.connect(func(meta) -> void:
		var m := str(meta)
		if m.begins_with("summon:"):
			on_open.call(m.substr(7)))


## 商店说明卡里点名字 → 一张召唤物小卡(InspectCard 的 spec): 头像 + 名字 + 签牌 + 属性一行 + 攻击 / 技能 / 被动逐条。
## 列取第 0 列(★1 / 第一档), 卡底一行灰字说明「完整数据见图鉴」。
static func card_spec(id: String) -> Dictionary:
	var si: Dictionary = info(id, 0)
	if si.is_empty():
		return {}
	var parts: PackedStringArray = []
	for st in si.get("stats", []):
		parts.append("%s %s" % [str(st["label"]), str(st["disp"])])
	var body: PackedStringArray = []
	var ctx := {"atk": float(_disp_of(si, "atk")), "maxHp": float(_disp_of(si, "hp")), "lv": 1}
	var rows: Array = []
	for pv in si.get("passives", []):
		rows.append([Lang.t("被动"), pv])
	if not (si.get("basic", {}) as Dictionary).is_empty():
		rows.append([Lang.t("攻击"), si["basic"]])
	if not (si.get("skill", {}) as Dictionary).is_empty():
		rows.append([Lang.t("技能"), si["skill"]])
	for r in rows:
		var d: Dictionary = r[1]
		body.append("[color=#ffd93d]%s · %s[/color]\n%s" % [str(r[0]), Lang.t(str(d["name"])),
			SkillText.render_bbcode(Lang.t(str(d["desc"])), ctx, {}, 20)])
	var cols: Array = si.get("cols", [])
	var head: String = ("%s %s · " % [str(si.get("col_title", "")), str(cols[0])]) if not cols.is_empty() else ""
	return {"icon": str(si.get("avatar", "")), "title": Lang.t(str(si["name"])), "title_col": Color("#ffd93d"),
		"tag_bb": "[color=#58d3ff]%s[/color]" % "  ·  ".join(PackedStringArray(si.get("tags", []))),
		"body": "[color=#aab8c6]%s%s[/color]\n\n%s" % [head, "  ".join(parts), "\n\n".join(body)],
		"foot": Lang.t("完整数据见图鉴「角色」")}


static func _disp_of(si: Dictionary, key: String) -> String:
	for st in si.get("stats", []):
		if str(st["key"]) == key:
			return str(st["disp"])
	return "0"
