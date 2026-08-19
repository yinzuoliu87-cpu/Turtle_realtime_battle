extends Node
## verify_turtle_balance_r6.gd — 第六轮龟平衡 + 文案↔代码一致 (用户 2026-07-30)
##
## ★期望值一律写【用户口述的字面需求值】，不从代码常量读回来 ——
##   拿代码跟它自己比是恒真式；verify_trainer_magicstone 曾经就是这样，把常量改坏照样 ALL PASS。
##
## 用户 2026-07-30 逐字（三条指令合起来 = 本轮全部需求）:
##   「加强寒冰龟，削弱灵魂风暴，龟派气波，糖衣炮弹，灵魂打击」
##   「冰霜每0.5秒伤害加强到0.25ATK，每层增益的攻速提升到5%，过」
##   「糖衣炮弹每跳提供的护盾值削弱为1.5%自身最大生命值，龟能消耗改为130，
##     灵魂打击附带的目标当前生命值比例削弱为15%，后面镰刀斩击的诅咒时长削弱为4秒」
##   「那就不动普攻附带的伤害，把诅咒时长削弱为3秒」  ← 覆盖上一条的 15% 与 4秒
##   「灵魂风暴龟能削弱到105，龟牌气波不在增加暴伤buff，而吸血buff提升为20%」
##
## 查四组：
##   ① 7 项数值改动（每项都配一条「旧值已消失」，否则加了新的没删旧的照样 PASS）
##   ② 文案 ↔ 代码一致 —— ★本轮的真教训在这里。
##      我按 pets.json 的 tooltip 向用户报「无头灵魂打击 = 0.9A 物理 + 20% 当前生命」，
##      代码一直是 0.5A 魔法 + 10%（差一倍、类型也错），而且文案【完全没写】镰刀横扫与锁龟能。
##      所以本组直接读 data/pets.json 断言文案带着新数值、且旧数值不许残留。
##   ③ 本轮【故意不动】的（用户明说"那就不动普攻附带的伤害"）——
##      它是下一轮的判据，必须保证没被我顺手改掉
##   ④ 双向审计器在位（tools/pet_number_audit.py 进了 run-tests.sh 门禁）
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_turtle_balance_r6.tscn

# ── 需求值（用户口述的字面值）──
const WANT_FROST_ATK := 0.25          # 冰霜每 0.5 秒 = 0.25×ATK（原 0.18）
const WANT_ICICLE_ASPD := 0.05        # 每层冰柱 +5% 攻速（原 3%）
const WANT_BARRAGE_ENERGY := 130.0    # 糖衣炮弹龟能（原 120）
const WANT_BARRAGE_SHIELD := 0.015    # 糖衣炮弹每跳友军护盾 = 1.5% 自身最大生命（原 2%）
const WANT_SCYTHE_CURSE := 3.0        # 镰刀横扫诅咒秒数（原 5）
const WANT_STORM_ENERGY := 105.0      # 灵魂风暴龟能（原 95）
const WANT_CHIWAVE_LIFESTEAL := 0.20  # 龟派气波自增吸血（原 10%）
# 本轮故意不动
const FROZEN_SOUL_ATK := 0.5          # 灵魂打击普攻附带 0.5×ATK 魔法
const FROZEN_SOUL_HPPCT := 0.10       # 灵魂打击普攻附带 10% 目标【当前】生命

var _fail := 0
var _S := {}
var _pets := ""


func _ready() -> void:
	print("=== 第六轮龟平衡 + 文案↔代码一致 ===")
	for k in ["res://scripts/systems/skill_energy.gd",
			"res://scripts/systems/skills/ice_system.gd",
			"res://scripts/systems/skills/candy_system.gd",
			"res://scripts/systems/skills/headless_system.gd",
			"res://scripts/scenes/RealtimeBattle3DScene.gd"]:
		_S[k.get_file()] = FileAccess.get_file_as_string(k)
	_pets = FileAccess.get_file_as_string("res://data/pets.json")
	var tot := 0
	for v in _S.values():
		tot += str(v).length()
	print("  ★分母: 读到 %d 份源码 / %d 字符 + pets.json %d 字符" % [_S.size(), tot, _pets.length()])
	_chk("★分母: 五份源码都非空", _S.size() == 5 and tot > 150000)
	## ★分母改成"真的解析出 28 只龟", 不再按字符数。
	##   原来写 `length() > 100000` —— 2026-08-18 把简述从"塞四段"精简成"一句话"之后,
	##   文件正常地变小了, 这条分母就红了。**按体积当分母, 等于禁止文件变小。**
	var _pj = JSON.parse_string(_pets)
	_chk("★分母: pets.json 解析得出 28 只龟", _pj is Array and (_pj as Array).size() == 28)

	_nums()
	_text()
	_frozen()
	_auditor()

	if _fail == 0:
		print("ALL PASS — 第六轮龟平衡")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)


