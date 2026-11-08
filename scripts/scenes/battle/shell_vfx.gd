class_name ShellVfx
extends RefCounted
## 龟壳「复制」「暗影俯冲」的演出(2026-11-08 重做)。只管画面: 不改伤害 / 时机 / 范围 / 火道结算, 不碰对局随机流
##   (落点全是确定性公式), 不往单位字典写东西(例外: 闪白走全项目共用的 battle._vfx._flash; 潜影两层节点挂在
##   u["_shade_pool"] / u["_shade_wisp"], 与冰寒标记 _chill_spr 同一个原语, 由跟随通道按 shell_stealth 收)。
##
## 用户 11-08:「龟壳的复制和暗影，这些需要优…需要设计。」复制参考用户指定的「谢老师(塞拉斯) R 偷别人大招」, 暗影俯冲对标库奇 W。
## 参考逐帧: docs/studies/20261108-龟壳复制参考-塞拉斯R逐帧.md、docs/studies/20261108-龟壳暗影俯冲参考-库奇W逐帧.md;
## 方向: docs/plans/20261108-训龟大师羁绊与画面一批.md 第二批「龟壳复制 / 暗影」。原来两个技能全是程序柔光团(_make_fire_glow_tex)。
## 帧表由 tools/assetgen/build_shell_vfx.py 画(硬边像素、零半透明), 补间一律走 battle._reg_tween()(跟 sim 步), 节点补间 bind_node。
##
## 暗影俯冲(库奇的橙换成暗紫; 11-08 晚起是「匀速飞 + 沿途火道」, 下面三个入口都由 ShellSystem 在 sim 回调里**当场**调):
##   ① launch: 起飞那一刻, 起跳点身后, 黑紫烟团 2 帧 → 紫芯白亮火球 2 帧(公告板)
##   ②~④ trail_patch: 龟壳飞过路线上第 k 个等分点那一刻落一块贴地火团(起点、落点各一块, 间距 ≤ PATCH_GAP),
##        可见宽 = 火道宽(画面 = 判定), 生成 3 帧 → 循环 → 消散 4 帧, 从落下到消失 = 那一处的燃烧时长, 先落先灭
##   ⑤ hit: 撞到一名敌人那一刻, 敌人身上 1 帧最亮 + 3 帧收
##   ⑥ 落地不另放大爆炸(只留调用方现有的冲击环 + 落点那块火团)
## 复制(暗紫 + 白, 不用金):
##   ① 甩链月牙闪光 2 帧 ② 分节锁链(粗 → 细 → 只剩暗紫细线) + 原主身上紫旋涡 ③ 原主身后白色圆闪 + 脚下「已被偷」小圈
##   ④ 粗紫流从原主流回龟壳 3 帧, 末帧原主闪白 ⑤ 头顶图标底框(跟图标同步弹入 / 淡出) ⑥ 持有态碎电弧 ⑦ 每发放出那一刻龟壳闪白

const SkillIcons := preload("res://scripts/gamedata/skill_icons.gd")
## ★ShellSystem 走全局类名, 不在这里 preload: shell_system.gd 要 preload 本文件, 两边互相 preload 会成环。

const LAUNCH := "res://assets/sprites/vfx/shell-dive-launch.png"
const PATCH := "res://assets/sprites/vfx/shell-dive-patch.png"
const HIT := "res://assets/sprites/vfx/shell-dive-hit.png"
const CRESCENT := "res://assets/sprites/vfx/shell-copy-crescent.png"
const LINK := "res://assets/sprites/vfx/shell-copy-link.png"
const VORTEX := "res://assets/sprites/vfx/shell-copy-vortex.png"
const GRAB := "res://assets/sprites/vfx/shell-copy-grab.png"
const MARK := "res://assets/sprites/vfx/shell-copy-mark.png"
const DRAIN := "res://assets/sprites/vfx/shell-copy-drain.png"
const BADGE := "res://assets/sprites/vfx/shell-copy-badge.png"
const ARC := "res://assets/sprites/vfx/shell-copy-arc.png"

