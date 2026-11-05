extends Node

## Audio — 全局音频 (Autoload 单例)
##
## 用法:
##   Audio.play_sfx("hit-physical")
##   Audio.play_sfx_for_cls("crit-dmg")     # 按 VisualConstants cls 自动选音
##   Audio.play_bgm("battle")
##   Audio.stop_bgm()
##
## SFX 来源: PoC public/sfx/*.wav (直接拷过来)
## BGM 来源: PoC public/audio/*.mp3

## ★2026-11-05 音效全部重做(用户「旧的那个普攻、伤害音效、盾音效，全部都要重做…原来的音效要删掉」):
##   旧的 PoC 七条(hit-physical / hit-crit / heal / shield-gain / shield-break / defeat / rebirth)与 11-04 的 ev/ 一起删了,
##   全部改由事件表 SfxEvents(tools/assetgen/build_sfx_v2.py 生成)提供。
## 旧名 → 新名(只为放旧录像: 逐帧直播 / 回放里录的是当时的事件名)。新代码一律用新名。
const ALIASES := {
	"hit-physical": "g_hit", "hit-crit": "g_crit", "heal": "g_heal", "shield-gain": "g_shield_gain",
	"shield-break": "g_shield_break", "rebirth": "g_rebirth", "unit_death": "g_death",
}

const BGM_PATHS: Dictionary = {
	"menu":    "res://assets/audio/bgm/bgm-menu.mp3",
	"battle":  "res://assets/audio/bgm/bgm-battle.mp3",
	"boss":    "res://assets/audio/bgm/bgm-boss.mp3",
}

# 默认音量 (linear, 0-1)
var sfx_volume: float = 0.8
var bgm_volume: float = 0.45
## 上一局复算期间(快进, 遮罩盖着)不出音效: 一帧几百步, 每一击都生一个播放器会堆成几百个。
## 写的人: `AbandonedMatch.build_cover` / 撤遮罩时还原。不进存档(与 sfx_volume 那个玩家设置无关)。
var mute_sfx := false
## 开场标(scripts/scenes/studio_intro.gd)播着时压住背景音乐: play_bgm 照常换曲、起播, 但停在静音, 不淡入;
##   开场结束调 release_bgm_hold() 再淡入。默认 false ⇒ 别的路径一字不变。
var bgm_hold := false
var _held_target_db: float = -80.0

# SFX 播放器池 (一次性 spawn, 自动 free)
var _sfx_cache: Dictionary = {}   # name → AudioStream(有变体的 = 第一个变体)
## 变体(云顶普攻 / 命中 3~4 个随机轮换): name → [AudioStream, ...]; 上一次播的序号, 下一次不连续重复
var _var_cache: Dictionary = {}
var _var_last: Dictionary = {}
var recent: Array[String] = []    # 最近真播出去的音效名(play_sfx 里记)

# BGM 单例
var _bgm_player: AudioStreamPlayer = null
var _current_bgm: String = ""
## 当前 BGM 的场景基准音量(menu 0.4 / battle·boss 0.35 / 默认 0.45)。
## apply_bgm_volume 必须用它, 否则拖滑条会把音量跳到另一条公式上(2026-07-19 修)。
var _current_base_vol: float = 0.45


## 开发用总闸: `QUIET=1` ⇒ 整个引擎一声不出。
##
## ★由来(2026-10-01): 用户在用电脑时要求「一定要静音」。我先答了"headless 没窗口",
##   被指出那答的不是他问的那一维; 改成到处加 `--audio-driver Dummy` 之后他说**还是有声音**,
##   最后挑明「你一开窗口，就有声音」。
## ★★为什么不靠 `--audio-driver Dummy`: 我**拿不出它生效的证据** ——
##   `--verbose` 里引擎根本不打印选中了哪个音频驱动, 于是"我加了 Dummy"只是个说法。
##   把静音做在**引擎内部的主总线**上就不一样了: 它与音频驱动无关, 而且
##   `AudioServer.is_bus_mute(0)` 能被门禁直接量(见 verify_quiet_mute)。
##   ⇒ 规矩: **凡是我自己起的 Godot(含开窗口的), 一律 QUIET=1。**
func _apply_quiet_gate() -> void:
	if not OS.has_environment("QUIET"):
		return
	if str(OS.get_environment("QUIET")).strip_edges() in ["", "0", "false"]:
		return
	AudioServer.set_bus_mute(0, true)                 # 主总线静音(盖住一切, 含 BGM 与 SFX)
	AudioServer.set_bus_volume_db(0, -80.0)           # 双保险: 就算有人把 mute 改回去也听不见
	sfx_volume = 0.0
	bgm_volume = 0.0
	print("[Audio] QUIET=1 ⇒ 主总线已静音(mute=%s, %.0f dB)" % [
		str(AudioServer.is_bus_mute(0)), AudioServer.get_bus_volume_db(0)])