## ① 7 项数值 —— 每项配一条「旧值已消失」
func _nums() -> void:
	print("  ── ① 代码数值(7 项) ──")
	var se: String = _S["skill_energy.gd"]
	var ic: String = _S["ice_system.gd"]
	var ca: String = _S["candy_system.gd"]
	var hl: String = _S["headless_system.gd"]
	var rb: String = _S["RealtimeBattle3DScene.gd"]

	# 1. 冰霜每跳伤害
	_chk("① 冰霜每跳 = %.2fA 魔法" % WANT_FROST_ATK,
		ic.contains("battle._atk_dmg(u, %.2f, o, true)" % WANT_FROST_ATK))
	_chk("① 冰霜旧值 0.18 已消失", not ic.contains("battle._atk_dmg(u, 0.18, o, true)"))
	# 2. 冰柱每层攻速
	_chk("① 冰柱每层攻速 = %d%%" % int(WANT_ICICLE_ASPD * 100.0),
		ic.contains("const ICICLE_ASPD := %.2f" % WANT_ICICLE_ASPD))
	_chk("① 冰柱攻速旧值 0.03 已消失", not ic.contains("const ICICLE_ASPD := 0.03"))
	# 3. 糖衣炮弹龟能
	_chk("① 糖衣炮弹龟能 = %d" % int(WANT_BARRAGE_ENERGY),
		se.contains('"candyBarrage": %.1f' % WANT_BARRAGE_ENERGY))
	_chk("① 糖衣炮弹龟能旧值 120 已消失", not se.contains('"candyBarrage": 120.0'))
	# 4. 糖衣炮弹护盾（★只查护盾那一行；同函数里伤害也有 maxHp*0.02，不能一刀切）
	_chk("① 糖衣炮弹每跳护盾 = %.1f%% 自身最大生命" % (WANT_BARRAGE_SHIELD * 100.0),
		ca.contains('_grant_shield(o, uu["maxHp"] * %.3f, 2.0)' % WANT_BARRAGE_SHIELD))
	_chk("① 糖衣炮弹护盾旧值 0.02 已消失（伤害那处的 0.02 不算）",
		not ca.contains('_grant_shield(o, uu["maxHp"] * 0.02, 2.0)'))
	# 5. 镰刀横扫诅咒
	_chk("① 镰刀横扫诅咒 = %.1f 秒" % WANT_SCYTHE_CURSE,
		hl.contains("_add_curse(o, %.1f, uu)" % WANT_SCYTHE_CURSE))
	_chk("① 镰刀诅咒旧值 5.0 已消失", not hl.contains("_add_curse(o, 5.0, uu)"))
	# 6. 灵魂风暴龟能
	_chk("① 灵魂风暴龟能 = %d" % int(WANT_STORM_ENERGY),
		se.contains('"ghostStorm": %.1f' % WANT_STORM_ENERGY))
	_chk("① 灵魂风暴龟能旧值 95 已消失", not se.contains('"ghostStorm": 95.0'))
	# 7. 龟派气波: 删暴伤 + 吸血 20%
	_chk("① 龟派气波吸血 = %d%%" % int(WANT_CHIWAVE_LIFESTEAL * 100.0),
		rb.contains('u["lifesteal"] = float(u["lifesteal"]) + %.2f' % WANT_CHIWAVE_LIFESTEAL)
		and rb.contains('uu["lifesteal"] = float(uu["lifesteal"]) - %.2f' % WANT_CHIWAVE_LIFESTEAL))
	_chk("① 龟派气波吸血旧值 0.10 已消失",
		not rb.contains('u["lifesteal"] = float(u["lifesteal"]) + 0.10'))
	# ★暴伤要【加减两处都没了】—— 只删掉"加"那半边会让龟越打越弱, 是比不删更糟的 bug
	_chk("① ★龟派气波暴伤 buff 加/减两处都已删除",
		not rb.contains('u["crit_dmg"] = float(u["crit_dmg"]) + 0.20')
		and not rb.contains('uu["crit_dmg"] = float(uu["crit_dmg"]) - 0.20')
		and not rb.contains('u["crit_dmg"] += 0.20'))


