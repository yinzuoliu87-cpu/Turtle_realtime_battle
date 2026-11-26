"""holy_guard_ticks_1126.py —— 146 圣枪护盾改成「数秒内每秒给一份」+ 独立颜色的特殊护盾
用户 11-26 晚:「不应该是一次性提供啊，应该是数秒之内每秒提供这个护盾啊。哎，这个护盾是特殊护盾，又有特殊颜色呢。」
做法同圣甲圣盾(_holyShieldVal): 护盾进普通护盾池 shield, 另记一个标记 _spearShieldVal = 其中属于圣枪护盾的量;
血条按标记画金色段; 每步把标记收敛到不超过池子(ShieldSynergySystem.converge_marks, 同圣盾 / 壳盾)。
一次性; 原行尾二进制读写, 每处替换次数核对。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b, n in pairs:
        assert s.count(a) == n, (rel, a[:70], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


SP = "scripts/systems/equip/eq_spear_batch.gd"
patch(SP, [
    ("const HOLY_GUARD_PCT := [0.40, 0.60, 1.00]     # 圣枪护盾 = 最大生命值 ×(不衰减, 换路随单位重建清掉)\n",
     "const HOLY_GUARD_PCT := [0.40, 0.60, 1.00]     # 圣枪护盾合计 = 最大生命值 ×(不衰减, 换路随单位重建清掉)\n"
     "const HOLY_GUARD_SEC := 4                      # 4 秒内每秒给一份(开头那一下给第 1 份, 共 4 份; 用户 11-26「数秒之内每秒提供」)\n", 1),
    ("""		u["_own_grant_vfx"] = true   # 圣枪护盾自己画(不叠通用六棱罩)
		battle._damage._grant_shield(u, float(u.get("maxHp", 0.0)) * float(HOLY_GUARD_PCT[si]))
		battle._damage._buff(u, "def", float(HOLY_RESIST[si]), false, 99999.0)   # 到这一路结束(换路单位重建, buff 随之清)
		battle._damage._buff(u, "mr", float(HOLY_RESIST[si]), false, 99999.0)
		_fx("holy_guard", [u, int(HOLY_RESIST[si])])
""",
     """		battle._damage._buff(u, "def", float(HOLY_RESIST[si]), false, 99999.0)   # 到这一路结束(换路单位重建, buff 随之清)
		battle._damage._buff(u, "mr", float(HOLY_RESIST[si]), false, 99999.0)
		_fx("holy_guard", [u, int(HOLY_RESIST[si])])
		## 每份 = 触发那一刻的最大生命 × 合计比例 ÷ 份数(之后临时等级涨了最大生命也不改这一份)
		_set_acc(u, "holy_gper:" + ck, float(u.get("maxHp", 0.0)) * float(HOLY_GUARD_PCT[si]) / float(HOLY_GUARD_SEC))
		_set_acc(u, "holy_gn:" + ck, 0.0)
		_set_acc(u, "holy_ga:" + ck, 1.0)   # 触发这一步就给第 1 份
	var gn := int(_acc(u, "holy_gn:" + ck))
	if _acc(u, "holy_g:" + ck) > 0.0 and gn < HOLY_GUARD_SEC:
		var ga := _acc(u, "holy_ga:" + ck) + (0.0 if gn == 0 else delta)
		if ga >= 1.0:
			ga -= 1.0
			_holy_guard_part(u, _acc(u, "holy_gper:" + ck))
			_set_acc(u, "holy_gn:" + ck, float(gn + 1))
		_set_acc(u, "holy_ga:" + ck, ga)
""", 1),
    ("""## 光球候选: 友方只有统领与小将""",
     """## 圣枪护盾的一份: 进护盾池, 另记标记 _spearShieldVal(血条画金色段 / 面板单列); 不弹通用得盾罩、不跳通用「+N 盾」, 演出自己画
func _holy_guard_part(u: Dictionary, amt: float) -> void:
	if amt <= 0.0 or not u.get("alive", false):
		return
	var sb: float = float(u.get("shield", 0.0))
	u["_own_grant_vfx"] = true
	u["_own_grant_txt"] = true
	battle._damage._grant_shield(u, amt)
	var got: float = maxf(0.0, float(u.get("shield", 0.0)) - sb)
	u["_spearShieldVal"] = minf(float(u.get("_spearShieldVal", 0.0)) + got, float(u.get("shield", 0.0)))
	stat["holy_guard_part"] += 1
	_fx("holy_guard_tick", [u, int(got)])


## 光球候选: 友方只有统领与小将""", 1),
    ('"holy_guard": 0, "holy_channel": 0,', '"holy_guard": 0, "holy_guard_part": 0, "holy_channel": 0,', 1),
])

