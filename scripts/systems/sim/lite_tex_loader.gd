extends ResourceFormatLoader
## lite_tex_loader.gd —— 无头陪练号省内存: 解码后 ≥ MIN_BYTES 的贴图, 换成【同尺寸、不含像素】的 PlaceholderTexture2D。
##
## ★为什么(2026-10-27 实测): 服务器上每个陪练号(无头客户端 + SIM_DRIVER=1, 由 sim_driver.gd 驱动)峰值 RSS ≈ 0.75GB,
##   其中约 245MB 是解码后的大贴图像素 —— 主要是选龟屏把 28 只龟的全身动作表(4000×1000 级)全部载入
##   (TeamSelectScene._apply_pet_idle_texture)。无头不画画面, 这些像素从头到尾没人看。
##   Linux 实测峰值 776 → 523MB。
## ★只扔像素、不改尺寸: 占位贴图的 get_width / get_height / get_size 与原图一致 ⇒ 帧切分、精灵包围盒、
##   按贴图尺寸算的布局全部不变。读像素的地方(get_image)拿到 null —— 各处的空值判断由
##   tests/verify_bot_lite_textures.gd ③ 逐处量。
## ★行为不变的证据: 战斗录像双向交叉重放(现状录 → 本方式放 / 本方式录 → 现状放), 所有校验点一致。
## ★开关: 只在「无头 且 SIM_DRIVER 恰好是 "1"」时装 —— 与 GameState._ready 里存档开关同一句判断。
##   真人客户端(有画面)、门禁(从不设 SIM_DRIVER)、裁判机(不设 SIM_DRIVER)都不装。
## ★装在哪: autoload/persistent_bg.gd 的 _init。它是第一个 autoload, _init 早于其余 autoload 脚本载入与任何场景;
##   晚装的话, 装之前已经载进来的贴图仍是带像素的真贴图(缓存里那份不会被换掉)。
## ★小贴图: _load 返回 null ⇒ ResourceLoader 接着问下一个加载器 = 引擎原装的 CompressedTexture2D 加载器, 照常有像素。

## 解码后 RGBA 字节数(宽 × 高 × 4) ≥ 它才换占位。256×256 恰好等于它(算大); 672×96 = 258048(算小)。
const MIN_BYTES := 262144

var min_bytes := MIN_BYTES
var n_ph := 0          # 换成占位的张数(只供日志; 线程载入时可能少数, 不影响行为)
var bytes_saved := 0   # 省下的解码字节数(同上)
var _first_logged := false


## 判据: 无头 且 SIM_DRIVER 恰好是 "1"。两个输入由调用方传 —— 测试缝: 门禁不用真起一个陪练号就能量两面。
static func wanted(headless: bool, sim_driver: String) -> bool:
	return headless and sim_driver == "1"


## 是陪练号 ⇒ 装上(排在所有加载器最前)并返回这个加载器; 否则什么都不做、返回 null。
## 注册前后各打一行 `[LiteTex]`, 服务器上 grep 这两行确认生效。
static func install_if_bot(headless: bool, sim_driver: String) -> ResourceFormatLoader:
	if not wanted(headless, sim_driver):
		return null
	var ld: ResourceFormatLoader = new()
	print("[LiteTex] 无头陪练号(SIM_DRIVER=1): 注册大贴图占位加载器, 解码后 >= %d 字节的贴图只留尺寸不留像素" % MIN_BYTES)
	ResourceLoader.add_resource_format_loader(ld, true)
	print("[LiteTex] 已注册(排在最前); 小贴图照常交给引擎原装加载器")
	return ld


# zero-caller-ok: ResourceFormatLoader 引擎虚函数, ResourceLoader 挑加载器时调
func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["ctex"])


# zero-caller-ok: ResourceFormatLoader 引擎虚函数, ResourceLoader 按类型提示挑加载器时调
func _handles_type(type: StringName) -> bool:
	return type == &"CompressedTexture2D" or ClassDB.is_parent_class(&"CompressedTexture2D", type)


# zero-caller-ok: ResourceFormatLoader 引擎虚函数, ResourceLoader.get_resource_type 时调
func _get_resource_type(path: String) -> String:
	return "CompressedTexture2D" if path.get_extension().to_lower() == "ctex" else ""


## 只读 ctex 文件头(魔数 GST2 / 格式版本 / 宽 / 高), 不解码像素。
func _load(path: String, original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:   # zero-caller-ok: ResourceFormatLoader 引擎虚函数, ResourceLoader 载 .ctex 时调
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var magic := f.get_buffer(4).get_string_from_ascii()
	if magic != "GST2":
		return null
	f.get_32()
	var w := f.get_32()
	var h := f.get_32()
	f.close()
	if w <= 0 or h <= 0 or w * h * 4 < min_bytes:
		return null
	var t := PlaceholderTexture2D.new()
	t.size = Vector2(w, h)
	n_ph += 1
	bytes_saved += w * h * 4
	if not _first_logged:
		_first_logged = true
		print("[LiteTex] 第一张占位: %s %dx%d" % [original_path, w, h])
	return t
