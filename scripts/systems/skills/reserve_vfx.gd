class_name ReserveVfx
extends RefCounted
## 援军小将·四面合围 的演出(方案书 docs/plans/20261029-终极战场援军小将.md; 结算在 ReserveSystem, 数值在 ReserveConsts)。
## 素材全部由 tools/build_reserve_vfx.py 逐像素确定性生成(专用、硬边、零半透明、逐帧; pixel_size 恒定只切帧, 不靠缩放)。
##
## ★纯表现: 不读写任何单位字段、不用 _battle_rng、不往 _pending_shots 里塞东西 —— 只建 / 改 / 删自己挂进 battle._world 的节点,
##   节点名字都带 TAG, 全部由自己的 tween(battle._reg_tween, 按 sim 步喂)按时收掉。门禁 tests/verify_reserve_vfx.gd。
##
## 分段表(t = 施法那一刻; 气波 WAVE_SPEED 码/秒从 WAVE_RADIUS 码外出发 ⇒ 名义 0.684 秒合拢):
##   | 段     | 说什么                         | 时间            | 怎么画                                                              |
##   | 锁定   | 这个人被盯上了, 四道冲这儿合拢 | 0 ~ 合拢 + 0.14 | 贴地: 四角括号 + 四个朝内箭头(转到「施法者→目标」方向 = 正指四道来向), 箭头随气波逼近逐帧收拢, 合拢那帧括号收紧后散掉; lock_follow 每步跟目标 |
##   | 凝聚   | 气在这四个点凝成气团           | 0 ~ 0.20        | 立着(气团高度): 8 颗光点向内汇聚 → 白热团 + 十字尖芒 → 小环弹开碎掉 |
##   | 出现印 | 气团从这儿出发, 有这么宽       | 0 ~ 0.22        | 贴地: 一圈由小到大的环, 末帧外沿 = 判定半宽 WAVE_HALF_W               |
##   | 弹体   | 一道有方向的气波在追人         | 飞行全程        | reserve-wave-dir(机头 +X, 6 帧循环) —— 弹体节点归飞行逻辑管, 素材由 build_reserve_vfx.py 画 |
##   | 拖尾   | 气团在高速往前冲               | 飞行全程        | 飞行逻辑每步调 wave_trail(弹体位置, 方向, 弹长): 在弹体尾焰末端留一团(6 帧散掉, 与弹体同一像素密度), 间距 ≥ TRAIL_GAP |
##   | 命中   | 打中了(用户问过「有命中特效吗」) | 0.245         | 立着、不被地面 / 立绘挡: 一下亮闪 → 粗冲击环外扩断开 + 碎屑下坠; 摆在被打者「气波来的那一侧」 |
##   | 散去   | 没打中就没了                   | 0.20            | wave_fizzle(位置): 气团裂成 4 缕飘散                                  |

const FX_LOCK := "res://assets/sprites/vfx/reserve-lock.png"      # 贴地 10 帧 88²
const FX_GATHER := "res://assets/sprites/vfx/reserve-gather.png"  # 立牌 6 帧 32²
const FX_RING := "res://assets/sprites/vfx/reserve-ring.png"      # 贴地 5 帧 40²; 末帧外沿半径 RING_LAST_R 像素
const FX_TRAIL := "res://assets/sprites/vfx/reserve-trail.png"    # 立牌 6 帧 16²
const FX_FIZZLE := "res://assets/sprites/vfx/reserve-fizzle.png"  # 立牌 5 帧 16²
const FX_HIT := "res://assets/sprites/vfx/reserve-hit.png"        # 立牌 7 帧 56² × 2 行变体
## 有方向的气波弹体 reserve-wave-dir.png(非立牌、机头朝 +X、6 帧 40×20 循环)归飞行逻辑(ReserveSystem)建和转, 这里不加载它
##   (一张图只许一个文件加载, asset_borrow_audit 管着); 只按它的几何接拖尾:
const WAVE_DIR_TAIL_FRAC := 17.5 / 40.0   ## 帧中心(x=19.5)到尾焰末端(x≈2)= 帧宽的这么多 ⇒ 尾端离弹体中心 = 弹长 × 它
const WAVE_DIR_W_PX := 40.0               ## 弹体一帧宽(像素): 拖尾团按「弹长 / 它」的同一像素密度画, 和弹体一个网格