## 通用得盾飘字可由给盾方关掉(同 _own_grant_vfx)
patch("scripts/scenes/battle/battle_damage.gd", [
    ("""	if got >= 8:                             # #1 护盾飘字 "+N 盾" (浅蓝); 门槛过滤每帧微盾被动防刷屏
""", """	if got >= 8 and not bool(u.get("_own_grant_txt", false)):   # #1 护盾飘字 "+N 盾" (浅蓝); 门槛过滤每帧微盾被动防刷屏; _own_grant_txt = 给盾方自己跳字(146 圣枪护盾跳金色「+N 圣枪护盾」)
""", 1),
    ("""	u.erase("_own_grant_vfx")
""", """	u.erase("_own_grant_vfx")
	u.erase("_own_grant_txt")
""", 1),
])

## 标记收敛(同圣盾 / 壳盾)
patch("scripts/systems/equip/shield_synergy_system.gd", [
    ("""		if float((u as Dictionary).get("_hidingShellVal", 0.0)) > sh:
			u["_hidingShellVal"] = sh
""", """		if float((u as Dictionary).get("_hidingShellVal", 0.0)) > sh:
			u["_hidingShellVal"] = sh
		if float((u as Dictionary).get("_spearShieldVal", 0.0)) > sh:   # 146 圣枪护盾标记(11-26)
			u["_spearShieldVal"] = sh
""", 1),
])

## 血条: 金色段
patch("scripts/scenes/hp_bar.gd", [
    ("""var _urchin := 0.0        # 海胆护盾量""",
     """var _spear := 0.0         # 146 圣枪护盾量(shield 中属圣枪护盾的部分, 标记 _spearShieldVal) — 画金色段(11-26 用户「特殊护盾，又有特殊颜色」)
var _urchin := 0.0        # 海胆护盾量""", 1),
    ("""	_urchin = clampf(float(f.get("urchin_sh_left", 0)), 0.0, maxf(0.0, _shield - _holy - _hshell))   # 海胆盾段: 随10秒衰减自动缩
""", """	_urchin = clampf(float(f.get("urchin_sh_left", 0)), 0.0, maxf(0.0, _shield - _holy - _hshell))   # 海胆盾段: 随10秒衰减自动缩
	_spear = clampf(float(f.get("_spearShieldVal", 0)), 0.0, maxf(0.0, _shield - _holy - _hshell - _urchin))   # 圣枪护盾段
""", 1),
    ("""	cursor += _seg_special(x, cursor, w, _urchin, _URCHIN_L, _URCHIN_D)
	cursor += _seg(x, cursor, w, maxf(0.0, _shield - _holy - _hshell - _urchin), _SHIELD_L, _SHIELD_D, 0.55)
""", """	cursor += _seg_special(x, cursor, w, _urchin, _URCHIN_L, _URCHIN_D)
	cursor += _seg_special(x, cursor, w, _spear, _SPEAR_L, _SPEAR_D)
	cursor += _seg(x, cursor, w, maxf(0.0, _shield - _holy - _hshell - _urchin - _spear), _SHIELD_L, _SHIELD_D, 0.55)
""", 1),
    ("""const _HOLY_L := Color8(0xff, 0xf4, 0xc0)""",
     """const _SPEAR_L := Color8(0xff, 0xc4, 0x3a)   # 146 圣枪护盾: 浓金(和圣盾的白黄、物理盾的暖黄褐分开; 与圣枪光球 / 枪身同色)
const _SPEAR_D := Color8(0xc0, 0x80, 0x10)
const _HOLY_L := Color8(0xff, 0xf4, 0xc0)""", 1),
])

## 直播 / 录像: 标记要进流(播放端血条同样画金色段)
patch("scripts/systems/stream/stream_recorder.gd", [
    ('"_ghost_hidden", "phys_shield", "_grey_stk",', '"_ghost_hidden", "phys_shield", "_spearShieldVal", "_grey_stk",', 1),
])

## 信息面板: 单列「圣枪护盾 N」(同物理护盾那颗)
patch("scripts/scenes/battle/info_panel.gd", [
    ("""	if float(u.get("phys_shield", 0.0)) >= 1.0:
""", """	if float(u.get("_spearShieldVal", 0.0)) >= 1.0:
		chips.append([Lang.t("圣枪护盾 %d") % int(u.get("_spearShieldVal", 0.0)), "#ffc43a", sic + "shield-icon.png"])
	if float(u.get("phys_shield", 0.0)) >= 1.0:
""", 1),
])

