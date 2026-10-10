class_name AbandonedMatch
extends RefCounted
## 中途退出的对局自动结算(杀进程 / 闪退 / 断电)。方案书 docs/plans/20261010-中途退出自动结算.md。
## 用户 2026-10-10「学习他们的做法」: 皇室战争 / 云顶 / 炉石 —— 退出不作废、也不直接判负, 按正常规则把这一局打完。
##
## ══════════════════════════════════════════════════════════════════════
##  做法
## ══════════════════════════════════════════════════════════════════════
##   ① 开局(`ReplayRecorder.start` 录制分支): 计分对局落一份「待结算单」 —— 录像(种子 / 状态 / 已发生的输入) + 开局那一刻的赛程身份。
##      每来一条输入(开打 / 点幕布 / 认输, 一局就几条)覆盖写一次。
##   ② 结算: `record_match` 把录像 id 挂到战绩行并 `save()` —— **这就是「已结算」标记**(与结算同一次落盘)。之后删单。
##   ③ 下次打开主菜单(登录墙之前): 有单且没结算 ⇒ 进战斗场, `ReplayRecorder` 以 "resume" 模式把这一局**在本机打完**:
##      前缀输入按步号重放; 之后没有人的输入 —— 幕布照 5 秒自己走, 摆位屏立刻按当前站位开打。
##      结束时走 `_settle_season` 原路(没有第二份结算公式), 露出正常结算屏。
##
## ★只结一次: 判「已结算」只看存档里的战绩行(`is_settled`)。结算时录像存不下来(拿不到 id) ⇒ 当场删单(宁可漏, 不可双)。
## ★不落单: 教学 / 调试场 / 表演赛 / 回放 / 存档不落盘的进程(`test_mode`) —— 见 `wanted()`。

const Phase2Cfg := preload("res://scripts/gamedata/phase2_config.gd")
const PATH := "user://pending_match.bin"
const FORMAT := 1
const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
## 复算本身没结算完(闪退)几次之后改判负; 判负那一次也没结算完就作废 —— 防「这份单子必崩 ⇒ 每次开机都崩」。
const MAX_RESIM_TRIES := 2

const TXT_RUNNING := "上一局结算中"
const TXT_DONE := "上一局已结算"
const TXT_LOSS_VERSION := "上一局判负 · 版本已更新"
const TXT_LOSS_CRASH := "上一局判负 · 结算异常"
const TXT_VOID_WEEK := "上一局已作废 · 已换周"
const TXT_VOID_CRASH := "上一局已作废 · 结算异常"

## 主菜单 → 战斗场: 待复算的那一份(`ReplayRecorder.start` 取走)。{"rec", "loss", "text"}
static var pending_resume: Dictionary = {}
## 主菜单要飘的一行(作废时)。读走即清。
static var notice := ""
## 最近一次判定(门禁的观测量)。
static var last_act := ""


# ─────────────────────────────── 落单 ───────────────────────────────

## 这一局要不要落待结算单。条件 = 录像判据 ∧ 战斗场「计分对局」判据 ∧ 不是表演赛 ∧ 存档会落盘。
static func wanted(battle) -> bool:
	if GameState == null or bool(GameState.test_mode):
		return false                      # 存档不落盘(无头 / NO_SAVE / 命令行场景 / 回放): 结了也存不下来
	if not ReplayRecorder.should_record():
		return false                      # 教学 / 非双路 / 周日不是决赛场
	if battle != null and battle.get("_world_builder") != null and not battle._world_builder._is_scored_match():
		return false                      # 调试场 / 特效台 / 地图编辑器 / 没有阵容
	return not Phase2Cfg.is_exhibition(GameState.is_eliminated(), ReplayRecorder.current_settle_kind())


## 开局那一刻的赛程身份(`week_phase` / `finals_match` 等不全在存档里, 复算前要原样摆回去)。
static func capture_meta() -> Dictionary:
	return {
		"week": int(GameState.week_anchor_ts),
		"phase": str(GameState.week_phase),
		"finals_match": (GameState.finals_match as Dictionary).duplicate(true),
		"dual_opponent": (GameState.dual_opponent as Dictionary).duplicate(true),
		"left_team": Array(GameState.left_team),
		"left_slots": Array(GameState.left_slots),
		"tries": 0,
	}


