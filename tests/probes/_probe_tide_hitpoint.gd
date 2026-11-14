extends Node
## 探针(2026-11-14 晚, 不是门禁): 043 浪打到一只单位的那一刻, 画面上浪的**前沿**和**浪峰**各在单位前后多少码。
## 用户 11-14:「海浪的判定击中点在哪？合适吗」。
## 结算: 单位挨打时刻 = 前摇 + fwd / WAVE_DIST × travel, fwd = 单位在推进方向上离起浪点多远 ⇒ 那一刻推进量 trav == fwd。
## 画面: 同一个 `BattleVfx._tide_vert`(网格顶点就是它算的)在 trav = fwd 时, 横截面 t = 1(最前沿) / 浪峰(高度最大处) 的位置。
## 跑法: <godot> --headless --path . res://tests/probes/_probe_tide_hitpoint.tscn

const V := preload("res://scripts/scenes/battle/battle_vfx.gd")


func _ready() -> void:
	var dir := Vector2.RIGHT
	var perp := dir.orthogonal()
	var start := Vector2(-700.0, 0.0)
	var half := 900.0
	var fwd := 1600.0                       # 单位离起浪点 1600 码(与 verify_equip_040_045 同一局)
	print("[量] 打到单位那一刻(推进量 = %.0f 码), 浪在这只单位所在那条线上的位置(+ = 已经越过单位, 往前)" % fwd)
	for u in [0.35, 0.42, 0.5, 0.58, 0.65]:
		var front: Array = V._tide_vert(start, dir, perp, half, 1.0, fwd, u, 1.0)
		var best_t := 0.0
		var best_h := -1.0
		for k in range(101):
			var tt: float = float(k) / 100.0
			var v: Array = V._tide_vert(start, dir, perp, half, 1.0, fwd, u, tt)
			if float(v[1]) > best_h:
				best_h = float(v[1])
				best_t = tt
		var crest: Array = V._tide_vert(start, dir, perp, half, 1.0, fwd, u, best_t)
		var back: Array = V._tide_vert(start, dir, perp, half, 1.0, fwd, u, 0.0)
		var unit_x: float = start.x + fwd
		print("  横向 u=%.2f: 前沿 %+.0f 码 · 浪峰 %+.0f 码 · 浪尾 %+.0f 码" % [u,
			(front[0] as Vector2).x - unit_x, (crest[0] as Vector2).x - unit_x, (back[0] as Vector2).x - unit_x])
	print("PROBE DONE")
	get_tree().quit(0)