## 取某龟某技的文案(brief + detail 拼一起)。
## ★必须【按技能取】不能全文件 grep —— 我第一版就是全文件查, 两条误红:
##   "10% 生命偷取" 是天使龟·平等的、"{N:0.9*ATK}" 是竹刺阵等 6 个技能的,
##   跟龟派气波/灵魂打击毫无关系。全文件 grep 既会误红, 反过来也会【被别的龟掩盖真漏】。
func _sk_text(pid: String, sname: String) -> String:
	var arr = JSON.parse_string(_pets)
	if not (arr is Array):
		return ""
	for x in arr:
		if str(x.get("id", "")) != pid:
			continue
		for s in x.get("skillPool", []):
			if str(s.get("name", "")) == sname:
				return str(s.get("brief", "")) + "\n" + str(s.get("detail", ""))
	return ""


## ② 文案 ↔ 代码 —— 本轮真教训: 我拿 tooltip 当事实源向用户汇报, 而它漂了一倍
func _text() -> void:
	print("  ── ② 文案(pets.json) 带上新数值 + 旧数值不许残留 ──")
	var frost := _sk_text("ice", "冰霜")
	var spike := _sk_text("ice", "冰锥")
	var barrage := _sk_text("candy", "糖衣炮弹")
	var wave := _sk_text("basic", "龟派气波")
	var soul := _sk_text("headless", "灵魂打击")
	# ★分母: 五段文案都真的取到了, 否则下面全是"空串不含旧值"的假 PASS
	_chk("② ★分母: 五段文案都取到(空串会让所有'旧值已消失'变假 PASS)",
		frost.length() > 80 and spike.length() > 80 and barrage.length() > 80
		and wave.length() > 80 and soul.length() > 80)

	# 冰霜
	_chk("② 文案·冰霜 = {M:0.25*ATK}", frost.contains("{M:0.25*ATK}"))
	_chk("② 文案·冰霜旧值 {M:0.18*ATK} 已消失", not frost.contains("{M:0.18*ATK}"))
	# 冰柱攻速(写在普攻【冰锥】的文案里)
	_chk("② 文案·冰柱每层 +5% 攻速",
		spike.contains("+5% 攻速") and spike.contains("+5% 攻击速度"))
	_chk("② 文案·冰柱旧值 +3% 已消失",
		not spike.contains("+3% 攻速") and not spike.contains("+3% 攻击速度"))
	# 糖衣炮弹护盾（★"2%"在同段里还用于伤害, 所以连上下文一起查）
	## ★判据只认【数字 + 它修饰的东西】, 不认填充词。
	##   原来写的是 `contains("相当于其 1.5% 最大生命值的护盾")` —— 把"相当于"这个
	##   纯赘词焊进了断言, 于是 2026-08-17 文案精简(删掉 28 处"相当于")时当场判红,
	##   而数字一个都没动。断言该守的是 1.5% 这个数, 不是我当初怎么造句。
	_chk("② 文案·糖衣炮弹护盾 1.5%",
		_has_txt(barrage, "1.5%最大生命值的护盾")
		and _has_txt(barrage, "范围内友军获得糖果龟1.5%最大生命值的护盾"))
	_chk("② 文案·糖衣炮弹护盾旧值 2% 已消失（伤害那处的 2% 不算）",
		not barrage.contains("2% 最大生命值的护盾")
		and not barrage.contains("范围内友军获得糖果龟2%最大生命值的护盾"))
	# 龟派气波
	## ★原来要求【两处】都写着 20% —— 一处在简述、一处在详情。简述精简成一句话后
	##   吸血那句只留在详情里, 这条就红了。判据的**意思**是"吸血写的是 20% 不是 10%",
	##   所以只要文案里出现 20% 的任一写法即可, 旧值 10% 仍必须彻底消失(下一条)。
	_chk("② 文案·龟派气波吸血 20%",
		wave.contains("20% 生命偷取") or wave.contains(">+20%</span>生命偷取"))
	_chk("② 文案·龟派气波旧值 10% 生命偷取已消失",
		not wave.contains("10% 生命偷取") and not wave.contains(">+10%</span>生命偷取"))
	_chk("② ★文案·龟派气波不再宣称暴击伤害 buff", not wave.contains("暴击伤害"))
	# 无头·灵魂打击 —— 本轮文案是【整段重写】的, 所以正反两面都查
	_chk("② 文案·灵魂打击 = 0.5A 魔法(不是 0.9A 物理)",
		soul.contains("{M:0.5*ATK}") and not soul.contains("{N:0.9*ATK}"))
	_chk("② 文案·灵魂打击 = 10% 目标当前生命(不是 20%)",
		soul.contains("10% 目标当前生命") or soul.contains("10%目标当前生命"))
	_chk("② ★文案·补上了此前完全没写的镰刀横扫", soul.contains("镰刀横扫"))
	_chk("② ★文案·镰刀横扫写明 3 秒诅咒", soul.contains("3 秒诅咒") or soul.contains("3秒诅咒"))
	_chk("② ★文案·镰刀横扫写明击退", soul.contains("击退"))
	_chk("② ★文案·灵魂打击写明锁龟能",
		soul.contains("锁龟能") or soul.contains("重新开始充能") or soul.contains("不充能"))