## 覆盖写待结算单(先写 .tmp 再改名; 改名之间被杀 ⇒ 读的时候回落 .tmp)。校验点不进单子(复算会重算)。
static func write(rec: Dictionary, meta: Dictionary) -> bool:
	var r := rec.duplicate(false)
	r["cps"] = []
	r.erase("end")
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("[Abandoned] 写不了 " + tmp)
		return false
	f.store_buffer(ReplayRecorder.encode({"v": FORMAT, "rec": r, "meta": meta}))
	f.close()
	var da := DirAccess.open("user://")
	if da == null:
		return false
	if FileAccess.file_exists(PATH):
		da.remove(PATH.get_file())
	return da.rename(tmp.get_file(), PATH.get_file()) == OK


static func read() -> Dictionary:
	for p in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			var d: Dictionary = ReplayRecorder.decode(FileAccess.get_file_as_bytes(p))
			if d.get("rec", null) is Dictionary and d.get("meta", null) is Dictionary:
				return d
	return {}


static func exists() -> bool:
	return FileAccess.file_exists(PATH) or FileAccess.file_exists(PATH + ".tmp")


static func clear() -> void:
	var da := DirAccess.open("user://")
	if da == null:
		return
	for p in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			da.remove(p.get_file())


## 这一局结算过了吗: 战绩行上挂着它的录像 id(`record_match` 写、随结算那次 `save()` 落盘)。
static func is_settled(id: String) -> bool:
	if id == "" or GameState == null:
		return false
	for row in GameState.match_history:
		if row is Dictionary and str((row as Dictionary).get("replay_id", "")) == id:
			return true
	return false


## 结算(`ReplayRecorder.on_settle`)之后删单。★deferred: 此刻 `record_match` 还没跑, 战绩行上还没有 id ——
##   等 `_settle_season` 整段跑完(同一帧末尾)再看「已结算」标记, 标记在才删。
static func clear_after_settle(id: String) -> void:
	(func() -> void: _clear_if_settled(id)).call_deferred()


static func _clear_if_settled(id: String) -> void:
	var p := read()
	if p.is_empty():
		return
	if str((p["rec"] as Dictionary).get("id", "")) == id and is_settled(id):
		clear()


# ─────────────────────────────── 判定 ───────────────────────────────

## 这一份单子该怎么办(纯函数: 喂单子 + 现在的周锚点 + 本机版本)。
##   none / settled / void_week / void_crash / loss_version / loss_crash / resume
static func decide(p: Dictionary, week_now: int, version: String) -> String:
	if p.is_empty():
		return "none"
	var rec: Dictionary = p["rec"]
	var meta: Dictionary = p["meta"]
	if is_settled(str(rec.get("id", ""))):
		return "settled"
	if int(meta.get("week", -1)) != week_now:
		return "void_week"
	var tries := int(meta.get("tries", 0))
	if tries > MAX_RESIM_TRIES:
		return "void_crash"
	if str(rec.get("client_version", "")) != version or int(rec.get("v", 0)) != ReplayRecorder.FORMAT_V:
		return "loss_version"
	if tries == MAX_RESIM_TRIES:
		return "loss_crash"
	return "resume"


## 主菜单调: 读单 → 判定 → 不用打的当场收掉; 要打的把状态摆好、挂上待复算。返回判定。
static func prepare() -> String:
	var p := read()
	if p.is_empty() and exists():
		clear()                               # 坏单
	var act := decide(p, int(GameState.week_anchor_ts), ReplayRecorder.client_version())
	last_act = act
	match act:
		"settled":
			clear()
		"void_week":
			clear()
			notice = TXT_VOID_WEEK
		"void_crash":
			clear()
			notice = TXT_VOID_CRASH
		"resume", "loss_version", "loss_crash":
			var meta: Dictionary = p["meta"]
			meta["tries"] = int(meta.get("tries", 0)) + 1          # ★先记一次再进场: 复算途中闪退也算一次
			write(p["rec"], meta)
			_apply(p)
			var loss: bool = act != "resume"
			pending_resume = {"rec": (p["rec"] as Dictionary).duplicate(true), "loss": loss,
				"text": TXT_DONE if not loss else (TXT_LOSS_VERSION if act == "loss_version" else TXT_LOSS_CRASH)}
	return act