func _ready() -> void:
	_apply_quiet_gate()
	## 音效事件表(SfxEvents, tools/assetgen/build_sfx_v2.py 生成): 普攻出手 / 命中 / 暴击 / 技能放出 / 技能命中 / 装备 / 公共 / 界面。
	##   定选依据(对云顶 / LoL 原声的量化): tools/sfx_pick_v2.py → .out/sfx_v2/pick_report.md。
	for ev in SfxEvents.EVENTS:
		var streams: Array = []
		for ep in SfxEvents.VARIANTS.get(ev, [SfxEvents.EVENTS[ev]]):
			if ResourceLoader.exists(str(ep)):
				streams.append(load(str(ep)))
		if streams.is_empty():
			continue
		_sfx_cache[ev] = streams[0]
		if streams.size() > 1:
			_var_cache[ev] = streams
	_ensure_master_limiter()
	_apply_master_trim()

	# BGM player 常驻
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	add_child(_bgm_player)


## ★2026-11-04 主总线限幅器(兜底): 多路音效 + 背景乐叠加时总输出不许削波 ——
##   实机录 2 分钟量出整段 −6.4 LUFS、1200 个 0.1 秒块里 981 个贴顶。主因已在源头修(命中锚点对齐黑箱 −16.4、全场命中同时最多 2 路),
##   这一层只管「万一还叠到顶」: 天花板 −1 dB。门禁 verify_sfx_events ⑦ 量它在不在。
const MASTER_CEILING_DB := -1.0


func _ensure_master_limiter() -> void:
	for i in range(AudioServer.get_bus_effect_count(0)):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = MASTER_CEILING_DB
	AudioServer.add_bus_effect(0, lim, 0)


## ★2026-11-04 总音量 −7 dB(主总线): 黑箱 Demo 实玩 4 分钟(用户亲自玩, Game Bar 录游戏自己的声音)整局 −25.6 LUFS,
##   我们实机 2 分钟 −11.3 LUFS, 响约 14 dB。单条声音已对齐黑箱(build_sfx.ANCHOR), 差在自走棋十几个单位一直在打的密度 + 背景乐。
##   目标定在手机游戏常见的 −18 左右, 不压到黑箱(PC)的 −25.6: 手机外放偏小, 压太低玩家要把音量开很大。
##   各声音之间的比例不变, 只整体往下。QUIET 静音时不动(静音优先)。门禁 verify_sfx_events ⑨。
const MASTER_TRIM_DB := -7.0


func _apply_master_trim() -> void:
	if AudioServer.is_bus_mute(0):
		return
	AudioServer.set_bus_volume_db(0, MASTER_TRIM_DB)


## 把 bgm_volume 即时应用到正在播放的 BGM player (滑条拖动时实时听感, 无淡入).
##
## ★必须与 play_bgm 用【同一条公式】: base_vol × (bgm_volume / 0.45)。
## 2026-07-19 第一版这里直接用了 bgm_volume, 把 base_vol 丢了 → 菜单(base 0.4)拖一下滑条
## 音量就跳到 0.45, 战斗(base 0.35)更明显(+29%), 而且数值没变也会跳。
func apply_bgm_volume() -> void:
	if _bgm_player != null and _bgm_player.playing:
		var lin: float = _current_base_vol * (bgm_volume / 0.45)
		_bgm_player.volume_db = linear_to_db(maxf(0.0001, lin))


# ─── SFX ──────────────────────────────────────────────────────

## play_sfx 加 pitch_scale + 默认 ±5% pitch 随机抖
##   破单调利器: 同一个音 5% 随机 pitch + 5% 随机 volume → 听感天差地别
func play_sfx(name: String, volume_scale: float = 1.0, pitch_base: float = 1.0,
		pitch_jitter: float = 0.05, vol_jitter: float = 0.05) -> void:
	if StreamRecorder.cur != null: StreamRecorder.cur.ev("sfx", [name, volume_scale, pitch_base])   # 逐帧直播事件层(S1): 裁判机静音也照录
	if not _sfx_cache.has(name):
		name = legacy_name(name)           # 旧录像里的旧事件名
	var stream: AudioStream = _pick_variant(name)
	if stream == null or mute_sfx:
		return
	## 最近真播出去的音效名(只记名字, 最多 32 条): 门禁 verify_sfx_events 量「这一下播的是哪条」, 不靠猜。
	recent.append(name)
	if recent.size() > 32:
		recent.pop_front()
	# 每次 spawn 一个临时 player, finished 后自动 free (避免重叠时 cut off 旧的)
	var p := AudioStreamPlayer.new()
	p.stream = stream
	var vol_mult: float = volume_scale * (1.0 + randf_range(-vol_jitter, vol_jitter))
	p.volume_db = linear_to_db(sfx_volume * maxf(0.01, vol_mult))
	p.pitch_scale = pitch_base * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## 这个名字有没有载入的音效(按来源出声的地方先问一句, 没有就走通用音)。