const FPS := 10.0                    # 帧表统一 10 帧 / 秒(参考研究按 10 fps 抽帧对拍)
## ── 暗影俯冲 ──
const PATCH_GAP := 100.0             # 沿途火团间距上限(码): 路线切成等分, 600 码 = 6 段 7 块(相邻烟晕叠一点, 连成一条火道)
const PATCH_VIS := 58.0 / 64.0       # 火团烟晕可见宽占一格的比例(帧表 64 像素一格, 烟晕外沿约 58)
const LAUNCH_YD := 96.0              # 起飞喷焰世界大小(码) ≈ 龟身
const HIT_YD := 120.0                # 命中火球 ≈ 1.5 倍龟身
## ── 复制 ──
const CH_H_SHELL := 0.8              # 锁链 / 紫流挂在龟壳身上的高度(米): 龟壳矮, 身体中段约 0.8
const CH_H_SRC := 1.0                # 挂在原主身上的高度(米): 立绘 2 米高, 取中段
const LINK_THICK := 12.0             # 锁链粗(码); 一节 10×6 像素 ⇒ 一节长 20 码, 沿线平铺不拉伸(实录 9 码粗只是一串虚点)
const DRAIN_THICK := 20.0            # 紫流粗(码); 一段 16×12 像素
const GRAB_YD := 108.0               # 抓住白闪 ≈ 1.3 倍身高
const MARK_YD := 80.0                # 「已被偷」小圈一格(32 像素)的世界宽(码)
const ARC_YD := 92.0                 # 持有态电弧一格(48 像素)的世界大小(码)
const BADGE_INNER := 22.0            # 底框定稿帧(第 3 帧)里图标那块的像素宽: 与图标世界高 COPY_ICON_H 对齐
const EMPTY_REACH := 120.0           # 原主找不到 / 已死: 朝正前方空甩多远(码)
## 闪白色(⑦ 放招 / ④ 原主被抽空)。比受击闪白(JUICE_FLASH_COLOR)略带淡紫, 门禁按它认「这一下是放招闪」。
const RELEASE_FLASH := Color(2.4, 2.3, 2.6)
const GROUND_PRIO := -1              # 贴地层(火团 / 已被偷小圈)的渲染优先级: 比立绘(0)先画 ⇒ 永远压在龟脚下
## 复制演出节拍(秒, 从施放那一刻起; 10 fps 一格 0.1 秒): ① 0~0.2 ② 0~0.3(0.2 变细 / 0.3 只剩细线) ③ 0.3 ④ 0.4~0.7
const T_THIN := 0.2
const T_GRAB := 0.3
const T_DRAIN := 0.4

var battle


func _init(b) -> void:
	battle = b


func _live() -> bool:
	return battle != null and battle._world != null and is_instance_valid(battle._world)


## 公告板帧表(先藏着, 由 _seq 到点显示)。size_yd = 一格的世界高(码)。
## prio / on_top: 排序在进树之前定好(录流器按进树那一刻的属性建镜像)。on_top = 贴在身上的那几层(旋涡 / 电弧), 不被立绘挡。
func _bb(path: String, hframes: int, size_yd: float, at: Vector2, h: float, prio: int = 0, on_top: bool = false) -> Sprite3D:
	var tex: Texture2D = load(path)
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = hframes
	s.frame = 0
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = (size_yd * battle.WS) / float(maxi(1, tex.get_height()))
	s.position = battle._world_pos(at, h)
	s.render_priority = prio
	s.no_depth_test = on_top
	s.visible = false
	battle._world.add_child(s)
	return s


