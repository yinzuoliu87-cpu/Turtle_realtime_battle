extends RefCounted
## equip_stats.gd — 59 件装备【逐星属性】单一事实源 + 展示格式化。
##
## ★2026-07-23 从 phase2_equip_runtime.gd(回合制旧引擎) 抽出:
##   实时版/图鉴/背包只用它的 STATS 表 + 这几个 stat 展示函数, 其余是回合制效果逻辑(实时零调用·已删)。
##   抽干净后, 装备【属性】只有这一份来源, 装备【效果】只有 RealtimeBattle3DScene._eq_* 一份, 不再分歧。
##
## 用 preload 引 (不用 class_name — 防 F5 未声明崩):
##   const EquipStats := preload("res://scripts/engine/equip_stats.gd")
##   EquipStats.STATS / EquipStats.stat_lines(id, star) / EquipStats.stat_line_all_stars(id)
##
## 单位 (从代码核实): crit=小数0~1 · _lifestealPct=整数% · armorPen/magicPen=flat · _maxEnergy=flat。

# ── 逐星基础属性 (idx 0=1★ / 1=2★ / 2=3★)。crit=小数。_lifestealPct=整数%。──
## 把某件装备某星级的属性表, 格式化成人能读的一行/多行(背包、图鉴共用)。
##
## ★字段与实装口径【一一对应】—— 见 RealtimeBattle3DScene._eq_apply_one_stats 里同名的 14 个分支。
## 加新字段时两边都要改, 否则背包会漏显示(用户2026-07-19「背包里我要看到每件装备提供的属性, 必须写完整」)。
## 百分比类字段在实装里是 /100 后加到单位上的, 这里按【玩家看到的百分比】显示。
static func stat_lines(item_id: String, star: int) -> Array:
	var arr: Array = STATS.get(item_id, [])
	var i: int = clampi(star, 1, 3) - 1
	if i < 0 or i >= arr.size():
		return []
	var st: Dictionary = arr[i]
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
	"p2eq_015": [{"hp": 60, "reflectPct": 10}, {"hp": 90, "reflectPct": 17}, {"hp": 140, "reflectPct": 25}],
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
	"p2eq_024": [{"atk": 30, "magicPen": 15, "_maxEnergy": 20}, {"atk": 55, "magicPen": 25, "_maxEnergy": 20}, {"atk": 300, "magicPen": 50, "_maxEnergy": 20}],
	"p2eq_025": [{"atk": 25}, {"atk": 35}, {"atk": 55}],
	"p2eq_028": [{"hp": 30, "magicPen": 5}, {"hp": 40, "magicPen": 9}, {"hp": 60, "magicPen": 14}],
	"p2eq_029": [{"hp": 50, "def": 9}, {"hp": 110, "def": 15}, {"hp": 150, "def": 25}],
	# ── 潮汐系 041/042/044/047 + 枪械 055/058 (批6) ──
	"p2eq_041": [{"hp": 40, "shieldHealPct": 10}, {"hp": 90, "shieldHealPct": 15}, {"hp": 170, "shieldHealPct": 20}],
	"p2eq_042": [{"hp": 60, "shieldHealPct": 20}, {"hp": 100, "shieldHealPct": 25}, {"hp": 180, "shieldHealPct": 30}],
	"p2eq_044": [{"hp": 40, "def": 5}, {"hp": 60, "def": 12}, {"hp": 90, "def": 20}],
	"p2eq_047": [{"hp": 100}, {"hp": 200}, {"hp": 700}],
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
}
