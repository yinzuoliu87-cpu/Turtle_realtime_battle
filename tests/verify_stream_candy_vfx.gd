extends "res://tests/verify_stream_parity.gd"
## verify_stream_candy_vfx.gd —— 糖果龟普攻【横扫大锤】/ 技能【糖果锤】新特效(2026-11-15, scripts/scenes/battle/candy_vfx.gd)在直播里画得一样。
## 用户 11-15「接下来主要针对一下糖果龟的这个特效去专门修一下，尤其这个就是它的普通攻击和糖果锤」。
## 新特效(Blender 序列帧公告板 + 叠加发光 + 贴地裂痕)全是按出生参数驱动的粒子(`@afx`); 贴地裂痕带朝向(沿砸出去的方向转),
##   朝向只在建节点时整份发一次(录流器 `_node_new`), 手机渲染步不再碰它。斜着砸一锤, 看手机重放出来的裂痕是不是也转了。
## 做法: 父类 verify_stream_parity 的「录流 → 重放 → 逐采样点比」整套(节点 id / 显隐 / 帧号 / 贴图 / 变换 / 颜色 / 普查 / 飘字)。
## 判据:
##   ① 分母: 糖果锤真砸了(地面裂痕建过 ≥ 1 个)、至少一个是斜的(|朝向| > 0.1 弧度)、普攻序列帧建过 ≥ 1 个;
##      流里发了出生参数的粒子 > 0; 父类采样点里至少一个落在某道裂痕的寿命内(否则 ③ 比不到它)
##   ③ 重放逐采样点与原生一致(父类 ★★ 那几条)
## 反向验证(11-15): 见方案书 docs/plans/20261115c-糖果龟普攻与糖果锤特效.md §6。

const ZONE_PATH := "res://assets/sprites/vfx/candy-crack.png"
const PIN_PATH := "res://assets/sprites/vfx/candy-sweep.png"
const ZONE_LIFE_STEPS := 96         # candy_vfx.gd 裂痕寿命 CRACK_LIFE 1.6 秒 × 60

var _zones: Array = []             # [建出来那一步, 朝向]
var _pins := 0
var _rec_ref = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	## 糖果龟(技能选糖果锤, skillPool 下标 1)在左下, 两只木桩在右上 ⇒ 砸出去的方向是斜的
	var sc := {"tag": "糖果锤", "frames": 600, "seed": "424242", "loadouts": {"candy": 1}, "pairs": [
		["candy", "left", 420.0, 420.0, []],
		["stone", "right", 560.0, 330.0, []],
		["stone", "right", 600.0, 300.0, []]]}
	var hook := func(n: Node) -> void:
		if n is Sprite3D and (n as Sprite3D).texture != null:
			var path: String = (n as Sprite3D).texture.resource_path
			if path == ZONE_PATH:
				_zones.append([int(StreamRecorder.cur._step_n) if StreamRecorder.cur != null else -1, (n as Node3D).rotation.y])
			elif path == PIN_PATH:
				_pins += 1
	get_tree().node_added.connect(hook)
	var nat: Dictionary = await _record_det(sc)
	get_tree().node_added.disconnect(hook)
	var meta: Dictionary = nat["meta"]
	var tilted := 0
	for z in _zones:
		if absf(float(z[1])) > 0.1:
			tilted += 1
	var covered := 0
	for st in (nat["snaps"] as Dictionary).keys():
		for z in _zones:
			if int(st) >= int(z[0]) and int(st) < int(z[0]) + ZONE_LIFE_STEPS:
				covered += 1
				break
	print("  [量] 地面裂痕 %d 个(斜的 %d 个, 朝向 %s) · 普攻序列帧 %d 个 · 落在裂痕寿命内的采样点 %d 个 · 出生参数粒子 %d" % [
		_zones.size(), tilted, str(_zones.map(func(z): return snappedf(float(z[1]), 0.01))), _pins, covered, int(meta.get("afx", 0))])
	_ok("① 分母: 糖果锤真砸了(地面裂痕 %d ≥ 1), 至少一个是斜的(%d)" % [_zones.size(), tilted], _zones.size() >= 1 and tilted >= 1)
	_ok("① 分母: 普攻序列帧建过(%d ≥ 1)" % _pins, _pins >= 1)
	_ok("① 分母: 流里发了出生参数 `@afx` 的粒子 %d > 0" % int(meta.get("afx", 0)), int(meta.get("afx", 0)) > 0)
	_ok("① 分母: 采样点落在裂痕寿命内 %d ≥ 1(否则比不到它)" % covered, covered >= 1)
	await _play_and_compare("det " + str(sc["tag"]), nat["chunks"], meta, nat)
	_finish()