## 贴地帧表: 走 battle._vfx.ground_sprite(像素风三条硬约束在那里写一次: NEAREST / AXIS_Y 躺平 / 不转)。
## ★排在立绘后面(render_priority -1 + sorting_offset -1, 同 battle_vfx 激光地印): 11-08 实录第一版火团与站在上面的龟
##   深度并列, 落地区 5 秒里落点那名敌人和龟壳整个被火团盖没(只剩隐身描边)。地上的印子不该盖住龟。
func _ground(path: String, hframes: int, size_yd: float, at: Vector2, h: float) -> Sprite3D:
	var tex: Texture2D = load(path)
	var ps: float = (size_yd * battle.WS) / float(maxi(1, tex.get_height()))
	var s: Sprite3D = battle._vfx.ground_sprite(path, hframes, 1, 0, ps, at, h)
	s.render_priority = GROUND_PRIO
	s.sorting_offset = -1.0
	s.visible = false
	battle._world.add_child(s)
	return s


## 按 sim 钟逐格切帧: delay 秒后显示 frames[0], 之后每 1/fps 秒换下一格, 最后一格停满一格再自销。
## ★不用 tween_method 连续插值: 帧号是整数, 一格一个回调, 录流器录到的就是这几格。
func _seq(s: Sprite3D, frames: Array, fps: float, delay: float = 0.0, free_at_end: bool = true) -> void:
	var tw = battle._reg_tween()
	tw.bind_node(s)
	if delay > 0.0:
		tw.tween_interval(delay)
	var dt: float = 1.0 / fps
	for i in range(frames.size()):
		if i > 0:
			tw.tween_interval(dt)
		tw.tween_callback(_show.bind(s, int(frames[i])))
	tw.tween_interval(dt)
	if free_at_end:
		tw.tween_callback(s.queue_free)


## 不等长的逐格: steps = [[帧号, 停几秒], …]。头顶底框要跟图标的弹入 / 保持 / 淡出秒数对齐时用。
func _seq_t(s: Sprite3D, steps: Array, delay: float = 0.0) -> void:
	var tw = battle._reg_tween()
	tw.bind_node(s)
	if delay > 0.0:
		tw.tween_interval(delay)
	for st in steps:
		tw.tween_callback(_show.bind(s, int(st[0])))
		tw.tween_interval(maxf(0.001, float(st[1])))
	tw.tween_callback(s.queue_free)


func _show(s, f: int) -> void:
	if is_instance_valid(s):
		s.frame = f
		s.visible = true


func _loop_frames(base: int, n: int, count: int) -> Array:
	var out: Array = []
	for i in range(maxi(1, count)):
		out.append(base + i % n)
	return out


# ═══════════════════════════════ 暗影俯冲 ═══════════════════════════════

## 一块贴地火团: 生成 3 帧 → 循环 hold 秒 → 消散 4 帧 → 自销。kind 记在节点 meta 上(门禁按它分沿途 / 落地区)。
func _patch(at: Vector2, cell_yd: float, hold: float, delay: float, kind: String, h: float) -> void:
	var s := _ground(PATCH, 11, cell_yd, at, h)
	s.set_meta("shell_fx", kind)
	var fr: Array = [0, 1, 2]
	fr.append_array(_loop_frames(3, 4, int(round(hold * FPS))))
	fr.append_array([7, 8, 9, 10])
	_seq(s, fr, FPS, delay)


## 一条路线切几等分(火团 = 等分数 + 1 块)。ShellSystem 用它决定龟壳飞到哪儿落下一块。
static func patch_count(L: float) -> int:
	return maxi(1, ceili(L / PATCH_GAP))


## 起飞那一刻: 起跳点身后 20 码起飞喷焰(库奇第 9~10 帧: 先黑烟、后火球)。
func launch(start: Vector2, dir: Vector2) -> void:
	if not _live():
		return
	var ln := _bb(LAUNCH, 4, LAUNCH_YD, start - dir * 20.0, 0.9)
	ln.set_meta("shell_fx", "launch")
	_seq(ln, [0, 1, 2, 3], FPS)


