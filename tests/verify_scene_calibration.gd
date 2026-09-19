extends Node
## verify_scene_calibration.gd — 战斗场景那几个【标定出来的常量】不许被悄悄改
##
## ★由来(2026-09-18): `tools/battle_scene_audit.py` 的四条判据是拿 **34 张真实游戏内画面**
##   标定出来的, 但它**需要渲染 ⇒ 进不了无头门禁**(方案书 20260918 的 R10)。
##   于是 v0.19.405~408 连着四版在调这些数, **一条门禁都没守着**。
##
## ⇒ 本门禁是那条判据的【替身】, 而且要说清它守的是什么、不守什么:
##   ✅ 守住: 这些数**不会在没人重新标定的情况下被改掉**。
##   ❌ 不守: 改完好不好看。那个只能实拍 + 人眼, 本门禁不冒充它。
##
## ★判据形状: 产品常量 == 【标定时量出来的字面值】。
##   ★★不许写成「产品常量 == 产品常量」—— 主会话当天刚栽过:
##     `verify_edge_wall` 第一版判据是 `size.y == BWB.WALL_H_M`, 测试也读同一个常量,
##     把常量改成一半时**一条都没红**。判据必须钉在【外部的、量出来的】数上。
##
## ★每个数后面都写清它是【怎么量出来的】。改它就要重跑那次测量, 不是改这行。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_scene_calibration.tscn --quit-after 600

const BWB := preload("res://scripts/scenes/battle/battle_world_builder.gd")

var _ok := 0
var _fail := 0

func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])

