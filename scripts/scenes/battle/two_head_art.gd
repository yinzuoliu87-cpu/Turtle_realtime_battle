class_name TwoHeadArt
extends RefCounted
## 变脸龟(id two_head)动作驱动 —— 2026-10-20(方案书 docs/plans/20261007-双头龟重绘两形态.md)。
##
## ★这是【渲染层】: 每个渲染步由 battle_render 调 `tick(u)`, 只读 sim 状态(state / state_t / pending /
##   two_form / _anim_lock_until / _slam), 只写立绘节点与 `RENDER_OWNED_KEYS` 里登记的 `_tha_*` 键。
##   sim 不读这里写的任何东西 ⇒ 结算时刻与数值一个字不动(确定性门禁 verify_determinism_* 守着)。
## ★计时全用游戏钟 `battle._t`(不用渲染 delta): 命中帧要对齐的是 sim 的结算时刻,
##   而渲染步的节奏随帧率变(memory fb-second-clock-drops-events)。
##
## ★帧表: `pets/animations/two_head/*.png`, 128×128 方帧横排。每张的第 0 帧(去掉变脸后半段)
##   【逐像素等于】游戏里的立绘贴在 (24,48) —— 所以归一不用量 bbox: 像素尺寸 = 立绘的 idle_px,
##   脚底 = 帧底(立绘 80 像素高贴在 48 行 ⇒ 底边正好是 128)。门禁 verify_two_head_anim 逐张核这条。
## ★朝向: 全部沿用立绘朝向(项目约定原图朝左), 出手 / 落锤都往左 ⇒ 由 battle_render 的 flip_h 统一翻。
##
## 关键帧(命中帧)对齐: 每条动作有一个关键帧 k 与关键时刻 tk(= sim 结算那一刻)。
##   关键帧之前的 k 帧按【真实可用时长】(从开播到 tk)均摊 —— 攻速变快前摇变短, 动作也跟着变快;
##   关键帧之后按固定帧率播完。

const DIR := "res://assets/sprites/pets/animations/two_head/"
const FRAME := 128
const ART_X := 24          # 立绘(80×80)在帧格里的位置
const ART_Y := 48

## 动作表: 名字 → [关键帧下标(-1 = 循环动作), 关键帧之后的帧率]
const CLIPS := {
	"ranged_idle": [-1, 7.0], "melee_idle": [-1, 7.0],
	"ranged_walk": [-1, 11.0], "melee_walk": [-1, 11.0],
	"ranged_attack": [5, 16.0],     # 第5帧 掌心出手闪 = 灵能弹离手
	"melee_attack": [4, 16.0],      # 第4帧 锤落到左下 = 挥锤命中
	"ranged_strike": [5, 14.0],     # 第5帧 双臂推出 = 法球离手
	"melee_strike": [6, 16.0],      # 第6帧 锤头砸地 = 锤击落地结算(前面 3~5 帧举锤过顶 = 空中)
	"ranged_disrupt": [5, 14.0],    # 第5帧 手按太阳穴瞪眼 = 精神波发出
	"melee_absorb": [4, 16.0],      # 第4帧 攥拳回扯、红色生命流出现 = 吸收结算
	"to_melee_a": [8, 20.0],        # 第8帧 紫斗篷挡满脸 = 切形态那一刻
	"to_melee_b": [0, 20.0],        # 斗篷甩开 → 战士
	"to_ranged_a": [8, 20.0],       # 第8帧 红斗篷挡满脸 = 切形态那一刻
	"to_ranged_b": [0, 20.0],       # 斗篷甩开 → 术士
	"fusion_cast": [10, 12.0],      # 0~8 掀兜帽、两张脸同时露出; 第10帧 推出 = 第一道魔法波
}
## 前摇期间播的动作(关键帧 = 前摇结束那一刻)
const WINDUP_CLIPS := ["ranged_attack", "melee_attack", "to_melee_a", "to_ranged_a", "fusion_cast"]
## 死亡走 battle_vfx._play_action 的单位自带表 `_act_rows`(死亡后渲染步不再管这只龟)
const DEATH_FPS := 22.0
## 锤击跳跃时长 —— 与 TwoHeadSystem 里锤击弧线的 tween 时长同一个常量
const WALK_SPEED := 48.0   # 码/秒, 与通用走路判据同一档(battle_render._update_run_anim)