## 龟壳飞过第 k 个等分点那一刻: 一块贴地火团。width = 火道宽(烟晕可见宽对齐判定宽); life = 从落下到消失(= 那一处的燃烧时长)。
## 总寿命 = 生成 3 格 + 循环 + 消散 4 格 ⇒ 循环段 = 寿命 - 0.7 秒。高度按 k 错开一点, 叠在一起的两块不闪。
func trail_patch(at: Vector2, k: int, life: float, width: float) -> void:
	if not _live():
		return
	_patch(at, width / PATCH_VIS, maxf(0.1, life - 0.7), 0.0, "trail", 0.05 + 0.002 * float(k % 8))


## 撞到一名敌人那一刻: 敌人身上炸命中火球(库奇第 14 帧)。
func hit(o: Dictionary) -> void:
	if not _live():
		return
	var s := _bb(HIT, 4, HIT_YD, o["pos"], 1.0)
	s.set_meta("shell_fx", "hit")
	_seq(s, [0, 1, 2, 3], FPS)


# ═══════════════════════════════ 潜影(被动) ═══════════════════════════════
## 用户 11-08 晚:「除了主动的…暗影冲刺，还有被动它在暗影形态下，它应该是怎么样的呢？隐形的话，透明的还是怎么样的？这都没设计啊。」
## 原来: 进潜影只把立绘 modulate.a 补到 0.4 —— 可渲染步每帧按 _body_tint 重写 modulate, 第一帧就被盖回不透明,
##   潜影期间画面上什么都没有, 只剩进入那一下 3 缕程序柔光。
## 参考(Riot 官方技能演示, 自己这边视角; 抽帧在 .out/ref_stealth): Twitch Q = 黑烟球炸开 + 本色火舌, 之后身体变淡、脚下一团黑影跟着走;
##   伊芙琳被动 = 黑紫烟升起, 全身变成暗影剪影。都看得见 —— 是「影子」, 不是消失。我们双方都是旁观, 敌我同一个样子。
## 四层: ① 进入烟球(stealth_enter) ② 身体暗紫半透明剪影(battle_render 每帧写 shade_tint) ③ 脚下暗影池 + 身上暗火(stealth_layers,
##   跟随通道循环, shell_stealth 变假就收) ④ 破隐紫闪 + 暗烟外散(stealth_break)。
const SHADE_ENTER := "res://assets/sprites/vfx/shell-shade-enter.png"
const SHADE_BREAK := "res://assets/sprites/vfx/shell-shade-break.png"
const SHADE_POOL := "res://assets/sprites/vfx/shell-shade-pool.png"
const SHADE_WISP := "res://assets/sprites/vfx/shell-shade-wisp.png"
## ★第一版 (0.46, 0.34, 0.72, 0.5) + 120 码不透明暗影池: 实录里身体叠在暗池上整个被吞掉, 远看只剩一团漩涡, 认不出是龟壳(11-08 晚自查)。
##   ⇒ 身体调浅、透明度提到约 0.6(伊芙琳那样「认得出是谁的影子」), 暗影池缩到 80 码、再压到六成透明当软影子。
const SHADE_TINT := Color(0.6, 0.48, 0.9, 0.6)    # 潜影期间立绘颜色: 乘到原色上 = 偏暗的紫色剪影(花纹 / 符文还认得出), 透明约四成
const SHADE_BREATH := 0.06                        # 透明度慢呼吸幅度(±)
const SHADE_FPS := 12.0                           # 进入 / 破隐两段的帧率(6 帧 0.5 秒 / 5 帧 0.42 秒)
const POOL_FPS := 6.0                             # 暗影池旋臂: 4 帧一圈 0.67 秒
const WISP_FPS := 8.0                             # 身上暗火: 6 帧一圈 0.75 秒
const ENTER_YD := 130.0                           # 进入烟球一格(64 像素)世界大小(码) ≈ 1.35 倍龟身
const BREAK_YD := 140.0
const POOL_YD := 80.0                             # 脚下暗影池一格的世界宽(码) ≈ 龟壳身宽(只当脚下影子, 不盖过本体)
const POOL_ALPHA := 0.6                           # 暗影池整体透明度(帧表本身零半透明, 这里整张压淡)
const WISP_YD := 70.0                             # 身上暗火一格(64 像素高)的世界高(码) ≈ 1.7 米(第一版 110 码 2.6 米: 底下垂到地面, 像往下滴的小泡)
const POOL_H := 0.03                              # 暗影池离地高度(米): 贴地, 不跟单位高度走
const WISP_H := 1.0                               # 暗火挂在身体中段偏上(米, 跟单位高度走): 从背上往上窜