## 主菜单入口(登录墙之前)。返回 true = 已切去战斗场复算(主菜单不用再往下建)。
static func resume_if_any(tree: SceneTree) -> bool:
	if GameState == null:
		return false
	var act := prepare()
	if pending_resume.is_empty() or tree == null:
		return false
	print("[Abandoned] 上一局未结算(%s) ⇒ 复算" % act)
	tree.change_scene_to_file(BATTLE_SCENE)
	return true


## 把开局那一刻的状态摆回 GameState(录像 state + 赛程身份)。★持久装备是**合并**: 录像只带上场统领那几把。
static func _apply(p: Dictionary) -> void:
	var st: Dictionary = (p["rec"] as Dictionary).get("state", {})
	for n in st:
		var k := str(n)
		if not k in ReplayRecorder.STATE_KEYS:
			continue
		var v = st[n]
		if k == "persistent_equipped" and v is Dictionary and GameState.persistent_equipped is Dictionary:
			var pe: Dictionary = (GameState.persistent_equipped as Dictionary).duplicate(true)
			for pid in v:
				pe[pid] = _dup(v[pid])
			GameState.persistent_equipped = pe
			continue
		GameState.set(k, _dup(v))
	var meta: Dictionary = p["meta"]
	GameState.week_phase = str(meta.get("phase", ""))
	GameState.finals_match = _dup(meta.get("finals_match", {}))
	GameState.dual_opponent = _dup(meta.get("dual_opponent", {}))
	GameState.left_team.assign(meta.get("left_team", []))
	GameState.left_slots.assign(meta.get("left_slots", []))
	GameState.tutorial = false


static func _dup(v):
	return v.duplicate(true) if (v is Array or v is Dictionary) else v


# ─────────────────────────────── 复算期间的画面 ───────────────────────────────

static var _sfx_was_muted := false


## 盖住战场(复算是快进, 不给人看)、停掉 3D 渲染、音效静音。返回遮罩节点。
static func build_cover(battle: Node) -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.name = "AbandonedCover"
	cl.layer = 120
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.1, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(bg)
	var lab := Label.new()
	lab.text = TXT_RUNNING
	lab.add_theme_font_size_override("font_size", 30)
	lab.add_theme_color_override("font_color", Color("#ffd93d"))
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(lab)
	battle.add_child(cl)
	var sub = battle.get("_sub")
	if sub is SubViewport and is_instance_valid(sub):
		(sub as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	var au := battle.get_node_or_null("/root/Audio")
	if au != null and au.get("mute_sfx") != null:
		_sfx_was_muted = bool(au.mute_sfx)
		au.mute_sfx = true
	cl.tree_exiting.connect(_restore.bind(battle))
	return cl


## 复算结束、结算屏已出: 撤遮罩, 顶上留一行说明这是上一局。
static func reveal(battle: Node, cover: Node, text: String) -> void:
	if cover != null and is_instance_valid(cover):
		cover.queue_free()
	var cl := CanvasLayer.new()
	cl.name = "AbandonedHeader"
	cl.layer = 121
	var lab := Label.new()
	lab.name = "AbandonedHeaderLabel"
	lab.text = text
	lab.add_theme_font_size_override("font_size", 24)
	lab.add_theme_color_override("font_color", Color("#ffd93d"))
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lab.add_theme_constant_override("outline_size", 5)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lab.offset_top = 14.0
	lab.offset_bottom = 54.0
	cl.add_child(lab)
	battle.add_child(cl)


static func _restore(battle: Node) -> void:
	if battle == null or not is_instance_valid(battle):
		return
	var sub = battle.get("_sub")
	if sub is SubViewport and is_instance_valid(sub):
		(sub as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var au := battle.get_node_or_null("/root/Audio")
	if au != null and au.get("mute_sfx") != null:
		au.mute_sfx = _sfx_was_muted
