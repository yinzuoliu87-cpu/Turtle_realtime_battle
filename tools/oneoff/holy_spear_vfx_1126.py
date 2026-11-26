"""holy_spear_vfx_1126.py —— 146 圣枪演出层(方案书 20261126c 附录 A 分段表; 素材 tools/assetgen/pack_holy_spear_art.py)
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


VF = "scripts/scenes/battle/spear_eq_vfx.gd"

NEW_FUNCS = '''## ── 146 圣枪(11-26 晚用户重做 · 方案书 20261126c 附录 A 分段表 · 参考 docs/studies/20261126-参考-娜美W冲击之潮.md) ──
##   ① 圣枪护盾: 一支金色长枪从头顶落下插进脚边, 地面冲击环 + 金色十字(holy-guard, 12 帧)
##   ③ 引导: 头顶细金环 + 十字星 + 刻度慢转 + 光点汇聚(holy-channel, 循环), 跟着携带者, 引导结束才收
##   ④ 光球: 白金光球 + 十字星 + 呼吸光环(holy-orb, 循环), 按飞行方向转, 按速度飞(结算在 sim, 这里只跟着画)
##   ⑤ 砸中友方: 落点金色光柱(holy-ally, 0.65 秒) + 「等级 +1」
##   ⑥ 砸中敌方: 金色十字星爆(旧圣枪自己的 spear-holy-burst) + 一颗小光点从敌人飞回携带者(对应拿到的护盾)
##   娜美 W 的办法: 同一种飞行物, 落点分两种 —— 友方是往上的光柱(增益), 敌方是往外炸的星爆(伤害)。
const HOLY_GUARD_M := 7.75      # holy-guard 帧高(米): 插住的枪(41 像素)约 2 米, 比龟高一点
const HOLY_GUARD_BELOW := 22.0  # 帧里锚点(脚底)下面还有多少像素(打包脚本打印的)
const HOLY_ALLY_M := 4.0        # holy-ally 帧高(米): 光柱约 3.5 米
const HOLY_ALLY_BELOW := 13.0
const HOLY_CH_M := 3.8          # holy-channel 帧高(米): 头顶光环离地约 2.3 米
const HOLY_CH_BELOW := 13.0
const HOLY_ORB_M := 1.3         # 光球帧宽(米)
const HOLY_BACK_SEC := 0.35     # 敌方那颗回流光点飞回携带者的时长(纯演出)
var _holy_ch := {}              # 携带者立绘实例 id → 引导光环节点
var _holy_back: Array = []      # {node, from(Vector2), to(单位), t}


func _feet_strip(path: String, nf: int, at: Vector2, h_m: float, below_px: float, fps: float, loop: bool, life: float, follow = null) -> Sprite3D:
	if not ResourceLoader.exists(path):
		return null
	var th: float = float((load(path) as Texture2D).get_height())
	var off: float = below_px * h_m / maxf(1.0, th)   # 锚点(脚底)对上地面: 帧底边往下挪锚点下面那几像素
	return _strip(path, nf, battle._world_pos(at, -off), h_m, fps, loop, life, false, follow, -off)


func holy_guard(u: Dictionary) -> void:
	_feet_strip(SV + "holy-guard.png", 12, Vector2(u["pos"]), HOLY_GUARD_M, HOLY_GUARD_BELOW, 13.0, false, 12.0 / 13.0, u)


func holy_channel(u: Dictionary, on: bool) -> void:
	var k := _uid(u)
	_free(_holy_ch.get(k, null))
	_holy_ch.erase(k)
	if on:
		var s := _feet_strip(SV + "holy-channel.png", 12, Vector2(u["pos"]), HOLY_CH_M, HOLY_CH_BELOW, 12.0, true, 600.0, u)
		if s != null:
			_holy_ch[k] = s


func _holy_orb_node(at: Vector2, dir: Vector2, len_m: float) -> Sprite3D:
	var path := SV + "holy-orb.png"
	if not _ok() or not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path)
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = 8
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = len_m / float(t.get_width() / 8)
	s.position = battle._world_pos(at, 1.0)
	battle._world.add_child(s)
	_orient_to(s, dir)
	_mfx.append({"node": s, "nf": 8, "fps": 12.0, "t": 0.0, "life": 600.0, "loop": true, "follow": null, "h": 1.0})
	return s


func holy_orb_fly(u: Dictionary, tg: Dictionary, _ally: bool):
	return _holy_orb_node(Vector2(u["pos"]), Vector2(tg["pos"]) - Vector2(u["pos"]), HOLY_ORB_M)


func holy_orb_step(node, p2: Vector2, to2: Vector2) -> void:
	javelin_step(node, p2, to2)


func holy_orb_end(node, hit: bool, tg: Dictionary, ally: bool) -> void:
	_free(node)
	if not hit or not tg.get("alive", false):
		return
	var at := Vector2(tg["pos"])
	if ally:
		_feet_strip(SV + "holy-ally.png", 9, at, HOLY_ALLY_M, HOLY_ALLY_BELOW, 14.0, false, 9.0 / 14.0, tg)
		battle._vfx._float_text(tg["pos"] + Vector2(0, -64), Lang.t("等级 +1"), Color("#ffe08a"))
	else:
		_strip(SV + "spear-holy-burst.png", 9, battle._world_pos(at, 0.0), 2.2, 18.0, false, 9.0 / 18.0, false, null, 0.0)


## 敌方光球命中后给携带者的那层护盾: 一颗小光点从敌人飞回携带者(sim 里护盾当场就给了, 这里只是让人看得出护盾从哪来)
func holy_shield_back(from_u: Dictionary, to_u: Dictionary) -> void:
	var n := _holy_orb_node(Vector2(from_u["pos"]), Vector2(to_u["pos"]) - Vector2(from_u["pos"]), HOLY_ORB_M * 0.55)
	if n != null:
		_holy_back.append({"node": n, "from": Vector2(from_u["pos"]), "to": to_u, "t": 0.0})


func _tick_holy_back(delta: float) -> void:
	var keep: Array = []
	for b in _holy_back:
		var n = b["node"]
		if n == null or not is_instance_valid(n):
			continue
		b["t"] = float(b["t"]) + delta
		var k: float = clampf(float(b["t"]) / HOLY_BACK_SEC, 0.0, 1.0)
		var dst := Vector2((b["to"] as Dictionary)["pos"])
		var p: Vector2 = Vector2(b["from"]).lerp(dst, k * k)   # 先慢后快, 被携带者「吸」回去
		(n as Sprite3D).position = battle._world_pos(p, 1.0 + 0.6 * sin(PI * k))
		_orient_to(n, dst - p)
		if k >= 1.0:
			_free(n)
		else:
			keep.append(b)
	_holy_back = keep


'''

patch(VF, [
    ("# ── 筹码 ──\n", NEW_FUNCS + "# ── 筹码 ──\n", 1),
    ("##   146 圣枪    (待重新设计)圣痕: 头顶金色矛十字印记; 第 3 层引爆: 金光十字炸开\n",
     "##   146 圣枪    11-26 晚重做: 圣枪护盾 / 引导光环 / 光球 / 砸中友方光柱 / 砸中敌方星爆 + 护盾回流(见下面 146 那一段)\n", 1),
])
print("ok")
