extends RefCounted
## blocklist.gd —— 本机黑名单(拉黑其他玩家, 2026-10-20 · App Store 审核指南 1.2「屏蔽滥用者」)。
##
## ★只存在本机(`user://blocklist.json`), 服务端不知道谁拉黑了谁: 拉黑只是「我不想再看到这个昵称」,
##   不影响匹配 / 排名 / 对方的任何东西。删除账号时一起清掉(`account_delete.wipe_local`)。
## ★键 = 玩家 ID(`#XXXXXX`, 屏幕上那串)。昵称会改、会重名, 玩家 ID 不会 —— 拉黑必须钉在「人」上。
## ★被拉黑的人: 昵称在本机一律显示成**默认昵称**(与没起名的玩家同一个生成器 `_P2.nickname_fallback`,
##   种子 = 玩家 ID ⇒ 同一个人每次都是同一个默认名, 看着像普通玩家, 不像被打了码)。
## ★屏幕侧只有两个入口: `shown_name(名字, ID)`(单个) / `mask(数据)`(整份网络回包, 递归找带 name+tag 的字典)。
##   各屏在「数据进来的那一处」调一次, 不在每个 Label 上各写一份。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

const PATH := "user://blocklist.json"
const MAX_ENTRIES := 200
## 种子前缀: 与账号默认名的种子分开(否则被拉黑者显示的默认名 = 某个真实账号的默认名的概率更高)。
const SEED_PREFIX := "blocked:"
## 原名存回字典的哪个键(`mask` 换名之后, 举报要的是原名)。
const RAW_KEY := "name_raw"

## {tag: {"name": 拉黑时看到的昵称, "t": 拉黑时刻(毫秒)}}。null = 还没读盘。
static var _cache = null


static func _load() -> Dictionary:
	if _cache is Dictionary:
		return _cache
	_cache = _read_file()
	return _cache


## 读盘(文件坏了 / 不存在 ⇒ 空名单; 不认识的键丢掉)。
static func _read_file() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(PATH):
		return out
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(PATH)) != OK or not (j.data is Dictionary):
		return out
	for k in (j.data as Dictionary).keys():
		var e = (j.data as Dictionary)[k]
		if _P2.tag_valid(str(k)) and e is Dictionary:
			out[str(k)] = {"name": str((e as Dictionary).get("name", "")), "t": int((e as Dictionary).get("t", 0))}
	return out


static func _store() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[Blocklist] 写不了 %s" % PATH)
		return
	f.store_string(JSON.stringify(_load()))
	f.close()


static func is_blocked(tag: String) -> bool:
	return tag != "" and _load().has(tag)


## 拉黑。返回是否真的加进去了(格式不对 / 已满 / 已在名单里 ⇒ false)。
static func add(tag: String, name: String) -> bool:
	if not _P2.tag_valid(tag) or is_blocked(tag):
		return false
	var d := _load()
	if d.size() >= MAX_ENTRIES:
		return false
	## 时刻用毫秒并且严格递增: 同一秒里连拉两个人, 名单顺序也分得出先后(「新拉黑的在前」)。
	var t := int(Time.get_unix_time_from_system() * 1000.0)
	for k in d.keys():
		t = maxi(t, int(d[k]["t"]) + 1)
	_cache[tag] = {"name": name.strip_edges().left(40), "t": t}
	_store()
	return true


## 移出黑名单。返回是否真的移了。
static func remove(tag: String) -> bool:
	var d := _load()
	if not d.has(tag):
		return false
	_cache.erase(tag)
	_store()
	return true


## 名单(新拉黑的在前): [{tag, name, t}]。
static func entries() -> Array:
	var out: Array = []
	var d := _load()
	for k in d.keys():
		out.append({"tag": str(k), "name": str(d[k]["name"]), "t": int(d[k]["t"])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["t"]) > int(b["t"]))
	return out


static func count() -> int:
	return _load().size()


## 删号时: 名单与文件都清掉。
static func clear_all() -> void:
	_cache = {}
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## 被拉黑的人显示成什么。
static func masked_name(tag: String) -> String:
	return _P2.nickname_fallback(SEED_PREFIX + tag)


## 单个名字: 被拉黑 ⇒ 默认昵称; 否则原样。
static func shown_name(name: String, tag: String) -> String:
	return masked_name(tag) if is_blocked(tag) else name


## 整份数据(网络回包解析后的字典 / 数组): 递归找「同时带 name 与 tag 的字典」, 被拉黑的换名并把原名存进 RAW_KEY。
## ★就地改, 也返回同一个对象(方便 `data = BL.mask(data)` 的写法)。名单为空时一步都不走。
## ⚠ 只喂网络数据(纯 JSON 形状)。不许喂战斗里的单位字典 —— 那些互相引用成环(CLAUDE.md §3.2)。
## ★移出黑名单之后再喂同一份数据 ⇒ 名字换回原名(RAW_KEY 里存着), 宿主重画即可, 不必重新拉网络。
static func mask(v, depth: int = 0):
	if depth > 8:
		return v
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("name") and d.has("tag"):
			if is_blocked(str(d["tag"])):
				if not d.has(RAW_KEY):
					d[RAW_KEY] = d["name"]
				d["name"] = masked_name(str(d["tag"]))
			elif d.has(RAW_KEY):
				d["name"] = d[RAW_KEY]
				d.erase(RAW_KEY)
		for k in d.keys():
			var x = d[k]
			if x is Dictionary or x is Array:
				mask(x, depth + 1)
	elif v is Array:
		for x in v:
			if x is Dictionary or x is Array:
				mask(x, depth + 1)
	return v


## 举报时要的原名: 换过名的取 RAW_KEY, 否则就是 name。
static func raw_name(d: Dictionary) -> String:
	return str(d.get(RAW_KEY, d.get("name", "")))


## 只给门禁用: 丢掉内存里那份(下次从盘上重读)。
static func _reset_cache_for_test() -> void:
	_cache = null
