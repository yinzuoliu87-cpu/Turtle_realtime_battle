extends RefCounted
## equip_stats.gd — 59 件装备【逐星属性】单一事实源 + 展示格式化。
##
## ★2026-07-23 从 phase2_equip_runtime.gd(回合制旧引擎) 抽出:
##   实时版/图鉴/背包只用它的 STATS 表 + 这几个 stat 展示函数, 其余是回合制效果逻辑(实时零调用·已删)。
##   抽干净后, 装备【属性】只有这一份来源, 装备【效果】只有 RealtimeBattle3DScene._eq_* 一份, 不再分歧。
##
## 用 preload 引 (不用 class_name — 防 F5 未声明崩):
##   const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")
##   EquipStats.STATS / EquipStats.stat_lines(id, star) / EquipStats.stat_line_all_stars(id)
##
## 单位 (从代码核实): crit=小数0~1 · _lifestealPct=整数% · armorPen/magicPen=flat · _maxEnergy=flat。

# ── 逐星基础属性 (idx 0=1★ / 1=2★ / 2=3★)。crit=小数。_lifestealPct=整数%。──
## 把某件装备某星级的属性表, 格式化成人能读的一行/多行(背包、图鉴共用)。
##
## ★字段与实装口径【一一对应】—— 见 scripts/systems/equip/equip_stats_apply.gd 的
## _eq_apply_one_stats 里同名的 14 个分支。(2026-08-02 更正指路: 拆分后已不在 RealtimeBattle3DScene)
## 加新字段时两边都要改, 否则背包会漏显示(用户2026-07-19「背包里我要看到每件装备提供的属性, 必须写完整」)。
## 百分比类字段在实装里是 /100 后加到单位上的, 这里按【玩家看到的百分比】显示。
static func stat_lines(item_id: String, star: int) -> Array:
	var arr: Array = STATS.get(item_id, [])
	var i: int = clampi(star, 1, 3) - 1
	if i < 0 or i >= arr.size():
		return []
	return lines_of(arr[i])


## ★2026-08-03 抽出的纯函数: 属性 dict → [[标签, 显示值], …]。
## 为什么要抽: 原来只能按 item_id 查表, 于是【还没有任何装备用的新字段】没法测 ——
## 而那正是 dodgePct 烂掉的原因(展示分支写了、施加分支从来没有, 图鉴上的数字是假的,
## 活了很久到 v0.18.9 才修)。抽出来之后, 门禁可以直接喂一个 {"_aspdPct": 20} 验两侧成对。
static func lines_of(st: Dictionary) -> Array:
	var out: Array = []
	# 顺序 = 玩家最关心的在前(攻→生命→双抗→暴击→穿透→吸血→增幅→龟能)
	if st.has("atk"):            out.append(["攻击力", "+%d" % int(st["atk"])])
	if st.has("hp"):             out.append(["最大生命", "+%d" % int(st["hp"])])
	if st.has("def"):            out.append(["护甲", "+%d" % int(st["def"])])
	if st.has("mr"):             out.append(["魔抗", "+%d" % int(st["mr"])])
	if st.has("crit"):           out.append(["暴击率", "+%d%%" % int(round(float(st["crit"]) * 100.0))])
	if st.has("critDmg"):        out.append(["暴击伤害", "+%d%%" % int(round(float(st["critDmg"]) * 100.0))])
	if st.has("armorPen"):       out.append(["护甲穿透", "+%d" % int(st["armorPen"])])
	if st.has("magicPen"):       out.append(["魔法穿透", "+%d" % int(st["magicPen"])])
	if st.has("_lifestealPct"):  out.append(["生命偷取", "+%d%%" % int(st["_lifestealPct"])])
	if st.has("dodgePct"):       out.append(["闪避", "+%d%%" % int(st["dodgePct"])])
	if st.has("reflectPct"):     out.append(["反伤", "+%d%%" % int(st["reflectPct"])])
	if st.has("healAmp"):        out.append(["治疗增幅", "+%d%%" % int(st["healAmp"])])
	if st.has("shieldAmp"):      out.append(["护盾增幅", "+%d%%" % int(st["shieldAmp"])])
	if st.has("shieldHealPct"):  out.append(["治疗与护盾增幅", "+%d%%" % int(st["shieldHealPct"])])
	if st.has("_maxEnergy"):     out.append(["初始龟能", "+%d" % int(st["_maxEnergy"])])
	if st.has("_echargePct"):    out.append(["龟能充能速率", "+%d%%" % int(st["_echargePct"])])
	if st.has("_rangeAdd"):      out.append(["射程", "+%d" % int(st["_rangeAdd"])])
	# ★2026-08-03 批2 新增三个属性字段(方案书 D7)。龟能充能速率(_echargePct)本来就有。
	#   ⚠ 多件叠加一律【加】不是【乘】(D16, 用户原话「u4加吧」) —— 施加侧见 equip_stats_apply.gd。
	if st.has("_aspdPct"):       out.append(["攻击速度", "+%d%%" % int(st["_aspdPct"])])
	if st.has("_mspdPct"):       out.append(["移动速度", "+%d%%" % int(st["_mspdPct"])])
	if st.has("_rangePct"):      out.append(["攻击射程", "+%d%%" % int(st["_rangePct"])])
	return out

