extends RefCounted
## sim_roster.gd — 模拟玩家「第 N 号槽位用哪三只龟、各带哪一招」的**唯一一份**分配表。
##
## ★为什么要它(用户 2026-10-06):「买装备, 像上周一样, 但这次换不同的龟、不同的技能」。
##   上周 10 个号走的是教学那三只(basic/stone/bamboo)的老路 + 人手点, 龟和技能几乎没覆盖。
##   ⇒ 60 个槽位按槽号**确定性**地分龟分招, 让 28 只龟 × 每只 3 招尽量全覆盖。
##
## ★分配规则(纯函数, 不读钟、不读随机):
##   · 把 180 个位置(60 槽 × 3 只)按 28 一段切成「轮」; 每一轮里 28 只龟**各出现恰好一次**,
##     顺序 = (段内序号 × STRIDE + 轮号 × SHIFT) mod 28 —— STRIDE 与 28 互质 ⇒ 是一个排列;
##     轮号偏移让同一个槽位组合不会每轮重复同一批邻居。
##   · 某只龟第 j 次出场带 choices[(j + 龟序号) mod 3] 这一招 ⇒ 6~7 次出场里三招**轮着来**,
##     每一招至少 2 次。
##   · 跨轮那几格可能让同一只龟在一个槽里出现两次 ⇒ 往后找第一个不重复的位置**对调**(确定性修补)。
##   · 可选招 = idx 1 + `SkillChoice.playable_indices` 里 ≥2 的(与选龟页 `dev_locked` 同一条判据:
##     idx 1 是签名技, 恒可选; 2/3 要 impl==true)。
##
## ★覆盖口径: `SIM_ROSTER=pid,pid,pid` / `SIM_SKILLS=i,i,i` 可整个覆盖某一槽(调试用)。
## ★只给模拟窗口用。产品代码不引用本文件。

const SLOTS_DEFAULT := 60
const STRIDE := 11      # gcd(11, 28) = 1
const SHIFT := 5
## ★p61 起(2026-10-06 扩到 120 人, 用户「下周准备大概 120 个选手」)换一套步长 ——
##   旧公式每轮同一个步长 ⇒ 每 28 个位置三连组就重来一遍(实测 120 槽里 84 槽与别人同一组三只龟)。
##   p01..p60 已有存档、已在台账里登记, **一个字不动**; 只有第 181 个位置(p61 第一只)起走这套:
##   每一轮换一个与 28 互质的步长, 轮间再错 7 位。
const SPLIT_POS := 180
const STRIDES2 := [3, 5, 9, 13, 15, 17, 19, 23, 25, 27]
const SHIFT2 := 7


## 一只龟可选的主动技位次(1..3 里真能选的)。
static func choices_for(pet: Dictionary) -> Array:
	var out: Array = [1]
	for i in SkillChoice.playable_indices(pet):
		if int(i) >= 2 and not out.has(int(i)):
			out.append(int(i))
	return out


## 全表: 返回 [ {slot, pets:[3 个 id], skills:[3 个 idx]} ] × n。`pets_in` = DataRegistry.all_pets 那种数组。
static func table(pets_in: Array, n: int = SLOTS_DEFAULT) -> Array:
	var ids: Array = []
	var by_id := {}
	for p in pets_in:
		if p is Dictionary and str((p as Dictionary).get("id", "")) != "":
			ids.append(str(p["id"]))
			by_id[str(p["id"])] = p
	var m := ids.size()
	if m < 3:
		return []
	## ① 180 个位置的龟序列
	var seq: Array = []
	for pos in range(n * 3):
		if pos < SPLIT_POS:
			var rnd := pos / m
			var k := pos % m
			seq.append(ids[(k * STRIDE + rnd * SHIFT) % m])
		else:
			var q := pos - SPLIT_POS
			var r2 := q / m
			var k2 := q % m
			seq.append(ids[(k2 * int(STRIDES2[r2 % STRIDES2.size()]) + r2 * SHIFT2) % m])
	## ② 槽内去重(跨轮那几格)
	for s in range(n):
		for a in range(3):
			var pa := s * 3 + a
			var dup := false
			for b in range(a):
				if seq[s * 3 + b] == seq[pa]:
					dup = true
			if not dup:
				continue
			for q in range(pa + 1, seq.size()):
				var cand: String = seq[q]
				var clash := false
				for b in range(3):
					if s * 3 + b != pa and seq[s * 3 + b] == cand:
						clash = true
				if not clash:
					var tmp = seq[pa]; seq[pa] = seq[q]; seq[q] = tmp
					break
	## ③ 招式: 第 j 次出场 → choices[(j + 龟序号) mod len]
	var seen := {}
	var out: Array = []
	for s in range(n):
		var pets: Array = []
		var skills: Array = []
		for a in range(3):
			var pid: String = seq[s * 3 + a]
			var j: int = int(seen.get(pid, 0))
			seen[pid] = j + 1
			var ch: Array = choices_for(by_id[pid])
			pets.append(pid)
			skills.append(int(ch[(j + ids.find(pid)) % ch.size()]))
		out.append({"slot": s + 1, "pets": pets, "skills": skills})
	return out


## 某一槽位的分配(带环境变量覆盖)。slot 从 1 起。
static func for_slot(slot: int, pets_in: Array) -> Dictionary:
	var t := table(pets_in, maxi(SLOTS_DEFAULT, slot))
	var r: Dictionary = (t[slot - 1] as Dictionary).duplicate(true) if slot >= 1 and slot <= t.size() else {"slot": slot, "pets": [], "skills": []}
	var ov := OS.get_environment("SIM_ROSTER").strip_edges()
	if ov != "":
		r["pets"] = Array(ov.split(",", false))
	var sk := OS.get_environment("SIM_SKILLS").strip_edges()
	if sk != "":
		var a: Array = []
		for x in sk.split(",", false):
			a.append(int(x))
		r["skills"] = a
	return r
