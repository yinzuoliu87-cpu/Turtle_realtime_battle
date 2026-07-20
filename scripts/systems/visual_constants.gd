class_name VisualConstants extends RefCounted

## VisualConstants — 视觉规范常量 (跟 Phaser PoC 1:1 同步)
##
## 来源: games/turtle-battle-poc/src/systems/visual_dispatcher.ts:42-71
##
## 同步原则:
##   - 十六进制颜色 100% 同
##   - base 字号 (px → font_size) 100% 同
##   - size-by-amount 缩放公式 100% 同
##   - 暴击 ×1.2 100% 同
##   - 字体 m6x11.ttf 100% 同 (assets/fonts/m6x11.ttf)
##
## Godot 端唯一不同: 渲染引擎 (Freetype + outline 比 Phaser CSS text-shadow 干净一点)


## FLOAT_STYLE — 飘字 class → {color, base_size}
## Phaser visual_dispatcher.ts:42-71 1:1
const FLOAT_STYLE: Dictionary = {
	# ── 三色伤害 (物理红 / 魔法蓝 / 真伤白) ──
	"direct-dmg":   {"color": "#ff4444", "size": 22},
	"phys-dmg":     {"color": "#ff4444", "size": 22},   # alias
	"magic-dmg":    {"color": "#4dabf7", "size": 22},
	"true-dmg":     {"color": "#ffffff", "size": 22},
	"pierce-dmg":   {"color": "#ffffff", "size": 20},
	"shield-dmg":   {"color": "#aaaaaa", "size": 16},

	# ── 暴击 (同色, 大字号) ──
	"crit-dmg":     {"color": "#ff4444", "size": 26},
	"crit-magic":   {"color": "#4dabf7", "size": 26},
	"crit-true":    {"color": "#ffffff", "size": 26},
	"crit-pierce":  {"color": "#ffffff", "size": 24},
	"crit":         {"color": "#ff4444", "size": 26},

	# ── 治疗 / 护盾 ──
	"heal-num":     {"color": "#06d6a0", "size": 24},
	"heal":         {"color": "#06d6a0", "size": 24},   # alias
	"shield-num":   {"color": "#ffffff", "size": 22},
	"shield-gain":  {"color": "#ffffff", "size": 22},   # alias

	# ── 标签 / 触发 ──
	"crit-label":   {"color": "#ffd700", "size": 14},   # font-weight:900
	"passive-num":  {"color": "#7dffb3", "size": 16},
	"debuff-label": {"color": "#ff9f43", "size": 14},

	# ── DoT (按伤害类型上色) ──
	"dot-dmg":      {"color": "#4dabf7", "size": 18},   # 灼烧 = 魔蓝
	"dot-poison":   {"color": "#4dabf7", "size": 18},
	"dot-bleed":    {"color": "#ff4444", "size": 18},   # 流血 = 物红
	"dot-curse":    {"color": "#ffffff", "size": 18},   # 诅咒 = 真白

	# ── 特殊 ──
	"counter-dmg":  {"color": "#ffd93d", "size": 20},
	"death-explode":{"color": "#ff2222", "size": 24},
	"bubble-num":   {"color": "#4cc9f0", "size": 18},
	"bubble-burst": {"color": "#ff9f43", "size": 22},
	"dodge-num":    {"color": "#a0e8ff", "size": 16},
	"miss":         {"color": "#a0e8ff", "size": 16},   # alias
}


## 按伤害数值动态缩放字号 — Phaser visual_dispatcher.ts:293-299 1:1
## 公式:
##   <20:    20px
##   20-60:  20→24 线性
##   60-400: 24→35 线性
##   400+:   35px
##   暴击 (cls.startsWith('crit')):  ×1.2
static func size_by_amount(amount: int, is_crit: bool = false) -> int:
	var base_size: float
	if amount < 20:
		base_size = 20.0
	elif amount < 60:
		base_size = 20.0 + (float(amount - 20) / 40.0) * 4.0
	elif amount < 400:
		base_size = 24.0 + (float(amount - 60) / 340.0) * 11.0
	else:
		base_size = 35.0
	if is_crit:
		base_size *= 1.2
	return roundi(base_size)


## 给定 effect.kind + dmg_type + is_crit → 决定用哪个 FloatCls
## 这样 BattleScene 不用自己 if-else 一堆。
static func cls_for(kind: String, dmg_type: String = "physical", is_crit: bool = false) -> String:
	if kind == "heal":
		return "heal-num"
	if kind == "shield":
		return "shield-num"
	if kind == "miss" or kind == "dodge":
		return "dodge-num"
	if kind == "damage":
		if is_crit:
			if dmg_type == "magic":
				return "crit-magic"
			if dmg_type == "true":
				return "crit-true"
			return "crit-dmg"
		# 非暴击
		if dmg_type == "magic":
			return "magic-dmg"
		if dmg_type == "true":
			return "true-dmg"
		return "direct-dmg"
	# 未知 fallback
	return "direct-dmg"


## 拿 FLOAT_STYLE 的 color → Godot Color 对象
static func color_of(cls: String) -> Color:
	var style: Dictionary = FLOAT_STYLE.get(cls, {})
	var hex: String = style.get("color", "#ffffff")
	return Color(hex)


## 拿 FLOAT_STYLE base size (未经 amount 缩放, 用于 label 类)
static func base_size_of(cls: String) -> int:
	var style: Dictionary = FLOAT_STYLE.get(cls, {})
	return style.get("size", 18)


# ─── Juice 参数 (跟 Phaser BattleScene 同步) ───────────────────
# ⛔ 2026-07-19 核实: 本段常量【全部零读取】, 且与实际生效的那套【连单位都不同】(这里 毫秒/像素, 实际是 秒/米)。
# 实际生效的是 RealtimeBattle3DScene.gd 的 JUICE_* 一组(JUICE_HITSTOP_HEAVY=0.055秒 / JUICE_SHAKE_HEAVY=0.10米 等)。
# 想调顿帧/震屏去改那边 —— 改这里等于调到空气上。
# (本文件其余部分 FLOAT_STYLE / color_of / cls_for / base_size_of 另算, 别整个文件删)

## hit-stop 微停时长 (毫秒) — Phaser BattleScene:2796 juiceHitStop(70)
const HIT_STOP_MS_CRIT: int = 70

## 震屏强度 (Phaser cameras.shake(duration_ms, magnitude_0_to_1))
const SHAKE_CRIT_DURATION: float = 0.15      # 150ms
const SHAKE_CRIT_STRENGTH: float = 6.0       # ≈ 0.009 normalized → 6px on 1280
const SHAKE_BIG_DURATION: float = 0.11       # 110ms
const SHAKE_BIG_STRENGTH: float = 3.5        # ≈ 0.005 → 3.5px

## 大伤害判定: 伤害 / 目标 maxHp 比例
## Phaser BattleScene:2795-2797: pct > 0.12 触发轻震 (非暴击) — 跟 Phaser 同
const BIG_HIT_HP_RATIO: float = 0.12

## 飘字浮动时长 (秒) — Phaser DOM animation ~800-900ms 接近
const FLOAT_DURATION_S: float = 0.85
const FLOAT_RISE_PX: float = 60.0

## 延迟伤害条 (Phaser P2.4 同款): 红条秒减, 灰条 200ms 后跟收缩
const DELAYED_HP_BAR_DELAY_S: float = 0.2
const DELAYED_HP_BAR_DURATION_S: float = 0.4