func has_sfx(name: String) -> bool:
	return _sfx_cache.has(name)


## 旧事件名 → 新事件名(旧录像): 七条固定的走 ALIASES; atk_<龟> → bah_<龟>; cast_<技能类型> → sk_<技能类型>。认不出原样返回。
func legacy_name(name: String) -> String:
	if ALIASES.has(name):
		return str(ALIASES[name])
	if name.begins_with("atk_"):
		return "bah_" + name.substr(4)
	if name.begins_with("cast_") and _sfx_cache.has("sk_" + name.substr(5)):
		return "sk_" + name.substr(5)
	return name


## 有变体的随机挑一个, 不连续重复同一个(只用全局 randf, 不碰战斗随机流)。
func _pick_variant(name: String) -> AudioStream:
	if not _var_cache.has(name):
		return _sfx_cache.get(name)
	var arr: Array = _var_cache[name]
	var i: int = randi() % arr.size()
	if i == int(_var_last.get(name, -1)):
		i = (i + 1) % arr.size()
	_var_last[name] = i
	return arr[i]


## 按 VisualConstants cls (飘字类) 自动选 SFX, 跟 Phaser visual_dispatcher.ts:215-242 同步
## 用户报 "Phaser 都用同一个受击太单一" → 这里靠 pitch_base 按伤害类型分音色:
##   物理       pitch=1.0  (基础)
##   魔法       pitch=1.18 (更高更"zap")
##   真伤       pitch=0.85 (更低更"boom")
##   穿透/破盾  pitch=1.3  (短脆"叮")
##   DoT       pitch ≈ dmg_type 对应 (灼烧/中毒按魔法、流血按物理、诅咒按真伤)
##   暴击       走 hit-crit 强音
func play_sfx_for_cls(cls: String) -> void:
	## 11-05 全部换成 v2 公共声(g_*); 不再靠变调把一条声音假装成几种
	if cls.begins_with("crit"):
		play_sfx("g_crit", 1.0, 1.0, 0.03)
	elif cls in ["direct-dmg", "phys-dmg", "dot-bleed", "magic-dmg", "dot-dmg", "dot-poison", "true-dmg", "dot-curse", "pierce-dmg"]:
		play_sfx("g_hit", 0.85, 1.0, 0.05)
	elif cls in ["heal-num", "heal"]:
		play_sfx("g_heal", 1.0, 1.0, 0.04)
	elif cls in ["shield-num", "shield-gain"]:
		play_sfx("g_shield_gain", 0.9, 1.0, 0.05)
	elif cls == "shield-dmg":
		play_sfx("g_shield_break", 1.0, 1.0, 0.06)
	elif cls in ["dodge-num", "miss"]:
		play_sfx("g_dodge", 0.8, 1.0, 0.04)
	# (删 death-explode→defeat 分支: 无人spawn该cls=死代码, 且PoC fireSfxForCls无此case=自创; 防日后接死爆float误响死亡音)


# ─── BGM ──────────────────────────────────────────────────────

## base_vol = 该场景 BGM 的基准音量 (1:1 PoC: menu 0.4 / battle·boss 0.35); 0.45=旧统一基准。
##   实际音量 = base_vol × (用户设置 bgm_volume / 0.45) → 用户没动设置时就是 PoC 基准, 动了按比例缩。
func play_bgm(name: String, fade_in_s: float = 1.0, base_vol: float = 0.45) -> void:
	if _current_bgm == name and _bgm_player.playing:
		return
	var path: String = BGM_PATHS.get(name, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true

	_current_bgm = name
	_current_base_vol = base_vol      # 记下本曲基准, 供 apply_bgm_volume 用同一条公式(见该函数注释)
	_bgm_player.stream = stream
	_bgm_player.volume_db = -80.0    # 起点静音
	_bgm_player.play()
	# 淡入 (1:1 PoC battle BGM volume 0→target, Sine.easeIn)
	var target_lin: float = base_vol * (bgm_volume / 0.45)
	var target_db: float = linear_to_db(maxf(0.0001, target_lin))
	if bgm_hold:
		_held_target_db = target_db
		return
	var tween := create_tween()
	tween.tween_property(_bgm_player, "volume_db", target_db, fade_in_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## 开场标结束: 放开压着的背景音乐, 按 play_bgm 当时要的目标音量淡入。没压着 ⇒ 什么都不做。
func release_bgm_hold(fade_in_s: float = 0.6) -> void:
	if not bgm_hold:
		return
	bgm_hold = false
	if _bgm_player != null and _bgm_player.playing and _current_bgm != "":
		var tween := create_tween()
		tween.tween_property(_bgm_player, "volume_db", _held_target_db, fade_in_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func stop_bgm(fade_out_s: float = 0.5) -> void:
	if not _bgm_player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_bgm_player, "volume_db", -80.0, fade_out_s)
	tween.tween_callback(_bgm_player.stop)
	_current_bgm = ""