## 潜影期间立绘颜色(battle_render 每帧调; 只读游戏钟)。
static func shade_tint(t: float) -> Color:
	return Color(SHADE_TINT.r, SHADE_TINT.g, SHADE_TINT.b, SHADE_TINT.a + SHADE_BREATH * sin(t * 2.4))


## 进潜影那一刻: 黑紫烟球胀开 + 紫色弯火舌, 再散成几团往上飘(Twitch Q 第 1.25~2 秒)。
func stealth_enter(u: Dictionary) -> void:
	if not _live():
		return
	var s := _bb(SHADE_ENTER, 6, ENTER_YD, u["pos"], 0.7, 1)
	s.set_meta("shell_fx", "shade_enter")
	_seq(s, [0, 1, 2, 3, 4, 5], SHADE_FPS)


## 破隐那一刻: 亮紫一闪 + 一圈暗烟往外散。
func stealth_break(u: Dictionary) -> void:
	if not _live():
		return
	var s := _bb(SHADE_BREAK, 5, BREAK_YD, u["pos"], 0.7, 1)
	s.set_meta("shell_fx", "shade_break")
	_seq(s, [0, 1, 2, 3, 4], SHADE_FPS)


## 渲染步调(battle_render._tick_shell_shade): 潜影中还没挂 ⇒ 挂脚下暗影池 + 身上暗火, 交给跟随通道循环、贴着走;
##   shell_stealth 变假 / 单位死了由跟随通道收(while_key), 不另起计时。
func stealth_layers(u: Dictionary) -> void:
	if not _live() or not u.get("alive", false):
		return
	var pool := _ground(SHADE_POOL, 4, POOL_YD, u["pos"], POOL_H)
	pool.set_meta("shell_fx", "shade_pool")
	pool.modulate = Color(1, 1, 1, POOL_ALPHA)
	pool.visible = true
	var wisp := _bb(SHADE_WISP, 6, WISP_YD, u["pos"], WISP_H, 1)
	wisp.set_meta("shell_fx", "shade_wisp")
	wisp.visible = true
	u["_shade_pool"] = pool
	u["_shade_wisp"] = wisp
	battle._follow_vfx.append({"spr": pool, "unit": u, "h": POOL_H, "ground": true,
		"loop_fps": POOL_FPS, "loop_n": 4, "loop_t0": battle._t, "while_key": "shell_stealth", "clear_key": "_shade_pool"})
	battle._follow_vfx.append({"spr": wisp, "unit": u, "h": WISP_H,
		"loop_fps": WISP_FPS, "loop_n": 6, "loop_t0": battle._t, "while_key": "shell_stealth", "clear_key": "_shade_wisp"})


# ═══════════════════════════════ 复制 ═══════════════════════════════

## 被抄技能 stype 的原主: 施放时扫敌方 active_skills, 第一个含它的(只读)。找不到返回 null。
func source_of(u: Dictionary, stype: String):
	for o in battle._targeting._enemies_of(u):
		if (o.get("active_skills", []) as Array).has(stype):
			return o
	return null