var battle
var _tex := {}


func _init(b) -> void:
	battle = b


func tex(key: String) -> Texture2D:
	if not _tex.has(key):
		var p := DIR + key + ".png"
		_tex[key] = load(p) if ResourceLoader.exists(p) else null
	return _tex[key]


func frames_of(key: String) -> int:
	var t := tex(key)
	return maxi(1, int(t.get_width()) / FRAME) if t != null else 1


## 出生 / 换形态时(sim 侧调): 死亡表按形态装进单位自带表, 动作帧与立绘同一个像素尺寸。
func attach(u: Dictionary) -> void:
	var form := str(u.get("two_form", "ranged"))
	u["_act_rows"] = {"death": ["pets/animations/two_head/%s_death.png" % form, DEATH_FPS]}
	u["_art_px"] = float(u.get("idle_px", battle.PIXEL_SIZE))
	u["_art_offy"] = FRAME * 0.5


## 渲染步每帧调。返回 false = 这一帧不归我管(交回通用的 _update_run_anim / _advance_anim)。
func tick(u: Dictionary) -> bool:
	if not u.get("alive", false) or u.get("_manual_anim", false) or u.has("_cake_o_idle_sd"):
		return false
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr) or tex("ranged_idle") == null:
		return false
	var t: float = float(battle._t)
	var form := str(u.get("two_form", "ranged"))
	_observe(u, t, form)
	# ── 正在播的一次性动作 ──
	var clip := str(u.get("_tha_clip", ""))
	if clip != "":
		var f := _clip_frame(u, clip, t)
		if f >= 0:
			_show(u, clip, f)
			return true
		var q: Array = u.get("_tha_q", [])
		u["_tha_clip"] = ""
		if not q.is_empty():
			var nx: Array = q.pop_front()
			u["_tha_q"] = q
			_play(u, str(nx[0]), float(nx[1]), float(nx[2]))
			var f2 := _clip_frame(u, str(nx[0]), t)
			if f2 >= 0:
				_show(u, str(nx[0]), f2)
				return true
			u["_tha_clip"] = ""
	# ── 循环: 走 / 站 ──
	var walk := _walking(u, t)
	var key := form + ("_walk" if walk else "_idle")
	var fps: float = float(CLIPS[key][1])
	_show(u, key, int((t - float(u.get("_tha_loop_t0", 0.0))) * fps) % frames_of(key))
	return true


## 从 sim 状态里认出"该开播哪条动作"。只读 sim 字段。
func _observe(u: Dictionary, t: float, form: String) -> void:
	# ① 前摇: 普攻 / 放技能都先进 windup, 结束那一刻就是出手(普攻) / 切形态(技能)
	var st_now := str(u.get("state", ""))
	var was_wu: bool = str(u.get("_tha_ws", "")) == "windup"
	u["_tha_ws"] = st_now
	if st_now == "windup":
		var tk: float = t + maxf(0.0, float(u.get("state_t", 0.0)))
		if not was_wu:
			var p := str(u.get("pending", ""))
			if p == "B":
				_play(u, form + "_attack", t, tk)
			elif p.begins_with("K:"):
				var st := p.substr(2)
				u["_tha_pend"] = st
				if st == "twoHeadFusion":
					_play(u, "fusion_cast", t, tk)
				else:
					_play(u, "to_melee_a" if form == "ranged" else "to_ranged_a", t, tk)
		elif str(u.get("_tha_clip", "")) in WINDUP_CLIPS:
			## 同一段前摇还在继续。★前摇被冻住(眩晕 / 钩住 / 时停)时 state_t 不走而 _t 照走 ⇒
			##   关键时刻跟着往后挪; 开播时刻挪同样多 ⇒ 画面停在当前帧, 解冻后接着播, 出手帧仍对齐。
			##   (2026-10-20 实拍抓到: 被训龟大师钩住眩晕 4 秒, 旧写法每帧重开 = 一直卡在第 0 帧。)
			var otk: float = float(u.get("_tha_tk", tk))
			if tk > otk + 0.0005:
				u["_tha_t0"] = float(u.get("_tha_t0", t)) + (tk - otk)
			u["_tha_tk"] = tk
	elif str(u.get("_tha_clip", "")) in WINDUP_CLIPS:
		# 前摇被打断(击飞等让状态离开 windup): 关键时刻还没到就离开了 ⇒ 这一下没打出去, 动作作废
		if t < float(u.get("_tha_tk", 0.0)) - 0.05:
			u["_tha_clip"] = ""
			u["_tha_q"] = []
	# ② 形态变了 = 切形态那一刻(_two_head_after_cast): 播变脸后半段, 接着排该形态的技能动作
	if form != str(u.get("_tha_form", "")):
		var first := not u.has("_tha_form")
		u["_tha_form"] = form
		if first:
			return
		var b := "to_" + form + "_b"
		var b_end: float = t + float(frames_of(b)) / float(CLIPS[b][1])
		_play(u, b, t, t)
		## 主文件在切形态后把 _anim_lock_until 设成【放技能那一刻】; 延时队列比它早 1 个 sim 步出手(实测:
		##   法球离手那一步 = lock − 1/60 秒), 所以关键时刻再往前挪一步, 出手帧才正好落在离手那一步。
		var cast_t: float = float(u.get("_anim_lock_until", t)) - battle.SIM_DT
		var st := str(u.get("_tha_pend", ""))
		var sk := ""
		if st == "twoHeadStrike":
			sk = "melee_strike" if form == "melee" else "ranged_strike"
			if form == "melee":
				cast_t += TwoHeadSystem.HAMMER_LEAP_SEC          # 锤击: 关键帧 = 落地砸下那一刻
		elif st == "twoHeadDisrupt":
			sk = "melee_absorb" if form == "melee" else "ranged_disrupt"
		u["_tha_q"] = [[sk, minf(b_end, cast_t - 0.05), cast_t]] if sk != "" else []
		u["_tha_pend"] = ""