## 从 shader 源码里抠 uniform 默认值。★先剥注释 —— 否则注释里写的数会冒充真值。
func _num(path: String, uname: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var src := f.get_as_text()
	f.close()
	var clean := ""
	for line in src.split("\n"):
		var i: int = line.find("//")
		clean += (line.substr(0, i) if i >= 0 else line) + "\n"
	## ★第一版写的是「找到 key 之后再找 =」—— 错的:
	##   `EMISSION = c_pre_foam * 0.09;` 里那个 `=` **就在 key 里面**, 于是切出
	##   " c_pre_foam * 0.09" 这种不是数的东西; 而 `foam_col.rgb, foam * 0.46` 后面根本没有 `=`。
	##   ★是【分母断言】当场把它抓出来的 —— 否则 null 会被静默当成"读到了"然后这两条形同虚设。
	##   现在改成: 从 key 结束处往后, 取**紧跟着的第一个数**。
	var at: int = clean.find(uname)
	if at < 0:
		return null
	var i: int = at + uname.length()
	var n: int = clean.length()
	while i < n and clean[i] == " ":
		i += 1
	var j: int = i
	while j < n and (clean[j].is_valid_int() or clean[j] == "." or clean[j] == "-"):
		j += 1
	if j <= i:
		return null
	var s: String = clean.substr(i, j - i)
	return s.to_float() if s.is_valid_float() else null

func _ready() -> void:
	await get_tree().process_frame
	print("── 战斗场景标定常量 ──")

	## ── ① 边界带(v0.19.405 标定 → 2026-09-20 换实现后改账) ──
	## ★★**改账不是加白名单**: 实现从【逐格 billboard 墙卡】换成【沿整圈边界的连续 mesh】,
	##   原来那两个常量的含义变了:
	##   · `WALL_H_M`(1.11) 是 **billboard 口径** —— 不吃俯角压缩, 31px 只要 1.11 米;
	##     真实竖直几何同样读出 31px 要 **1.75 米**(差 1.58 倍, 别混用)。
	##   · `WALL_GAIN`(2.05) 是 **UNSHADED 的补偿** —— 被地面亮度牵着走,
	##     2026-09-18 一天内重标定三次(1.55→1.70→2.05)。新带**吃光**, 这个常量已删(W8 关闭)。
	## ★几何与材质的活判据在 `tests/verify_edge_wall.gd`(17 条, 走真场景树量 mesh);
	##   本文件只留一条**标定值钉子**, 防它被惄悄改掉。
	_chk("① 带高 WALL_H_M_GEO == 1.75 米(真几何口径·不是 billboard 的 1.11)",
		absf(BWB.WALL_H_M_GEO - 1.75) < 0.001, "%.3f" % BWB.WALL_H_M_GEO)

	const W := "res://scripts/scenes/battle/shaders/ground_water.gdshader"
	## ── ①b 水体压暗系数(v0.19.413·153 帧真实游戏内画面标定) ──
	## ★★**调色板原值一个像素不动** —— 「水是什么色」由硬锁表说了算(#1fb8c4),
	##   「它被照得多亮」由着色说了算。我第一版直接改了 `shallow_col`,
	##   `verify_water_palette` **当场红**(实测 #3d8094 ≠ #1fb8c4) —— 红得对。
	## 理由: 参考里水比地面暗(帧 29), 而改前本项目水比石台还亮 +10;
	##   改后实拍 水−石台 **−45** · 中心−外围 **+20.6**(参考 +22) · 亮部饱和 **0.35**(参考 0.394)。
	var dim = _num(W, "uniform float body_dim =")
	_chk("★分母: 读得到水体压暗系数 body_dim", dim != null)
	if dim != null:
		_chk("①b 水体压暗 body_dim == 0.62(153 帧标定·动它就要重拍重量)",
			absf(float(dim) - 0.62) < 0.001, "%.3f" % float(dim))

	## ── ② 水面(v0.19.406·34 张参考标定) ──
	var emis = _num(W, "EMISSION = c_pre_foam *")
	_chk("★分母: 读得到水面 EMISSION 系数", emis != null)
	if emis != null:
		## 0.09: 改前 0.26 的自发光是「整条水带明度 176」的一大来源, 而水体色明度才 140。
		## ★★改账(2026-09-20): 0.09→0 —— 自发光让水**拿不到「比地面暗」**。
		##   旧值 0.09 是 v0.19.406 对着**亮水体**标定的; 水压暗后它变成一层抬底。
		_chk("② 水自发光 == 0(压暗后不再自发光·让它吃光)",
			emis != null and absf(float(emis) - 0.0) < 0.001, "%.3f" % float(emis) if emis != null else "null")
	var foam = _num(W, "foam_col.rgb, foam *")
	_chk("★分母: 读得到泡沫强度", foam != null)
	if foam != null:
		## 0.46: 岸线那条亮边原本是饱和水色(判据③ 卡在这), 换成白泡沫。
		## ★宽度**没动**(仍 0.34) —— 当年被否的是「宽 0.62 + 强 0.55」那个组合(整座岛套发光环)。
		## ★★改账(2026-09-20): 0.46→0.18 —— 泡沫/浪尖强度是当初对着**亮水体**标定的,
		##   水体压暗后同样强度的对比度翻倍 ⇒ 岸线变成一条**发光描边环**(实拍看见的)。
		##   ★仍然**只动强度不动宽度** —— 当年被否的是「宽 0.62 + 强 0.55」那个组合。
		_chk("② 泡沫强度 == 0.18(水压暗后重标定·只动强度不动宽度)",
			foam != null and absf(float(foam) - 0.18) < 0.001, "%.3f" % float(foam) if foam != null else "null")
	## ── ③ 焦散(v0.19.406) ──
	const C := "res://scripts/scenes/battle/shaders/ground_common.gdshaderinc"
	var ca = _num(C, "caustic_amt =")
	_chk("★分母: 读得到 caustic_amt", ca != null)
	if ca != null:
		## 0.40: 焦散色饱和度只有 0.38 —— 正是参考里那种「低饱和的光」。
		## 让光去当最亮的, 水退回中间调。与上面的 EMISSION 是一对, 改一个必须两个一起看。
		_chk("③ 焦散强度 == 0.40(与水自发光 0.09 是一对)", absf(float(ca) - 0.40) < 0.001, "%.3f" % float(ca))

	## ── ④ 灯光(v0.19.407·A/B 三变体 + 5 次基线排噪声) ──
	## 1.55 / 0.55: V3 方案。★V2「环境光中性化」实测几乎零变化, 当场否掉了我自己的假设。
	## ★优势跑过 5 次基线确认不是噪声(亮部饱和基线 0.542~0.621 极差 0.079, V3 0.486 在区间外)。
	var b := BWB.new(null)
	var src_f := FileAccess.open("res://scripts/scenes/battle/battle_world_builder.gd", FileAccess.READ)
	_chk("★分母: 读得到 world_builder 源码", src_f != null)
	if src_f != null:
		var s := src_f.get_as_text()
		src_f.close()
		_chk("④ 主光 light_energy == 1.55(A/B 变体 V3)", s.contains("light.light_energy = 1.55"))
		_chk("④ 环境光 ambient_light_energy == 0.55(与主光是一对)", s.contains("env.ambient_light_energy = 0.55"))
		## ★背景剪影带三层的 z 是按【可见宽度】算的, 不是估的。
		_chk("⑤ 远景剪影带三层都在(z=-16/-19/-22)",
			s.contains("\"z\": -16.0") and s.contains("\"z\": -19.0") and s.contains("\"z\": -22.0"))
	print("")
	if _fail == 0:
		print("ALL PASS — 场景标定常量 (%d/%d)" % [_ok, _ok])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _ok])
	get_tree().quit(1 if _fail > 0 else 0)