## 施放那一刻调(与第一发同时开始, 不推迟第一发)。stypes: 这次抄到的技能(1~2 个); hold_end: 持有态电弧挂到第几秒。
func copy_begin(u: Dictionary, stypes: Array, hold_end: float) -> void:
	if not _live() or not u.get("alive", false):
		return
	var srcs: Array = []
	for st in stypes:
		var o = source_of(u, str(st))
		if o == null:
			continue
		var dup := false
		for q in srcs:
			if is_same(q, o):
				dup = true
		if not dup:
			srcs.append(o)
	var me: Vector2 = u["pos"]
	if srcs.is_empty():
		## 原主找不到: 朝正前方空甩(只有 ① ②)
		var fwd := Vector2(1.0 if bool(u.get("face_right", true)) else -1.0, 0.0)
		_crescent(me, fwd)
		_chain(me, me + fwd * EMPTY_REACH, CH_H_SHELL)
	for o in srcs:
		var sp: Vector2 = o["pos"]
		var d: Vector2 = sp - me
		_crescent(me, DetMath.norm(d) if DetMath.vlen(d) > 1.0 else Vector2.RIGHT)
		_chain(me, sp, CH_H_SRC)
		var vx := _bb(VORTEX, 2, 40.0, sp, CH_H_SRC, 5, true)
		vx.set_meta("shell_fx", "vortex")
		_seq(vx, [0, 1], FPS, T_THIN)
		var tw = battle._reg_tween()
		tw.tween_interval(T_GRAB)
		tw.tween_callback(_grab.bind(u, o, hold_end + 0.3))
	## ⑥ 持有态: 抓住那一刻起, 龟壳身上碎电弧循环到 hold_end
	var arc := _bb(ARC, 4, ARC_YD, me, CH_H_SHELL, 6, true)
	arc.set_meta("shell_fx", "arc")
	battle._follow_vfx.append({"spr": arc, "unit": u, "h": CH_H_SHELL})
	_seq(arc, _loop_frames(0, 4, int(round((hold_end - T_GRAB) * FPS))), FPS, T_GRAB)


## ① 甩链月牙: 龟壳身侧(朝原主那边), 朝左时水平翻转。
func _crescent(me: Vector2, dir: Vector2) -> void:
	var c := _bb(CRESCENT, 2, 70.0, me + dir * 26.0, CH_H_SHELL)
	c.flip_h = dir.x < 0.0
	c.set_meta("shell_fx", "crescent")
	_seq(c, [0, 1], FPS)


## ② 分节锁链: 摆法同 PullRopeVfx.shoot(沿线一节节, 由近到远亮起, 不拉伸), 链环用龟壳自己的图;
##   色阶按离龟壳远近(龟壳端暗紫 → 原主端白), 0.2 秒变细, 0.3 秒只剩一条暗紫细线, 0.4 秒收。
func _chain(me: Vector2, to: Vector2, toh: float) -> void:
	var tex: Texture2D = load(LINK)
	var ps: float = (LINK_THICK * battle.WS) / float(maxi(1, tex.get_height()))
	var link_yd: float = 10.0 * ps / battle.WS
	var links: Array = PullRopeVfx.shoot(battle, me, CH_H_SHELL, to, toh, tex, LINK_THICK, link_yd, 0.1, 0.4 - 0.12)
	for lk in links:
		lk.hframes = 12
		lk.set_meta("shell_fx", "link")
		lk.set_meta("tier", clampi(int(float(lk.get_meta("rope_f", 0.0)) * 4.0), 0, 3))
		lk.frame = int(lk.get_meta("tier"))
	var tw = battle._reg_tween()
	tw.tween_interval(T_THIN)
	tw.tween_callback(_link_state.bind(links, 1))
	tw.tween_interval(T_GRAB - T_THIN)
	tw.tween_callback(_link_state.bind(links, 2))


func _link_state(links: Array, state: int) -> void:
	for lk in links:
		if is_instance_valid(lk):
			lk.frame = state * 4 + int(lk.get_meta("tier", 0))