const TAG := "ReserveVfx"            ## 自己建的节点名字里都带它(门禁按它数残节点)
const TEXEL := 3.0                   ## 一个素材像素 = 3 码(与旧弹体 reserve-wave 48 码 / 16 像素同一密度)
const RING_LAST_R := 18.0            ## reserve-ring 末帧外沿半径(像素) —— 换算成 WAVE_HALF_W 码
const WAVE_H := 1.0                  ## 气团飞行高度(= battle_ballistics._skillshot_sprite 的 1.0)
const LOCK_Y := 0.04                 ## 贴地层高度(地砖顶面 y=0; 同过肩摔陷坑 / 冲击环的 0.03~0.06)
const RING_Y := 0.05
const LOCK_POP := 0.05               ## 锁定第 0 帧(弹出)停多久; 1~6 帧把剩下的名义合拢时间均分
const GATHER_DURS := [0.04, 0.035, 0.03, 0.035, 0.03, 0.03]
const RING_DURS := [0.03, 0.04, 0.05, 0.05, 0.05]
const TRAIL_DURS := [0.045, 0.045, 0.045, 0.045, 0.045, 0.045]
const FIZZLE_DURS := [0.04, 0.04, 0.04, 0.04, 0.04]
const HIT_DURS := [0.03, 0.035, 0.035, 0.04, 0.04, 0.035, 0.03]
const TRAIL_GAP := 12.0              ## 拖尾团间距(码): 附近还有一团没散完的就不再留
const TRAIL_SORT := -0.2             ## 尾迹排序往后垫: 永远画在弹体底下
const HIT_BACK := 16.0               ## 命中爆点往气波来的那一侧挪多少码(四道同时打一个人 ⇒ 四个面各一朵)
const HIT_TOWARD_CAM := 0.3          ## 再朝镜头挪这么多米
const HIT_PRIORITY := 10             ## 命中爆点不做深度测试 + 画在最上层: 被打者立绘 / 地面都挡不住它(用户要「一眼看到」)
const CAM_DIR_FALLBACK := Vector3(0.0, 0.780, 0.626)   ## 没有相机时(裁判进程)用默认机位 (0,28,22)→(0,0.6,0) 的反方向

var battle
var _puffs: Array = []               ## 还活着的尾迹团 [instance_id, 游戏坐标]
var _puff_n := 0
var _hit_n := 0
var _locks: Array = []               ## 还活着的锁定标记 instance_id(两边各有一只援军小将时可能同时两个)


func _init(b) -> void:
	battle = b


# ───────────────────────────── 对外入口 ─────────────────────────────

## 施法那一刻: 四个出发点各一次凝聚(立着) + 出现印(贴地), 目标脚下一个锁定标记(贴地, 转到「施法者 → 目标」方向)。
## `points` = ReserveSystem.spawn_points 的结果(第 0 个 = 靠施法者那侧); `center` = 目标此刻的位置。
func converge_spawn(points: Array, center: Vector2) -> void:
	if not _has_world():
		return
	for p in points:
		var pv: Vector2 = p
		_play(FX_GATHER, battle._world_pos(pv, WAVE_H), TEXEL * battle.WS, false, GATHER_DURS, "Gather")
		_play(FX_RING, battle._world_pos(pv, RING_Y), ReserveConsts.WAVE_HALF_W * battle.WS / RING_LAST_R, true, RING_DURS, "Ring")
	var f := Vector2.RIGHT
	if not points.is_empty():
		var d: Vector2 = (points[0] as Vector2) - center
		if DetMath.vlen(d) > 1.0:
			f = DetMath.norm(d)
	var lk: Sprite3D = _play(FX_LOCK, battle._world_pos(center, LOCK_Y), TEXEL * battle.WS, true, lock_durs(), "Lock", 0, lock_basis(f))
	if lk != null:
		_locks.append(lk.get_instance_id())


