class_name SkillChoice
extends RefCounted
## 「这只龟的 3选1 主动技, 哪几个是**真能放出来**的」—— 全项目唯一一份判据。
##
## ══════════════════════════════════════════════════════════════════════
##  为什么非抽出来不可 (2026-09-25)
## ══════════════════════════════════════════════════════════════════════
## 用户:「每次机器人选的龟都只选了默认技能」「得修」。
##
## 量出来的分母: **0 / 184** 条现役种子池快照、**0 / 12718** 条队列原料快照带
## `loadouts` 字段 ⇒ 玩家打到的每一个对手, 每一只龟, 永远走消费侧那句
## `var idx := 1`(`RealtimeBattle3DScene.gd:5184`)的默认签名技。
## 而 28 只龟**全部**有 2~3 个已实装的替代技 ⇒ 对手身上只体现了三分之一的技能多样性。
##
## 生产侧有**三个**, 而 2026-09-17 那次(U10)只补了其中一个:
##   ① `Backend.build_ghost_snapshot()` —— 玩家自己上传   ✅ 09-17 补了
##   ② `Backend.make_bot()`             —— 合成机器人     ❌ 写死 `"loadouts": {}`
##   ③ `tests/_cohort.gd`               —— 造种子池的队列 ❌ 写死 `"loadouts": {}`
## 这正是 memory [[fb-hand-rolled-copies-drift]] / [[fb-fix-the-shared-primitive-not-one-instance]]
## 那一类: 同一个形状有 N 个实现, 只修了一处。⇒ 判据只留这一份, 三处都调它。
##
## ══════════════════════════════════════════════════════════════════════
##  判据本身: idx ≥ 1 且 `impl == true`
## ══════════════════════════════════════════════════════════════════════
## · `skillPool[0]` 是**普攻**, 不参与选(固定)。
## · `impl != true` 的候选是**未实装**的: 选了也放不出来, 消费侧会静默回落到 idx=1
##   (`skill_picker.gd:70` 的 `dev_locked` 就是这条判据, 玩家侧显示成「开发中」锁)。
##   ⇒ 给机器人随机挑时**必须挑在这个集合里**, 否则 `randi() % 3 + 1` 会给
##   diamond / rainbow / chest 挑到它们那个没实装的 idx=1, 结果等于没选。
static func playable_indices(pet: Dictionary) -> Array:
	var pool: Array = pet.get("skillPool", []) if pet.get("skillPool") is Array else []
	var out: Array = []
	for i in range(1, pool.size()):
		var sk = pool[i]
		if sk is Dictionary and bool((sk as Dictionary).get("impl", false)):
			out.append(i)
	return out


## 非默认候选是不是「开发中」锁着(玩家侧那把锁的唯一判据)。
## ★`idx == 1` 单独放过: 它是各龟的**签名技**, 是 pool 里的默认那一个,
##   历史上一直不吃这把锁(即便某几只龟的 idx=1 没标 impl)。
static func dev_locked(pet: Dictionary, idx: int) -> bool:
	if idx <= 0 or idx == 1:
		return false
	var pool: Array = pet.get("skillPool", []) if pet.get("skillPool") is Array else []
	if idx >= pool.size():
		return true
	var sk = pool[idx]
	return not (sk is Dictionary and bool((sk as Dictionary).get("impl", false)))


## 给机器人/队列模拟随机挑一个**能放出来**的技能位次。
## ★一个都没有时返回 1 —— 与消费侧的兜底同一个值, 不另造一种"没选"的表示。
##   (返回 0 会被当成普攻, 那是另一种 bug。)
static func pick(pet: Dictionary, rng: RandomNumberGenerator) -> int:
	var ok: Array = playable_indices(pet)
	if ok.is_empty():
		return 1
	return int(ok[rng.randi() % ok.size()])


## 给一队龟挑一整份 `loadouts` = {pet_id → idx}。三个生产者都用这一条。
## ★`pet_of` 是个 `Callable(String) -> Dictionary`(取龟定义) —— 各调用方拿数据的
##   路子不同(DataRegistry.launch_pets / 自己缓存的表), 注入比在这里假设更稳。
static func pick_loadouts(pet_ids: Array, pet_of: Callable,
		rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for pid in pet_ids:
		var p := str(pid)
		var d = pet_of.call(p)
		if d is Dictionary and not (d as Dictionary).is_empty():
			out[p] = pick(d as Dictionary, rng)
	return out
