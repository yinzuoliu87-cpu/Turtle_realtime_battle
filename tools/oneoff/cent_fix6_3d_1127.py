"""cent_fix6_3d_1127.py —— 百夫长第六轮(用户 11-27):
  「这举盾任何方向上都有可能举盾啊…还是需要三 D 特效」⇒ 龟甲阵弧盾改成世界空间里的 3D 弧面网格(Cent3dVfx.gen_aegis + cent_aegis.gdshader),
      按举盾方向绕 Y 转: 地面上朝哪个方向都立得对(原来是朝镜头的平面图, 只能左右两种)
      方向 = 本体朝向那一侧最近的敌人(那一侧没有敌人就正前方), 举盾那一刻定下、3 秒内不转(潘森 E 也是定向)
      张开 0.15 秒(中间往两边、地面往上长) → 循环(六边形龟甲格 + 往上流的光带) → 每 0.5 秒盾后出刺那一下整片闪 → 放盾按格碎掉 0.3 秒
  「冲击罩…武器头部有一层冲击罩一样的冲击波一样的东西…冲出去」⇒ 普攻: 两层 3D 激波罩(Cent3dVfx.gen_shock + cent_shock.gdshader)
      罩在矛尖上, 沿真实刺击方向(朝目标)往前冲 1.6 米、边冲边张大、0.3 秒散掉; 上一版矛尖前那张半月形平面图删掉
  「骑兵…太快了…没有冲击罩…命中特效也没有」⇒ 冲锋速度 520 → 300 码/秒(马跑帧条 14 → 10 fps 跟着放慢);
      马头前一层压低压宽的土金色船头浪(同一个激波罩着色器, 形状 / 颜色不同), 跟着马走;
      撞到人: 撞点炸开一层冲击罩 + 大号火星 + 扬土 + 轻震屏
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load(rel):
    raw = open(os.path.join(ROOT, rel), "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    return raw.decode("utf-8").replace("\r\n", "\n"), nl


def save(rel, s, nl):
    open(os.path.join(ROOT, rel), "wb").write(s.replace("\n", nl).encode("utf-8"))


def rep(s, a, b, n=1):
    assert s.count(a) == n, (a[:70], s.count(a))
    return s.replace(a, b)


def cut(s, start, end_marker):
    """把 start 开始到 end_marker(不含)之间整段换掉, 返回 (前, 后)"""
    i = s.index(start)
    j = s.index(end_marker, i)
    assert s.count(start) == 1
    return s[:i], s[j:]


AEGIS_NEW = '''## 龟甲阵(11-27 第六轮, 用户「这举盾任何方向上都有可能举盾…需要三 D 特效」): 世界空间里一面 3D 弧形能量盾
##   网格 Cent3dVfx.gen_aegis(以本体为圆心、半径 AEGIS_R 的竖立弧面), 着色器 cent_aegis.gdshader(六边形龟甲格 / 流光 / 亮边 / 碎裂)
##   方向 = 本体朝向那一侧最近的敌人(没有就正前方), 举盾那一刻定下; 节点绕 Y 转到这个方向 ⇒ 斜着、朝上朝下都立得对
var _aegis: Array = []      # {u, node, mat, t, dir, off}
const AEGIS_R := 1.45       # 弧半径(米): 盾面离本体中心多远
const AEGIS_ARC := 2.2      # 张角(弧度, 约 126°)
const AEGIS_H := 3.0        # 盾高(米), 比人高半个身位
const AEGIS_LEAN := 0.35    # 顶部往外翻(米)
const AEGIS_OPEN_SEC := 0.15
const AEGIS_BRK_SEC := 0.3
const AEGIS_JAB_IV := 0.5   # 盾后出刺节奏(= 结算 POKE_IV、帧条捅出帧)


func _aegis_dir(u: Dictionary) -> Vector2:
	var spr = u.get("sprite", null)
	var fx: float = (1.0 if (spr as Sprite3D).flip_h else -1.0) if is_instance_valid(spr) else _face(u).x   # 本体帧条原画朝左, flip_h = 朝右
	var best: Vector2 = Vector2(fx, 0.0)
	var bd := INF
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false):
			continue
		var d: Vector2 = Vector2(o["pos"]) - Vector2(u["pos"])
		if d.x * fx <= 0.0 or d.length() < 1.0:
			continue
		if d.length() < bd:
			bd = d.length()
			best = d.normalized()
	return best


func cent_shield(u: Dictionary, sec: float) -> void:
	## 帧条 = 举盾 6 帧 + 撑盾 36 帧(打包脚本里拼好); 整条恰好播满举盾时长 ⇒ 0.4 秒举起, 之后一直撑着, 到点放下回待机
	var sd := _cent_sd("shield", 14.0)
	var nf: int = int(sd.get("frames", 42)) if not sd.is_empty() else 42
	_cent_play(u, "shield", float(nf) / maxf(0.5, sec))   # 42 帧 / 3 秒 = 14 fps: 盾后出刺的捅出帧恰好落在 0.5 / 1.0 / … 秒(= 结算 POKE_IV)
	battle._vfx._flash(u, Color(1.0, 0.9, 0.55), 0.12)   # 扎稳那一下本体闪白金
	cent_shield_off(u)
	if _ok():
		var dir := _aegis_dir(u)
		var mi := Cent3dVfx.node(battle._world, Cent3dVfx.gen_aegis(AEGIS_R, AEGIS_ARC, AEGIS_H, AEGIS_LEAN, 24, 10),
			Cent3dVfx.AEGIS_SHADER, Cent3dVfx.AEGIS_SP,
			{"open": 0.0, "fade": 1.0, "t": 0.0, "flash": 0.0, "brk": 0.0,
			 "size_m": Vector2(AEGIS_R * AEGIS_ARC, AEGIS_H)})
		mi.rotation = Vector3(0.0, Cent3dVfx.yaw_of(dir), 0.0)
		mi.position = battle._world_pos(Vector2(u["pos"]), 0.0)
		_aegis.append({"u": u, "node": mi, "mat": mi.material_override, "t": 0.0, "dir": dir, "off": -1.0})
	_strip(LION_DUST, 7, battle._world_pos(Vector2(u["pos"]), 0.0), 1.6, 16.0, false, 7.0 / 16.0, false, null, 0.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.5)


## 放盾: 按格碎掉(AEGIS_BRK_SEC), 碎完再删节点
func cent_shield_off(u: Dictionary) -> void:
	for a in _aegis:
		if is_same(a["u"], u) and float(a["off"]) < 0.0:
			a["off"] = 0.0


func _tick_aegis(delta: float) -> void:
	var keep: Array = []
	for a in _aegis:
		var n = a["node"]
		var u: Dictionary = a["u"]
		if n == null or not is_instance_valid(n):
			continue
		if not u.get("alive", false) and float(a["off"]) < 0.0:
			a["off"] = 0.0
		var mat: ShaderMaterial = a["mat"]
		a["t"] = float(a["t"]) + delta
		var t: float = float(a["t"])
		(n as MeshInstance3D).position = battle._world_pos(Vector2(u["pos"]), 0.0)
		mat.set_shader_parameter("t", t)
		mat.set_shader_parameter("open", minf(1.0, t / AEGIS_OPEN_SEC))
		## 盾后出刺那一下(0.5 / 1.0 / … 秒, 跟本体帧条捅出帧同一刻)整片闪, 0.15 秒退掉
		var ph: float = fmod(t, AEGIS_JAB_IV)
		var fl: float = (1.0 - ph / 0.15) if t >= AEGIS_JAB_IV - 0.001 and ph < 0.15 else 0.0
		mat.set_shader_parameter("flash", maxf(0.0, fl))
		if float(a["off"]) >= 0.0:
			a["off"] = float(a["off"]) + delta
			var k: float = float(a["off"]) / AEGIS_BRK_SEC
			mat.set_shader_parameter("brk", minf(1.0, k))
			mat.set_shader_parameter("fade", 1.0 - 0.3 * minf(1.0, k))
			if k >= 1.0:
				_free(n)
				continue
		keep.append(a)
	_aegis = keep
'''

SHOCK_NEW = '''## 普攻冲击罩(11-27 第六轮, 用户「武器头部有一层冲击罩一样的冲击波…冲出去」): 刺到最远那一帧, 矛头外面裹两层 3D 激波罩
##   (Cent3dVfx.gen_shock 旋转抛物面 + cent_shock.gdshader), 沿真实刺击方向(朝目标)往前冲 CENT_SHOCK_DIST、边冲边张大, CENT_SHOCK_SEC 散掉
##   起点 = 命中帧矛尖(帧里 (21,161), 脚底 (96,191) ⇒ 立足点往前 75 像素、离地 30 像素, 按镜头的左右 / 上下轴换成世界坐标)
const CENT_IMP_FWD_PX := 75.0
const CENT_IMP_UP_PX := 30.0
const CENT_SHOCK_SEC := 0.3
const CENT_SHOCK_DIST := 1.6
var _shocks: Array = []   # {node, mat, t, life, p0, d3, dist, s0, s1, spin}


func _shock(p0: Vector3, d3: Vector3, mesh: Mesh, params: Dictionary, life: float, dist: float, s0: Vector3, s1: Vector3, spin: float) -> void:
	if not _ok():
		return
	var mi := Cent3dVfx.node(battle._world, mesh, Cent3dVfx.SHOCK_SHADER, Cent3dVfx.SHOCK_SP, params)
	var fl := Vector3(d3.x, 0.0, d3.z)
	var yaw: float = Cent3dVfx.yaw_of(Vector2(fl.x, fl.z).normalized()) if fl.length() > 0.001 else 0.0
	var pitch: float = atan2(d3.y, maxf(0.001, fl.length()))
	mi.rotation = Vector3(0.0, yaw, pitch)
	mi.position = p0
	mi.scale = s0
	_shocks.append({"node": mi, "mat": mi.material_override, "t": 0.0, "life": life, "p0": p0, "d3": d3.normalized(), "dist": dist, "s0": s0, "s1": s1, "spin": spin})


func _tick_shocks(delta: float) -> void:
	var keep: Array = []
	for s in _shocks:
		var n = s["node"]
		if n == null or not is_instance_valid(n):
			continue
		s["t"] = float(s["t"]) + delta
		var k: float = float(s["t"]) / float(s["life"])
		if k >= 1.0:
			_free(n)
			continue
		var e: float = 1.0 - (1.0 - k) * (1.0 - k)   # 先快后慢
		(n as MeshInstance3D).position = Vector3(s["p0"]) + Vector3(s["d3"]) * float(s["dist"]) * e
		(n as MeshInstance3D).scale = (s["s0"] as Vector3).lerp(s["s1"] as Vector3, e)
		var mat: ShaderMaterial = s["mat"]
		mat.set_shader_parameter("prog", float(s["t"]) * float(s["spin"]))
		mat.set_shader_parameter("fade", 1.0 - smoothstep(0.45, 1.0, k))
		keep.append(s)
	_shocks = keep


func _cent_impact_dome(u: Dictionary, tg: Dictionary) -> void:
	var spr = u.get("sprite", null)
	if not _ok() or not is_instance_valid(spr):
		return
	var px: float = float((spr as Sprite3D).pixel_size)
	var fr: bool = bool((spr as Sprite3D).flip_h)   # 原画朝左; 翻转 = 朝右
	var base: Vector3 = (spr as Sprite3D).global_position
	var cb: Basis = battle._cam.global_transform.basis if battle.get("_cam") != null else Basis.IDENTITY   # 立绘是朝镜头的板: 帧里的左右 / 上下 = 镜头的 x / y 轴
	var tip: Vector3 = base + cb.x * (CENT_IMP_FWD_PX * px * (1.0 if fr else -1.0)) + cb.y * (CENT_IMP_UP_PX * px)
	var d2: Vector2 = Vector2(tg["pos"]) - Vector2(u["pos"])
	if d2.length() < 1.0 or signf(d2.x) != (1.0 if fr else -1.0):
		d2 = Vector2(1.0 if fr else -1.0, 0.0)   # 目标在身后(刚转身那一下)就按朝向冲
	var d3 := Vector3(d2.normalized().x, 0.0, d2.normalized().y)
	## 外层: 白金薄罩, 大、冲得远; 内层: 小、亮、紧贴矛尖, 冲得近(两层错开读得出厚度)
	_shock(tip, d3, Cent3dVfx.gen_shock(1.0, 0.5, 8, 20), {"prog": 0.0, "fade": 1.0, "rings": 3.0, "rim_pow": 1.4, "tail": 0.45,
		"col_a": Vector3(1.0, 0.97, 0.88), "col_b": Vector3(1.0, 0.74, 0.3)}, CENT_SHOCK_SEC, CENT_SHOCK_DIST, Vector3(0.45, 0.45, 0.45), Vector3(1.25, 1.25, 1.25), 9.0)
	_shock(tip - d3 * 0.1, d3, Cent3dVfx.gen_shock(0.6, 0.26, 6, 16), {"prog": 0.0, "fade": 1.0, "rings": 2.0, "rim_pow": 1.1, "tail": 0.5,
		"col_a": Vector3(1.0, 1.0, 1.0), "col_b": Vector3(1.0, 0.88, 0.55)}, CENT_SHOCK_SEC * 0.8, CENT_SHOCK_DIST * 0.55, Vector3(0.6, 0.6, 0.6), Vector3(1.1, 1.1, 1.1), 7.0)


'''


def main():
    rel = "scripts/scenes/battle/spear_eq_vfx.gd"
    s, nl = load(rel)
    a, b = cut(s, "## 龟甲阵(11-27 用户「技能特效感觉都不明显」)", "## 3 档举盾期间每 0.5 秒刺周围")
    s = a + AEGIS_NEW + "\n\n" + b
    a, b = cut(s, "## 普攻冲击罩(11-27 用户「矛刺出去…想要那种明显一点的冲击罩」)", "func cent_thrust(u: Dictionary, t: Dictionary, n: int) -> void:\n")
    s = a + SHOCK_NEW + b
    s = rep(s, "\t_cent_impact_dome(u)   # 矛尖前炸开的冲击罩(附录 C)\n", "\t_cent_impact_dome(u, t)   # 矛头裹着冲击罩冲出去(第六轮 3D)\n")
    s = rep(s, "\t_tick_aegis()\n\t_tick_cent_glows()\n", "\t_tick_aegis(delta)\n\t_tick_shocks(delta)\n\t_tick_cent_glows()\n")
    ## 骑兵: 马跑帧条放慢 + 船头浪 + 命中冲击罩
    s = rep(s, '\tvar n := _strip(V + "eq-cavalry-run.png", 8, battle._world_pos(Vector2(c["pos"]), 0.0), 2.6, 14.0, true, 0.0)   # 最后加 ⇒ 画在最上面\n',
            '\tvar n := _strip(V + "eq-cavalry-run.png", 8, battle._world_pos(Vector2(c["pos"]), 0.0), 2.6, 10.0, true, 0.0)   # 最后加 ⇒ 画在最上面; 11-27 冲锋 520 → 300 码/秒, 跑帧 14 → 10 fps\n')
    s = rep(s, '\t\t_cav_nodes.append({"c": c, "node": n, "parts": parts, "dust_t": 0.0})\n',
            '\t\t## 马头前的船头浪(11-27 用户「也没有冲击罩啊」): 压低压宽的土金色激波罩, 跟着马走、波纹一直往后退\n'
            '\t\tvar bow := Cent3dVfx.node(battle._world, Cent3dVfx.gen_shock(1.1, 1.0, 8, 20), Cent3dVfx.SHOCK_SHADER, Cent3dVfx.SHOCK_SP,\n'
            '\t\t\t{"prog": 0.0, "fade": 0.85, "rings": 3.0, "rim_pow": 1.3, "tail": 0.5, "col_a": Vector3(1.0, 0.93, 0.75), "col_b": Vector3(0.85, 0.6, 0.3)})\n'
            '\t\tbow.scale = Vector3(1.0, 0.75, 1.35)\n'
            '\t\tbow.rotation = Vector3(0.0, Cent3dVfx.yaw_of(dir), 0.0)\n'
            '\t\t_cav_nodes.append({"c": c, "node": n, "parts": parts, "dust_t": 0.0, "bow": bow, "bt": 0.0})\n')
    s = rep(s, '\t\t\tr3["dust_t"] = float(r3.get("dust_t", 0.0)) + delta\n',
            '\t\t\tvar bw = r3.get("bow")\n'
            '\t\t\tif bw != null and is_instance_valid(bw):   # 船头浪: 马头前 70 码、离地 0.9 米\n'
            '\t\t\t\tr3["bt"] = float(r3.get("bt", 0.0)) + delta\n'
            '\t\t\t\t(bw as MeshInstance3D).position = battle._world_pos(cp + Vector2(r3["c"]["dir"]) * 70.0, 0.9)\n'
            '\t\t\t\t((bw as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("prog", float(r3["bt"]) * 4.0)\n'
            '\t\t\tr3["dust_t"] = float(r3.get("dust_t", 0.0)) + delta\n')
    s = rep(s, '\t\tif is_same(r["c"], c):\n\t\t\t_free(r["node"])\n\t\t\tfor pt in r.get("parts", []):\n',
            '\t\tif is_same(r["c"], c):\n\t\t\t_free(r["node"])\n\t\t\t_free(r.get("bow"))\n\t\t\tfor pt in r.get("parts", []):\n')
    s = rep(s, '\tfor r4 in _cav_nodes:\n\t\tfor pt in r4.get("parts", []):\n',
            '\tfor sk in _shocks:\n\t\t_free(sk["node"])\n\t_shocks.clear()\n\tfor r4 in _cav_nodes:\n\t\t_free(r4.get("bow"))\n\t\tfor pt in r4.get("parts", []):\n')
    s = rep(s, '''func cent_cav_hit(_c: Dictionary, o: Dictionary) -> void:
	_strip(LION_DUST, 7, battle._world_pos(Vector2(o["pos"]), 0.0), 1.4, 16.0, false, 7.0 / 16.0, false, null, 0.0)   # 马蹄踏过扬土(底层扬尘)
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.5), 1.5, 20.0, false, 6.0 / 20.0, false, null, 0.0)
''', '''## 骑兵撞人(11-27 用户「命中特效也没有」): 撞点沿冲锋方向炸开一层冲击罩 + 大号火星 + 扬土 + 轻震屏
func cent_cav_hit(c: Dictionary, o: Dictionary) -> void:
	var d2: Vector2 = Vector2(c["dir"])
	_shock(battle._world_pos(Vector2(o["pos"]) - d2 * 20.0, 0.9), Vector3(d2.x, 0.0, d2.y), Cent3dVfx.gen_shock(0.9, 0.8, 8, 20),
		{"prog": 0.0, "fade": 1.0, "rings": 2.0, "rim_pow": 1.2, "tail": 0.45, "col_a": Vector3(1.0, 0.96, 0.85), "col_b": Vector3(1.0, 0.66, 0.28)},
		0.32, 1.3, Vector3(0.5, 0.5, 0.5), Vector3(1.5, 1.5, 1.5), 8.0)
	_strip(LION_DUST, 7, battle._world_pos(Vector2(o["pos"]), 0.0), 2.0, 16.0, false, 7.0 / 16.0, false, null, 0.0)   # 马蹄踏过扬土(底层扬尘)
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.6), 2.4, 20.0, false, 6.0 / 20.0, false, null, 0.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.25)
''')
    save(rel, s, nl)

    rel = "scripts/systems/equip/spear_synergy_system.gd"
    s, nl = load(rel)
    s = rep(s, "const CAV_SPD := 520.0\n", "const CAV_SPD := 300.0            # 11-27 用户「速度是很快, 太快了」: 520 → 300 码/秒\n")
    save(rel, s, nl)

    rel = "tools/assetgen/pack_spear_chip_art.py"
    s, nl = load(rel)
    s = rep(s, ' ("centurion-thrust-impact", "spear-cent-dome", False),', '')
    save(rel, s, nl)
    for f in ["spear-cent-dome.png", "spear-cent-dome.png.import"]:
        p = os.path.join(ROOT, "assets", "sprites", "vfx", f)
        if os.path.exists(p):
            os.remove(p)
    print("ok")


main()