## 单行紧凑版(给 tooltip / 一行标签用): "攻击力+20 · 暴击率+25%"
static func stat_line_compact(item_id: String, star: int) -> String:
	var parts: Array = []
	for kv in stat_lines(item_id, star):
		parts.append("%s%s" % [kv[0], kv[1]])
	return " · ".join(parts) if not parts.is_empty() else "无属性加成"

## 三星合并版(给图鉴用): "攻击力 +8/14/30 · 暴击率 +15/25/40%"
##
## 星级间某字段缺失时补 "—", 例如只有 3★ 才给的属性显示成 "—/—/+20"。
static func stat_lines_all_stars(item_id: String) -> Array:
	var names: Array = []          # 保持 stat_lines 的字段顺序, 不用 Dictionary(无序)
	var by_name: Dictionary = {}
	for s in [1, 2, 3]:
		for kv in stat_lines(item_id, s):
			var n: String = str(kv[0])
			if not by_name.has(n):
				by_name[n] = ["—", "—", "—"]
				names.append(n)
			by_name[n][s - 1] = str(kv[1])
	var out: Array = []
	for n in names:
		out.append([n, "/".join(PackedStringArray(by_name[n]))])
	return out

## 三星合并单行: "攻击力 +8/+14/+30 · 暴击率 +15%/+25%/+40%"
static func stat_line_all_stars(item_id: String) -> String:
	var parts: Array = []
	for kv in stat_lines_all_stars(item_id):
		parts.append("%s %s" % [kv[0], kv[1]])
	return " · ".join(parts) if not parts.is_empty() else "无属性加成"