## ③ 抓住 + ④ 抽能量。原主这时已死就不抓(锁链照常收掉)。mark_end: 「已被偷」小圈挂到第几秒(从施放起算)。
func _grab(u: Dictionary, o: Dictionary, mark_end: float) -> void:
	if not _live() or not o.get("alive", false):
		return
	var sp: Vector2 = o["pos"]
	## 身后白色圆闪: 渲染优先级比立绘低, 原主立绘压在它前面
	var g := _bb(GRAB, 2, GRAB_YD, sp, CH_H_SRC, -1)          # 比原主立绘先画 ⇒ 压在身后
	g.set_meta("shell_fx", "grab")
	_seq(g, [0, 1], FPS)
	## 脚下「已被偷」小圈(贴地, 跟着原主走): 出现 1 格 → 挂着 → 淡 2 格
	var mk := _ground(MARK, 4, MARK_YD, sp, 0.045)
	mk.set_meta("shell_fx", "mark")
	battle._follow_vfx.append({"spr": mk, "unit": o, "h": 0.045})
	var hold_n: int = maxi(1, int(round((mark_end - T_GRAB) * FPS)) - 3)
	var mf: Array = [0]
	mf.append_array(_loop_frames(1, 1, hold_n))
	mf.append_array([2, 3])
	_seq(mk, mf, FPS)
	## ④ 抽能量: 0.1 秒后粗紫流从原主流回龟壳(3 格), 末格原主闪白
	var tw = battle._reg_tween()
	tw.tween_interval(T_DRAIN - T_GRAB)
	tw.tween_callback(_drain.bind(u, o))


func _drain(u: Dictionary, o: Dictionary) -> void:
	if not _live() or not u.get("alive", false):
		return
	var tex: Texture2D = load(DRAIN)
	var ps: float = (DRAIN_THICK * battle.WS) / float(maxi(1, tex.get_height()))
	var seg_yd: float = 16.0 * ps / battle.WS
	var segs: Array = PullRopeVfx.shoot(battle, o["pos"], CH_H_SRC, u["pos"], CH_H_SHELL, tex, DRAIN_THICK, seg_yd, 0.04, 0.3 - 0.12)
	for sg in segs:
		sg.hframes = 3
		sg.frame = 0
		sg.set_meta("shell_fx", "drain")
	var tw = battle._reg_tween()
	tw.tween_interval(1.0 / FPS)
	tw.tween_callback(_segs_frame.bind(segs, 1))
	tw.tween_interval(1.0 / FPS)
	tw.tween_callback(_segs_frame.bind(segs, 2))
	tw.tween_callback(_flash.bind(o))


func _segs_frame(segs: Array, f: int) -> void:
	for sg in segs:
		if is_instance_valid(sg):
			sg.frame = f


func _flash(o: Dictionary) -> void:
	if _live():
		battle._vfx._flash(o, RELEASE_FLASH)


## ⑦ 每发被抄技能放出那一刻: 龟壳闪白 1 帧(之后原技能特效原样播)。
func copy_release(u: Dictionary) -> void:
	_flash(u)


## ⑤ 头顶图标 + 边框(暗紫描边 + 白外发光, 中间空出来露图标)。图标本体仍由 battle._vfx.copy_steal_icon 出(弹入 / 保持 / 淡出秒数见 ShellSystem.COPY_ICON_*),
##   底框按同样的秒数逐格切: 弹入 4 格 → 定稿格保持 → 淡出 2 格。没图标的技能(小将技)两样都不画。
func copy_icon(u: Dictionary, stype: String, hold: float) -> void:
	battle._vfx.copy_steal_icon(u, stype, hold)
	if not _live() or not u.get("alive", false) or SkillIcons.path_of(stype, u) == "":
		return
	var b := _bb(BADGE, 6, ShellSystem.COPY_ICON_H * 32.0 / BADGE_INNER, u["pos"], ShellSystem.COPY_ICON_HEIGHT, -1)   # 压在图标下面
	b.set_meta("shell_fx", "badge")
	battle._follow_vfx.append({"spr": b, "unit": u, "h": ShellSystem.COPY_ICON_HEIGHT})
	var pop: float = ShellSystem.COPY_ICON_POP / 4.0
	var fade: float = ShellSystem.COPY_ICON_FADE / 2.0
	_seq_t(b, [[0, pop], [1, pop], [2, pop], [3, pop + maxf(0.05, hold)], [4, fade], [5, fade]])