## 演出: 枪插着到给完最后一份; 每一份地面金环再亮一次 + 金色「+N 圣枪护盾」
VF = "scripts/scenes/battle/spear_eq_vfx.gd"
patch(VF, [
    ("""	var s := _feet_strip(SV + "holy-guard-up.png", 12, at + Vector2(0.0, -4.0), HOLY_GUARD_M, HOLY_GUARD_BELOW, 13.0, false, 12.0 / 13.0)   # 插住就不动(不跟人走)
	if s != null:
		s.no_depth_test = false
		s.render_priority = -1
	_strip(SV + "holy-guard-ground.png", 12, battle._world_pos(at + Vector2(0.0, -12.0), 0.02), HOLY_GUARD_GROUND_M, 13.0, false, 12.0 / 13.0, true, null, 0.02)   # 往后 12 码: 圆心对上立绘脚底(11-26 录像量过, 不挪圆心偏在脚前)
""", """	var life: float = float(EqSpearBatch.HOLY_GUARD_SEC) - 1.0 + 3.0 / 13.0 + 0.25   # 枪插到给完最后一份再收(最后一份在第 3 秒)
	var s := _feet_strip(SV + "holy-guard-up.png", 12, at + Vector2(0.0, -4.0), HOLY_GUARD_M, HOLY_GUARD_BELOW, 13.0, false, life)   # 插住就不动(不跟人走)
	if s != null:
		s.no_depth_test = false
		s.render_priority = -1
		_holy_spears.append({"f": _mfx.back(), "t": 0.0, "life": life})
""", 1),
    ("""var _holy_back: Array = []      # {node, from(Vector2), to(单位), t}
""", """var _holy_back: Array = []      # {node, from(Vector2), to(单位), t}
var _holy_spears: Array = []    # 插着的圣枪 {f(_mfx 那一条), t, life}: 落下(帧 0~8) → 定格插着 → 最后 3 帧碎散
const HOLY_SPEAR_HOLD := 8      # holy-guard-up 第 8 帧 = 插住、还没开始碎


## 圣枪护盾的一份(4 秒内每秒一份): 地面金环在脚下再亮一次 + 金色「+N 圣枪护盾」(和血条那段同色)
func holy_guard_tick(u: Dictionary, amt: int) -> void:
	var at := Vector2(u["pos"])
	_strip(SV + "holy-guard-ground.png", 12, battle._world_pos(at + Vector2(0.0, -12.0), 0.02), HOLY_GUARD_GROUND_M, 13.0, false, 12.0 / 13.0, true, u, 0.02)   # 往后 12 码: 圆心对上立绘脚底(11-26 录像量过)
	if amt > 0:
		battle._vfx._float_text(u["pos"] + Vector2(0, -52), Lang.t("+%d 圣枪护盾") % amt, Color("#ffc43a"), false, "shield")


func _tick_holy_spears(delta: float) -> void:
	var keep: Array = []
	for h in _holy_spears:
		var f: Dictionary = h["f"]
		var n = f["node"]
		if n == null or not is_instance_valid(n):
			continue
		h["t"] = float(h["t"]) + delta
		var t: float = float(h["t"])
		var tail: float = float(h["life"]) - 3.0 / 13.0
		f["hold"] = mini(int(t * 13.0), HOLY_SPEAR_HOLD) if t < tail else mini(HOLY_SPEAR_HOLD + 1 + int((t - tail) * 13.0), 11)
		keep.append(h)
	_holy_spears = keep
""", 1),
    ("""	_tick_holy_back(delta)
""", """	_tick_holy_back(delta)
	_tick_holy_spears(delta)
""", 1),
    ("""	for b in _holy_back:
		_free(b["node"])
	_holy_back.clear()
""", """	for b in _holy_back:
		_free(b["node"])
	_holy_back.clear()
	_holy_spears.clear()
""", 1),
])

## 文案: 4 秒内每秒一份
patch("data/phase2-equipment.json", [
    ("获得自身 {C:EqSpearBatch.HOLY_GUARD_PCT%}% 最大生命值的圣枪护盾，该护盾不会衰减。",
     "在 {C:EqSpearBatch.HOLY_GUARD_SEC} 秒内每秒获得一层圣枪护盾，共计自身 {C:EqSpearBatch.HOLY_GUARD_PCT%}% 最大生命值，圣枪护盾不会衰减。", 1),
])
p = os.path.join(ROOT, "locale/en.po")
raw = open(p, "rb").read()
nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
a = 'msgid "等级 +1"\nmsgstr "Level +1"\n'
assert s.count(a) == 1
s = s.replace(a, a + '\nmsgid "+%d 圣枪护盾"\nmsgstr "+%d Holy Lance Shield"\n\nmsgid "圣枪护盾 %d"\nmsgstr "Holy Lance Shield %d"\n')
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