## (每步调)锁定标记跟着目标走 —— 气波追踪目标, 合拢点就是目标此刻的位置。挪的是离 `pos` 最近的那个(各跟各的目标)。
func lock_follow(pos: Vector2) -> void:
	if not _has_world():
		return
	var at: Vector3 = battle._world_pos(pos, LOCK_Y)
	var best: Node3D = null
	var best_d: float = INF
	for i in range(_locks.size() - 1, -1, -1):
		var o: Object = instance_from_id(int(_locks[i]))
		if o == null or not is_instance_valid(o) or (o as Node).is_queued_for_deletion():
			_locks.remove_at(i)
			continue
		var d: float = ((o as Node3D).position - at).length()
		if d < best_d:
			best_d = d
			best = o as Node3D
	if best != null:
		best.position = at


## (每步调)一道气波此刻在 `pos`、朝 `dir` 飞(弹体在场上长 `wave_len` 码): 在它尾焰末端留一团尾迹。附近 TRAIL_GAP 码内还有一团没散完的就不留
##   (飞着 ⇒ 间距均匀; 停着(顿帧 / 卡住)⇒ 一团散完才补一团, 不叠成一摞)。不认是哪道波: 四道离得远互不干扰。
func wave_trail(pos: Vector2, dir: Vector2, wave_len: float = 72.0) -> void:
	if not _has_world():
		return
	var at2: Vector2 = pos - dir * (wave_len * WAVE_DIR_TAIL_FRAC)
	for i in range(_puffs.size() - 1, -1, -1):
		var rec: Array = _puffs[i]
		var o: Object = instance_from_id(int(rec[0]))
		if o == null or not is_instance_valid(o) or (o as Node).is_queued_for_deletion():
			_puffs.remove_at(i)
			continue
		if DetMath.vlen((rec[1] as Vector2) - at2) < TRAIL_GAP:
			return
	_puff_n += 1
	var sp: Sprite3D = _play(FX_TRAIL, battle._world_pos(at2, WAVE_H), wave_len / WAVE_DIR_W_PX * battle.WS, false, TRAIL_DURS, "Trail", 0, null,
		TRAIL_SORT, _puff_n % 2 == 0)
	if sp != null:
		_puffs.append([sp.get_instance_id(), at2])


## 一道气波打中了站在 `pos` 的敌人: 命中爆点。`dir` = 气波飞行方向(给了就把爆点挪到被打者「气波来的那一侧」)。
func wave_hit(pos: Vector2, dir: Vector2 = Vector2.ZERO) -> void:
	if not _has_world():
		return
	var at2: Vector2 = pos
	if DetMath.vlen(dir) > 0.5:
		at2 = pos - DetMath.norm(dir) * HIT_BACK
	var at: Vector3 = battle._world_pos(at2, WAVE_H) + _toward_cam() * HIT_TOWARD_CAM
	_hit_n += 1
	## 两行变体 × 左右翻 = 4 种样子轮流(四道同时打一个人时叠出来不是同一张)
	var sp: Sprite3D = _play(FX_HIT, at, TEXEL * battle.WS, false, HIT_DURS, "Hit", _hit_n % 2, null, 0.3, ((_hit_n >> 1) & 1) == 1,
		HIT_PRIORITY)
	if sp != null:
		battle._shake(battle.JUICE_SHAKE_HEAVY * 0.6)


