class_name MagicEqVfx
extends BombEqVfx
## magic_eq_vfx.gd —— 魔法书羁绊【飞弹】+ 魔法书 10 件 + 三种骷髅 的演出层(2026-11-25 · 方案书 docs/plans/20261125b-魔法书羁绊.md)
##
## ★只画不判定: 结算全在 EqMagicBatch / MagicbookSynergySystem; 无头 / 没有世界节点时什么都不做(继承的 _ok())。
## ★生命周期 = 继承炸弹演出层的 `tick` / `_anim` / `_later`(不用 tween, CLAUDE.md §4.5); 本文件只换特效表(覆盖 `_row`)。
## 飞行物的位置由结算侧每步回调(`bolt_step` / `missile_step`)摆, 演出不自己按固定秒数补间。

## 特效表: 名 → [路径, 帧宽, 帧高, 内容直径(像素), 锚点 x, 锚点 y]
const MSHEETS := {}


func _row(key: String) -> Array:   # zero-caller-ok: 覆盖父类 BombEqVfx._row —— 父类的 _anim / _load 经它查表, 调用方在父类
	return MSHEETS.get(key, [])


# ── 飞行物(结算侧每步摆位置) ──
func mb_launch(_u: Dictionary, _tgt: Dictionary, _i: int, _n: int):
	return null


func mb_step(_node, _from2: Vector2, _p2: Vector2, _to2: Vector2, _k: float, _i: int) -> void:
	pass


func mb_land(_node, _tgt: Dictionary, _hit: bool) -> void:
	pass


func note_launch(_u: Dictionary, _tgt: Dictionary):
	return null


func note_land(_node, _tgt: Dictionary, _hit: bool) -> void:
	pass


func fire_launch(_u: Dictionary, _tgt: Dictionary):
	return null


func fire_land(_node, _tgt: Dictionary) -> void:
	pass


func forb_launch(_u: Dictionary, _tgt: Dictionary):
	return null


func forb_land(_node, _tgt: Dictionary) -> void:
	pass


func bolt_step(_node, _from2: Vector2, _p2: Vector2, _to2: Vector2, _k: float) -> void:
	pass


func wave_launch(_p: Dictionary, _dir: Vector2):
	return null


# ═══════════════════════════════ 123 亡者之书 · 骷髅 ═══════════════════════════════

## 技能动作帧条(112 方帧, 与待机同贴地线); 出招帧 = SKEL_SKILL_HIT(从 0 数), 帧率 = 出招帧 / 前摇秒数 ⇒ 出招帧落在结算那一刻
const SKEL_SKILL := {
	"skel_warrior": "res://assets/sprites/vfx/eq-skelw-skill.png",
	"skel_mage": "res://assets/sprites/vfx/eq-skelm-skill.png",
	"skel_priest": "res://assets/sprites/vfx/eq-skelp-skill.png",
}
const SKEL_SKILL_HIT := {"skel_warrior": 2, "skel_mage": 3, "skel_priest": 3}   # 抄自 pack_magic_art.py SKEL_HIT(怒吼 / 火团最大 / 双手前推)
static var _ssd := {}


func _skel_sd(kind: String, fps: float) -> Dictionary:
	if not _ssd.has(kind):
		var path: String = SKEL_SKILL.get(kind, "")
		var sd := {}
		if path != "" and ResourceLoader.exists(path):
			var t: Texture2D = load(path)
			sd = battle._sprite_dict_from(t, {"frames": t.get_width() / 112, "frameW": 112, "frameH": 112, "duration": 800}, false)
		_ssd[kind] = sd
	var out: Dictionary = (_ssd[kind] as Dictionary).duplicate()
	if not out.is_empty():
		out["fps"] = fps
	return out


func skel_cast(p: Dictionary, kind: String, windup: float) -> void:
	if not _ok() or not p.get("alive", false):
		return
	var sd := _skel_sd(kind, float(SKEL_SKILL_HIT.get(kind, 4)) / maxf(0.05, windup))
	if not sd.is_empty():
		battle._set_anim_sheet(p, sd, "skel_" + kind, true)