## ③ 本轮故意不动的 —— 用户 2026-07-30 逐字:「那就不动普攻附带的伤害」
func _frozen() -> void:
	print("  ── ③ 本轮故意不动的(用户明说不动·下轮判据) ──")
	var rb: String = _S["RealtimeBattle3DScene.gd"]
	_chk("③ ★灵魂打击普攻附带仍是 %.1fA 魔法(用户: 不动)" % FROZEN_SOUL_ATK,
		rb.contains("_atk_dmg(u, %.1f, tgt, true)" % FROZEN_SOUL_ATK))
	_chk("③ ★灵魂打击普攻附带仍是 %d%% 目标【当前】生命(不是最大生命)" % int(FROZEN_SOUL_HPPCT * 100.0),
		rb.contains('int(tgt["hp"] * %.2f)' % FROZEN_SOUL_HPPCT))
	# 用户先说削到 15%, 紧接着改口"那就不动" —— 15% 若出现在代码里就是我没跟上改口
	_chk("③ ★没有误实施被改口撤销的 15%", not rb.contains('int(tgt["hp"] * 0.15)'))


## ④ 双向审计器在位（否则本轮的一致性只是一次性的, 下轮又会漂）
func _auditor() -> void:
	print("  ── ④ 双向审计器在位 ──")
	for p in ["res://tools/pet_code_scope.py", "res://tools/pet_effect_dump.py",
			"res://tools/pet_number_audit.py"]:
		_chk("④ %s 在位" % p.get_file(), FileAccess.file_exists(p))
	var rt := FileAccess.get_file_as_string("res://run-tests.sh")
	_chk("④ ★pet_number_audit 进了 run-tests.sh 门禁(不进门禁等于没有)",
		rt.contains("pet_number_audit.py"))
	var au := FileAccess.get_file_as_string("res://tools/pet_number_audit.py")
	_chk("④ 审计器是【双向】的(有 ②代码→文案 那一半)",
		au.contains("HIDDEN") and au.contains("CATEGORY_WORDS"))


func _chk(name: String, ok: bool) -> void:
	print("  [%s] %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fail += 1


## 文案子串比对: 先把**空格全去掉**再比。
## ★2026-08-19 排版统一(数字与汉字之间补空格)一次打断了三条这样的断言。
##   它们真正要守的是"这个数值有没有出现在文案里", **不是"空格打在哪"** ——
##   拿排版当判据, 每次改一次文案排版就要改一遍测试, 而且红了还看不出是真是假。
func _has_txt(hay: String, needle: String) -> bool:
	return hay.replace(" ", "").replace("　", "").contains(needle.replace(" ", ""))