## (可选)一道气波没打中就消失了(飞满 / 目标没了): 在它最后的位置散掉。
func wave_fizzle(pos: Vector2) -> void:
	if not _has_world():
		return
	_play(FX_FIZZLE, battle._world_pos(pos, WAVE_H), TEXEL * battle.WS, false, FIZZLE_DURS, "Fizzle", 0, null, TRAIL_SORT)


# ───────────────────────────── 时间表 / 朝向(门禁也读) ─────────────────────────────

## 锁定 10 帧的时长: 帧 0 弹出 LOCK_POP; 帧 1~6 均分到名义合拢时刻(= 出发半径 / 速度) —— 箭头收拢与气波合拢同一刻;
##   帧 7 括号收紧, 帧 8~9 散掉。常量改了它自己跟着变。
static func lock_durs() -> Array:
	var arrive: float = ReserveConsts.WAVE_RADIUS / ReserveConsts.WAVE_SPEED
	var step: float = maxf(0.02, (arrive - LOCK_POP) / 6.0)
	return [LOCK_POP, step, step, step, step, step, step, 0.05, 0.05, 0.04]


## 贴地锁定的朝向: 本地 X → f(施法者那侧), 本地 Z → 垂直方向; 本地 Y 仍朝上(AXIS_Y 躺平不变)。不用三角函数。
static func lock_basis(f: Vector2) -> Basis:
	return Basis(Vector3(f.x, 0.0, f.y), Vector3.UP, Vector3(-f.y, 0.0, f.x))


# ───────────────────────────── 内部 ─────────────────────────────

func _has_world() -> bool:
	return battle != null and is_instance_valid(battle) and battle._world != null and is_instance_valid(battle._world)


## 一段逐帧动画: `durs` = 每帧停多久(秒, 长度 = 一行的帧数), 播完自删。`row` = 第几行变体。
## `flat` = 躺平贴地(AXIS_Y, 可带朝向 `rot`); 否则正对镜头。`prio` > 0 ⇒ 不做深度测试、按它排在最上层。
## 走 sim 步(_reg_tween), 时停 / 回放都跟着 sim 走。
func _play(path: String, at: Vector3, ps: float, flat: bool, durs: Array, nm: String, row: int = 0, rot = null,
		sort_off: float = 0.0, flip: bool = false, prio: int = 0) -> Sprite3D:
	if not _has_world() or not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var n: int = durs.size()
	var cell: float = float(tex.get_width()) / float(n)
	var rows: int = maxi(1, int(round(float(tex.get_height()) / maxf(1.0, cell))))
	var base: int = clampi(row, 0, rows - 1) * n
	var sp := Sprite3D.new()
	## ★名字带上自己的 instance_id 保证不重名: 同名兄弟节点会被引擎改成「@Sprite3D@N」, 标记就丢了(门禁数不到)
	sp.name = "%s%s_%d" % [TAG, nm, sp.get_instance_id()]
	sp.texture = tex
	sp.hframes = n
	sp.vframes = rows
	sp.frame = base
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false
	sp.transparent = true
	sp.pixel_size = ps
	sp.sorting_offset = sort_off
	sp.flip_h = flip
	if prio > 0:
		sp.no_depth_test = true
		sp.render_priority = prio
	if flat:
		sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sp.axis = Vector3.AXIS_Y      # ★AXIS_Y 本身就是躺平, 不再转 -90°(memory fb-axis-y-plus-rotation-cancels)
		if rot is Basis:
			sp.basis = rot
	else:
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.position = at
	battle._world.add_child(sp)
	var tw = battle._reg_tween()
	tw.bind_node(sp)
	for k in range(n):
		var fk: int = base + k
		tw.tween_callback(func() -> void: sp.frame = fk)
		tw.tween_interval(float(durs[k]))
	tw.tween_callback(sp.queue_free)
	return sp


func _toward_cam() -> Vector3:
	var cam = battle.get("_cam")
	if is_instance_valid(cam) and cam is Camera3D:
		return (cam as Camera3D).transform.basis.z.normalized()
	return CAM_DIR_FALLBACK