func _play(u: Dictionary, key: String, ts: float, tk: float) -> void:
	u["_tha_clip"] = key
	u["_tha_t0"] = ts
	u["_tha_tk"] = maxf(ts, tk)


## 当前该显示第几帧; 播完返回 -1。
func _clip_frame(u: Dictionary, key: String, t: float) -> int:
	var n := frames_of(key)
	var k: int = int(CLIPS[key][0])
	var fps: float = float(CLIPS[key][1])
	var ts: float = float(u.get("_tha_t0", t))
	var tk: float = float(u.get("_tha_tk", t))
	if t < tk and k > 0:
		return clampi(int(float(k) * (t - ts) / maxf(0.001, tk - ts)), 0, k - 1)
	var f: int = k + int((t - tk) * fps)
	return f if f < n else -1


## 走路判据: 0.1 游戏秒窗口内的位移速度(与通用走路同一档阈值)。
func _walking(u: Dictionary, t: float) -> bool:
	var p: Vector2 = u["pos"]
	var lp: Vector2 = u.get("_tha_lp", p)
	var lt: float = float(u.get("_tha_lt", t))
	if t - lt >= 0.1:
		var sp: float = DetMath.vlen(p - lp) / maxf(0.001, t - lt)
		var w: bool = sp > WALK_SPEED
		if w != bool(u.get("_tha_walk", false)):
			u["_tha_loop_t0"] = t
		u["_tha_walk"] = w
		u["_tha_lp"] = p
		u["_tha_lt"] = t
	elif not u.has("_tha_lt"):
		u["_tha_lp"] = p
		u["_tha_lt"] = t
	return bool(u.get("_tha_walk", false))


## 把立绘节点切到这张表的第 f 帧。像素尺寸 = 立绘的 idle_px, 脚底 = 帧底(见文件头)。
func _show(u: Dictionary, key: String, f: int) -> void:
	var spr = u["sprite"]
	var tx := tex(key)
	if tx == null:
		return
	if spr.texture != tx:
		spr.frame = 0                      # ★先归零再改帧网格(setter 立即校验, 见 _set_anim_sheet 长注释)
		spr.texture = tx
		spr.hframes = frames_of(key)
		spr.vframes = 1
		var mat = u.get("grounded_mat", null)
		if mat != null and mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("tex", tx)
			(mat as ShaderMaterial).set_shader_parameter("vframes", 1.0)
		spr.pixel_size = float(u.get("idle_px", battle.PIXEL_SIZE))
		spr.offset = Vector2(0.0, FRAME * 0.5)
	spr.frame = clampi(f, 0, maxi(0, int(spr.hframes) * int(spr.vframes) - 1))
