"""cent_fix19_wave_attach_1127.py —— 修: 二档冲击罩 / 突刺气劲没跟上结算的冲击波(11-27 回答用户「二档箭头长度怎么变化」时查出)
  结算顺序是先 _fx("cent_wave") 后 _fx("cent_thrust"): cent_wave 到时罩子还没建 ⇒ 挂不上, 罩子按自己的「先快后慢」路线走
  改: cent_wave 先把波存进 _wave_wait, 罩子建好时(_cent_impact_dome 末尾)认领同一个百夫长的波
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, "scripts/scenes/battle/spear_eq_vfx.gd")
raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:70], s.count(a)); s = s.replace(a, b)
rep('''func cent_wave(u: Dictionary, wv: Dictionary) -> void:
	for i in range(_stabs.size() - 1, -1, -1):
		var st: Dictionary = _stabs[i]
		if st.has("u") and is_same(st["u"], u) and not st.has("w"):
			st["w"] = wv
			st["life"] = 99.0
			return
''', '''var _wave_wait: Array = []   # 结算先发 cent_wave、后发 cent_thrust: 波先存这里, 罩子建好时认领 {u, w}

func cent_wave(u: Dictionary, wv: Dictionary) -> void:
	_wave_wait.append({"u": u, "w": wv})
''')
rep('''		"u": u, "front": [fr_dark, fr_hot], "spray": spray, "skid": 0.0, "h": tip.y, "arrow": arrow, "tail": tail, "haze": haze})
''', '''		"u": u, "front": [fr_dark, fr_hot], "spray": spray, "skid": 0.0, "h": tip.y, "arrow": arrow, "tail": tail, "haze": haze})
	## 认领这一刺的冲击波(二档起): 罩子 / 箭头改跟结算的波头走, 到头(cent_wave_end)再淡掉
	for i in range(_wave_wait.size() - 1, -1, -1):
		if is_same(_wave_wait[i]["u"], u):
			(_stabs.back() as Dictionary)["w"] = _wave_wait[i]["w"]
			(_stabs.back() as Dictionary)["life"] = 99.0
			_wave_wait.remove_at(i)
			break
	_wave_wait = _wave_wait.filter(func(x): return not is_same(x["u"], u))
''')
rep("\t_stabs.clear()\n", "\t_stabs.clear()\n\t_wave_wait.clear()\n")
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