const STATS := {
	"p2eq_001": [{"atk": 5, "crit": 0.10}, {"atk": 12, "crit": 0.15}, {"atk": 20, "crit": 0.25}],
	"p2eq_002": [{"atk": 12}, {"atk": 24}, {"atk": 40}],
	"p2eq_003": [{"atk": 8, "armorPen": 5, "crit": 0.15}, {"atk": 14, "armorPen": 7, "crit": 0.25}, {"atk": 30, "armorPen": 10, "crit": 0.40}],
	"p2eq_004": [{"atk": 15, "crit": 0.25, "_lifestealPct": 5}, {"atk": 30, "crit": 0.35, "_lifestealPct": 9}, {"atk": 90, "crit": 0.60, "_lifestealPct": 15}],
	"p2eq_005": [{"atk": 14, "_lifestealPct": 4, "_maxEnergy": 20}, {"atk": 30, "_lifestealPct": 7, "_maxEnergy": 20}, {"atk": 50, "_lifestealPct": 10, "_maxEnergy": 20}],
	"p2eq_006": [{"atk": 18, "armorPen": 6}, {"atk": 40, "armorPen": 12}, {"atk": 90, "armorPen": 20}],
	"p2eq_007": [{"atk": 5, "hp": 20}, {"atk": 10, "hp": 45}, {"atk": 20, "hp": 100}],
	"p2eq_008": [{"atk": 8, "armorPen": 4, "magicPen": 4}, {"atk": 15, "armorPen": 8, "magicPen": 8}, {"atk": 30, "armorPen": 12, "magicPen": 12}],
	"p2eq_009": [{"atk": 12, "_maxEnergy": 20}, {"atk": 25, "_maxEnergy": 20}, {"atk": 40, "_maxEnergy": 20}],
	"p2eq_010": [{"atk": 30, "armorPen": 10, "hp": 50}, {"atk": 75, "armorPen": 18, "hp": 120}, {"atk": 200, "armorPen": 30, "hp": 1300}],
	# ── 剑系 011 (饮血护符坠) ──
	"p2eq_011": [{"atk": 10, "_lifestealPct": 15, "healAmp": 15, "shieldAmp": 15}, {"atk": 23, "_lifestealPct": 24, "healAmp": 24, "shieldAmp": 24}, {"atk": 40, "_lifestealPct": 33, "healAmp": 33, "shieldAmp": 33}],
	# ── 盾系 012-017 ──
	"p2eq_012": [{"hp": 40, "def": 5}, {"hp": 70, "def": 10}, {"hp": 100, "def": 18}],
	"p2eq_013": [{"hp": 60, "reflectPct": 8}, {"hp": 110, "reflectPct": 11}, {"hp": 200, "reflectPct": 15}],
	"p2eq_014": [{"hp": 80, "def": 14, "mr": 14}, {"hp": 160, "def": 25, "mr": 25}, {"hp": 600, "def": 50, "mr": 50}],
	"p2eq_015": [{"hp": 100, "reflectPct": 12}, {"hp": 200, "reflectPct": 25}, {"hp": 1000, "reflectPct": 40}],   # 用户2026-07-30 加强: hp 60/90/140→100/200/1000, 反伤 10/17/25→12/25/40
	"p2eq_016": [{"def": 6, "mr": 6}, {"def": 13, "mr": 13}, {"def": 21, "mr": 21}],
	"p2eq_017": [{"hp": 200, "def": 15, "mr": 15}, {"hp": 450, "def": 35, "mr": 35}, {"hp": 4000, "def": 150, "mr": 150}],
	# ── 盾系 018-021 (批3) ──
	"p2eq_018": [{"hp": 70, "mr": 8, "healAmp": 5, "shieldAmp": 5}, {"hp": 140, "mr": 13, "healAmp": 13, "shieldAmp": 13}, {"hp": 300, "mr": 18, "healAmp": 20, "shieldAmp": 20}],
	"p2eq_019": [{"def": 5, "mr": 10}, {"def": 10, "mr": 15}, {"def": 16, "mr": 21}],
	"p2eq_020": [{"hp": 100, "def": 3, "mr": 3, "_echargePct": 10}, {"hp": 140, "def": 4, "mr": 4, "_echargePct": 10}, {"hp": 210, "def": 6, "mr": 6, "_echargePct": 10}],
	"p2eq_021": [{"hp": 60, "_maxEnergy": 20}, {"hp": 100, "_maxEnergy": 20}, {"hp": 180, "_maxEnergy": 20}],
	# ── 杖系/元素 022-025,028,029 (批4) ──
	"p2eq_022": [{"atk": 8, "_echargePct": 10}, {"atk": 15, "_echargePct": 10}, {"atk": 25, "_echargePct": 10}],
	"p2eq_023": [{"hp": 40, "atk": 10, "magicPen": 5}, {"hp": 60, "atk": 25, "magicPen": 8}, {"hp": 80, "atk": 40, "magicPen": 13}],
	# 龙蛋削弱二(用户 2026-07-29): 30/55/300 攻 → 20/45/70; 魔穿 15/25/50 → 8/15/27。
	# 原 ★3 的 300 攻是全表第三高、只输给两件 5 费装备, 而其他 3 费装备顶天 55 —— 3 费卖 5 费的强度。
	"p2eq_024": [{"atk": 20, "magicPen": 8, "_maxEnergy": 20}, {"atk": 45, "magicPen": 15, "_maxEnergy": 20}, {"atk": 70, "magicPen": 27, "_maxEnergy": 20}],
	"p2eq_025": [{"atk": 25}, {"atk": 35}, {"atk": 55}],
	"p2eq_028": [{"hp": 30, "magicPen": 5}, {"hp": 40, "magicPen": 9}, {"hp": 60, "magicPen": 14}],
	"p2eq_029": [{"hp": 50, "def": 9}, {"hp": 110, "def": 15}, {"hp": 150, "def": 25}],
	# ── 潮汐系 041/042/044/047 + 枪械 055/058 (批6) ──
	"p2eq_041": [{"hp": 40, "shieldHealPct": 10}, {"hp": 90, "shieldHealPct": 15}, {"hp": 170, "shieldHealPct": 20}],
	"p2eq_042": [{"hp": 60, "shieldHealPct": 20}, {"hp": 100, "shieldHealPct": 25}, {"hp": 180, "shieldHealPct": 30}],
	"p2eq_044": [{"hp": 40, "def": 5}, {"hp": 60, "def": 12}, {"hp": 90, "def": 20}],
	# 重击锤: 3★ hp 700→400 (用户2026-08-01)。★连带: 它的 hammer_pct 是 ATK += maxHp×15%,
	#   砍血等于连攻一起砍 —— 这是按字面执行的已知副作用, 见 docs/plans/20260801-装备批次13条.md R4。
	"p2eq_047": [{"hp": 100}, {"hp": 200}, {"hp": 400}],
	"p2eq_055": [{"atk": 9, "_maxEnergy": 20}, {"atk": 15, "_maxEnergy": 20}, {"atk": 21, "_maxEnergy": 20}],
	"p2eq_058": [{"atk": 17, "_maxEnergy": 20}, {"atk": 29, "_maxEnergy": 20}, {"atk": 41, "_maxEnergy": 20}],
	# ── 召唤系 037/038/040 + 潮汐 045 (批7) ──
	"p2eq_037": [{"atk": 10, "hp": 80}, {"atk": 25, "hp": 130}, {"atk": 40, "hp": 180}],
	"p2eq_038": [{"hp": 80}, {"hp": 140}, {"hp": 200}],
	"p2eq_040": [{"hp": 100}, {"hp": 200}, {"hp": 500}],
	"p2eq_045": [{"hp": 90, "def": 4, "mr": 4}, {"hp": 170, "def": 8, "mr": 8}, {"hp": 300, "def": 15, "mr": 15}],
	# ── 枪械系 048/050/051/057 (批8, on_cast 连射) ──
	"p2eq_048": [{"atk": 12}, {"atk": 25}, {"atk": 41}],
	"p2eq_050": [{"atk": 20, "armorPen": 5}, {"atk": 50, "armorPen": 11}, {"atk": 120, "armorPen": 18}],
	"p2eq_051": [{"atk": 16, "armorPen": 3, "_lifestealPct": 4}, {"atk": 28, "armorPen": 6, "_lifestealPct": 6}, {"atk": 42, "armorPen": 10, "_lifestealPct": 9}],
	"p2eq_057": [{"atk": 18, "armorPen": 10}, {"atk": 30, "armorPen": 16}, {"atk": 70, "armorPen": 30}],
	# ── 枪械049连发弩/053霰弹/054瞄准镜 + 独立059沙漏 (批9) ──
	"p2eq_049": [{"atk": 15, "crit": 0.15}, {"atk": 32, "crit": 0.25}, {"atk": 50, "crit": 0.40}],
	"p2eq_053": [{"atk": 14, "crit": 0.10}, {"atk": 25, "crit": 0.15}, {"atk": 41, "crit": 0.25}],
	"p2eq_054": [{"atk": 10, "crit": 0.15, "critDmg": 0.10}, {"atk": 15, "crit": 0.25, "critDmg": 0.15}, {"atk": 20, "crit": 0.40, "critDmg": 0.20}],
	"p2eq_059": [{"hp": 100, "_echargePct": 10}, {"hp": 210, "_echargePct": 10}, {"hp": 1000, "_echargePct": 10}],   # 沙漏: +生命 + 龟能充能+10%(echarge_perm×1.1); 主动=JoJo时停(登场10s触发, _eq_hourglass_timestop)
	# ── 杖系026雷电/027电棍/030·031水晶球 + 潮汐043海浪护符 (批10) ──
	"p2eq_026": [{"magicPen": 8}, {"magicPen": 13}, {"magicPen": 20}],
	"p2eq_027": [{"hp": 20, "def": 5, "mr": 5}, {"hp": 40, "def": 8, "mr": 8}, {"hp": 80, "def": 13, "mr": 13}],
	"p2eq_030": [{"atk": 7, "hp": 20, "magicPen": 5}, {"atk": 12, "hp": 40, "magicPen": 8}, {"atk": 20, "hp": 80, "magicPen": 13}],
	"p2eq_031": [{"atk": 7, "hp": 20, "magicPen": 3}, {"atk": 12, "hp": 40, "magicPen": 6}, {"atk": 20, "hp": 80, "magicPen": 10}],
	"p2eq_043": [{"hp": 80, "shieldHealPct": 10}, {"hp": 200, "shieldHealPct": 20}, {"hp": 5000, "shieldHealPct": 30}],
	# ── 召唤034玩偶小熊 (批12, 召唤大熊fighter — spawn管线在BattleScene) ──
	"p2eq_034": [{"atk": 20, "hp": 120}, {"atk": 50, "hp": 250}, {"atk": 300, "hp": 1000}],
	# ── 召唤039竹制弓箭 + 枪械052左轮 (批11) ──
	"p2eq_039": [{"hp": 80}, {"hp": 140}, {"hp": 200}],
	"p2eq_052": [{"atk": 40, "armorPen": 15}, {"atk": 90, "armorPen": 24}, {"atk": 500, "armorPen": 50}],
	# ── 召唤035黄铜齿轮 (批12, 死亡钩子) ──
	"p2eq_035": [{"hp": 100, "atk": 5}, {"hp": 130, "atk": 13}, {"hp": 180, "atk": 22}],
	# ── 召唤036温泉蛋 (批13, 复用孵化进度) ──
	"p2eq_036": [{"hp": 70}, {"hp": 120}, {"hp": 180}],
	# ── 潮汐046幽灵墨鱼 (批14, 复用_roll_dodge) ──
	"p2eq_046": [{"hp": 80, "dodgePct": 15}, {"hp": 140, "dodgePct": 25}, {"hp": 400, "dodgePct": 50}],
	# ── 枪械056飞镖 (批15, 复用_knockedUpThisTurn击飞靶子) ──
	"p2eq_056": [{"atk": 45}, {"atk": 90}, {"atk": 400}],
	# ── 召唤032唤灵骨符(纯属性) + 033复活海螺(复用e_conch死亡变虫) (批16) ──
	"p2eq_032": [{"hp": 50}, {"hp": 60}, {"hp": 70}],
	"p2eq_033": [{"hp": 110}, {"hp": 270}, {"hp": 3000}],
	"p2eq_060": [{"def": 5, "mr": 5}, {"def": 11, "mr": 11}, {"def": 19, "mr": 19}],   # 灵物 · 1费 · 磷光水母伞(★用户 §0.5「属性改为给护甲和魔抗」·数值我提 5/11/19 用户「数值可以」)
	"p2eq_061": [{"_rangeAdd": 50, "_aspdPct": 15}, {"_rangeAdd": 50, "_aspdPct": 30}, {"_rangeAdd": 50, "_aspdPct": 50}],   # 灵物 · 2费 · 钻孔螺(★用户范例「装备3」原话: 50 射程 + 15/30/50% 攻速; 射程三星同值)
	"p2eq_062": [{"atk": 12, "_mspdPct": 5}, {"atk": 30, "_mspdPct": 9}, {"atk": 66, "_mspdPct": 15}],   # 灵物 · 2费 · 螳螂虾钳(★用户 §0.5 只写「攻击力·移速」没给数, 我按同为 2 费的 092 沉船罗盘同带取值)
	"p2eq_063": [{"_aspdPct": 8, "crit": 0.10}, {"_aspdPct": 15, "crit": 0.18}, {"_aspdPct": 25, "crit": 0.30}],   # 灵物 · 3费 · 白鲸气环(★用户 §0.5 只写「攻速·暴击率」没给数, 我按同为 3 费的 083 潮汐细剑同带取值)
	"p2eq_064": [{"hp": 100, "_echargePct": 10}, {"hp": 260, "_echargePct": 18}, {"hp": 600, "_echargePct": 30}],   # 灵物 · 4费 · 溺者的浮囊(★用户 §0.5「生命值 · 龟能充能速率」; 生命沿用原值, 充能速率我按 4 费带取值)
	# ── 药水四件(2026-08-05 用户逐件重做·§0.5 定稿) ────────────────────────────
	# 065 射程走 flat 通道 `_rangeAdd`(三星同值 50): 系统原来只有百分比字段, 用户写的是绝对值。
	#   副作用已告知用户并接受: 近战基础 70 ⇒ +50 码约 +50%, 远程 400~450 ⇒ 只 +12%, 对近战收益大得多。
	"p2eq_065": [{"_rangeAdd": 50, "_aspdPct": 10, "_lifestealPct": 3}, {"_rangeAdd": 50, "_aspdPct": 20, "_lifestealPct": 6}, {"_rangeAdd": 50, "_aspdPct": 30, "_lifestealPct": 10}],   # 药水 · 3费 · 鲨肝油
	"p2eq_066": [{"_maxEnergy": 20, "_mspdPct": 6}, {"_maxEnergy": 35, "_mspdPct": 11}, {"_maxEnergy": 60, "_mspdPct": 18}],   # 药水 · 4费 · 鲸涎浓浆(喝药后的十项属性【不在这里】: 那是效果, 在 eq_potion_batch.gd)
	"p2eq_067": [{"hp": 110, "atk": 15, "magicPen": 10}, {"hp": 280, "atk": 38, "magicPen": 20}, {"hp": 650, "atk": 90, "magicPen": 38}],   # 药水 · 4费 · 毒药瓶
	"p2eq_068": [{"hp": 180, "_aspdPct": 10, "shieldHealPct": 15}, {"hp": 460, "_aspdPct": 18, "shieldHealPct": 25}, {"hp": 1100, "_aspdPct": 30, "shieldHealPct": 40}],   # 药水 · 5费 · 深海气压罐(★shieldHealPct 是现成的合并字段, 用户点名不要拆成 healAmp+shieldAmp)
	# ── 食物 4 件(2026-08-05 用户逐件重做·§0.5 定稿): 属性【字段】由用户点名, 逐星数值我填 ──
	"p2eq_069": [{"_lifestealPct": 5, "_echargePct": 8}, {"_lifestealPct": 9, "_echargePct": 14}, {"_lifestealPct": 15, "_echargePct": 24}],   # 食物 · 3费 · 珊瑚糖糕(用户: 生命偷取 · 龟能充能速率)
	"p2eq_070": [{"hp": 120, "atk": 18}, {"hp": 300, "atk": 45}, {"hp": 700, "atk": 100}],   # 食物 · 4费 · 压舱咸鱼砖(用户: 生命值 · 攻击力 —— ★三段效果全按最大生命缩放, hp 就是它的核心属性)
	"p2eq_071": [{"shieldHealPct": 14, "def": 10, "mr": 10}, {"shieldHealPct": 26, "def": 22, "mr": 22}, {"shieldHealPct": 45, "def": 40, "mr": 40}],   # 食物 · 4费 · 炼乳罐(用户: 治疗和护盾强度 · 双抗)
	"p2eq_072": [{"hp": 200, "def": 10, "mr": 10}, {"hp": 550, "def": 24, "mr": 24}, {"hp": 1400, "def": 55, "mr": 55}],   # 食物 · 5费 · 铁皮蛋糕盒(用户: 双抗 · 生命值)
	"p2eq_073": [{"crit": 0.1, "_rangeAdd": 50}, {"crit": 0.18, "_rangeAdd": 70}, {"crit": 0.3, "_rangeAdd": 100}],   # 弓箭 · 1费 · 藤蔓弓弦(2026-08-05 用户亲手重写·§0.5: 射程改成【绝对码数】50/70/100, 走 _rangeAdd 不是百分比)
	"p2eq_074": [{"hp": 50, "_aspdPct": 6}, {"hp": 120, "_aspdPct": 11}, {"hp": 260, "_aspdPct": 18}],   # 弓箭 · 1费 · 鲸骨胸甲(2026-08-05 用户亲手重写·§0.5)
	"p2eq_075": [{"atk": 12, "_rangeAdd": 40}, {"atk": 30, "_rangeAdd": 60}, {"atk": 68, "_rangeAdd": 90}],   # 弓箭 · 2费 · 测距绳结(2026-08-05 用户亲手重写·§0.5)
	"p2eq_076": [{"atk": 20, "_lifestealPct": 6, "critDmg": 0.15}, {"atk": 50, "_lifestealPct": 11, "critDmg": 0.28}, {"atk": 115, "_lifestealPct": 18, "critDmg": 0.5}],   # 弓箭 · 4费 · 连发弩机(2026-08-05 用户亲手重写·§0.5: 属性类别改成攻击力/吸血/暴伤, 原案的暴击与射程作废)
	"p2eq_077": [{"armorPen": 4, "_aspdPct": 5}, {"armorPen": 9, "_aspdPct": 9}, {"armorPen": 18, "_aspdPct": 15}],   # 枪 · 1费 · 铜管手铳
	"p2eq_078": [{"armorPen": 5, "_aspdPct": 6}, {"armorPen": 11, "_aspdPct": 11}, {"armorPen": 22, "_aspdPct": 18}],   # 枪 · 2费 · 双管贝壳枪
	"p2eq_079": [{"armorPen": 7, "_aspdPct": 8}, {"armorPen": 15, "_aspdPct": 15}, {"armorPen": 30, "_aspdPct": 25}],   # 枪 · 3费 · 军械库连射机
	"p2eq_080": [{"atk": 30, "armorPen": 14, "_aspdPct": 10}, {"atk": 90, "armorPen": 30, "_aspdPct": 18}, {"atk": 260, "armorPen": 55, "_aspdPct": 30}],   # 枪 · 5费 · 穿甲重炮
	"p2eq_081": [{"hp": 50, "def": 6}, {"hp": 120, "def": 13}, {"hp": 260, "def": 22}],   # 盾 · 1费 · 藤编圆盾
	"p2eq_082": [{"hp": 70, "def": 7}, {"hp": 170, "def": 15}, {"hp": 380, "def": 26}],   # 盾 · 2费 · 砗磲护心甲
	"p2eq_083": [{"atk": 18, "crit": 0.1}, {"atk": 42, "crit": 0.18}, {"atk": 92, "crit": 0.3}],   # 剑 · 3费 · 潮汐细剑
	"p2eq_084": [{"atk": 22, "crit": 0.12}, {"atk": 55, "crit": 0.22}, {"atk": 125, "crit": 0.38}],   # 剑 · 4费 · 血牙巨剑
	"p2eq_085": [{"mr": 9, "_echargePct": 5}, {"mr": 19, "_echargePct": 9}, {"mr": 34, "_echargePct": 15}],   # 奇械 · 1费 · 铜齿护符
	"p2eq_086": [{"def": 12, "mr": 18, "_echargePct": 10}, {"def": 30, "mr": 45, "_echargePct": 18}, {"def": 80, "mr": 130, "_echargePct": 30}],   # 奇械 · 5费 · 极地反冲装置
	"p2eq_087": [{"hp": 150, "mr": 20, "_echargePct": 8}, {"hp": 420, "mr": 50, "_echargePct": 14}, {"hp": 1200, "mr": 145, "_echargePct": 24}],   # 奇械 · 5费 · 深渊铸币机
	"p2eq_088": [{"magicPen": 5, "_maxEnergy": 12}, {"magicPen": 11, "_maxEnergy": 22}, {"magicPen": 20, "_maxEnergy": 40}],   # 法器 · 1费 · 潮汐骨杖
	"p2eq_089": [{"magicPen": 5, "_echargePct": 6}, {"magicPen": 11, "_echargePct": 11}, {"magicPen": 20, "_echargePct": 18}],   # 法器 · 1费 · 蚀月符纸
	"p2eq_090": [{"magicPen": 18, "_maxEnergy": 45, "_echargePct": 12}, {"magicPen": 42, "_maxEnergy": 80, "_echargePct": 22}, {"magicPen": 110, "_maxEnergy": 150, "_echargePct": 38}],   # 法器 · 5费 · 万潮法典
	"p2eq_091": [{"hp": 50, "_lifestealPct": 4}, {"hp": 120, "_lifestealPct": 8}, {"hp": 260, "_lifestealPct": 14}],   # 遗物 · 1费 · 远古龟甲片
	# 2026-08-05 用户重做: 属性原话「提供 50/70/100 生命值和 10/22/40 魔抗」——
	# 就这两项, 所以原来的 atk/_lifestealPct 一并换掉(不是加在它们之上)。
	"p2eq_092": [{"hp": 50, "mr": 10}, {"hp": 70, "mr": 22}, {"hp": 100, "mr": 40}],   # 遗物 · 2费 · 毒蛾茧
	"p2eq_093": [{"def": 6, "_lifestealPct": 5}, {"def": 14, "_lifestealPct": 10}, {"def": 30, "_lifestealPct": 17}],   # 遗物 · 2费 · 祭坛残石
	"p2eq_094": [{"atk": 25, "hp": 120, "_lifestealPct": 9}, {"atk": 62, "hp": 300, "_lifestealPct": 18}, {"atk": 140, "hp": 700, "_lifestealPct": 30}],   # 遗物 · 4费 · 觉醒之核
	"p2eq_095": [{"hp": 250}, {"hp": 250}, {"hp": 250}],   # 圣光护盾(盾羁绊3档赠送·不占容量·三星同值: 它不参与合成)
}
